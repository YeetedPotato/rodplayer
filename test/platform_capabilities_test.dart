import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

void main() {
  test('temporary environment exposes conservative backend capabilities', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();
    expect(environment.device.platformLabel, isNot('FireTV'));
    expect(environment.primaryBackend.id, 'media_kit');
    expect(environment.primaryBackend.videoCodecs, isNotEmpty);
  });
}
