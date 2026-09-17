import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

/// media_kit/mpv implementation of [AdvancedPlaybackControls].
///
/// mpv property writes can be unavailable on a particular host, so those
/// features intentionally remain [CapabilitySupport.unknown].
class MediaKitAdvancedPlaybackControls implements AdvancedPlaybackControls {
  MediaKitAdvancedPlaybackControls(this.player);

  final Player player;

  @override
  final AdvancedPlaybackCapabilities capabilities = const AdvancedPlaybackCapabilities(
    playbackRate: CapabilitySupport.supported,
    audioDelay: CapabilitySupport.unknown,
    subtitleDelay: CapabilitySupport.unknown,
    subtitleStyling: CapabilitySupport.unknown,
    chapterNavigation: CapabilitySupport.supported,
    accurateSeek: CapabilitySupport.supported,
    fastSeek: CapabilitySupport.unknown,
    audioTrackSwitching: CapabilitySupport.supported,
    subtitleTrackSwitching: CapabilitySupport.supported,
    markerAwareness: CapabilitySupport.unknown,
    diagnostics: CapabilitySupport.unsupported,
  );

  @override
  final ValueNotifier<double> rate = ValueNotifier<double>(1.0);
  @override
  final ValueNotifier<Duration> audioDelay = ValueNotifier<Duration>(Duration.zero);
  @override
  final ValueNotifier<Duration> subtitleDelay = ValueNotifier<Duration>(Duration.zero);
  @override
  final ValueNotifier<List<PlaybackChapter>> chapters = ValueNotifier<List<PlaybackChapter>>(<PlaybackChapter>[]);
  @override
  final ValueNotifier<List<PlaybackMarker>> markers = ValueNotifier<List<PlaybackMarker>>(<PlaybackMarker>[]);

  Future<void> _setProperty(String name, String value) async {
    try {
      final dynamic platform = player.platform;
      await platform.setProperty(name, value);
    } catch (_) {
      // The active media_kit host may not expose direct mpv properties.
    }
  }

  @override
  Future<void> setRate(double value) async {
    rate.value = value.clamp(0.5, 2.0).toDouble();
    await player.setRate(rate.value);
  }

  @override
  Future<void> adjustAudioDelay(Duration value) async {
    audioDelay.value = value;
    await _setProperty('audio-delay', '${value.inMicroseconds / Duration.microsecondsPerSecond}');
  }

  @override
  Future<void> adjustSubtitleDelay(Duration value) async {
    subtitleDelay.value = value;
    await _setProperty('sub-delay', '${value.inMicroseconds / Duration.microsecondsPerSecond}');
  }

  @override
  Future<void> setSubtitleStyle(SubtitleStyle style) async {
    final properties = <String, String>{
      if (style.fontSize != null) 'sub-font-size': '${style.fontSize}',
      if (style.fontFamily != null) 'sub-font': style.fontFamily!,
      if (style.color != null) 'sub-color': style.color!,
      if (style.backgroundColor != null) 'sub-back-color': style.backgroundColor!,
      if (style.margin != null) 'sub-margin-y': '${style.margin}',
      if (style.position != null) 'sub-pos': '${style.position}',
    };
    for (final entry in properties.entries) {
      await _setProperty(entry.key, entry.value);
    }
  }

  @override
  void setChapters(Iterable<PlaybackChapter> values) => chapters.value = List<PlaybackChapter>.unmodifiable(values);

  @override
  void setMarkers(Iterable<PlaybackMarker> values) => markers.value = List<PlaybackMarker>.unmodifiable(values);

  @override
  Future<void> seekToChapter(int index) async {
    if (index >= 0 && index < chapters.value.length) await player.seek(chapters.value[index].start);
  }

  @override
  Future<void> nextChapter() async {
    final current = player.state.position;
    final next = chapters.value.firstWhere(
      (chapter) => chapter.start > current,
      orElse: () => chapters.value.isEmpty ? const PlaybackChapter(title: '', start: Duration.zero) : chapters.value.last,
    );
    if (next.title.isNotEmpty) await player.seek(next.start);
  }

  @override
  Future<void> previousChapter() async {
    final current = player.state.position;
    final prior = chapters.value.where((chapter) => chapter.start < current - const Duration(seconds: 2)).toList();
    if (prior.isNotEmpty) await player.seek(prior.last.start);
  }

  @override
  Future<void> seekAccurate(Duration position) => player.seek(position);

  @override
  Future<void> seekFast(Duration position) async {
    await _setProperty('hr-seek', 'no');
    await player.seek(position);
  }

  @override
  PlaybackMarker? markerAt(Duration position) {
    for (final marker in markers.value) {
      if (position >= marker.start && position < marker.end) return marker;
    }
    return null;
  }

  void dispose() {
    rate.dispose();
    audioDelay.dispose();
    subtitleDelay.dispose();
    chapters.dispose();
    markers.dispose();
  }
}
