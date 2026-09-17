import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';

import 'fakes/test_playback_engine.dart';

void main() {
  test('advanced capabilities preserve partial and unknown support', () {
    const capabilities = AdvancedPlaybackCapabilities(
      playbackRate: CapabilitySupport.supported,
      subtitleStyling: CapabilitySupport.unknown,
      diagnostics: CapabilitySupport.unsupported,
    );

    expect(capabilities.playbackRate, CapabilitySupport.supported);
    expect(capabilities.subtitleStyling, CapabilitySupport.unknown);
    expect(capabilities.diagnostics, CapabilitySupport.unsupported);
  });

  test('session exposes its active backend advanced controls', () async {
    final engine = TestPlaybackEngine();
    final advanced = _FakeAdvancedControls();
    final session = PlaybackRuntimeSession(
      runtimeId: 'test',
      plan: _plan(),
      engine: engine,
      advanced: advanced,
    );

    expect(session.advanced, same(advanced));
    expect(session.advancedCapabilities.playbackRate, CapabilitySupport.supported);
    await session.dispose();
    await session.dispose();
    expect(engine.disposed, isTrue);
  });

  test('runtimes without controls are explicitly advanced-unsupported', () {
    final session = PlaybackRuntimeSession(runtimeId: 'native', plan: _plan(), engine: TestPlaybackEngine());

    expect(session.advanced, isNull);
    expect(session.advancedCapabilities.playbackRate, CapabilitySupport.unsupported);
    expect(session.advancedCapabilities.audioTrackSwitching, CapabilitySupport.unsupported);
    expect(session.advancedCapabilities.diagnostics, CapabilitySupport.unsupported);
  });

  test('generic contract and player UI boundary do not import media_kit', () {
    final contract = File('lib/core/playback/advanced_playback.dart').readAsStringSync();
    final playerView = File('lib/ui/player/video_player_view.dart').readAsStringSync();

    expect(contract, isNot(contains('package:media_kit')));
    expect(playerView, isNot(contains('package:media_kit')));
  });

  test('media kit runtime wires generic controls into its session', () {
    final runtime = File('lib/core/player/player_controller.dart').readAsStringSync();
    final controls = File('lib/core/player/media_kit_advanced_playback_controls.dart').readAsStringSync();

    expect(runtime, contains('advanced: engine.advanced'));
    expect(controls, contains('implements AdvancedPlaybackControls'));
    expect(controls, contains('CapabilitySupport.unknown'));
  });
}

PlaybackPlan _plan() => PlaybackPlan(
      itemId: 'item',
      mediaSourceId: 'source',
      playSessionId: 'session',
      playMethod: PlayMethod.directPlay,
      playbackUri: Uri.parse('https://server/media'),
      engineId: 'test',
      source: MediaSourceInfo.fromJson(<String, dynamic>{'Id': 'source', 'MediaStreams': <dynamic>[]}),
    );

class _FakeAdvancedControls implements AdvancedPlaybackControls {
  @override
  final capabilities = const AdvancedPlaybackCapabilities(
    playbackRate: CapabilitySupport.supported,
    accurateSeek: CapabilitySupport.supported,
  );
  @override
  final rate = ValueNotifier<double>(1);
  @override
  final audioDelay = ValueNotifier<Duration>(Duration.zero);
  @override
  final subtitleDelay = ValueNotifier<Duration>(Duration.zero);
  @override
  final chapters = ValueNotifier<List<PlaybackChapter>>(<PlaybackChapter>[]);
  @override
  final markers = ValueNotifier<List<PlaybackMarker>>(<PlaybackMarker>[]);

  @override
  Future<void> adjustAudioDelay(Duration value) async => audioDelay.value = value;
  @override
  Future<void> adjustSubtitleDelay(Duration value) async => subtitleDelay.value = value;
  @override
  PlaybackMarker? markerAt(Duration position) => null;
  @override
  Future<void> nextChapter() async {}
  @override
  Future<void> previousChapter() async {}
  @override
  Future<void> seekAccurate(Duration position) async {}
  @override
  Future<void> seekFast(Duration position) async {}
  @override
  Future<void> seekToChapter(int index) async {}
  @override
  void setChapters(Iterable<PlaybackChapter> values) => chapters.value = List<PlaybackChapter>.unmodifiable(values);
  @override
  Future<void> setRate(double value) async => rate.value = value;
  @override
  void setMarkers(Iterable<PlaybackMarker> values) => markers.value = List<PlaybackMarker>.unmodifiable(values);
  @override
  Future<void> setSubtitleStyle(SubtitleStyle style) async {}
}
