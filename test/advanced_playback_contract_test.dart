import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_metadata.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/media_kit_advanced_playback_controls.dart';
import 'package:rodplayer/core/player/track_controller.dart';

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

  test('session synchronizes logical metadata without transferring ownership', () {
    final advanced = _FakeAdvancedControls();
    final session = PlaybackRuntimeSession(runtimeId: 'test', plan: _plan(), engine: TestPlaybackEngine(), advanced: advanced);
    final metadata = PlaybackMetadata(chapters: <PlaybackChapter>[const PlaybackChapter(title: 'Opening', start: Duration.zero)], markers: <PlaybackMarker>[const PlaybackMarker(kind: 'Intro', start: Duration.zero, end: Duration(seconds: 10))]);

    session.synchronizeMetadata(metadata);

    expect(advanced.chapters.value.single.title, 'Opening');
    expect(advanced.markers.value.single.kind, 'Intro');
  });

  test('optional metadata synchronization failures do not escape', () {
    final advanced = _ThrowingMetadataControls();
    final session = PlaybackRuntimeSession(
      runtimeId: 'test',
      plan: _plan(),
      engine: TestPlaybackEngine(),
      advanced: advanced,
    );
    final metadata = PlaybackMetadata(
      chapters: <PlaybackChapter>[
        const PlaybackChapter(title: 'Opening', start: Duration.zero),
      ],
      markers: <PlaybackMarker>[
        const PlaybackMarker(
          kind: 'Intro',
          start: Duration.zero,
          end: Duration(seconds: 10),
        ),
      ],
    );

    expect(() => session.synchronizeMetadata(metadata), returnsNormally);
    expect(advanced.chaptersCalled, isTrue);
    expect(advanced.markersCalled, isTrue);
  });
  test('runtimes without controls are explicitly advanced-unsupported', () {
    final session = PlaybackRuntimeSession(runtimeId: 'native', plan: _plan(), engine: TestPlaybackEngine());

    expect(session.advanced, isNull);
    expect(session.advancedCapabilities.playbackRate, CapabilitySupport.unsupported);
    expect(session.advancedCapabilities.audioTrackSwitching, CapabilitySupport.unsupported);
    expect(session.advancedCapabilities.diagnostics, CapabilitySupport.unsupported);
  });

  test('effective track capabilities come only from the active track controller', () {
    final session = PlaybackRuntimeSession(
      runtimeId: 'test',
      plan: _plan(),
      engine: TestPlaybackEngine(),
      advanced: _FakeAdvancedControls(),
      tracks: _FakeTracks(const TrackSelectionCapabilities(
        audioSelection: CapabilitySupport.unknown,
        subtitleSelection: CapabilitySupport.supported,
      )),
    );

    expect(session.advancedCapabilities.audioTrackSwitching, CapabilitySupport.unknown);
    expect(session.advancedCapabilities.subtitleTrackSwitching, CapabilitySupport.supported);
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
    expect(controls, isNot(contains('hr-seek')));
  });

  test('media kit controls confirm only successful runtime operations', () async {
    final backend = _FakeMediaKitAdvancedBackend();
    final controls = MediaKitAdvancedPlaybackControls.forTesting(backend);

    expect(controls.capabilities.playbackRate, CapabilitySupport.supported);
    expect(controls.capabilities.audioDelay, CapabilitySupport.unknown);
    expect(controls.capabilities.subtitleDelay, CapabilitySupport.unknown);

    await controls.setRate(3);
    await controls.adjustAudioDelay(const Duration(milliseconds: -250));
    await controls.adjustSubtitleDelay(const Duration(milliseconds: 1250));

    expect(backend.rates, <double>[2]);
    expect(backend.properties, <String, String>{'audio-delay': '-0.25', 'sub-delay': '1.25'});
    expect(controls.rate.value, 2);
    expect(controls.audioDelay.value, const Duration(milliseconds: -250));
    expect(controls.subtitleDelay.value, const Duration(milliseconds: 1250));
    expect(controls.capabilities.playbackRate, CapabilitySupport.supported);
    expect(controls.capabilities.audioDelay, CapabilitySupport.supported);
    expect(controls.capabilities.subtitleDelay, CapabilitySupport.supported);
  });

  test('media kit control failures retain state and unknown capability truth', () async {
    final backend = _FakeMediaKitAdvancedBackend(failProperties: true, failRates: true);
    final controls = MediaKitAdvancedPlaybackControls.forTesting(backend);

    await expectLater(controls.setRate(1.5), throwsStateError);
    await expectLater(controls.adjustAudioDelay(const Duration(milliseconds: 500)), throwsStateError);
    await expectLater(controls.adjustSubtitleDelay(const Duration(milliseconds: 500)), throwsStateError);

    expect(controls.rate.value, 1);
    expect(controls.audioDelay.value, Duration.zero);
    expect(controls.subtitleDelay.value, Duration.zero);
    expect(controls.capabilities.playbackRate, CapabilitySupport.supported);
    expect(controls.capabilities.audioDelay, CapabilitySupport.unknown);
    expect(controls.capabilities.subtitleDelay, CapabilitySupport.unknown);
  });

  test('media kit uses one-shot exact and keyframe seek commands', () async {
    final backend = _FakeMediaKitAdvancedBackend();
    final controls = MediaKitAdvancedPlaybackControls.forTesting(backend);
    controls.setChapters(<PlaybackChapter>[const PlaybackChapter(title: 'Part', start: Duration(seconds: 8))]);

    await controls.seekToChapter(0);
    await controls.seekFast(const Duration(milliseconds: 1500));

    expect(backend.commands, <List<String>>[
      <String>['seek', '8.0', 'absolute+exact'],
      <String>['seek', '1.5', 'absolute+keyframes'],
    ]);
    expect(controls.capabilities.accurateSeek, CapabilitySupport.supported);
    expect(controls.capabilities.fastSeek, CapabilitySupport.supported);
    expect(controls.capabilities.chapterNavigation, CapabilitySupport.supported);
  });

  test('failed fast seek remains unknown and never mutates persistent seek settings', () async {
    final backend = _FakeMediaKitAdvancedBackend(failCommands: true);
    final controls = MediaKitAdvancedPlaybackControls.forTesting(backend);

    await expectLater(controls.seekFast(const Duration(seconds: 3)), throwsStateError);

    expect(controls.capabilities.fastSeek, CapabilitySupport.unknown);
    expect(backend.properties, isEmpty);
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
  final ValueNotifier<double> rate = ValueNotifier<double>(1);
  @override
  final ValueNotifier<Duration> audioDelay = ValueNotifier<Duration>(Duration.zero);
  @override
  final ValueNotifier<Duration> subtitleDelay = ValueNotifier<Duration>(Duration.zero);
  @override
  final ValueNotifier<List<PlaybackChapter>> chapters = ValueNotifier<List<PlaybackChapter>>(<PlaybackChapter>[]);
  @override
  final ValueNotifier<List<PlaybackMarker>> markers = ValueNotifier<List<PlaybackMarker>>(<PlaybackMarker>[]);

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

class _ThrowingMetadataControls extends _FakeAdvancedControls {
  bool chaptersCalled = false;
  bool markersCalled = false;

  @override
  void setChapters(Iterable<PlaybackChapter> values) {
    chaptersCalled = true;
    throw StateError('chapter metadata unavailable');
  }

  @override
  void setMarkers(Iterable<PlaybackMarker> values) {
    markersCalled = true;
    throw StateError('marker metadata unavailable');
  }
}
class _FakeTracks extends TrackSelectionController {
  _FakeTracks(this.capabilities);

  @override
  final TrackSelectionCapabilities capabilities;
  @override
  List<RodPlayerTrack> get audioTracks => const <RodPlayerTrack>[];
  @override
  List<RodPlayerTrack> get subtitleTracks => const <RodPlayerTrack>[];
  @override
  RodPlayerTrack? get selectedAudio => null;
  @override
  RodPlayerTrack? get selectedSubtitle => null;
  @override
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track) async => const TrackSwitchResult(mode: TrackSwitchMode.serverRenegotiation);
  @override
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track) async => const TrackSwitchResult(mode: TrackSwitchMode.serverRenegotiation);
}

class _FakeMediaKitAdvancedBackend implements MediaKitAdvancedPlaybackBackend {
  _FakeMediaKitAdvancedBackend({this.failRates = false, this.failProperties = false, this.failCommands = false});

  final bool failRates;
  final bool failProperties;
  final bool failCommands;
  final List<double> rates = <double>[];
  final Map<String, String> properties = <String, String>{};
  final List<List<String>> commands = <List<String>>[];

  @override
  Duration get position => Duration.zero;

  @override
  Future<void> command(List<String> arguments) async {
    if (failCommands) throw StateError('command failed');
    commands.add(arguments);
  }

  @override
  Future<void> setProperty(String name, String value) async {
    if (failProperties) throw StateError('property failed');
    properties[name] = value;
  }

  @override
  Future<void> setRate(double value) async {
    if (failRates) throw StateError('rate failed');
    rates.add(value);
  }
}
