import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/player/player_controller.dart';

void main() {
  group('MediaKitPlaybackEngine', () {
    setUpAll(MediaKit.ensureInitialized);

    test('starts with the default playback state', () {
      final engine = MediaKitPlaybackEngine();
      addTearDown(engine.dispose);
      expect(engine.playing.value, isFalse);
      expect(engine.buffering.value, isFalse);
      expect(engine.error.value, isNull);
    });

    test('exposes the resilience-focused mpv properties', () {
      // TODO(phase-2): make these PlaybackEnvironment/backend/output-dependent.
      expect(MediaKitPlaybackEngine.mpvProperties['cache'], 'yes');
      expect(MediaKitPlaybackEngine.mpvProperties['network-timeout'], '15');
      expect(MediaKitPlaybackEngine.mpvProperties['demuxer-max-bytes'], '512MiB');
      expect(MediaKitPlaybackEngine.mpvProperties['demuxer-max-back-bytes'], '256MiB');
    });

    test('configures passthrough and libass subtitle fallback', () {
      // TODO(phase-2): make passthrough/subtitle behavior depend on environment capabilities.
      expect(MediaKitPlaybackEngine.mpvProperties['audio-spdif'], 'ac3,eac3,dts,dts-hd,truehd');
      expect(MediaKitPlaybackEngine.mpvProperties['audio-passthrough'], 'yes');
      expect(MediaKitPlaybackEngine.mpvProperties['audio-fallback-to-null'], 'no');
      expect(MediaKitPlaybackEngine.mpvProperties['sub-auto'], 'fuzzy');
      expect(MediaKitPlaybackEngine.mpvProperties['sub-ass'], 'yes');
      expect(MediaKitPlaybackEngine.mpvProperties['sub-forced'], 'yes');
    });

    test('provides platform-safe effective mpv properties', () {
      expect(MediaKitPlaybackEngine.effectiveMpvProperties['audio-device'], anyOf(isNull, 'auto'));
      expect(MediaKitPlaybackEngine.effectiveMpvProperties['sub-auto'], 'fuzzy');
    });

    test('engine exposes reload primitive without owning retry schedule', () async {
      final engine = MediaKitPlaybackEngine();
      addTearDown(engine.dispose);
      expect(engine.player.state.position, Duration.zero);
      await expectLater(engine.retryCurrent(), completion(isFalse));
    });

    test('final failure remains observable through the error notifier', () {
      final engine = MediaKitPlaybackEngine();
      addTearDown(engine.dispose);
      engine.error.value = 'retry attempts exhausted';
      expect(engine.error.value, 'retry attempts exhausted');
    });

    test('state notifiers accept playback and buffering updates', () {
      final engine = MediaKitPlaybackEngine();
      addTearDown(engine.dispose);
      final playingValues = <bool>[];
      final bufferingValues = <bool>[];
      engine.playing.addListener(() => playingValues.add(engine.playing.value));
      engine.buffering.addListener(() => bufferingValues.add(engine.buffering.value));
      engine.playing.value = true;
      engine.buffering.value = true;
      engine.playing.value = false;
      engine.buffering.value = false;
      expect(playingValues, <bool>[true, false]);
      expect(bufferingValues, <bool>[true, false]);
    });

    test('error notifier can represent and clear a retry failure', () {
      final engine = MediaKitPlaybackEngine();
      addTearDown(engine.dispose);
      engine.error.value = 'network failure';
      expect(engine.error.value, 'network failure');
      engine.error.value = null;
      expect(engine.error.value, isNull);
    });
  });
}
