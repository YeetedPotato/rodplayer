import 'dart:async';

import 'package:rodplayer/core/playback/playback_decision.dart';
import 'package:rodplayer/core/playback/playback_recovery_controller.dart';
import 'package:rodplayer/core/playback/stall_detector.dart';
import 'package:rodplayer/core/playback/stream_token_provider.dart';

/// Coordinates stalls, authentication recovery, and playback fallbacks.
class PlaybackCoordinator {
  PlaybackCoordinator({
    required this.stallDetector,
    required this.recoveryController,
    required this.tokenProvider,
    required this.retryCurrent,
    required this.fallback,
  });

  final StallDetector stallDetector;
  final PlaybackRecoveryController recoveryController;
  final StreamTokenProvider tokenProvider;
  final Future<bool> Function() retryCurrent;
  final Future<PlaybackDecision> Function() fallback;
  final _status = StreamController<String>.broadcast();
  StreamSubscription<StallEvent>? _stallSubscription;
  bool _attached = false;
  bool _disposed = false;

  Stream<String> get statuses => _status.stream;

  void attach() {
    if (_attached || _disposed) return;
    _attached = true;
    _stallSubscription = stallDetector.events.listen((event) {
      if (event.stalled) {
        _emit('Stall detected, attempting recovery...');
        unawaited(_recover('Playback stalled'));
      }
    });
  }

  void detach() {
    final subscription = _stallSubscription;
    _stallSubscription = null;
    unawaited(subscription?.cancel() ?? Future<void>.value());
    _attached = false;
  }

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

  Future<void> _recover(String reason) async {
    await recoveryController.handleFailure(
      reason: reason,
      retryCurrent: retryCurrent,
      fallback: () async {
        _emit('Falling back to transcode...');
        return fallback();
      },
    );
  }

  void _emit(String message) {
    if (!_status.isClosed) _status.add(message);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    detach();
    await _status.close();
  }
}
