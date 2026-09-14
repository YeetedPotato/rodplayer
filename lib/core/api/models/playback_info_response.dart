import 'package:rodplayer/core/api/models/media_source_info.dart';

class PlaybackInfoResponse {
  const PlaybackInfoResponse({
    required this.mediaSources,
    required this.raw,
    this.playSessionId,
    this.errorCode,
  });

  final List<MediaSourceInfo> mediaSources;
  final String? playSessionId;
  final String? errorCode;
  final Map<String, dynamic> raw;

  factory PlaybackInfoResponse.fromJson(Map<String, dynamic> json) => PlaybackInfoResponse(
        mediaSources: (json['MediaSources'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((value) => MediaSourceInfo.fromJson(Map<String, dynamic>.from(value)))
            .toList(growable: false),
        playSessionId: json['PlaySessionId'] as String?,
        errorCode: json['ErrorCode'] as String?,
        raw: Map<String, dynamic>.unmodifiable(json),
      );
}
