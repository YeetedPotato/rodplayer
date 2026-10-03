import 'dart:async';

enum LiveSeekability { unseekable, seekable }

/// Time-shift values are monotonic offsets within the live session, not wall
/// clock timestamps. Null bounds mean the server did not provide a window.
final class LiveTimeline {
  const LiveTimeline({
    required this.seekability,
    this.windowStart,
    this.liveEdge,
    this.position,
  });

  final LiveSeekability seekability;
  final Duration? windowStart;
  final Duration? liveEdge;
  final Duration? position;

  bool get hasWindow =>
      seekability == LiveSeekability.seekable &&
      windowStart != null &&
      liveEdge != null &&
      liveEdge! >= windowStart!;

  Duration? clamp(Duration requested) {
    if (!hasWindow) return null;
    return requested < windowStart!
        ? windowStart
        : requested > liveEdge!
        ? liveEdge
        : requested;
  }

  LiveTimeline moveWindow({
    required Duration start,
    required Duration edge,
    Duration? current,
  }) {
    if (seekability != LiveSeekability.seekable || edge < start) {
      throw StateError('Invalid live capture window');
    }
    final requested = current ?? position ?? edge;
    final nextPosition = requested < start
        ? start
        : requested > edge
        ? edge
        : requested;
    return LiveTimeline(
      seekability: seekability,
      windowStart: start,
      liveEdge: edge,
      position: nextPosition,
    );
  }

  LiveTimeline goLive() => LiveTimeline(
    seekability: seekability,
    windowStart: windowStart,
    liveEdge: liveEdge,
    position: liveEdge,
  );
}

enum LiveRecoveryReason {
  temporaryNetworkInterruption,
  serverTuneFailure,
  expiredSource,
  unseekableSource,
  captureWindowMoved,
}

enum LiveRecoveryAction { waitForConnection, retune, goLive, rebuffer, stop }

LiveRecoveryAction liveRecoveryAction(LiveRecoveryReason reason) =>
    switch (reason) {
      LiveRecoveryReason.temporaryNetworkInterruption =>
        LiveRecoveryAction.waitForConnection,
      LiveRecoveryReason.serverTuneFailure => LiveRecoveryAction.stop,
      LiveRecoveryReason.expiredSource => LiveRecoveryAction.retune,
      LiveRecoveryReason.unseekableSource => LiveRecoveryAction.goLive,
      LiveRecoveryReason.captureWindowMoved => LiveRecoveryAction.rebuffer,
    };

final class LivePlaybackSession {
  LivePlaybackSession({
    required this.sessionId,
    required this.serverId,
    required this.channelId,
    required this.playSessionId,
    required this.timeline,
    this.mediaSourceId,
    this.generation = 0,
  });

  final String sessionId;
  final String serverId;
  final String channelId;
  final String playSessionId;
  final String? mediaSourceId;
  final LiveTimeline timeline;
  final int generation;

  LivePlaybackSession copyWith({
    String? channelId,
    String? playSessionId,
    String? mediaSourceId,
    LiveTimeline? timeline,
    int? generation,
  }) => LivePlaybackSession(
    sessionId: sessionId,
    serverId: serverId,
    channelId: channelId ?? this.channelId,
    playSessionId: playSessionId ?? this.playSessionId,
    mediaSourceId: mediaSourceId ?? this.mediaSourceId,
    timeline: timeline ?? this.timeline,
    generation: generation ?? this.generation,
  );
}

abstract interface class LivePlaybackCandidate {
  String get channelId;
  Future<void> close();
}

/// Opens a replacement before publishing it. Failed/superseded candidates do
/// not tear down the current channel; the latest requested channel wins.
final class LiveChannelRetuneCoordinator<T extends LivePlaybackCandidate> {
  LiveChannelRetuneCoordinator({required this.open}) : current = null;

  final Future<T> Function(String channelId) open;
  T? current;
  int _generation = 0;
  bool _disposed = false;
  _RetuneRequest<T>? _pending;
  _RetuneRequest<T>? _inFlight;
  Future<void>? _drainTask;
  Future<void>? _disposeTask;

  int get generation => _generation;

  Future<bool> retune(String channelId) {
    if (_disposed) throw StateError('Live retune coordinator is closed');
    if (channelId.trim().isEmpty) {
      throw ArgumentError.value(channelId, 'channelId');
    }
    final request = _RetuneRequest<T>(channelId, ++_generation);
    _pending?.complete(false);
    _inFlight?.complete(false);
    _pending = request;
    _startDrain();
    return request.result.future;
  }

  void _startDrain() {
    if (_drainTask != null || _disposed) return;
    final task = _drainPending();
    _drainTask = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_drainTask, task)) _drainTask = null;
        if (!_disposed && _pending != null) _startDrain();
      }),
    );
  }

  Future<void> _drainPending() async {
    while (!_disposed && _pending != null) {
      final request = _pending!;
      _pending = null;
      _inFlight = request;
      final T candidate;
      try {
        candidate = await open(request.channelId);
      } on Object catch (error, stack) {
        _inFlight = null;
        if (_disposed || request.generation != _generation) {
          request.complete(false);
        } else {
          request.completeError(error, stack);
        }
        continue;
      }
      _inFlight = null;
      if (_disposed || request.generation != _generation) {
        try {
          await candidate.close();
        } on Object {
          // A stale candidate never takes ownership of the current channel.
        }
        request.complete(false);
        continue;
      }
      final previous = current;
      current = candidate;
      try {
        await previous?.close();
      } on Object {
        // The replacement is already current; old cleanup cannot roll it back.
      }
      request.complete(true);
    }
  }

  Future<void> dispose() => _disposeTask ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _generation++;
    _pending?.complete(false);
    _pending = null;
    _inFlight?.complete(false);
    final previous = current;
    current = null;
    try {
      await previous?.close();
    } finally {
      await _drainTask;
    }
  }
}

final class _RetuneRequest<T extends LivePlaybackCandidate> {
  _RetuneRequest(this.channelId, this.generation);

  final String channelId;
  final int generation;
  final Completer<bool> result = Completer<bool>();

  void complete(bool value) {
    if (!result.isCompleted) result.complete(value);
  }

  void completeError(Object error, StackTrace stack) {
    if (!result.isCompleted) result.completeError(error, stack);
  }
}
