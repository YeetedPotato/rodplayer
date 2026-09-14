import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/player/player_controller.dart';

void main() {
  test('dispose cancels subscriptions and disposes state notifiers', () async {
    final engine = MediaKitPlaybackEngine();
    final playingValues = <bool>[];
    final bufferingValues = <bool>[];
    final errors = <String?>[];
    engine.playing.addListener(() => playingValues.add(engine.playing.value));
    engine.buffering.addListener(() => bufferingValues.add(engine.buffering.value));
    engine.error.addListener(() => errors.add(engine.error.value));
    await engine.dispose();
    await engine.dispose();
    expect(() => engine.playing.value = true, throwsA(isA<FlutterError>()));
    expect(() => engine.buffering.value = true, throwsA(isA<FlutterError>()));
    expect(() => engine.error.value = 'after dispose', throwsA(isA<FlutterError>()));
    expect(playingValues, isEmpty);
    expect(bufferingValues, isEmpty);
    expect(errors, isEmpty);
  });
}
