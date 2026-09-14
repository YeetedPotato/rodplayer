import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/player/player_controller.dart';

void main() {
  group('MediaKitPlaybackEngine resilience integration contract', () {
    late MediaKitPlaybackEngine engine;
    setUp(() {
      engine = MediaKitPlaybackEngine();
    });
    tearDown(() => engine.dispose());

    test('engine reports errors but does not schedule competing retry loops', () async {
      engine.error.value = 'network failure';
      expect(engine.error.value, 'network failure');
      await expectLater(engine.retryCurrent(), completion(isFalse));
    });
  });
}
