import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/playback/playback_reporting.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/core/player/track_controller.dart';

import 'fakes/test_playback_engine.dart';

void main() {
  test('selected media kit plan resolves to media kit runtime', () {
    final runtime = MediaKitPlaybackRuntime();
    final registry = PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]);

    expect(registry.resolve('media_kit'), same(runtime));
  });

  test('missing runtime returns typed unavailable failure', () async {
    final coordinator = _coordinator(PlaybackRuntimeRegistry(executableBackendIds: const <String>{}));

    await expectLater(coordinator.activate(_plan('missing', engineId: 'missing')), throwsA(isA<PlaybackRuntimeUnavailableException>()));
  });

  test('future unavailable backend cannot execute', () {
    final registry = PlaybackRuntimeRegistry(executableBackendIds: const <String>{'media_kit'});

    expect(registry.canExecute('android_native'), isFalse);
  });

  test('runtime open receives exact authoritative PlaybackPlan and URL', () async {
    final runtime = _FakeRuntime('media_kit');
    final plan = _plan('one', uri: Uri.parse('https://server/transcode.m3u8'));

    await _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime])).activate(plan);

    expect(runtime.opened.single, same(plan));
    expect(runtime.opened.single.playbackUri.toString(), 'https://server/transcode.m3u8');
  });

  test('replacing plan preserves logical session and updates server fields', () async {
    final runtime = _FakeRuntime('media_kit');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]));

    await coordinator.activate(_plan('one', playSessionId: 'play-one', audio: 1, subtitle: 2));
    await coordinator.activate(_plan('two', playSessionId: 'play-two', audio: 3, subtitle: 4));

    expect(coordinator.session.id, 'logical');
    expect(coordinator.session.activePlan.playSessionId, 'play-two');
    expect(coordinator.session.selectedAudio, 3);
    expect(coordinator.session.selectedSubtitle, 4);
  });

  test('active controls follow runtime replacement and clear on disposal', () async {
    final firstTracks = _SelectableTracks();
    final secondTracks = _SelectableTracks();
    final first = _FakeRuntime('first', tracks: firstTracks);
    final second = _FakeRuntime('second', tracks: secondTracks);
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[first, second]));

    await coordinator.activate(_plan('one', engineId: 'first'));
    expect(coordinator.activeControls.value.tracks, same(firstTracks));
    await coordinator.activate(_plan('two', engineId: 'second'));
    expect(coordinator.activeControls.value.tracks, same(secondTracks));
    await coordinator.dispose();
    expect(coordinator.activeControls.value.tracks, isNull);
    expect(coordinator.activeControls.value.advanced, isNull);
  });

  test('activation is serialized and newest plan wins', () async {
    final runtime = _ControlledRuntime('media_kit');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]));

    final first = coordinator.activate(_plan('one'));
    final second = coordinator.activate(_plan('two'));
    expect(runtime.activeOpens, 1);
    runtime.completeNext();
    await expectLater(first, throwsA(isA<StateError>()));
    expect(runtime.activeOpens, 1);
    runtime.completeNext();
    await second;

    expect(runtime.maxActiveOpens, 1);
    expect(runtime.created.first.disposeCount, 1);
    expect(coordinator.session.activePlan.mediaSourceId, 'two');
  });

  test('dispose during activation is safe and disposes opened runtime once', () async {
    final runtime = _ControlledRuntime('media_kit');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]));

    final activation = coordinator.activate(_plan('one'));
    await coordinator.dispose();
    runtime.completeNext();

    await expectLater(activation, throwsA(isA<StateError>()));
    expect(runtime.created.single.disposeCount, 1);
  });

  test('queued activation after dispose never opens', () async {
    final runtime = _ControlledRuntime('media_kit');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]));

    final first = coordinator.activate(_plan('one'));
    final second = coordinator.activate(_plan('two'));
    await coordinator.dispose();
    runtime.completeNext();

    await expectLater(first, throwsA(isA<StateError>()));
    await expectLater(second, throwsA(isA<StateError>()));
    expect(runtime.opened.map((plan) => plan.mediaSourceId), <String>['one']);
  });

  test('cleanup failure does not wedge queued activation drain', () async {
    final runtime = _ThrowingFirstDisposeRuntime('media_kit');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]));

    await coordinator.activate(_plan('one'));
    final secondSession = await coordinator.activate(_plan('two'));
    expect(secondSession.engine, same(runtime.created[1]));
    expect(coordinator.session.activePlan.mediaSourceId, 'two');
    expect(coordinator.diagnostics?.cleanupFailure, isA<StateError>());
    expect(runtime.created[1].disposeCount, 0);

    await coordinator.activate(_plan('three'));
    expect(coordinator.session.activePlan.mediaSourceId, 'three');
  });

  test('runtime is disposed exactly once on replacement and coordinator dispose', () async {
    final runtime = _FakeRuntime('media_kit');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]));

    await coordinator.activate(_plan('one'));
    await coordinator.activate(_plan('two'));
    await coordinator.dispose();
    await coordinator.dispose();

    expect(runtime.created.map((engine) => engine.disposeCount), <int>[1, 1]);
  });

  test('video surface and track switch mode survive routing', () async {
    final runtime = _FakeRuntime('media_kit', surface: const _FakeSurface(), tracks: const _FakeTracks());
    final session = await _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime])).activate(_plan('one'));

    expect(session.surface, isA<PlaybackVideoSurface>());
    expect((await session.tracks!.selectAudio(const RodPlayerTrack(engineTrackId: 'a', label: 'A'))).mode, TrackSwitchMode.local);
  });

  test('reporting reads newest active plan', () async {
    final runtime = _FakeRuntime('media_kit');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime]));
    await coordinator.activate(_plan('one', playSessionId: 'play-one'));
    await coordinator.activate(_plan('two', playSessionId: 'play-two'));

    final state = PlaybackReportState(
      itemId: coordinator.session.itemId,
      playSessionId: coordinator.session.activePlan.playSessionId,
      mediaSourceId: coordinator.session.activePlan.mediaSourceId,
      positionTicks: 0,
      playMethod: coordinator.session.activePlan.playMethod,
    );

    expect(state.toJson(), containsPair('PlaySessionId', 'play-two'));
    expect(state.toJson(), containsPair('MediaSourceId', 'two'));
  });

  test('activation failover tries second candidate after first open fails', () async {
    final first = _FailingRuntime('apple_native');
    final second = _FakeRuntime('apple_compatibility');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[first, second]));

    final session = await coordinator.activateFirst(<PlaybackPlan>[_plan('one', engineId: 'apple_native'), _plan('two', engineId: 'apple_compatibility')]);

    expect(session.runtimeId, 'apple_compatibility');
    expect(coordinator.session.activePlan.engineId, 'apple_compatibility');
    expect(coordinator.diagnostics?.attemptedRuntimeIds, <String>['apple_native', 'apple_compatibility']);
    expect(coordinator.diagnostics?.activationFailures.keys, contains('apple_native'));
  });

  test('activation failover can skip two failed candidates', () async {
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[_FailingRuntime('a'), _FailingRuntime('b'), _FakeRuntime('c')]));

    final session = await coordinator.activateFirst(<PlaybackPlan>[_plan('a', engineId: 'a'), _plan('b', engineId: 'b'), _plan('c', engineId: 'c')]);

    expect(session.runtimeId, 'c');
    expect(coordinator.session.activePlan.engineId, 'c');
    expect(coordinator.diagnostics?.activationFailures.keys, containsAll(<String>['a', 'b']));
  });

  test('all activation failover attempts fail with aggregate error', () async {
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[_FailingRuntime('a'), _FailingRuntime('b')]));

    await expectLater(coordinator.activateFirst(<PlaybackPlan>[_plan('a', engineId: 'a'), _plan('b', engineId: 'b')]), throwsA(isA<PlaybackActivationAggregateException>()));
  });

  test('superseded failover cannot commit', () async {
    final slow = _ControlledRuntime('fallback');
    final replacement = _FakeRuntime('replacement');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[_FailingRuntime('failed'), slow, replacement]));

    final first = coordinator.activateFirst(<PlaybackPlan>[_plan('failed', engineId: 'failed'), _plan('fallback', engineId: 'fallback')]);
    await slow.waitUntilOpenStarted();
    final second = coordinator.activate(_plan('replacement', engineId: 'replacement'));
    slow.completeNext();

    await expectLater(first, throwsA(isA<StateError>()));
    await second;
    expect(coordinator.session.activePlan.engineId, 'replacement');
    expect(slow.created.single.disposeCount, 1);
  });

  test('dispose during failover prevents later commit', () async {
    final slow = _ControlledRuntime('fallback');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[_FailingRuntime('failed'), slow]));

    final activation = coordinator.activateFirst(<PlaybackPlan>[_plan('failed', engineId: 'failed'), _plan('fallback', engineId: 'fallback')]);
    await slow.waitUntilOpenStarted();
    await coordinator.dispose();
    slow.completeNext();

    await expectLater(activation, throwsA(isA<StateError>()));
    expect(coordinator.active, isNull);
  });

  test('superseded before fallback starts completes old request', () async {
    final failed = _ControlledFailingRuntime('failed');
    final fallback = _FakeRuntime('fallback');
    final replacement = _FakeRuntime('replacement');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[failed, fallback, replacement]));

    final first = coordinator.activateFirst(<PlaybackPlan>[_plan('failed', engineId: 'failed'), _plan('fallback', engineId: 'fallback')]);
    await failed.waitUntilOpenStarted();
    final second = coordinator.activate(_plan('replacement', engineId: 'replacement'));
    failed.completeNext();

    await expectLater(first, throwsA(isA<StateError>()));
    await second;
    expect(fallback.opened, isEmpty);
    expect(coordinator.session.activePlan.engineId, 'replacement');
  });

  test('cleanup failure after successful failover is diagnostic only', () async {
    final runtime = _ThrowingFirstDisposeRuntime('media_kit');
    final coordinator = _coordinator(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[runtime, _FailingRuntime('failed')]));

    await coordinator.activate(_plan('one'));
    final session = await coordinator.activateFirst(<PlaybackPlan>[_plan('failed', engineId: 'failed'), _plan('two')]);

    expect(session.plan.mediaSourceId, 'two');
    expect(coordinator.diagnostics?.cleanupFailure, isA<StateError>());
    expect(coordinator.diagnostics?.activationFailures.keys, contains('failed'));
    expect(coordinator.session.activePlan.mediaSourceId, 'two');
  });
}

PlaybackRuntimeCoordinator _coordinator(PlaybackRuntimeRegistry registry) => PlaybackRuntimeCoordinator(
      registry: registry,
      session: LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: _plan('initial')),
    );

PlaybackPlan _plan(String sourceId, {String engineId = 'media_kit', Uri? uri, String? playSessionId, int? audio, int? subtitle}) => PlaybackPlan(
      itemId: 'item',
      mediaSourceId: sourceId,
      playSessionId: playSessionId ?? 'play-$sourceId',
      playMethod: PlayMethod.directPlay,
      playbackUri: uri ?? Uri.parse('https://media/$sourceId'),
      engineId: engineId,
      selectedAudioStreamIndex: audio,
      selectedSubtitleStreamIndex: subtitle,
      source: MediaSourceInfo.fromJson(<String, dynamic>{'Id': sourceId, 'MediaStreams': <dynamic>[]}),
    );

class _FakeRuntime implements PlaybackBackendRuntime {
  _FakeRuntime(this.backendId, {this.surface, this.tracks});

  @override
  final String backendId;
  final PlaybackVideoSurface? surface;
  final TrackSelectionController? tracks;
  final opened = <PlaybackPlan>[];
  final created = <_CountingEngine>[];

  @override
  bool get isAvailable => true;

  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async {
    opened.add(plan);
    final engine = _CountingEngine(id: backendId);
    created.add(engine);
    await engine.load(plan);
    return PlaybackRuntimeSession(runtimeId: backendId, plan: plan, engine: engine, surface: surface, tracks: tracks);
  }
}

class _ControlledRuntime extends _FakeRuntime {
  _ControlledRuntime(super.backendId);

  final _pending = <Completer<void>>[];
  final _openStarted = <Completer<void>>[];
  var activeOpens = 0;
  var maxActiveOpens = 0;

  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async {
    final completer = Completer<void>();
    _pending.add(completer);
    final started = Completer<void>();
    _openStarted.add(started);
    activeOpens += 1;
    if (activeOpens > maxActiveOpens) maxActiveOpens = activeOpens;
    started.complete();
    await completer.future;
    activeOpens -= 1;
    return super.open(plan);
  }

  void completeNext() => _pending.removeAt(0).complete();
  Future<void> waitUntilOpenStarted() async {
    while (_openStarted.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await _openStarted.first.future;
  }
}

class _ThrowingFirstDisposeRuntime extends _FakeRuntime {
  _ThrowingFirstDisposeRuntime(super.backendId);

  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async {
    opened.add(plan);
    final engine = created.isEmpty ? _ThrowingDisposeEngine(id: backendId) : _CountingEngine(id: backendId);
    created.add(engine);
    await engine.load(plan);
    return PlaybackRuntimeSession(runtimeId: backendId, plan: plan, engine: engine);
  }
}

class _FailingRuntime implements PlaybackBackendRuntime {
  const _FailingRuntime(this.backendId);

  @override
  final String backendId;

  @override
  bool get isAvailable => true;

  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async => throw StateError('open failed $backendId');
}

class _ControlledFailingRuntime implements PlaybackBackendRuntime {
  _ControlledFailingRuntime(this.backendId);

  @override
  final String backendId;
  final _pending = <Completer<void>>[];
  final _openStarted = <Completer<void>>[];

  @override
  bool get isAvailable => true;

  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async {
    final completer = Completer<void>();
    _pending.add(completer);
    final started = Completer<void>();
    _openStarted.add(started);
    started.complete();
    await completer.future;
    throw StateError('open failed $backendId');
  }

  void completeNext() => _pending.removeAt(0).complete();
  Future<void> waitUntilOpenStarted() async {
    while (_openStarted.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await _openStarted.first.future;
  }
}

class _CountingEngine extends TestPlaybackEngine {
  _CountingEngine({required super.id});

  var disposeCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    await super.dispose();
  }
}

class _ThrowingDisposeEngine extends _CountingEngine {
  _ThrowingDisposeEngine({required super.id});

  @override
  Future<void> dispose() async {
    await super.dispose();
    throw StateError('dispose failed');
  }
}

class _FakeSurface implements PlaybackVideoSurface {
  const _FakeSurface();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _FakeTracks implements TrackSelectionController {
  @override
  TrackSelectionCapabilities get capabilities => const TrackSelectionCapabilities.unavailable();

  const _FakeTracks();

  @override
  List<RodPlayerTrack> get audioTracks => const <RodPlayerTrack>[];

  @override
  List<RodPlayerTrack> get subtitleTracks => const <RodPlayerTrack>[];

  @override
  RodPlayerTrack? get selectedAudio => null;

  @override
  RodPlayerTrack? get selectedSubtitle => null;

  @override
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track) async => TrackSwitchResult(mode: TrackSwitchMode.local, serverStreamIndex: track.serverStreamIndex);

  @override
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track) async => TrackSwitchResult(mode: TrackSwitchMode.local, serverStreamIndex: track?.serverStreamIndex);
}

class _SelectableTracks extends _FakeTracks {
  _SelectableTracks() : super();
}
