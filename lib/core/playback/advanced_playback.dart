import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

class PlaybackChapter {
  const PlaybackChapter({required this.title, required this.start, this.end});

  final String title;
  final Duration start;
  final Duration? end;

  factory PlaybackChapter.fromMap(Map<String, Object?> map) {
    final rawStart = map['start'] ?? map['startTime'];
    final start = rawStart is Duration
        ? rawStart
        : Duration(milliseconds: ((rawStart as num?)?.toDouble() ?? 0) * 1000 ~/ 1);
    final rawEnd = map['end'] ?? map['endTime'];
    return PlaybackChapter(
      title: (map['title'] ?? map['name'] ?? 'Chapter').toString(),
      start: start,
      end: rawEnd == null
          ? null
          : (rawEnd is Duration
              ? rawEnd
              : Duration(milliseconds: ((rawEnd as num).toDouble() * 1000).round())),
    );
  }
}

class PlaybackMarker {
  const PlaybackMarker({required this.kind, required this.start, required this.end});

  final String kind;
  final Duration start;
  final Duration end;
}

class SubtitleStyle {
  const SubtitleStyle({
    this.fontSize,
    this.fontFamily,
    this.color,
    this.backgroundColor,
    this.margin,
    this.position,
  });

  final double? fontSize;
  final String? fontFamily;
  final String? color;
  final String? backgroundColor;
  final double? margin;
  final double? position;
}

/// Truthful feature support for one active playback runtime.
///
/// This is runtime-scoped: callers must not infer support from a platform or
/// backend identifier. [unknown] remains distinct from [unsupported].
class AdvancedPlaybackCapabilities {
  const AdvancedPlaybackCapabilities({
    this.playbackRate = CapabilitySupport.unsupported,
    this.audioDelay = CapabilitySupport.unsupported,
    this.subtitleDelay = CapabilitySupport.unsupported,
    this.subtitleStyling = CapabilitySupport.unsupported,
    this.chapterNavigation = CapabilitySupport.unsupported,
    this.accurateSeek = CapabilitySupport.unsupported,
    this.fastSeek = CapabilitySupport.unsupported,
    this.audioTrackSwitching = CapabilitySupport.unsupported,
    this.subtitleTrackSwitching = CapabilitySupport.unsupported,
    this.markerAwareness = CapabilitySupport.unsupported,
    this.diagnostics = CapabilitySupport.unsupported,
  });

  const AdvancedPlaybackCapabilities.unavailable()
      : playbackRate = CapabilitySupport.unsupported,
        audioDelay = CapabilitySupport.unsupported,
        subtitleDelay = CapabilitySupport.unsupported,
        subtitleStyling = CapabilitySupport.unsupported,
        chapterNavigation = CapabilitySupport.unsupported,
        accurateSeek = CapabilitySupport.unsupported,
        fastSeek = CapabilitySupport.unsupported,
        audioTrackSwitching = CapabilitySupport.unsupported,
        subtitleTrackSwitching = CapabilitySupport.unsupported,
        markerAwareness = CapabilitySupport.unsupported,
        diagnostics = CapabilitySupport.unsupported;

  final CapabilitySupport playbackRate;
  final CapabilitySupport audioDelay;
  final CapabilitySupport subtitleDelay;
  final CapabilitySupport subtitleStyling;
  final CapabilitySupport chapterNavigation;
  final CapabilitySupport accurateSeek;
  final CapabilitySupport fastSeek;
  final CapabilitySupport audioTrackSwitching;
  final CapabilitySupport subtitleTrackSwitching;
  final CapabilitySupport markerAwareness;
  final CapabilitySupport diagnostics;

  AdvancedPlaybackCapabilities withTrackSelection({
    required CapabilitySupport audioTrackSwitching,
    required CapabilitySupport subtitleTrackSwitching,
  }) =>
      AdvancedPlaybackCapabilities(
        playbackRate: playbackRate,
        audioDelay: audioDelay,
        subtitleDelay: subtitleDelay,
        subtitleStyling: subtitleStyling,
        chapterNavigation: chapterNavigation,
        accurateSeek: accurateSeek,
        fastSeek: fastSeek,
        audioTrackSwitching: audioTrackSwitching,
        subtitleTrackSwitching: subtitleTrackSwitching,
        markerAwareness: markerAwareness,
        diagnostics: diagnostics,
      );

  AdvancedPlaybackCapabilities copyWith({
    CapabilitySupport? playbackRate,
    CapabilitySupport? audioDelay,
    CapabilitySupport? subtitleDelay,
    CapabilitySupport? subtitleStyling,
    CapabilitySupport? chapterNavigation,
    CapabilitySupport? accurateSeek,
    CapabilitySupport? fastSeek,
    CapabilitySupport? audioTrackSwitching,
    CapabilitySupport? subtitleTrackSwitching,
    CapabilitySupport? markerAwareness,
    CapabilitySupport? diagnostics,
  }) =>
      AdvancedPlaybackCapabilities(
        playbackRate: playbackRate ?? this.playbackRate,
        audioDelay: audioDelay ?? this.audioDelay,
        subtitleDelay: subtitleDelay ?? this.subtitleDelay,
        subtitleStyling: subtitleStyling ?? this.subtitleStyling,
        chapterNavigation: chapterNavigation ?? this.chapterNavigation,
        accurateSeek: accurateSeek ?? this.accurateSeek,
        fastSeek: fastSeek ?? this.fastSeek,
        audioTrackSwitching: audioTrackSwitching ?? this.audioTrackSwitching,
        subtitleTrackSwitching: subtitleTrackSwitching ?? this.subtitleTrackSwitching,
        markerAwareness: markerAwareness ?? this.markerAwareness,
        diagnostics: diagnostics ?? this.diagnostics,
      );
}

/// Optional runtime-level controls beyond the small [PlaybackEngine] transport
/// contract. The runtime owns these controls; callers must not dispose them.
abstract interface class AdvancedPlaybackControls {
  AdvancedPlaybackCapabilities get capabilities;

  ValueListenable<double> get rate;
  ValueListenable<Duration> get audioDelay;
  ValueListenable<Duration> get subtitleDelay;
  ValueListenable<List<PlaybackChapter>> get chapters;
  ValueListenable<List<PlaybackMarker>> get markers;

  Future<void> setRate(double value);
  Future<void> adjustAudioDelay(Duration value);
  Future<void> adjustSubtitleDelay(Duration value);
  Future<void> setSubtitleStyle(SubtitleStyle style);
  void setChapters(Iterable<PlaybackChapter> values);
  void setMarkers(Iterable<PlaybackMarker> values);
  Future<void> seekToChapter(int index);
  Future<void> nextChapter();
  Future<void> previousChapter();
  Future<void> seekAccurate(Duration position);
  Future<void> seekFast(Duration position);
  PlaybackMarker? markerAt(Duration position);
}
