class MediaStream {
  const MediaStream({
    required this.index,
    required this.type,
    required this.raw,
    this.codec,
    this.profile,
    this.level,
    this.bitDepth,
    this.bitRate,
    this.width,
    this.height,
    this.averageFrameRate,
    this.realFrameRate,
    this.videoRange,
    this.videoRangeType,
    this.codecTag,
    this.channels,
    this.channelLayout,
    this.audioSpatialFormat,
    this.language,
    this.title,
    this.displayTitle,
    this.isDefault,
    this.isForced,
    this.isExternal,
    this.isTextSubtitleStream,
    this.deliveryUrl,
  });

  final int? index;
  final String type;
  final String? codec;
  final String? profile;
  final int? level;
  final int? bitDepth;
  final int? bitRate;
  final int? width;
  final int? height;
  final double? averageFrameRate;
  final double? realFrameRate;
  final String? videoRange;
  final String? videoRangeType;
  final String? codecTag;
  final int? channels;
  final String? channelLayout;
  final String? audioSpatialFormat;
  final String? language;
  final String? title;
  final String? displayTitle;
  final bool? isDefault;
  final bool? isForced;
  final bool? isExternal;
  final bool? isTextSubtitleStream;
  final String? deliveryUrl;
  final Map<String, dynamic> raw;

  factory MediaStream.fromJson(Map<String, dynamic> json) => MediaStream(
        index: _int(json['Index']),
        type: '${json['Type'] ?? ''}',
        codec: _str(json['Codec']),
        profile: _str(json['Profile']),
        level: _int(json['Level']),
        bitDepth: _int(json['BitDepth']),
        bitRate: _int(json['BitRate'] ?? json['Bitrate']),
        width: _int(json['Width']),
        height: _int(json['Height']),
        averageFrameRate: _double(json['AverageFrameRate']),
        realFrameRate: _double(json['RealFrameRate']),
        videoRange: _str(json['VideoRange']),
        videoRangeType: _str(json['VideoRangeType']),
        codecTag: _str(json['CodecTag']),
        channels: _int(json['Channels']),
        channelLayout: _str(json['ChannelLayout']),
        audioSpatialFormat: _str(json['AudioSpatialFormat']),
        language: _str(json['Language']),
        title: _str(json['Title']),
        displayTitle: _str(json['DisplayTitle']),
        isDefault: _bool(json['IsDefault']),
        isForced: _bool(json['IsForced']),
        isExternal: _bool(json['IsExternal']),
        isTextSubtitleStream: _bool(json['IsTextSubtitleStream']),
        deliveryUrl: _str(json['DeliveryUrl']),
        raw: Map<String, dynamic>.unmodifiable(json),
      );

  Map<String, dynamic> toJson() => raw;
}

int? _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value');
double? _double(Object? value) => value is num ? value.toDouble() : double.tryParse('$value');
String? _str(Object? value) => value == null ? null : '$value';
bool? _bool(Object? value) => value is bool ? value : null;
