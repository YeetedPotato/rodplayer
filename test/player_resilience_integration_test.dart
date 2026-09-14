import 'package:flutter_test/flutter_test.dart';

import 'fakes/test_playback_engine.dart';

void main() {
  test('PlaybackEngine exposes failures without owning retry scheduling', () async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    engine.error.value = 'network failure';
    expect(engine.error.value, 'network failure');
    expect(engine.playing.value, isFalse);
  });
}
