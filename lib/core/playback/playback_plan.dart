import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';

enum PlaybackDeliveryMode { directPlay, directStream, transcode }

enum VideoOperation { copy, transcode, none, unknown }

enum AudioOperation { copy, transcode, none, unknown }

enum SubtitleOperation { native, external, burnIn, none, unknown }

enum HdrHandling { preserve, toneMapToSdr, none, unknown }

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
    this.deliveryMode,
    this.videoOperation = VideoOperation.unknown,
    this.audioOperation = AudioOperation.unknown,
    this.subtitleOperation = SubtitleOperation.unknown,
    this.hdrHandling = HdrHandling.unknown,
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
  final PlaybackDeliveryMode? deliveryMode;
  final VideoOperation videoOperation;
  final AudioOperation audioOperation;
  final SubtitleOperation subtitleOperation;
  final HdrHandling hdrHandling;
}
