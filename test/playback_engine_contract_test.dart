import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/player/player_controller.dart';

void main() {
  setUpAll(MediaKit.ensureInitialized);

  test('media_kit backend implements generic PlaybackEngine contract', () {
    final engine = MediaKitPlaybackEngine();
    addTearDown(engine.dispose);
    expect(engine, isA<PlaybackEngine>());
    expect(engine.id, 'media_kit');
  });
}
