import 'dart:async';

import 'package:rodplayer/core/playback/playback_decision.dart';
import 'package:rodplayer/core/playback/playback_recovery_controller.dart';
import 'package:rodplayer/core/playback/stall_detector.dart';
import 'package:rodplayer/core/playback/stream_token_provider.dart';

/// Coordinates stalls, authentication recovery, and playback fallbacks.
class PlaybackCoordinator {
  PlaybackCoordinator({required this.stallDetector, required this.recoveryController, required this.tokenProvider, required this.retryCurrent, required this.fallback});
  final StallDetector stallDetector;
  final PlaybackRecoveryController recoveryController;
  final StreamTokenProvider tokenProvider;
  final Future<bool> Function() retryCurrent;
  final Future<PlaybackDecision> Function() fallback;
  final _status = StreamController<String>.broadcast();
  StreamSubscription<StallEvent>? _stallSubscription;
  StreamSubscription<RecoveryState>? _recoverySubscription;
  Future<void>? _recoveryInFlight;
  bool _attached = false;
  bool _disposed = false;
  Stream<String> get statuses => _status.stream;
  void attach() {
    if (_attached || _disposed) return;
    _attached = true;
    _recoverySubscription = recoveryController.states.listen((state) => _emit(state.reason));
    _stallSubscription = stallDetector.events.listen((event) {
      if (event.stalled) { _emit('Stall detected, attempting recovery...'); unawaited(_recover('Playback stalled')); }
    });
  }
  void detach() {
    final stall = _stallSubscription; _stallSubscription = null; unawaited(stall?.cancel());
    final recovery = _recoverySubscription; _recoverySubscription = null; unawaited(recovery?.cancel());
    _attached = false;
  }
  void stopRecovery() { recoveryController.cancel(); detach(); }
  Future<void> handleStreamFailure({int? statusCode, bool networkDrop = false}) async {
    if (_disposed) return;
    final authFailure = statusCode == 401 || statusCode == 403;
    if (authFailure) {
      _emit('Stream authorization failed, refreshing token...');
      try {
        await tokenProvider.getValidToken(forceRefresh: true);
      } catch (error) {
        _emit('Token refresh failed: $error');
      }
    }
    final reason = authFailure ? 'Stream authorization failed' : networkDrop ? 'Network connection dropped' : 'Stream failed';
    await _recover(reason);
  }
  Future<void> _recover(String reason) {
    if (_disposed) return Future<void>.value();
    return _recoveryInFlight ??= _runRecovery(reason).whenComplete(() => _recoveryInFlight = null);
  }
  Future<void> _runRecovery(String reason) async {
    await recoveryController.handleFailure(reason: reason, retryCurrent: retryCurrent, fallback: () async { _emit('Selecting fallback playback plan...'); return fallback(); });
  }
  void _emit(String message) { if (!_status.isClosed) _status.add(message); }
  Future<void> dispose() async { if (_disposed) return; _disposed = true; recoveryController.cancel(); detach(); await _status.close(); }
}
