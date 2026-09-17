import 'dart:collection';

import 'package:rodplayer/core/api/models/media_stream.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

/// A URL-free, immutable projection of server playback facts for diagnostics.
class PlaybackDiagnosticsSnapshot {
  PlaybackDiagnosticsSnapshot._({
    required this.backendId,
    required this.playMethod,
    required List<String> transcodeReasons,
    this.runtimeId,
    this.deliveryMode,
    this.videoOperation = VideoOperation.unknown,
    this.audioOperation = AudioOperation.unknown,
    this.subtitleOperation = SubtitleOperation.unknown,
    this.hdrHandling = HdrHandling.unknown,
    this.container,
    this.protocol,
    this.sourceBitrate,
    this.videoStream,
    this.audioStream,
    this.subtitleStream,
  }) : transcodeReasons = UnmodifiableListView<String>(List<String>.of(transcodeReasons));

  factory PlaybackDiagnosticsSnapshot.fromPlan({
    required PlaybackPlan plan,
    String? runtimeId,
    int? selectedAudioStreamIndex,
    int? selectedSubtitleStreamIndex,
  }) => PlaybackDiagnosticsSnapshot._(
    backendId: plan.engineId,
    runtimeId: runtimeId,
    playMethod: plan.playMethod,
    deliveryMode: plan.deliveryMode,
    videoOperation: plan.videoOperation,
    audioOperation: plan.audioOperation,
    subtitleOperation: plan.subtitleOperation,
    hdrHandling: plan.hdrHandling,
    transcodeReasons: plan.transcodeReasons,
    container: plan.source.container,
    protocol: plan.source.protocol,
    sourceBitrate: plan.source.bitrate,
    videoStream: _single(plan.source.videoStreams),
    audioStream: _selected(plan.source.audioStreams, selectedAudioStreamIndex),
    subtitleStream: _selected(plan.source.subtitleStreams, selectedSubtitleStreamIndex),
  );

  final String backendId;
  final String? runtimeId;
  final PlayMethod playMethod;
  final PlaybackDeliveryMode? deliveryMode;
  final VideoOperation videoOperation;
  final AudioOperation audioOperation;
  final SubtitleOperation subtitleOperation;
  final HdrHandling hdrHandling;
  final List<String> transcodeReasons;
  final String? container;
  final String? protocol;
  final int? sourceBitrate;
  final PlaybackDiagnosticsStream? videoStream;
  final PlaybackDiagnosticsStream? audioStream;
  final PlaybackDiagnosticsStream? subtitleStream;

  static PlaybackDiagnosticsStream? _single(Iterable<MediaStream> streams) {
    final values = streams.toList(growable: false);
    return values.length == 1 ? PlaybackDiagnosticsStream.fromMediaStream(values.single) : null;
  }

  static PlaybackDiagnosticsStream? _selected(Iterable<MediaStream> streams, int? index) {
    if (index == null) return null;
    for (final stream in streams) {
      if (stream.index == index) return PlaybackDiagnosticsStream.fromMediaStream(stream);
    }
    return null;
  }
}

/// Safe stream metadata copied without raw maps or URLs.
class PlaybackDiagnosticsStream {
  const PlaybackDiagnosticsStream._({
    this.codec,
    this.profile,
    this.bitDepth,
    this.bitRate,
    this.width,
    this.height,
    this.averageFrameRate,
    this.realFrameRate,
    this.videoRange,
    this.videoRangeType,
    this.channels,
    this.channelLayout,
    this.audioSpatialFormat,
    this.language,
    this.title,
    this.isDefault,
    this.isForced,
    this.isExternal,
    this.isTextSubtitleStream,
  });

  factory PlaybackDiagnosticsStream.fromMediaStream(MediaStream stream) => PlaybackDiagnosticsStream._(
    codec: stream.codec,
    profile: stream.profile,
    bitDepth: stream.bitDepth,
    bitRate: stream.bitRate,
    width: stream.width,
    height: stream.height,
    averageFrameRate: stream.averageFrameRate,
    realFrameRate: stream.realFrameRate,
    videoRange: stream.videoRange,
    videoRangeType: stream.videoRangeType,
    channels: stream.channels,
    channelLayout: stream.channelLayout,
    audioSpatialFormat: stream.audioSpatialFormat,
    language: stream.language,
    title: stream.displayTitle ?? stream.title,
    isDefault: stream.isDefault,
    isForced: stream.isForced,
    isExternal: stream.isExternal,
    isTextSubtitleStream: stream.isTextSubtitleStream,
  );

  final String? codec;
  final String? profile;
  final int? bitDepth;
  final int? bitRate;
  final int? width;
  final int? height;
  final double? averageFrameRate;
  final double? realFrameRate;
  final String? videoRange;
  final String? videoRangeType;
  final int? channels;
  final String? channelLayout;
  final String? audioSpatialFormat;
  final String? language;
  final String? title;
  final bool? isDefault;
  final bool? isForced;
  final bool? isExternal;
  final bool? isTextSubtitleStream;
}
