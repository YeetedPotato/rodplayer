import 'dart:math' as math;

class MediaIntelligence {
  const MediaIntelligence({this.video, this.audio, this.subtitle, this.width, this.height, this.bitrate, this.durationTicks});
  final StreamIntelligence? video, audio, subtitle;
  final int? width, height, bitrate, durationTicks;

  factory MediaIntelligence.fromJson(Map<String, dynamic> json) {
    final streams = (json['MediaStreams'] ?? json['Streams'] ?? const <dynamic>[]) as List<dynamic>;
    StreamIntelligence? pick(String type) { for (final raw in streams) { final s = StreamIntelligence.fromJson(raw as Map<String, dynamic>); if (s.type == type) return s; } return null; }
    return MediaIntelligence(video: pick('Video'), audio: pick('Audio'), subtitle: pick('Subtitle'), width: _int(json['Width']), height: _int(json['Height']), bitrate: _int(json['Bitrate']), durationTicks: _int(json['RunTimeTicks']));
  }

  String get resolution => width == null || height == null ? 'Unknown' : '${width}x$height';
  bool get is4K => math.max(width ?? 0, height ?? 0) >= 2160;
  String get summary => [resolution, video?.displayCodec, video?.displayHdr, audio?.displayAudio].where((v) => v != null && v != 'Unknown').join(' • ');
}

class StreamIntelligence {
  const StreamIntelligence({required this.type, this.codec, this.profile, this.videoRange, this.videoRangeType, this.bitDepth, this.channels, this.channelLayout, this.audioSpatialFormat, this.localizedCodec, this.localizedDisplayTitle});
  final String type;
  final String? codec, profile, videoRange, videoRangeType, localizedCodec, localizedDisplayTitle, channelLayout, audioSpatialFormat;
  final int? bitDepth, channels;

  factory StreamIntelligence.fromJson(Map<String, dynamic> j) => StreamIntelligence(type: '${j['Type'] ?? ''}', codec: _str(j['Codec']), profile: _str(j['Profile']), videoRange: _str(j['VideoRange']), videoRangeType: _str(j['VideoRangeType']), bitDepth: _int(j['BitDepth']), channels: _int(j['Channels']), channelLayout: _str(j['ChannelLayout']), audioSpatialFormat: _str(j['AudioSpatialFormat']), localizedCodec: _str(j['LocalizedCodec']), localizedDisplayTitle: _str(j['DisplayTitle']));

  String get displayCodec {
    final c = (codec ?? localizedCodec ?? '').toLowerCase();
    if (c == 'hevc' || c == 'h265') return 'HEVC';
    if (c == 'av1') return 'AV1';
    if (c == 'avc' || c == 'h264') return 'H.264';
    return localizedDisplayTitle ?? localizedCodec ?? codec ?? 'Unknown';
  }

  String get displayHdr {
    final p = '${profile ?? ''} ${videoRange ?? ''} ${videoRangeType ?? ''}'.toLowerCase();
    if (p.contains('dolby') || p.contains('dv') || p.contains('dovi')) return 'Dolby Vision${profile == null ? '' : ' $profile'}';
    if (p.contains('hdr10+') || p.contains('hdr10plus')) return 'HDR10+';
    if (p.contains('hdr10')) return 'HDR10';
    if (p.contains('hlg')) return 'HLG';
    if (p.contains('hdr')) return 'HDR';
    return 'SDR';
  }

  String get displayAudio {
    final text = '${codec ?? ''} ${profile ?? ''} ${audioSpatialFormat ?? ''} ${localizedDisplayTitle ?? ''}'.toLowerCase();
    final name = text.contains('truehd') ? 'TrueHD' : text.contains('atmos') ? 'Atmos' : text.contains('dts:x') ? 'DTS:X' : text.contains('dts-hd') ? 'DTS-HD MA' : text.contains('flac') ? 'FLAC' : (codec ?? 'Audio');
    final layout = channelLayout ?? (channels == 8 ? '7.1' : channels == 6 ? '5.1' : channels == null ? null : '$channels ch');
    return layout == null ? name : '$name $layout';
  }
}

int? _int(dynamic value) => value is num ? value.toInt() : int.tryParse('$value');
String? _str(dynamic value) => value == null ? null : '$value';
