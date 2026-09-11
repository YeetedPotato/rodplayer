import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The playback engine. mpv options are deliberately centralized so platform
/// views and the HUD remain independent of the transport implementation.
class RodPlayerEngine {
  RodPlayerEngine() {
    player = Player(configuration: const PlayerConfiguration());
    controller = VideoController(player);
  }

  late final Player player;
  late final VideoController controller;

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

  Future<void> open(Uri uri, {String? title}) async {
    final media = Media(uri.toString(), httpHeaders: const {});
    for (final entry in mpvProperties.entries) {
      media.extras[entry.key] = entry.value;
    }
    await player.open(media, play: true);
  }

  Future<void> seek(Duration position) => player.seek(position);
  Future<void> dispose() => player.dispose();
}
