import 'package:rodplayer/core/playback/platform_capabilities.dart';

enum PlayMethod { directPlay, directStream, remux, transcode }

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
    final width = int.tryParse('${source['Width'] ?? 0}') ?? 0;
    final bitrate = int.tryParse('${source['Bitrate'] ?? 0}') ?? 0;
    final directUrl = source['DirectStreamUrl'] ?? source['Path'];
    final direct = capabilities.containers.contains(container) && capabilities.videoCodecs.contains(video) && capabilities.audioCodecs.contains(audio) && (bitrate == 0 || bitrate <= capabilities.maxStreamingBitrate);
    if (direct && directUrl is String && directUrl.isNotEmpty) return PlaybackDecision(method: PlayMethod.directPlay, reason: 'Direct Play: ${width >= 3840 ? '4K ' : ''}${video.toUpperCase()} / ${audio.toUpperCase()}', url: Uri.tryParse(directUrl));
    if (capabilities.containers.contains(container) && capabilities.videoCodecs.contains(video) && audio.isNotEmpty && !capabilities.audioCodecs.contains(audio)) {
      final streamUrl = source['TranscodingUrl'];
      return PlaybackDecision(method: PlayMethod.transcode, reason: 'Transcode: Audio codec not supported on platform, downmixing to AAC', url: streamUrl is String ? Uri.tryParse(streamUrl) : null);
    }
    if (capabilities.videoCodecs.contains(video) && capabilities.audioCodecs.contains(audio)) {
      final streamUrl = source['RemuxUrl'] ?? source['TranscodingUrl'];
      if (streamUrl is String && streamUrl.isNotEmpty) return PlaybackDecision(method: PlayMethod.remux, reason: 'Remux: container $container is not supported, preserving audio and video streams', url: Uri.tryParse(streamUrl));
    }
    final streamUrl = source['TranscodingUrl'];
    if (streamUrl is String && streamUrl.isNotEmpty) return PlaybackDecision(method: PlayMethod.directStream, reason: 'Direct Stream: server supplied a playable URL', url: Uri.tryParse(streamUrl));
    return const PlaybackDecision(method: PlayMethod.transcode, reason: 'Transcode: video or audio codec not supported on platform');
  }
}
