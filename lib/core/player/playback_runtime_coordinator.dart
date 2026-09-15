import 'dart:async';

import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
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
    this.attemptedRuntimeIds = const <String>[],
    this.cleanupFailure,
  });

  final String selectedBackendId;
  final String runtimeId;
  final String mediaSourceId;
  final String logicalSessionId;
  final int generation;
  final String? playSessionId;
  final Object? failure;
  final List<String> attemptedRuntimeIds;
  final Object? cleanupFailure;
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
    return activateFirst(<PlaybackPlan>[plan]);
  }

  Future<PlaybackRuntimeSession> activateCandidates(List<PlaybackBackendCandidate> candidates) {
    return activateFirst(<PlaybackPlan>[
      for (final candidate in candidates)
        if (candidate.isUsable) candidate.plan!,
    ]);
  }

  Future<PlaybackRuntimeSession> activateFirst(List<PlaybackPlan> plans) {
    if (_disposed) return Future<PlaybackRuntimeSession>.error(StateError('Playback runtime coordinator is disposed'));
    if (plans.isEmpty) return Future<PlaybackRuntimeSession>.error(StateError('No playback runtime candidates to activate'));
    final request = _ActivationRequest(plans: List<PlaybackPlan>.unmodifiable(plans), generation: ++_generation);
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
    final generation = request.generation;
    final failures = <String, Object>{};
    final attemptedRuntimeIds = <String>[];
    for (final plan in request.plans) {
      attemptedRuntimeIds.add(plan.engineId);
      final activated = await _tryActivatePlan(request, plan, generation, failures, attemptedRuntimeIds);
      if (activated) return;
      if (_disposed || generation != _generation) return;
    }
    if (failures.length == 1) {
      final failure = failures.values.single;
      request.completeError(failure is PlaybackRuntimeUnavailableException ? failure : PlaybackActivationException(failures.keys.single, failure));
      return;
    }
    request.completeError(PlaybackActivationAggregateException(Map<String, Object>.unmodifiable(failures)));
  }

  Future<bool> _tryActivatePlan(_ActivationRequest request, PlaybackPlan plan, int generation, Map<String, Object> failures, List<String> attemptedRuntimeIds) async {
    final runtime = registry.resolve(plan.engineId);
    if (runtime == null) {
      failures[plan.engineId] = PlaybackRuntimeUnavailableException(plan.engineId);
      return false;
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
        attemptedRuntimeIds: List<String>.unmodifiable(attemptedRuntimeIds),
      );
      failures[plan.engineId] = error;
      return false;
    }
    if (_disposed || generation != _generation) {
      try {
        await next.dispose();
      } finally {
        request.completeError(StateError(_disposed ? 'Playback runtime coordinator is disposed' : 'Playback activation was superseded'));
      }
      return true;
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
      return true;
    }
    _active = next;
    diagnostics = PlaybackRuntimeDiagnostics(
      selectedBackendId: plan.engineId,
      runtimeId: next.runtimeId,
      mediaSourceId: plan.mediaSourceId,
      logicalSessionId: session.id,
      generation: generation,
      playSessionId: plan.playSessionId,
      attemptedRuntimeIds: List<String>.unmodifiable(attemptedRuntimeIds),
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
        cleanupFailure: error,
        attemptedRuntimeIds: List<String>.unmodifiable(attemptedRuntimeIds),
      );
    }
    request.complete(next);
    return true;
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
  _ActivationRequest({required this.plans, required this.generation}) {
    _observed = completer.future..ignore();
  }

  final List<PlaybackPlan> plans;
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
