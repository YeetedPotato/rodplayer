import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/playback/runtime_playback_recovery.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';

import 'fakes/test_playback_engine.dart';

void main() {
  test('retry recovery preserves position and playing state without replacement', () async {
    final runtime = _Runtime('one');
    final session = _session();
    final coordinator = PlaybackRuntimeCoordinator(registry: PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]), session: session);
    final active = await coordinator.activate(session.activePlan);
    final engine = active.engine as _Engine;
    engine.position = const Duration(seconds: 12);
    await engine.play();
    engine.calls.clear();
    final recovery = RuntimePlaybackRecovery(coordinator: coordinator, session: session, negotiate: _none);
    await recovery.recover();
    expect(coordinator.active, same(active));
    expect(engine.calls, <String>['retry', 'seek:12', 'play']);
  });

  test('duplicate recovery is single-flight and invalidation prevents stale restore', () async {
    final gate = Completer<void>();
    final runtime = _Runtime('one', retry: () => gate.future);
    final session = _session();
    final coordinator = PlaybackRuntimeCoordinator(registry: PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]), session: session);
    final active = await coordinator.activate(session.activePlan);
    final engine = active.engine as _Engine;
    final recovery = RuntimePlaybackRecovery(coordinator: coordinator, session: session, negotiate: _none);
    final first = recovery.recover();
    final second = recovery.recover();
    recovery.invalidate();
    gate.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(engine.calls, <String>['retry']);
    expect(coordinator.active, same(active));
  });

  test('failed retry requests current item and stream indexes for fallback', () async {
    final runtime = _Runtime('one', retry: () async => throw StateError('retry'));
    final session = _session();
    final coordinator = PlaybackRuntimeCoordinator(registry: PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]), session: session);
    await coordinator.activate(session.activePlan);
    session.selectedAudio = 4;
    session.selectedSubtitle = 8;
    String? item; int? audio; int? subtitle;
    final recovery = RuntimePlaybackRecovery(coordinator: coordinator, session: session, negotiate: ({required itemId, audioStreamIndex, subtitleStreamIndex}) async { item = itemId; audio = audioStreamIndex; subtitle = subtitleStreamIndex; return const <PlaybackBackendCandidate>[]; });
    await recovery.recover();
    expect(item, 'item');
    expect(audio, 4);
    expect(subtitle, 8);
  });

  test('paused retry restores position and pause intent', () async {
    final runtime = _Runtime('one');
    final session = _session();
    final coordinator = PlaybackRuntimeCoordinator(registry: PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]), session: session);
    final active = await coordinator.activate(session.activePlan);
    final engine = active.engine as _Engine;
    engine.position = const Duration(seconds: 9);
    engine.calls.clear();
    await RuntimePlaybackRecovery(coordinator: coordinator, session: session, negotiate: _none).recover();
    expect(engine.calls, <String>['retry', 'seek:9', 'pause']);
  });

  test('superseded retry does not attempt another retry or restore state', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final runtime = _Runtime('one', retry: () { started.complete(); return gate.future; });
    final session = _session();
    final coordinator = PlaybackRuntimeCoordinator(registry: PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]), session: session);
    final active = await coordinator.activate(session.activePlan);
    final engine = active.engine as _Engine;
    final recovery = RuntimePlaybackRecovery(coordinator: coordinator, session: session, negotiate: _none, maxRetries: 2);
    final pending = recovery.recover();
    await started.future;
    await coordinator.activate(session.activePlan);
    gate.complete();
    await pending;
    expect(engine.calls, <String>['retry']);
  });

  test('superseded pending seek does not restore play state', () async {
    final seekGate = Completer<void>();
    final seekStarted = Completer<void>();
    final runtime = _Runtime('one');
    final session = _session();
    final coordinator = PlaybackRuntimeCoordinator(registry: PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]), session: session);
    final active = await coordinator.activate(session.activePlan);
    final engine = active.engine as _Engine;
    engine.position = const Duration(seconds: 7);
    engine.seekAction = (_) { seekStarted.complete(); return seekGate.future; };
    final pending = RuntimePlaybackRecovery(coordinator: coordinator, session: session, negotiate: _none).recover();
    await seekStarted.future;
    await coordinator.activate(session.activePlan);
    seekGate.complete();
    await pending;
    expect(engine.calls, <String>['retry', 'seek:7']);
  });

  test('failed retry publishes a prepared fallback and preserves the logical session', () async {
    final runtime = _Runtime('one', retry: () async => throw StateError('retry'));
    final session = _session();
    final coordinator = PlaybackRuntimeCoordinator(registry: PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]), session: session);
    final active = await coordinator.activate(session.activePlan);
    final old = active.engine as _Engine;
    old.position = const Duration(seconds: 11);
    await old.play();
    old.calls.clear();
    final fallbackPlan = _plan(mediaSourceId: 'fallback');
    await RuntimePlaybackRecovery(coordinator: coordinator, session: session, negotiate: ({required itemId, audioStreamIndex, subtitleStreamIndex}) async => <PlaybackBackendCandidate>[_candidate(fallbackPlan)]).recover();
    final replacement = coordinator.active!;
    final next = replacement.engine as _Engine;
    expect(replacement, isNot(same(active)));
    expect(session.id, 'logical');
    expect(session.activePlan.mediaSourceId, 'fallback');
    expect(session.position, const Duration(seconds: 11));
    expect(next.calls, <String>['seek:11', 'play']);
  });

  test('invalidation while negotiation is pending cannot activate a fallback', () async {
    final gate = Completer<List<PlaybackBackendCandidate>>();
    final negotiationStarted = Completer<void>();
    final runtime = _Runtime('one', retry: () async => throw StateError('retry'));
    final session = _session();
    final coordinator = PlaybackRuntimeCoordinator(registry: PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]), session: session);
    final active = await coordinator.activate(session.activePlan);
    final recovery = RuntimePlaybackRecovery(coordinator: coordinator, session: session, negotiate: ({required itemId, audioStreamIndex, subtitleStreamIndex}) { negotiationStarted.complete(); return gate.future; });
    final pending = recovery.recover();
    await negotiationStarted.future;
    recovery.invalidate();
    gate.complete(<PlaybackBackendCandidate>[_candidate(_plan(mediaSourceId: 'fallback'))]);
    await pending;
    expect(coordinator.active, same(active));
  });
}

Future<List<PlaybackBackendCandidate>> _none({required String itemId, int? audioStreamIndex, int? subtitleStreamIndex}) async => const <PlaybackBackendCandidate>[];

LogicalPlaybackSession _session() {
  final plan = _plan();
  return LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: plan);
}

PlaybackPlan _plan({String mediaSourceId = 'source'}) => PlaybackPlan(itemId: 'item', mediaSourceId: mediaSourceId, playSessionId: 'play-$mediaSourceId', playMethod: PlayMethod.directPlay, playbackUri: Uri.parse('https://media/$mediaSourceId'), engineId: 'one', source: MediaSourceInfo.fromJson(<String, dynamic>{'Id': mediaSourceId, 'MediaStreams': <dynamic>[]}));

PlaybackBackendCandidate _candidate(PlaybackPlan plan) {
  const backend = PlaybackBackendDescriptor(id: 'one', displayName: 'One', availability: BackendAvailability.available, priority: 1, capabilities: PlaybackBackendCapabilities(id: 'one', name: 'One'));
  return PlaybackBackendCandidate(backend: backend, plan: plan, score: const PlaybackPlanScore(total: 1, components: <String, int>{}));
}

class _Runtime implements PlaybackBackendRuntime {
  _Runtime(this.backendId, {this.retry});
  @override final String backendId;
  final Future<void> Function()? retry;
  @override bool get isAvailable => true;
  @override Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async => PlaybackRuntimeSession(runtimeId: backendId, plan: plan, engine: _Engine(retryAction: retry), surface: const _Surface());
}

class _Engine extends TestPlaybackEngine {
  _Engine({this.retryAction});
  final Future<void> Function()? retryAction;
  final calls = <String>[];
  Future<void> Function(Duration)? seekAction;
  @override Future<void> retry() async { calls.add('retry'); await retryAction?.call(); }
  @override Future<void> seek(Duration value) async { calls.add('seek:${value.inSeconds}'); await seekAction?.call(value); await super.seek(value); }
  @override Future<void> play() async { calls.add('play'); await super.play(); }
  @override Future<void> pause() async { calls.add('pause'); await super.pause(); }
}

class _Surface implements PlaybackVideoSurface { const _Surface(); @override Widget build(BuildContext context) => const SizedBox.shrink(); }
