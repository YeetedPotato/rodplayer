import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/playback_coordinator.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_engine.dart';

/// The playback engine. mpv options are deliberately centralized so platform
/// views and the HUD remain independent of the transport implementation.
class MediaKitPlaybackEngine implements PlaybackEngine {
  MediaKitPlaybackEngine({this.onError, this.coordinator}) {
    player = Player(configuration: const PlayerConfiguration());
    controller = VideoController(player);
    advanced = AdvancedPlaybackController(player);
    _subscriptions = <StreamSubscription<Object?>>[
      player.stream.error.listen(_handleError),
      player.stream.position.listen(_handlePositionChanged),
      player.stream.playing.listen(_handlePlayingChanged),
      player.stream.buffering.listen(_handleBufferingChanged),
    ];
  }
  late final Player player;
  late final VideoController controller;
  late final AdvancedPlaybackController advanced;
  final void Function(String error)? onError;
  final PlaybackCoordinator? coordinator;
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> buffering = ValueNotifier<bool>(false);
  late final List<StreamSubscription<Object?>> _subscriptions;
  Uri? _uri;
  Map<String, String> _headers = const <String, String>{};
  bool _disposed = false;
  @override
  String get id => 'media_kit';
  @override
  Duration get position => player.state.position;
  Stream<String> get statuses => coordinator?.statuses ?? const Stream<String>.empty();
  static const Map<String, String> mpvProperties = {'hwdec': 'auto-safe', 'vo': 'gpu-next', 'demuxer-max-bytes': '512MiB', 'demuxer-max-back-bytes': '256MiB', 'cache': 'yes', 'network-timeout': '15', 'socket-buffer-size': '4MiB', 'tone-mapping': 'bt.2446a', 'target-colorspace-hint': 'yes', 'audio-spdif': 'ac3,eac3,dts,dts-hd,truehd', 'audio-passthrough': 'yes', 'audio-fallback-to-null': 'no', 'sub-auto': 'fuzzy', 'sub-ass': 'yes', 'sub-forced': 'yes'};
  static Map<String, String> get effectiveMpvProperties {
    if (kIsWeb) return Map<String, String>.unmodifiable(<String, String>{...mpvProperties, 'audio-spdif': 'no', 'audio-passthrough': 'no'});
    return Map<String, String>.unmodifiable(<String, String>{...mpvProperties, 'audio-device': 'auto'});
  }
  @override
  Future<void> load(PlaybackPlan plan) => open(plan.playbackUri);
  Future<void> open(Uri uri, {String? title, Map<String, String>? headers, String? authToken}) async { _uri = uri; error.value = null; _headers = <String, String>{...?headers}; if (authToken != null && authToken.isNotEmpty) _headers['Authorization'] = 'Bearer $authToken'; coordinator?.attach(); await _openAtPosition(); }
  Future<void> _openAtPosition() async { final uri = _uri; if (_disposed || uri == null) return; final position = player.state.position; final media = Media(uri.toString(), httpHeaders: _headers); for (final entry in effectiveMpvProperties.entries) { media.extras?[entry.key] = entry.value; } await player.open(media, play: true); if (position > Duration.zero) await player.seek(position); }
  Future<bool> retryCurrent() async { if (_disposed || _uri == null) return false; try { await retry(); return error.value == null; } on Object { return false; } }
  void _handleError(String message) { if (_disposed) return; error.value = message; onError?.call(message); unawaited(coordinator?.handleStreamFailure(networkDrop: true) ?? Future<void>.value()); }
  Future<void> retry() async { if (_disposed || _uri == null) return; try { await _openAtPosition(); error.value = null; } on Object catch (retryError) { _handleError(retryError.toString()); } }
  void _handlePositionChanged(Duration value) { if (_disposed) return; coordinator?.stallDetector.update(position: value, isPlaying: playing.value, isBuffering: buffering.value); }
  void _handlePlayingChanged(bool value) { if (_disposed) return; playing.value = value; coordinator?.stallDetector.update(position: player.state.position, isPlaying: value, isBuffering: buffering.value); }
  void _handleBufferingChanged(bool value) { if (_disposed) return; buffering.value = value; coordinator?.stallDetector.update(position: player.state.position, isPlaying: playing.value, isBuffering: value); }
  Future<void> seek(Duration position) => advanced.seekAccurate(position);
  Future<void> seekFast(Duration position) => advanced.seekFast(position);
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> dispose() async { if (_disposed) return; _disposed = true; for (final subscription in _subscriptions) { await subscription.cancel(); } await coordinator?.dispose(); advanced.dispose(); error.dispose(); playing.dispose(); buffering.dispose(); await player.dispose(); }
}
