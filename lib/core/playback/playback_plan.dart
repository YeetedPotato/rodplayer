import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';

class PlaybackPlan {
  const PlaybackPlan({
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    required this.playMethod,
    required this.playbackUri,
    required this.engineId,
    required this.source,
    this.selectedAudioStreamIndex,
    this.selectedSubtitleStreamIndex,
    this.transcodeReasons = const <String>[],
    this.videoCopied = false,
    this.audioCopied = false,
    this.containerChanged = false,
  });

  final String itemId;
  final String mediaSourceId;
  final String? playSessionId;
  final PlayMethod playMethod;
  final Uri playbackUri;
  final String engineId;
  final MediaSourceInfo source;
  final int? selectedAudioStreamIndex;
  final int? selectedSubtitleStreamIndex;
  final List<String> transcodeReasons;
  final bool videoCopied;
  final bool audioCopied;
  final bool containerChanged;
}
