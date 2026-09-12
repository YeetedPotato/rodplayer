import 'dart:async';

import 'package:flutter/foundation.dart';

/// Detects when an actively playing stream stops advancing.
class StallEvent {
  const StallEvent({
    required this.position,
    required this.stalled,
    required this.isBuffering,
  });

  final Duration position;
  final bool stalled;
  final bool isBuffering;
}

class StallDetector {
  StallDetector({
    this.stallThreshold = const Duration(seconds: 4),
    this.tickInterval = const Duration(milliseconds: 250),
    this.onStall,
  }) : assert(stallThreshold > Duration.zero),
       assert(tickInterval > Duration.zero),
       _events = StreamController<StallEvent>.broadcast() {
    _timer = Timer.periodic(tickInterval, (_) => _check());
  }

  final Duration stallThreshold;
  final Duration tickInterval;
  final ValueChanged<StallEvent>? onStall;
  final StreamController<StallEvent> _events;
  late final Timer _timer;
  Duration? _position;
  DateTime? _lastAdvance;
  bool _playing = false;
  bool _buffering = false;
  bool _stalled = false;
  bool _disposed = false;

  Stream<StallEvent> get events => _events.stream;
  bool get isStalled => _stalled;

  /// Supplies the latest player state and playback position.
  void update({
    required Duration position,
    required bool isPlaying,
    bool isBuffering = false,
  }) {
    if (_disposed) return;
    final advanced = _position == null || position > _position!;
    _position = position;
    _playing = isPlaying;
    _buffering = isBuffering;
    if (advanced) {
      _lastAdvance = DateTime.now();
      if (_stalled) _emit(false);
    } else if (!_playing) {
      _reset();
    }
  }

  void _check() {
    if (_disposed || !_playing || _position == null || _lastAdvance == null) {
      return;
    }
    if (!_stalled && DateTime.now().difference(_lastAdvance!) >= stallThreshold) {
      _emit(true);
    }
  }

  void _emit(bool stalled) {
    _stalled = stalled;
    final event = StallEvent(
      position: _position!,
      stalled: stalled,
      isBuffering: _buffering,
    );
    if (!_events.isClosed) _events.add(event);
    onStall?.call(event);
  }

  void _reset() {
    _lastAdvance = null;
    if (_stalled) _emit(false);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer.cancel();
    await _events.close();
  }
}
