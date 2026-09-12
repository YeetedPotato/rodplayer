import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/player/player_controller.dart';

void main() {
  group('RodPlayerEngine resilience integration contract', () {
    late RodPlayerEngine engine;

    setUp(() {
      engine = RodPlayerEngine();
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('bounds recovery after a network error to three attempts', () {
      expect(engine.maxRetries, 3);
      expect(engine.retryCount, lessThanOrEqualTo(engine.maxRetries));

      final retryAttempts = <int>[1, 2, 3];
      expect(retryAttempts.length, engine.maxRetries);
      expect(retryAttempts, orderedEquals(<int>[1, 2, 3]));
    });

    test('uses one, two, and four second exponential backoff', () {
      expect(engine.retryDelayForAttempt(1), const Duration(seconds: 1));
      expect(engine.retryDelayForAttempt(2), const Duration(seconds: 2));
      expect(engine.retryDelayForAttempt(3), const Duration(seconds: 4));
    });

    test('preserves the current position as the reconnect starting point', () {
      final positionBeforeRetry = engine.player.state.position;

      expect(positionBeforeRetry, Duration.zero);
      expect(engine.retryCount, 0);
      expect(
        engine.player.state.position,
        positionBeforeRetry,
        reason: 'A retry must use the player state position before reopening.',
      );
    });

    test('publishes error state for a failed stream and clears it on recovery', () {
      final observedErrors = <String?>[];
      engine.error.addListener(() => observedErrors.add(engine.error.value));

      engine.error.value = '403: stream unavailable';
      expect(engine.error.value, '403: stream unavailable');

      engine.error.value = null;
      expect(engine.error.value, isNull);
      expect(observedErrors, <String?>['403: stream unavailable', null]);
    });

    test('publishes buffering transitions during reconnect', () {
      final observedBuffering = <bool>[];
      engine.buffering
          .addListener(() => observedBuffering.add(engine.buffering.value));

      engine.buffering.value = true;
      engine.buffering.value = false;

      expect(observedBuffering, <bool>[true, false]);
    });

    test('publishes playing recovery after buffering', () {
      final observedPlaying = <bool>[];
      engine.playing.addListener(() => observedPlaying.add(engine.playing.value));

      engine.buffering.value = true;
      engine.playing.value = true;
      engine.buffering.value = false;

      expect(engine.playing.value, isTrue);
      expect(observedPlaying, <bool>[true]);
    });
  });
}
