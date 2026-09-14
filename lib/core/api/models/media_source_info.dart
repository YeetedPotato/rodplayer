import 'package:rodplayer/core/api/models/media_stream.dart';
import 'package:rodplayer/core/api/models/play_method.dart';

class MediaSourceInfo {
  const MediaSourceInfo({
    required this.id,
    required this.mediaStreams,
    required this.raw,
    this.container,
    this.protocol,
    this.path,
    this.directStreamUrl,
    this.transcodingUrl,
    this.supportsDirectPlay,
    this.supportsDirectStream,
    this.supportsTranscoding,
    this.defaultAudioStreamIndex,
    this.defaultSubtitleStreamIndex,
    this.bitrate,
    this.runTimeTicks,
    this.transcodingReasons = const <String>[],
    this.playMethod,
    this.videoCopied,
    this.audioCopied,
    this.containerChanged,
  });

  final String id;
  final String? container;
  final String? protocol;
  final String? path;
  final String? directStreamUrl;
  final String? transcodingUrl;
  final bool? supportsDirectPlay;
  final bool? supportsDirectStream;
  final bool? supportsTranscoding;
  final List<MediaStream> mediaStreams;
  final int? defaultAudioStreamIndex;
  final int? defaultSubtitleStreamIndex;
  final int? bitrate;
  final int? runTimeTicks;
  final List<String> transcodingReasons;
  final PlayMethod? playMethod;
  final bool? videoCopied;
  final bool? audioCopied;
  final bool? containerChanged;
  final Map<String, dynamic> raw;

  List<MediaStream> get videoStreams => mediaStreams.where((s) => s.type == 'Video').toList(growable: false);
  List<MediaStream> get audioStreams => mediaStreams.where((s) => s.type == 'Audio').toList(growable: false);
  List<MediaStream> get subtitleStreams => mediaStreams.where((s) => s.type == 'Subtitle').toList(growable: false);

  factory MediaSourceInfo.fromJson(Map<String, dynamic> json) {
    final streams = (json['MediaStreams'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((value) => MediaStream.fromJson(Map<String, dynamic>.from(value)))
        .toList(growable: false);
    return MediaSourceInfo(
      id: '${json['Id'] ?? ''}',
      container: _str(json['Container']),
      protocol: _str(json['Protocol']),
      path: _str(json['Path']),
      directStreamUrl: _str(json['DirectStreamUrl']),
      transcodingUrl: _str(json['TranscodingUrl']),
      supportsDirectPlay: _bool(json['SupportsDirectPlay']),
      supportsDirectStream: _bool(json['SupportsDirectStream']),
      supportsTranscoding: _bool(json['SupportsTranscoding']),
      mediaStreams: streams,
      defaultAudioStreamIndex: _int(json['DefaultAudioStreamIndex']),
      defaultSubtitleStreamIndex: _int(json['DefaultSubtitleStreamIndex']),
      bitrate: _int(json['Bitrate']),
      runTimeTicks: _int(json['RunTimeTicks']),
      transcodingReasons: (json['TranscodingReasons'] as List<dynamic>? ?? const <dynamic>[]).map((v) => '$v').toList(growable: false),
      playMethod: json['PlayMethod'] == null ? null : PlayMethod.fromJson(json['PlayMethod']),
      videoCopied: _bool(json['VideoStreamCopy']),
      audioCopied: _bool(json['AudioStreamCopy']),
      containerChanged: _bool(json['ContainerChanged']),
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }
}

int? _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value');
String? _str(Object? value) => value == null ? null : '$value';
bool? _bool(Object? value) => value is bool ? value : null;
