import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/media_stream.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

/// Immutable server-derived metadata for one logical playback session.
///
/// This intentionally outlives an individual playback backend session.
class PlaybackMetadata {
  PlaybackMetadata({
    Iterable<PlaybackChapter> chapters = const <PlaybackChapter>[],
    Iterable<PlaybackMarker> markers = const <PlaybackMarker>[],
    Iterable<MediaStream> serverStreams = const <MediaStream>[],
    this.duration,
    this.mediaSourceId,
  })  : chapters = List<PlaybackChapter>.unmodifiable(chapters),
        markers = List<PlaybackMarker>.unmodifiable(markers),
        serverStreams = List<MediaStream>.unmodifiable(serverStreams);

  final List<PlaybackChapter> chapters;
  final List<PlaybackMarker> markers;
  final List<MediaStream> serverStreams;
  final Duration? duration;
  final String? mediaSourceId;

  factory PlaybackMetadata.fromPlan(PlaybackPlan plan) => _fromSource(plan.source);

  factory PlaybackMetadata.fromLibraryItem(JellyfinLibraryItem item) => PlaybackMetadata(
        chapters: _chapters(item.raw['Chapters']),
        markers: _markers(item.raw),
        serverStreams: _streams(item.raw['MediaStreams']),
      duration: item.runTime,
      );

  PlaybackMetadata mergeLibraryItem(JellyfinLibraryItem item) {
    final raw = item.raw;
    final itemChapters = raw.containsKey('Chapters') ? _chapters(raw['Chapters']) : chapters;
    final itemMarkers = raw.containsKey('MediaSegments') || raw.containsKey('Markers') ? _markers(raw) : markers;
    final itemStreams = _streams(raw['MediaStreams']);
    return PlaybackMetadata(
      chapters: itemChapters,
      markers: itemMarkers,
      serverStreams: itemStreams.isEmpty ? serverStreams : itemStreams,
      duration: item.runTime ?? duration,
      mediaSourceId: mediaSourceId,
    );
  }

  PlaybackMetadata withMediaSegments(Iterable<PlaybackMarker> values) => PlaybackMetadata(
        chapters: chapters,
        markers: _deduplicateMarkers(values),
        serverStreams: serverStreams,
        duration: duration,
        mediaSourceId: mediaSourceId,
      );

  PlaybackMetadata withPlanSource(PlaybackPlan plan) {
    final source = _fromSource(plan.source);
    return PlaybackMetadata(
      chapters: chapters.isEmpty ? source.chapters : chapters,
      markers: mediaSourceId != null && mediaSourceId != plan.source.id ? source.markers : (markers.isEmpty ? source.markers : markers),
      serverStreams: source.serverStreams.isEmpty ? serverStreams : source.serverStreams,
      duration: source.duration ?? duration,
      mediaSourceId: plan.source.id,
    );
  }

  static PlaybackMetadata _fromSource(MediaSourceInfo source) => PlaybackMetadata(
        chapters: _chapters(source.raw['Chapters']),
        markers: _markers(source.raw),
        serverStreams: source.mediaStreams,
        duration: _ticksToDuration(source.runTimeTicks),
        mediaSourceId: source.id,
      );
}

List<PlaybackChapter> _chapters(Object? value) {
  final parsed = <_ParsedChapter>[];
  for (final entry in _maps(value)) {
    final start = _ticksToDuration(entry['StartPositionTicks'] ?? entry['StartTicks']);
    if (start == null) continue;
    final end = _ticksToDuration(entry['EndPositionTicks'] ?? entry['EndTicks']);
    parsed.add(_ParsedChapter(
      title: _text(entry['Name'] ?? entry['Title']) ?? '',
      start: start,
      end: end != null && end > start ? end : null,
    ));
  }
  parsed.sort((left, right) => left.start.compareTo(right.start));
  return List<PlaybackChapter>.unmodifiable(<PlaybackChapter>[
    for (var index = 0; index < parsed.length; index += 1)
      PlaybackChapter(
        title: parsed[index].title,
        start: parsed[index].start,
        end: parsed[index].end ?? (index + 1 < parsed.length ? parsed[index + 1].start : null),
      ),
  ]);
}

List<PlaybackMarker> _markers(Map<String, dynamic> raw) {
  final parsed = <PlaybackMarker>[];
  for (final entry in <Map<String, dynamic>>[..._maps(raw['MediaSegments']), ..._maps(raw['Markers'])]) {
    final kind = _text(entry['Type'] ?? entry['Kind'] ?? entry['Name']);
    final start = _ticksToDuration(entry['StartPositionTicks'] ?? entry['StartTicks']);
    final end = _ticksToDuration(entry['EndPositionTicks'] ?? entry['EndTicks']);
    if (kind == null || start == null || end == null || start.isNegative || end <= start) continue;
    parsed.add(PlaybackMarker(kind: kind, start: start, end: end));
  }
  return List<PlaybackMarker>.unmodifiable(parsed);
}

List<PlaybackMarker> _deduplicateMarkers(Iterable<PlaybackMarker> values) {
  final seen = <String>{};
  return List<PlaybackMarker>.unmodifiable(values.where((marker) => seen.add('${marker.kind}|${marker.start.inMicroseconds}|${marker.end.inMicroseconds}')));
}

List<MediaStream> _streams(Object? value) => List<MediaStream>.unmodifiable(
      _maps(value).map(MediaStream.fromJson),
    );

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList(growable: false)
    : const <Map<String, dynamic>>[];

Duration? _ticksToDuration(Object? value) {
  final ticks = value is num ? value.toInt() : int.tryParse('$value');
  return ticks == null || ticks < 0 ? null : Duration(microseconds: ticks ~/ 10);
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

class _ParsedChapter {
  const _ParsedChapter({required this.title, required this.start, this.end});

  final String title;
  final Duration start;
  final Duration? end;
}
