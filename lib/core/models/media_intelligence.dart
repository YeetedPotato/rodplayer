import 'dart:math' as math;

import 'package:rodplayer/core/api/models/media_stream.dart';

class MediaIntelligence {
  const MediaIntelligence({
    this.streams = const <StreamIntelligence>[],
    this.width,
    this.height,
    this.bitrate,
    this.durationTicks,
  });

  final List<StreamIntelligence> streams;
  final int? width, height, bitrate, durationTicks;

  List<StreamIntelligence> get videoStreams => streams.where((s) => s.type == 'Video').toList(growable: false);
  List<StreamIntelligence> get audioStreams => streams.where((s) => s.type == 'Audio').toList(growable: false);
  List<StreamIntelligence> get subtitleStreams => streams.where((s) => s.type == 'Subtitle').toList(growable: false);
  StreamIntelligence? get video => _firstOrNull(videoStreams);
  StreamIntelligence? get audio => audioStreams.firstWhere((s) => s.isDefault == true, orElse: () => _firstOrNull(audioStreams) ?? StreamIntelligence.empty);
  StreamIntelligence? get subtitle => subtitleStreams.firstWhere((s) => s.isDefault == true, orElse: () => _firstOrNull(subtitleStreams) ?? StreamIntelligence.empty);

  factory MediaIntelligence.fromJson(Map<String, dynamic> json) {
    final values = (json['MediaStreams'] ?? json['Streams'] ?? const <dynamic>[]) as List<dynamic>? ?? const <dynamic>[];
    return MediaIntelligence(
      streams: values.whereType<Map>().map((raw) => StreamIntelligence.fromMediaStream(MediaStream.fromJson(Map<String, dynamic>.from(raw)))).toList(growable: false),
      width: _int(json['Width']),
      height: _int(json['Height']),
      bitrate: _int(json['Bitrate']),
      durationTicks: _int(json['RunTimeTicks']),
    );
  }

  String get resolution => width == null || height == null ? 'Unknown' : '${width}x$height';
  bool get is4K => math.max(width ?? 0, height ?? 0) >= 2160;
  String get summary => [resolution, video?.displayCodec, video?.displayHdr, audio?.displayAudio].where((v) => v != null && v != 'Unknown').join(' • ');
}

enum AudioCodecFamily { trueHd, dts, flac, aac, ac3, eac3, opus, other }
enum AudioDetailedFormat { trueHd, dtsHdMa, dts, flac, aac, ac3, eac3, opus, other }
enum SpatialFormat { atmos, dtsX, none }

class StreamIntelligence {
  const StreamIntelligence({
    required this.type,
    this.index,
    this.codec,
    this.profile,
    this.videoRange,
    this.videoRangeType,
    this.bitDepth,
    this.channels,
    this.channelLayout,
    this.audioSpatialFormat,
    this.language,
    this.title,
    this.displayTitle,
    this.isDefault,
    this.isForced,
    this.isExternal,
  });

  static const empty = StreamIntelligence(type: '');

  final String type;
  final int? index;
  final String? codec, profile, videoRange, videoRangeType, channelLayout, audioSpatialFormat, language, title, displayTitle;
  final int? bitDepth, channels;
  final bool? isDefault, isForced, isExternal;

  factory StreamIntelligence.fromMediaStream(MediaStream stream) => StreamIntelligence(
        type: stream.type,
        index: stream.index,
        codec: stream.codec,
        profile: stream.profile,
        videoRange: stream.videoRange,
        videoRangeType: stream.videoRangeType,
        bitDepth: stream.bitDepth,
        channels: stream.channels,
        channelLayout: stream.channelLayout,
        audioSpatialFormat: stream.audioSpatialFormat,
        language: stream.language,
        title: stream.title,
        displayTitle: stream.displayTitle,
        isDefault: stream.isDefault,
        isForced: stream.isForced,
        isExternal: stream.isExternal,
      );

  String get displayCodec {
    final c = (codec ?? '').toLowerCase();
    if (c == 'hevc' || c == 'h265' || c == 'h.265') return 'HEVC';
    if (c == 'av1') return 'AV1';
    if (c == 'avc' || c == 'h264' || c == 'h.264') return 'H.264';
    return displayTitle ?? codec ?? 'Unknown';
  }

  String get displayHdr {
    final p = '${profile ?? ''} ${videoRange ?? ''} ${videoRangeType ?? ''}'.toLowerCase();
    if (p.contains('dolby') || p.contains('dovi')) return 'Dolby Vision${profile == null ? '' : ' $profile'}';
    if (p.contains('hdr10+') || p.contains('hdr10plus')) return 'HDR10+';
    if (p.contains('hdr10')) return 'HDR10';
    if (p.contains('hlg')) return 'HLG';
    if (p.contains('hdr')) return 'HDR';
    return 'SDR';
  }

  AudioCodecFamily get codecFamily {
    final text = _audioText;
    if (text.contains('truehd')) return AudioCodecFamily.trueHd;
    if (text.contains('dts')) return AudioCodecFamily.dts;
    if (text.contains('flac')) return AudioCodecFamily.flac;
    if (text.contains('eac3')) return AudioCodecFamily.eac3;
    if (text.contains('ac3')) return AudioCodecFamily.ac3;
    if (text.contains('aac')) return AudioCodecFamily.aac;
    if (text.contains('opus')) return AudioCodecFamily.opus;
    return AudioCodecFamily.other;
  }

  AudioDetailedFormat get detailedFormat {
    final text = _audioText;
    if (text.contains('truehd')) return AudioDetailedFormat.trueHd;
    if (text.contains('dts-hd') || text.contains('dts hd')) return AudioDetailedFormat.dtsHdMa;
    if (text.contains('dts')) return AudioDetailedFormat.dts;
    if (text.contains('flac')) return AudioDetailedFormat.flac;
    if (text.contains('eac3')) return AudioDetailedFormat.eac3;
    if (text.contains('ac3')) return AudioDetailedFormat.ac3;
    if (text.contains('aac')) return AudioDetailedFormat.aac;
    if (text.contains('opus')) return AudioDetailedFormat.opus;
    return AudioDetailedFormat.other;
  }

  SpatialFormat get spatialFormat {
    final text = _audioText;
    if (text.contains('atmos')) return SpatialFormat.atmos;
    if (text.contains('dts:x') || text.contains('dtsx')) return SpatialFormat.dtsX;
    return SpatialFormat.none;
  }

  String get displayAudio {
    final name = switch (detailedFormat) {
      AudioDetailedFormat.trueHd => 'TrueHD',
      AudioDetailedFormat.dtsHdMa => 'DTS-HD MA',
      AudioDetailedFormat.dts => 'DTS',
      AudioDetailedFormat.flac => 'FLAC',
      AudioDetailedFormat.eac3 => 'E-AC-3',
      AudioDetailedFormat.ac3 => 'AC-3',
      AudioDetailedFormat.aac => 'AAC',
      AudioDetailedFormat.opus => 'Opus',
      AudioDetailedFormat.other => codec ?? 'Audio',
    };
    final spatial = spatialFormat == SpatialFormat.atmos ? ' Atmos' : spatialFormat == SpatialFormat.dtsX ? ' DTS:X' : '';
    final layout = channelLayout ?? (channels == 8 ? '7.1' : channels == 6 ? '5.1' : channels == null ? null : '$channels ch');
    return layout == null ? '$name$spatial' : '$name$spatial $layout';
  }

  String get _audioText => '${codec ?? ''} ${profile ?? ''} ${audioSpatialFormat ?? ''} ${displayTitle ?? ''}'.toLowerCase();
}

int? _int(dynamic value) => value is num ? value.toInt() : int.tryParse('$value');
T? _firstOrNull<T>(List<T> values) => values.isEmpty ? null : values.first;
