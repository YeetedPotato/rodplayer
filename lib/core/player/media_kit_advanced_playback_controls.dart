import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

/// Backend-private operations used by media_kit advanced controls.
///
/// This seam keeps libmpv access out of the generic advanced-playback
/// contract and permits deterministic control tests without a native player.
abstract interface class MediaKitAdvancedPlaybackBackend {
  Duration get position;

  Future<void> setRate(double value);
  Future<void> setProperty(String name, String value);
  Future<void> command(List<String> arguments);
}

class _PlayerBackend implements MediaKitAdvancedPlaybackBackend {
  _PlayerBackend(this._player);

  final Player _player;

  @override
  Duration get position => _player.state.position;

  @override
  Future<void> setRate(double value) => _player.setRate(value);

  @override
  Future<void> setProperty(String name, String value) async {
    final dynamic platform = _player.platform;
    if (platform == null) {
      throw StateError('media_kit does not expose an mpv property host');
    }
    await platform.setProperty(name, value);
  }

  @override
  Future<void> command(List<String> arguments) async {
    final dynamic platform = _player.platform;
    if (platform == null) {
      throw StateError('media_kit does not expose an mpv command host');
    }
    await platform.command(arguments);
  }
}

/// media_kit/mpv implementation of [AdvancedPlaybackControls].
///
/// Direct mpv operations start as unknown. A successful operation confirms
/// only that control for the active runtime; failures are propagated and do
/// not turn an unknown capability into a claim.
class MediaKitAdvancedPlaybackControls implements AdvancedPlaybackControls {
  MediaKitAdvancedPlaybackControls(Player player) : _backend = _PlayerBackend(player);

  @visibleForTesting
  MediaKitAdvancedPlaybackControls.forTesting(this._backend);

  final MediaKitAdvancedPlaybackBackend _backend;

  AdvancedPlaybackCapabilities _capabilities = const AdvancedPlaybackCapabilities(
    playbackRate: CapabilitySupport.unknown,
    audioDelay: CapabilitySupport.unknown,
    subtitleDelay: CapabilitySupport.unknown,
    subtitleStyling: CapabilitySupport.unknown,
    chapterNavigation: CapabilitySupport.unknown,
    accurateSeek: CapabilitySupport.unknown,
    fastSeek: CapabilitySupport.unknown,
    markerAwareness: CapabilitySupport.unknown,
    diagnostics: CapabilitySupport.unsupported,
  );

  @override
  AdvancedPlaybackCapabilities get capabilities => _capabilities;

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

  void _confirm({
    CapabilitySupport? playbackRate,
    CapabilitySupport? audioDelay,
    CapabilitySupport? subtitleDelay,
    CapabilitySupport? subtitleStyling,
    CapabilitySupport? chapterNavigation,
    CapabilitySupport? accurateSeek,
    CapabilitySupport? fastSeek,
  }) {
    _capabilities = _capabilities.copyWith(
      playbackRate: playbackRate,
      audioDelay: audioDelay,
      subtitleDelay: subtitleDelay,
      subtitleStyling: subtitleStyling,
      chapterNavigation: chapterNavigation,
      accurateSeek: accurateSeek,
      fastSeek: fastSeek,
    );
  }

  String _seconds(Duration value) => (value.inMicroseconds / Duration.microsecondsPerSecond).toString();

  @override
  Future<void> setRate(double value) async {
    final clamped = value.clamp(0.5, 2.0).toDouble();
    await _backend.setRate(clamped);
    rate.value = clamped;
    _confirm(playbackRate: CapabilitySupport.supported);
  }

  @override
  Future<void> adjustAudioDelay(Duration value) async {
    await _backend.setProperty('audio-delay', _seconds(value));
    audioDelay.value = value;
    _confirm(audioDelay: CapabilitySupport.supported);
  }

  @override
  Future<void> adjustSubtitleDelay(Duration value) async {
    await _backend.setProperty('sub-delay', _seconds(value));
    subtitleDelay.value = value;
    _confirm(subtitleDelay: CapabilitySupport.supported);
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
      await _backend.setProperty(entry.key, entry.value);
    }
    if (properties.isNotEmpty) {
      _confirm(subtitleStyling: CapabilitySupport.supported);
    }
  }

  @override
  void setChapters(Iterable<PlaybackChapter> values) => chapters.value = List<PlaybackChapter>.unmodifiable(values);

  @override
  void setMarkers(Iterable<PlaybackMarker> values) => markers.value = List<PlaybackMarker>.unmodifiable(values);

  @override
  Future<void> seekToChapter(int index) async {
    if (index >= 0 && index < chapters.value.length) {
      await seekAccurate(chapters.value[index].start);
      _confirm(chapterNavigation: CapabilitySupport.supported);
    }
  }

  @override
  Future<void> nextChapter() async {
    final next = chapters.value.firstWhere(
      (chapter) => chapter.start > _backend.position,
      orElse: () => chapters.value.isEmpty ? const PlaybackChapter(title: '', start: Duration.zero) : chapters.value.last,
    );
    if (next.title.isNotEmpty) {
      await seekAccurate(next.start);
      _confirm(chapterNavigation: CapabilitySupport.supported);
    }
  }

  @override
  Future<void> previousChapter() async {
    final prior = chapters.value.where((chapter) => chapter.start < _backend.position - const Duration(seconds: 2)).toList();
    if (prior.isNotEmpty) {
      await seekAccurate(prior.last.start);
      _confirm(chapterNavigation: CapabilitySupport.supported);
    }
  }

  @override
  Future<void> seekAccurate(Duration position) async {
    await _backend.command(<String>['seek', _seconds(position), 'absolute+exact']);
    _confirm(accurateSeek: CapabilitySupport.supported);
  }

  @override
  Future<void> seekFast(Duration position) async {
    await _backend.command(<String>['seek', _seconds(position), 'absolute+keyframes']);
    _confirm(fastSeek: CapabilitySupport.supported);
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
