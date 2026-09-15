import 'dart:async';

import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';

class PlaybackRuntimeDiagnostics {
  const PlaybackRuntimeDiagnostics({
    required this.selectedBackendId,
    required this.runtimeId,
    required this.mediaSourceId,
    required this.logicalSessionId,
    required this.generation,
    this.playSessionId,
    this.failure,
  });

  final String selectedBackendId;
  final String runtimeId;
  final String mediaSourceId;
  final String logicalSessionId;
  final int generation;
  final String? playSessionId;
  final Object? failure;
}

class PlaybackRuntimeCoordinator {
  PlaybackRuntimeCoordinator({
    required this.registry,
    required LogicalPlaybackSession session,
  }) : session = session;

  final PlaybackRuntimeRegistry registry;
  final LogicalPlaybackSession session;
  PlaybackRuntimeSession? _active;
  PlaybackRuntimeDiagnostics? diagnostics;
  Future<void> _tail = Future<void>.value();
  var _generation = 0;
  var _disposed = false;

  PlaybackRuntimeSession? get active => _active;

  Future<PlaybackRuntimeSession> activate(PlaybackPlan plan) {
    final completer = Completer<PlaybackRuntimeSession>();
    _tail = _tail.whenComplete(() async {
      try {
        completer.complete(await _activateNow(plan));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<PlaybackRuntimeSession> _activateNow(PlaybackPlan plan) async {
    if (_disposed) throw StateError('Playback runtime coordinator is disposed');
    final generation = ++_generation;
    final runtime = registry.resolve(plan.engineId);
    if (runtime == null) throw PlaybackRuntimeUnavailableException(plan.engineId);
    PlaybackRuntimeSession next;
    try {
      next = await runtime.open(plan);
    } on Object catch (error) {
      diagnostics = PlaybackRuntimeDiagnostics(
        selectedBackendId: plan.engineId,
        runtimeId: plan.engineId,
        mediaSourceId: plan.mediaSourceId,
        logicalSessionId: session.id,
        generation: generation,
        playSessionId: plan.playSessionId,
        failure: error,
      );
      throw PlaybackActivationException(plan.engineId, error);
    }
    if (_disposed || generation != _generation) {
      await next.dispose();
      throw StateError('Playback activation was superseded');
    }
    final previous = _active;
    _active = next;
    session.activatePlan(plan);
    diagnostics = PlaybackRuntimeDiagnostics(
      selectedBackendId: plan.engineId,
      runtimeId: next.runtimeId,
      mediaSourceId: plan.mediaSourceId,
      logicalSessionId: session.id,
      generation: generation,
      playSessionId: plan.playSessionId,
    );
    if (previous != null) await previous.dispose();
    return next;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    final active = _active;
    _active = null;
    if (active != null) await active.dispose();
  }
}
