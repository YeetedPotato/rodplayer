import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/player/player_controller.dart';

PlaybackEngine acceptsPlaybackEngine(MediaKitPlaybackEngine engine) => engine;

void main() {
  test('media_kit backend is assignable to generic PlaybackEngine contract', () {
    expect(acceptsPlaybackEngine, isA<PlaybackEngine Function(MediaKitPlaybackEngine)>());
  });
}
