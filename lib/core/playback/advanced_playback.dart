import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

class PlaybackChapter {
  const PlaybackChapter({required this.title, required this.start, this.end});
  final String title;
  final Duration start;
  final Duration? end;

  factory PlaybackChapter.fromMap(Map<String, Object?> map) {
    final rawStart = map['start'] ?? map['startTime'];
    final start = rawStart is Duration ? rawStart : Duration(milliseconds: ((rawStart as num?)?.toDouble() ?? 0) * 1000 ~/ 1);
    final rawEnd = map['end'] ?? map['endTime'];
    return PlaybackChapter(title: (map['title'] ?? map['name'] ?? 'Chapter').toString(), start: start, end: rawEnd == null ? null : (rawEnd is Duration ? rawEnd : Duration(milliseconds: ((rawEnd as num).toDouble() * 1000).round())));
  }
}

class PlaybackMarker {
  const PlaybackMarker({required this.kind, required this.start, required this.end});
  final String kind;
  final Duration start;
  final Duration end;
}

class SubtitleStyle {
  const SubtitleStyle({this.fontSize, this.fontFamily, this.color, this.backgroundColor, this.margin, this.position});
  final double? fontSize;
  final String? fontFamily;
  final String? color;
  final String? backgroundColor;
  final double? margin;
  final double? position;
}

/// Platform-neutral advanced playback facade. mpv properties are applied via
/// media_kit and remain safe to call on web and native targets.
class AdvancedPlaybackController {
  AdvancedPlaybackController(this.player);
  final Player player;
  final ValueNotifier<double> rate = ValueNotifier<double>(1.0);
  final ValueNotifier<Duration> audioDelay = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> subtitleDelay = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<List<PlaybackChapter>> chapters = ValueNotifier<List<PlaybackChapter>>(<PlaybackChapter>[]);
  final ValueNotifier<List<PlaybackMarker>> markers = ValueNotifier<List<PlaybackMarker>>(<PlaybackMarker>[]);

  Future<void> _setProperty(String name, String value) async {
    try {
      final dynamic platform = player.platform;
      await platform.setProperty(name, value);
    } catch (_) {
      // Platform does not support direct mpv property manipulation or web.
    }
  }

  Future<void> setRate(double value) async {
    rate.value = value.clamp(0.5, 2.0).toDouble();
    await player.setRate(rate.value);
  }

  Future<void> adjustAudioDelay(Duration value) async {
    audioDelay.value = value;
    await _setProperty('audio-delay', '${value.inMicroseconds / Duration.microsecondsPerSecond}');
  }

  Future<void> adjustSubtitleDelay(Duration value) async {
    subtitleDelay.value = value;
    await _setProperty('sub-delay', '${value.inMicroseconds / Duration.microsecondsPerSecond}');
  }

  Future<void> setSubtitleStyle(SubtitleStyle style) async {
    final properties = <String, String>{
      if (style.fontSize != null) 'sub-font-size': '${style.fontSize}',
      if (style.fontFamily != null) 'sub-font': style.fontFamily!,
      if (style.color != null) 'sub-color': style.color!,
      if (style.backgroundColor != null) 'sub-back-color': style.backgroundColor!,
      if (style.margin != null) 'sub-margin-y': '${style.margin}',
      if (style.position != null) 'sub-pos': '${style.position}',
    };
    for (final entry in properties.entries) { await _setProperty(entry.key, entry.value); }
  }
  void setChapters(Iterable<PlaybackChapter> values) => chapters.value = List<PlaybackChapter>.unmodifiable(values);
  void setMarkers(Iterable<PlaybackMarker> values) => markers.value = List<PlaybackMarker>.unmodifiable(values);
  Future<void> seekToChapter(int index) async { if (index >= 0 && index < chapters.value.length) await player.seek(chapters.value[index].start); }
  Future<void> nextChapter() async { final current = player.state.position; final next = chapters.value.firstWhere((chapter) => chapter.start > current, orElse: () => chapters.value.isEmpty ? const PlaybackChapter(title: '', start: Duration.zero) : chapters.value.last); if (next.title.isNotEmpty) await player.seek(next.start); }
  Future<void> previousChapter() async { final current = player.state.position; final prior = chapters.value.where((chapter) => chapter.start < current - const Duration(seconds: 2)).toList(); if (prior.isNotEmpty) await player.seek(prior.last.start); }
  Future<void> seekAccurate(Duration position) => player.seek(position);
  Future<void> seekFast(Duration position) async { await _setProperty('hr-seek', 'no'); await player.seek(position); }
  PlaybackMarker? markerAt(Duration position) { for (final marker in markers.value) { if (position >= marker.start && position < marker.end) return marker; } return null; }
  void dispose() { rate.dispose(); audioDelay.dispose(); subtitleDelay.dispose(); chapters.dispose(); markers.dispose(); }
}
