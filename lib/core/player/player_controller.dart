import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The playback engine. mpv options are deliberately centralized so platform
/// views and the HUD remain independent of the transport implementation.
class RodPlayerEngine {
  RodPlayerEngine({this.onError}) {
    player = Player(configuration: const PlayerConfiguration());
    controller = VideoController(player);
    _subscriptions = <StreamSubscription<Object?>>[
      player.stream.error.listen(_handleError),
      player.stream.playing.listen(_handlePlayingChanged),
      player.stream.buffering.listen(_handleBufferingChanged),
    ];
  }

  late final Player player;
  late final VideoController controller;

  final void Function(String error)? onError;
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> buffering = ValueNotifier<bool>(false);

  late final List<StreamSubscription<Object?>> _subscriptions;
  Uri? _uri;
  Map<String, String> _headers = const <String, String>{};
  int _retryCount = 0;
  bool _retryScheduled = false;
  bool _disposed = false;

  static const int _maxRetries = 3;

  static const Map<String, String> mpvProperties = {
    'hwdec': 'auto-safe',
    'vo': 'gpu-next',
    'demuxer-max-bytes': '512MiB',
    'demuxer-max-back-bytes': '256MiB',
    'cache': 'yes',
    'network-timeout': '15',
    'socket-buffer-size': '4MiB',
    'tone-mapping': 'bt.2446a',
    'target-colorspace-hint': 'yes',
  };

  Future<void> open(
    Uri uri, {
    String? title,
    Map<String, String>? headers,
    String? authToken,
  }) async {
    _uri = uri;
    _retryCount = 0;
    _retryScheduled = false;
    error.value = null;
    _headers = <String, String>{...?headers};
    if (authToken != null && authToken.isNotEmpty) {
      _headers['Authorization'] = 'Bearer $authToken';
    }
    await _openAtPosition();
  }

  Future<void> _openAtPosition() async {
    final uri = _uri;
    if (_disposed || uri == null) return;

    final position = player.state.position;
    final media = Media(uri.toString(), httpHeaders: _headers);
    for (final entry in mpvProperties.entries) {
      media.extras?[entry.key] = entry.value;
    }
    await player.open(media, play: true);
    if (position > Duration.zero) {
      await player.seek(position);
    }
  }

  void _handleError(String message) {
    if (_disposed) return;
    error.value = message;
    onError?.call(message);
    if (_retryScheduled || _retryCount >= _maxRetries || _uri == null) return;

    _retryScheduled = true;
    _retryCount++;
    unawaited(_retry());
  }

  Future<void> retry() async {
    if (_disposed || _uri == null) return;
    _retryScheduled = false;
    try {
      await _openAtPosition();
      error.value = null;
    } on Object catch (retryError) {
      _handleError(retryError.toString());
    }
  }

  Future<void> _retry() async {
    await Future<void>.delayed(Duration(seconds: _retryCount));
    await retry();
  }

  void _handlePlayingChanged(bool value) {
    if (!_disposed) playing.value = value;
  }

  void _handleBufferingChanged(bool value) {
    if (!_disposed) buffering.value = value;
  }

  Future<void> seek(Duration position) => player.seek(position);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    error.dispose();
    playing.dispose();
    buffering.dispose();
    await player.dispose();
  }
}
