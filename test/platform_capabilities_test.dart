import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/platform_capabilities.dart';

void main() {
  test('profiles use Remux branding and avoid AV1', () {
    for (final profile in PlatformProfile.values) {
      final capabilities = DeviceCapabilities.forProfile(profile);
      final json = capabilities.toDeviceProfile();
      expect(json['Name'], startsWith('Remux '));
      expect(capabilities.videoCodecs, isNot(contains('av1')));
      expect(json['DirectPlayProfiles'], isNotEmpty);
      expect(json['SubtitleProfiles'], isNotEmpty);
      expect(json['TranscodingProfiles'], isNotEmpty);
    }
  });

  test('current profile generates a bitrate', () {
    expect(DeviceCapabilities.currentDeviceProfile()['MaxStreamingBitrate'], greaterThan(0));
  });
}
