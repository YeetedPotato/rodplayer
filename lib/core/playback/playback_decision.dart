import 'package:rodplayer/core/playback/platform_capabilities.dart';

enum PlayMethod { directPlay, directStream, transcode }

class PlaybackDecision {
  const PlaybackDecision({required this.method, required this.reason, this.url});
  final PlayMethod method;
  final String reason;
  final Uri? url;
}

class PlaybackDecisionEngine {
  const PlaybackDecisionEngine(this.capabilities);
  final DeviceCapabilities capabilities;

  PlaybackDecision decide(Map<String, dynamic> source) {
    final container = '${source['Container'] ?? ''}'.toLowerCase();
    final video = '${source['VideoCodec'] ?? ''}'.toLowerCase();
    final audio = '${source['AudioCodec'] ?? ''}'.toLowerCase();
    final direct = capabilities.containers.contains(container) && capabilities.videoCodecs.contains(video) && capabilities.audioCodecs.contains(audio);
    final directUrl = source['DirectStreamUrl'] ?? source['Path'];
    if (direct && directUrl is String && directUrl.isNotEmpty) return PlaybackDecision(method: PlayMethod.directPlay, reason: 'Direct play: $container, $video, $audio', url: Uri.tryParse(directUrl));
    final streamUrl = source['TranscodingUrl'];
    if (streamUrl is String && streamUrl.isNotEmpty) return PlaybackDecision(method: PlayMethod.directStream, reason: 'Direct stream: server supplied a playable URL', url: Uri.tryParse(streamUrl));
    return PlaybackDecision(method: PlayMethod.transcode, reason: 'Media source is not supported by the current device profile');
  }
}
