import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/jellyfin_device_profile_mapper.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

void main() {
  test('serializes Jellyfin DeviceProfile structures without backend branding', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();
    final profile = const JellyfinDeviceProfileMapper().map(environment, environment.primaryBackend);
    expect(profile['Name'], 'RodPlayer');
    expect(profile.containsKey('DirectPlayProfiles'), isTrue);
    expect(profile.containsKey('TranscodingProfiles'), isTrue);
    expect(profile.containsKey('CodecProfiles'), isTrue);
    expect(profile.containsKey('SubtitleProfiles'), isTrue);
    expect(profile.toString().toLowerCase(), isNot(contains('remux')));
  });
}
