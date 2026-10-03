import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';

typedef PlaybackRuntimeCommit = Future<void> Function(
  PlaybackRuntimeSession? previous,
  PlaybackRuntimeSession replacement,
);

/// One coordinator-owned replacement intent, including its negotiation phase.
class PlaybackTransitionOperation {
  PlaybackTransitionOperation._(this._owner, this.generation);
  final PlaybackRuntimeCoordinator _owner;
  final int generation;
  bool _released = false;
  bool get isCurrent =>
      !_released && !_owner._disposed && _owner.generation == generation;
  void call() {
    if (_released) return;
    _released = true;
    if (identical(_owner._currentTransition, this)) {
      _owner._currentTransition = null;
    }
  }
}

class PlaybackActivationSupersededException extends StateError {
  PlaybackActivationSupersededException()
      : super('Playback activation was superseded');
}

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
    this.activationFailures = const <String, Object>{},
    this.cleanupFailure,
    this.observerFailure,
  });

  final String selectedBackendId;
  final String runtimeId;
  final String mediaSourceId;
  final String logicalSessionId;
  final int generation;
  final String? playSessionId;
  final Object? failure;
  final List<String> attemptedRuntimeIds;
  final Map<String, Object> activationFailures;
  final Object? cleanupFailure;
  final Object? observerFailure;
}

class PlaybackRuntimeCoordinator {
  PlaybackRuntimeCoordinator({required this.registry, required this.session});

  final PlaybackRuntimeRegistry registry;
  final LogicalPlaybackSession session;
  PlaybackRuntimeSession? _active;
  final ValueNotifier<PlaybackRuntimeViewBinding> activeBinding =
      ValueNotifier<PlaybackRuntimeViewBinding>(
    const PlaybackRuntimeViewBinding.unavailable(),
  );
  PlaybackRuntimeDiagnostics? diagnostics;
  final _queue = <_ActivationRequest>[];
  var _generation = 0;
  var _activeGeneration = 0;
  var _opening = false;
  var _disposed = false;
  PlaybackTransitionOperation? _currentTransition;

  PlaybackRuntimeSession? get active => _active;

  /// Changes whenever activation intent changes, including a pending
  /// replacement. Command targets use it to reject stale runtime controls.
  int get generation => _generation;

  /// Generation of the currently published runtime incarnation. Unlike
  /// [generation], this does not advance for an activation attempt which
  /// later fails; commands remain bound to the runtime that is still active.
  int get activeGeneration => _activeGeneration;

  bool get isTransitioning =>
      _opening || _queue.isNotEmpty || (_currentTransition?.isCurrent ?? false);

  /// Covers negotiation before an activation is queued. Presentation remains
  /// usable, but conflicting playback commands must wait for the transaction.
  PlaybackTransitionOperation beginTransition() {
    // Superseded async work may finish later, but it no longer blocks commands.
    return _currentTransition =
        PlaybackTransitionOperation._(this, ++_generation);
  }

  Future<PlaybackRuntimeSession> activate(
    PlaybackPlan plan, {
    PlaybackRuntimePreparation? prepare,
    bool Function()? canCommit,
    PlaybackRuntimeCommit? onCommit,
  }) {
    return activateFirst(
      <PlaybackPlan>[plan],
      prepare: prepare,
      canCommit: canCommit,
      onCommit: onCommit,
    );
  }

  Future<PlaybackRuntimeSession> activateCandidates(
    List<PlaybackBackendCandidate> candidates, {
    PlaybackRuntimePreparation? prepare,
    bool Function()? canCommit,
    PlaybackRuntimeCommit? onCommit,
    PlaybackTransitionOperation? transition,
  }) {
    return activateFirst(
      <PlaybackPlan>[
        for (final candidate in candidates)
          if (candidate.isUsable) candidate.plan!,
      ],
      prepare: prepare,
      canCommit: canCommit,
      onCommit: onCommit,
      transition: transition,
    );
  }

  Future<PlaybackRuntimeSession> activateFirst(
    List<PlaybackPlan> plans, {
    PlaybackRuntimePreparation? prepare,
    bool Function()? canCommit,
    PlaybackRuntimeCommit? onCommit,
    PlaybackTransitionOperation? transition,
  }) {
    if (_disposed)
      return Future<PlaybackRuntimeSession>.error(
        StateError('Playback runtime coordinator is disposed'),
      );
    if (plans.isEmpty)
      return Future<PlaybackRuntimeSession>.error(
        StateError('No playback runtime candidates to activate'),
      );
    if (transition != null &&
        (!identical(transition._owner, this) || !transition.isCurrent)) {
      return Future.error(PlaybackActivationSupersededException());
    }
    final request = _ActivationRequest(
      plans: List<PlaybackPlan>.unmodifiable(plans),
      generation: transition?.generation ?? ++_generation,
      prepare: prepare,
      canCommit: () =>
          (transition?.isCurrent ?? true) && (canCommit?.call() ?? true),
      onCommit: onCommit,
    );
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
    if (_isInvalid(request)) {
      request.completeError(_invalidError());
      return;
    }
    final failures = <String, Object>{};
    final attemptedRuntimeIds = <String>[];
    for (final plan in request.plans) {
      attemptedRuntimeIds.add(plan.engineId);
      final activated = await _tryActivatePlan(
        request,
        plan,
        generation,
        failures,
        attemptedRuntimeIds,
      );
      if (activated) return;
      if (_isInvalid(request)) {
        request.completeError(_invalidError());
        return;
      }
    }
    if (failures.length == 1) {
      final failure = failures.values.single;
      request.completeError(
        failure is PlaybackRuntimeUnavailableException
            ? failure
            : PlaybackActivationException(failures.keys.single, failure),
      );
      return;
    }
    request.completeError(
      PlaybackActivationAggregateException(
        Map<String, Object>.unmodifiable(failures),
      ),
    );
  }

  Future<bool> _tryActivatePlan(
    _ActivationRequest request,
    PlaybackPlan plan,
    int generation,
    Map<String, Object> failures,
    List<String> attemptedRuntimeIds,
  ) async {
    if (_isInvalid(request)) {
      request.completeError(_invalidError());
      return true;
    }
    final runtime = registry.resolve(plan.engineId);
    if (runtime == null) {
      _recordFailure(
        failures,
        plan.engineId,
        PlaybackRuntimeUnavailableException(plan.engineId),
      );
      return false;
    }
    final PlaybackRuntimeSession next;
    try {
      next = await runtime.open(plan);
    } on Object catch (error) {
      if (_isInvalid(request)) {
        request.completeError(_invalidError());
        return true;
      }
      _recordFailure(failures, plan.engineId, error);
      diagnostics = PlaybackRuntimeDiagnostics(
        selectedBackendId: plan.engineId,
        runtimeId: plan.engineId,
        mediaSourceId: plan.mediaSourceId,
        logicalSessionId: session.id,
        generation: generation,
        playSessionId: plan.playSessionId,
        failure: error,
        attemptedRuntimeIds: List<String>.unmodifiable(attemptedRuntimeIds),
        activationFailures: Map<String, Object>.unmodifiable(failures),
      );
      return false;
    }
    if (_isInvalid(request)) {
      try {
        await next.dispose();
      } finally {
        request.completeError(_invalidError());
      }
      return true;
    }
    try {
      next.bindLogicalSession(session);
      await request.prepare?.call(next);
    } on Object catch (error) {
      try {
        await next.dispose();
      } on Object {
        // Best-effort cleanup; preparation failure remains authoritative.
      }
      if (error is PlaybackActivationSupersededException ||
          _isInvalid(request)) {
        request.completeError(_invalidError());
        return true;
      }
      _recordFailure(failures, plan.engineId, error);
      return false;
    }
    if (_isInvalid(request)) {
      try {
        await next.dispose();
      } finally {
        request.completeError(_invalidError());
      }
      return true;
    }
    final previous = _active;
    try {
      next.synchronizeMetadata(session.metadata);
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
    _activeGeneration = generation;
    previous?.retireLogicalAuthority();
    next.claimLogicalAuthority();
    // Irrevocable, non-suspending commit: observers see the matching plan and
    // complete binding together. Async notifications cannot roll it back.
    activeBinding.value = PlaybackRuntimeViewBinding.fromSession(next);
    Object? observerFailure;
    try {
      if (!_disposed && generation == _generation && identical(_active, next)) {
        final notification = request.onCommit?.call(previous, next);
        if (notification != null) {
          unawaited(_observeNotification(notification, generation));
        }
      }
    } on Object catch (error) {
      observerFailure = error;
    }
    diagnostics = PlaybackRuntimeDiagnostics(
      selectedBackendId: plan.engineId,
      runtimeId: next.runtimeId,
      mediaSourceId: plan.mediaSourceId,
      logicalSessionId: session.id,
      generation: generation,
      playSessionId: plan.playSessionId,
      attemptedRuntimeIds: List<String>.unmodifiable(attemptedRuntimeIds),
      activationFailures: Map<String, Object>.unmodifiable(failures),
      observerFailure: observerFailure,
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
        observerFailure: observerFailure,
        attemptedRuntimeIds: List<String>.unmodifiable(attemptedRuntimeIds),
        activationFailures: Map<String, Object>.unmodifiable(failures),
      );
    }
    if (_disposed || generation != _generation || !identical(_active, next)) {
      request.completeError(_invalidError());
    } else {
      request.complete(next);
    }
    return true;
  }

  void _recordFailure(
    Map<String, Object> failures,
    String runtimeId,
    Object error,
  ) {
    if (!failures.containsKey(runtimeId)) {
      failures[runtimeId] = error;
      return;
    }
    var index = 2;
    while (failures.containsKey('$runtimeId#$index')) {
      index += 1;
    }
    failures['$runtimeId#$index'] = error;
  }

  // Notification is best-effort and cannot own retirement or queue progress.
  Future<void> _observeNotification(
      Future<void> notification, int generation) async {
    try {
      await notification.timeout(const Duration(seconds: 5));
    } on Object catch (error) {
      final current = diagnostics;
      if (current == null || current.generation != generation) return;
      diagnostics = PlaybackRuntimeDiagnostics(
        selectedBackendId: current.selectedBackendId,
        runtimeId: current.runtimeId,
        mediaSourceId: current.mediaSourceId,
        logicalSessionId: current.logicalSessionId,
        generation: current.generation,
        playSessionId: current.playSessionId,
        failure: current.failure,
        attemptedRuntimeIds: current.attemptedRuntimeIds,
        activationFailures: current.activationFailures,
        cleanupFailure: current.cleanupFailure,
        observerFailure: error,
      );
    }
  }

  bool _isInvalid(_ActivationRequest request) =>
      _disposed ||
      request.generation != _generation ||
      request.canCommit?.call() == false;

  Object _invalidError() => _disposed
      ? StateError('Playback runtime coordinator is disposed')
      : PlaybackActivationSupersededException();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _currentTransition = null;
    _generation += 1;
    _failQueued(StateError('Playback runtime coordinator is disposed'));
    final active = _active;
    active?.retireLogicalAuthority();
    _active = null;
    activeBinding.value = const PlaybackRuntimeViewBinding.unavailable();
    if (active != null) await active.dispose();
  }

  void synchronizeActiveMetadata() =>
      _active?.synchronizeMetadata(session.metadata);

  void _failQueued(Object error) {
    final queued = List<_ActivationRequest>.of(_queue);
    _queue.clear();
    for (final request in queued) {
      request.completeError(error);
    }
  }
}

class _ActivationRequest {
  _ActivationRequest({
    required this.plans,
    required this.generation,
    this.prepare,
    this.canCommit,
    this.onCommit,
  }) {
    _observed = completer.future..ignore();
  }

  final List<PlaybackPlan> plans;
  final int generation;
  final PlaybackRuntimePreparation? prepare;
  final bool Function()? canCommit;
  final PlaybackRuntimeCommit? onCommit;
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
