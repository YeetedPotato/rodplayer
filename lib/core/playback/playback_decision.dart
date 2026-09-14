import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

export 'package:rodplayer/core/api/models/play_method.dart';

class PlaybackDecision {
  const PlaybackDecision({required this.method, required this.reason, this.url});
  final PlayMethod method;
  final String reason;
  final Uri? url;
}

/// Legacy compatibility helper for simple cached-source selection.
///
/// New playback must use PlaybackNegotiator and server PlaybackInfo output.
class PlaybackDecisionEngine {
  const PlaybackDecisionEngine(this.backend);
  final PlaybackBackendCapabilities backend;

  PlaybackDecision decide(Map<String, dynamic> source) {
    final directUrl = source['DirectStreamUrl'] ?? source['Path'];
    if (source['SupportsDirectPlay'] == true && directUrl is String && directUrl.isNotEmpty) {
      return PlaybackDecision(method: PlayMethod.directPlay, reason: 'Server allows direct play', url: Uri.tryParse(directUrl));
    }
    if (source['SupportsDirectStream'] == true && directUrl is String && directUrl.isNotEmpty) {
      return PlaybackDecision(method: PlayMethod.directStream, reason: 'Server allows direct stream', url: Uri.tryParse(directUrl));
    }
    final transcodeUrl = source['TranscodingUrl'];
    if (transcodeUrl is String && transcodeUrl.isNotEmpty) {
      return PlaybackDecision(method: PlayMethod.transcode, reason: 'Server supplied a transcoding URL', url: Uri.tryParse(transcodeUrl));
    }
    return const PlaybackDecision(method: PlayMethod.transcode, reason: 'Server returned no playable URL');
  }
}
