import 'dart:async';

import 'package:rodplayer/core/playback/playback_decision.dart';

/// The phase currently visible to playback UI/HUD.
enum RecoveryPhase { idle, retrying, fallingBack, recovered, failed }

class RecoveryState {
  const RecoveryState({required this.phase, required this.reason, this.attempt = 0});

  final RecoveryPhase phase;
  final String reason;
  final int attempt;
}

/// Retries a broken stream, then asks the playback layer for a fallback.
class PlaybackRecoveryController {
  PlaybackRecoveryController({
    this.maxRetries = 3,
    this.initialBackoff = const Duration(milliseconds: 250),
    this.sleep = _defaultSleep,
  }) : assert(maxRetries >= 0);

  final int maxRetries;
  final Duration initialBackoff;
  final Future<void> Function(Duration) sleep;
  final _states = StreamController<RecoveryState>.broadcast();
  RecoveryState _state = const RecoveryState(phase: RecoveryPhase.idle, reason: 'Ready');
  bool _recovering = false;

  RecoveryState get state => _state;
  Stream<RecoveryState> get states => _states.stream;

  Future<void> handleFailure({
    required String reason,
    required Future<bool> Function() retryCurrent,
    required Future<PlaybackDecision> Function() fallback,
  }) async {
    if (_recovering) return;
    _recovering = true;
    try {
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        _emit(RecoveryState(phase: RecoveryPhase.retrying, reason: '$reason; retrying stream', attempt: attempt));
        await sleep(_backoff(attempt));
        if (await retryCurrent()) {
          _emit(RecoveryState(phase: RecoveryPhase.recovered, reason: 'Recovered current stream after retry $attempt', attempt: attempt));
          return;
        }
      }
      _emit(RecoveryState(phase: RecoveryPhase.fallingBack, reason: 'Direct play failed after $maxRetries retries; selecting fallback'));
      final decision = await fallback();
      if (decision.method != PlayMethod.directPlay || decision.url != null) {
        _emit(RecoveryState(phase: RecoveryPhase.recovered, reason: 'Fallback selected: ${decision.method.name}; ${decision.reason}'));
      } else {
        _emit(RecoveryState(phase: RecoveryPhase.failed, reason: 'Fallback unavailable: ${decision.reason}'));
      }
    } catch (error) {
      _emit(RecoveryState(phase: RecoveryPhase.failed, reason: 'Playback recovery failed: $error'));
    } finally {
      _recovering = false;
    }
  }

  Duration _backoff(int attempt) => initialBackoff * (1 << (attempt - 1));

  void _emit(RecoveryState value) {
    _state = value;
    if (!_states.isClosed) _states.add(value);
  }

  Future<void> dispose() => _states.close();
  static Future<void> _defaultSleep(Duration duration) => Future<void>.delayed(duration);
}
