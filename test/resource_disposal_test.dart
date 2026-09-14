import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/test_playback_engine.dart';

void main() {
  test('dispose releases fake engine state notifiers', () async {
    final engine = TestPlaybackEngine();
    await engine.dispose();
    await engine.dispose();
    expect(() => engine.playing.value = true, throwsA(isA<FlutterError>()));
    expect(() => engine.buffering.value = true, throwsA(isA<FlutterError>()));
    expect(() => engine.error.value = 'after dispose', throwsA(isA<FlutterError>()));
  });
}
