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
    required this.session,
  });

  final PlaybackRuntimeRegistry registry;
  final LogicalPlaybackSession session;
  PlaybackRuntimeSession? _active;
  PlaybackRuntimeDiagnostics? diagnostics;
  final _queue = <_ActivationRequest>[];
  var _generation = 0;
  var _opening = false;
  var _disposed = false;

  PlaybackRuntimeSession? get active => _active;

  Future<PlaybackRuntimeSession> activate(PlaybackPlan plan) {
    if (_disposed) return Future<PlaybackRuntimeSession>.error(StateError('Playback runtime coordinator is disposed'));
    final request = _ActivationRequest(plan: plan, generation: ++_generation);
    _queue.add(request);
    _startNext();
    return request.future;
  }

  void _startNext() {
    if (_opening || _queue.isEmpty) return;
    if (_disposed) {
      _failQueued(StateError('Playback runtime coordinator is disposed'));
      return;
    }
    final request = _queue.removeAt(0);
    _opening = true;
    unawaited(_runActivation(request));
  }

  Future<void> _runActivation(_ActivationRequest request) async {
    try {
      await _runActivationBody(request);
    } finally {
      _opening = false;
      _startNext();
    }
  }

  Future<void> _runActivationBody(_ActivationRequest request) async {
    final plan = request.plan;
    final generation = request.generation;
    final runtime = registry.resolve(plan.engineId);
    if (runtime == null) {
      request.completeError(PlaybackRuntimeUnavailableException(plan.engineId));
      return;
    }
    final PlaybackRuntimeSession next;
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
      request.completeError(PlaybackActivationException(plan.engineId, error));
      return;
    }
    if (_disposed || generation != _generation) {
      try {
        await next.dispose();
      } finally {
        request.completeError(StateError(_disposed ? 'Playback runtime coordinator is disposed' : 'Playback activation was superseded'));
      }
      return;
    }
    final previous = _active;
    try {
      session.activatePlan(plan);
    } on Object catch (error) {
      try {
        await next.dispose();
      } on Object {
        // Best-effort cleanup; the activation failure remains authoritative.
      }
      request.completeError(error);
      return;
    }
    _active = next;
    diagnostics = PlaybackRuntimeDiagnostics(
      selectedBackendId: plan.engineId,
      runtimeId: next.runtimeId,
      mediaSourceId: plan.mediaSourceId,
      logicalSessionId: session.id,
      generation: generation,
      playSessionId: plan.playSessionId,
    );
    try {
      if (previous != null) await previous.dispose();
    } on Object catch (error) {
      diagnostics = PlaybackRuntimeDiagnostics(
        selectedBackendId: plan.engineId,
        runtimeId: next.runtimeId,
        mediaSourceId: plan.mediaSourceId,
        logicalSessionId: session.id,
        generation: generation,
        playSessionId: plan.playSessionId,
        failure: error,
      );
    }
    request.complete(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    _failQueued(StateError('Playback runtime coordinator is disposed'));
    final active = _active;
    _active = null;
    if (active != null) await active.dispose();
  }

  void _failQueued(Object error) {
    final queued = List<_ActivationRequest>.of(_queue);
    _queue.clear();
    for (final request in queued) {
      request.completeError(error);
    }
  }
}

class _ActivationRequest {
  _ActivationRequest({required this.plan, required this.generation}) {
    _observed = completer.future..ignore();
  }

  final PlaybackPlan plan;
  final int generation;
  final completer = Completer<PlaybackRuntimeSession>();
  late final Future<PlaybackRuntimeSession> _observed;

  Future<PlaybackRuntimeSession> get future => _observed;

  void complete(PlaybackRuntimeSession session) {
    if (!completer.isCompleted) completer.complete(session);
  }

  void completeError(Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }
}
