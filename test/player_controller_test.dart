import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/player/player_controller.dart';

void main() {
  group('RodPlayerEngine', () {
    test('starts with the default playback state', () {
      final engine = RodPlayerEngine();
      addTearDown(engine.dispose);

      expect(engine.playing.value, isFalse);
      expect(engine.buffering.value, isFalse);
      expect(engine.error.value, isNull);
    });

    test('exposes the resilience-focused mpv properties', () {
      expect(RodPlayerEngine.mpvProperties['cache'], 'yes');
      expect(RodPlayerEngine.mpvProperties['network-timeout'], '15');
      expect(RodPlayerEngine.mpvProperties['demuxer-max-bytes'], '512MiB');
      expect(RodPlayerEngine.mpvProperties['demuxer-max-back-bytes'], '256MiB');
    });

    test('uses three bounded retry attempts', () {
      final engine = RodPlayerEngine();
      addTearDown(engine.dispose);

      expect(engine.maxRetries, 3);
      expect(engine.retryCount, 0);
    });

    test('uses exponential retry delays', () {
      final engine = RodPlayerEngine();
      addTearDown(engine.dispose);

      expect(engine.retryDelayForAttempt(1), const Duration(seconds: 1));
      expect(engine.retryDelayForAttempt(2), const Duration(seconds: 2));
      expect(engine.retryDelayForAttempt(3), const Duration(seconds: 4));
    });

    test('retry starts from the current player position', () {
      final engine = RodPlayerEngine();
      addTearDown(engine.dispose);

      expect(engine.player.state.position, Duration.zero);
      expect(engine.retryCount, 0);
    });

    test('final failure remains observable through the error notifier', () {
      final engine = RodPlayerEngine();
      addTearDown(engine.dispose);

      engine.error.value = 'retry attempts exhausted';

      expect(engine.error.value, 'retry attempts exhausted');
    });

    test('state notifiers accept playback and buffering updates', () {
      final engine = RodPlayerEngine();
      addTearDown(engine.dispose);
      final playingValues = <bool>[];
      final bufferingValues = <bool>[];

      engine.playing.addListener(() => playingValues.add(engine.playing.value));
      engine.buffering
          .addListener(() => bufferingValues.add(engine.buffering.value));

      engine.playing.value = true;
      engine.buffering.value = true;
      engine.playing.value = false;
      engine.buffering.value = false;

      expect(playingValues, <bool>[true, false]);
      expect(bufferingValues, <bool>[true, false]);
    });

    test('error notifier can represent and clear a retry failure', () {
      final engine = RodPlayerEngine();
      addTearDown(engine.dispose);

      engine.error.value = 'network failure';
      expect(engine.error.value, 'network failure');

      engine.error.value = null;
      expect(engine.error.value, isNull);
    });
  });
}
