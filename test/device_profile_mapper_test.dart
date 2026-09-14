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

  test('direct play profiles are explicit compatibility families', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();
    final profile = const JellyfinDeviceProfileMapper().map(environment, environment.primaryBackend);
    final direct = (profile['DirectPlayProfiles'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(direct.length, greaterThan(2));
    expect(
      direct,
      contains(<String, dynamic>{'Container': 'webm', 'Type': 'Video', 'VideoCodec': 'vp9,av1', 'AudioCodec': 'opus,vorbis'}),
    );
    expect(
      direct.any((entry) => entry['Container'] == 'webm' && '${entry['VideoCodec']}'.contains('hevc')),
      isFalse,
    );
  });

  test('subtitle delivery comes from capability rules', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();
    final profile = const JellyfinDeviceProfileMapper().map(environment, environment.primaryBackend);
    final subtitles = (profile['SubtitleProfiles'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(subtitles, contains(<String, dynamic>{'Format': 'pgssub', 'Method': 'Embed'}));
    expect(subtitles, contains(<String, dynamic>{'Format': 'ass', 'Method': 'External'}));
  });

  test('codec profile conditions serialize when capabilities express truthful limits', () {
    const backend = PlaybackBackendCapabilities(
      id: 'test',
      name: 'test',
      directPlayRules: <DirectPlayCapabilityRule>[
        DirectPlayCapabilityRule(containers: <String>['mp4'], type: 'Video', videoCodecs: <String>['hevc'], audioCodecs: <String>['aac']),
      ],
      videoCodecRules: <VideoCodecCapabilityRule>[
        VideoCodecCapabilityRule(codec: 'hevc', codecTags: <String>['hvc1'], maxBitDepth: 10),
      ],
      subtitleRules: <SubtitleCapabilityRule>[
        SubtitleCapabilityRule(codec: 'srt', deliveryMethod: 'External'),
      ],
    );
    const environment = PlaybackEnvironment(
      device: DeviceCapabilities(platformLabel: 'Test'),
      display: DisplayCapabilities(),
      audio: AudioCapabilities(),
      network: NetworkCapabilities(maxStreamingBitrate: 42000),
      backends: <PlaybackBackendCapabilities>[backend],
    );
    final profile = const JellyfinDeviceProfileMapper().map(environment, backend);
    final codecs = (profile['CodecProfiles'] as List<dynamic>).cast<Map<String, dynamic>>();
    final hevc = codecs.singleWhere((entry) => entry['Codec'] == 'hevc');
    expect(hevc['Conditions'].toString(), contains('VideoCodecTag'));
    expect(hevc['Conditions'].toString(), contains('hvc1'));
    expect(profile['MaxStreamingBitrate'], 42000);
  });
}
