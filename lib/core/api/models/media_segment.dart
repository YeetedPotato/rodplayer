import 'package:rodplayer/core/playback/advanced_playback.dart';

class JellyfinMediaSegment {
  const JellyfinMediaSegment({required this.type, required this.start, required this.end, this.id, this.itemId});

  final String type;
  final Duration start;
  final Duration end;
  final String? id;
  final String? itemId;

  PlaybackMarker get marker => PlaybackMarker(kind: type, start: start, end: end);

  static JellyfinMediaSegment? fromJson(Map<String, dynamic> json) {
    final type = json['Type']?.toString().trim();
    final start = _ticks(json['StartTicks'] ?? json['StartPositionTicks']);
    final end = _ticks(json['EndTicks'] ?? json['EndPositionTicks']);
    if (type == null || type.isEmpty || start == null || end == null || start.isNegative || end <= start) return null;
    final id = json['Id']?.toString().trim();
    final itemId = json['ItemId']?.toString().trim();
    return JellyfinMediaSegment(type: type, start: start, end: end, id: id == null || id.isEmpty ? null : id, itemId: itemId == null || itemId.isEmpty ? null : itemId);
  }
}

Duration? _ticks(Object? value) {
  final ticks = value is num ? value.toInt() : int.tryParse('$value');
  return ticks == null || ticks < 0 ? null : Duration(microseconds: ticks ~/ 10);
}
