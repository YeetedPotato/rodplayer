import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/jellyfin_device_profile_mapper.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

void main() {
  test('serializes Jellyfin DeviceProfile structures without backend branding', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();
    final profile = const JellyfinDeviceProfileMapper().map(environment, environment.primaryBackend.capabilities);
    expect(profile['Name'], 'RodPlayer');
    expect(profile.containsKey('DirectPlayProfiles'), isTrue);
    expect(profile.containsKey('TranscodingProfiles'), isTrue);
    expect(profile.containsKey('CodecProfiles'), isTrue);
    expect(profile.containsKey('SubtitleProfiles'), isTrue);
    expect(profile.toString().toLowerCase(), isNot(contains('remux')));
  });

  test('direct play profiles are explicit compatibility families', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();
    final profile = const JellyfinDeviceProfileMapper().map(environment, environment.primaryBackend.capabilities);
    final direct = (profile['DirectPlayProfiles'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(direct.length, greaterThan(2));
    expect(
      direct.any((entry) => entry['Container'] == 'webm' && entry['Type'] == 'Video' && entry['VideoCodec'] == 'vp9,av1' && entry['AudioCodec'] == 'opus,vorbis'),
      isTrue,
    );
    expect(
      direct.any((entry) => entry['Container'] == 'webm' && '${entry['VideoCodec']}'.contains('hevc')),
      isFalse,
    );
  });

  test('subtitle delivery comes from capability rules', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();
    final profile = const JellyfinDeviceProfileMapper().map(environment, environment.primaryBackend.capabilities);
    final subtitles = (profile['SubtitleProfiles'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(subtitles.any((entry) => entry['Format'] == 'pgssub' && entry['Method'] == 'Embed'), isTrue);
    expect(subtitles.any((entry) => entry['Format'] == 'ass' && entry['Method'] == 'External'), isTrue);
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
      identity: DeviceIdentity(
        installationId: 'test-installation',
        clientName: 'RodPlayer',
        appVersion: 'test',
        platformFamily: PlatformFamily.unknown,
        deviceName: 'Test device',
      ),
      device: DeviceCapabilities(platformLabel: 'Test'),
      compute: ComputeCapabilities(),
      display: DisplayCapabilities(),
      audio: AudioCapabilities(),
      network: NetworkCapabilities(maxStreamingBitrate: 42000),
      backends: <PlaybackBackendDescriptor>[
        PlaybackBackendDescriptor(
          id: 'test',
          displayName: 'Test',
          availability: BackendAvailability.available,
          priority: 0,
          capabilities: backend,
        ),
      ],
      effectiveProfiles: <EffectivePlaybackProfile>[
        EffectivePlaybackProfile(
          backendId: 'test',
          capabilities: backend,
          deviceProfile: EffectiveDeviceProfile(
            maxStreamingBitrate: 42000,
            directPlayRules: <DirectPlayCapabilityRule>[
              DirectPlayCapabilityRule(containers: <String>['mp4'], type: 'Video', videoCodecs: <String>['hevc'], audioCodecs: <String>['aac']),
            ],
            transcodingRules: <TranscodingCapabilityRule>[],
            videoCodecRules: <VideoCodecCapabilityRule>[
              VideoCodecCapabilityRule(codec: 'hevc', codecTags: <String>['hvc1'], maxBitDepth: 10),
            ],
            audioCodecRules: <AudioCodecCapabilityRule>[],
            subtitleRules: <SubtitleCapabilityRule>[
              SubtitleCapabilityRule(codec: 'srt', deliveryMethod: 'External'),
            ],
          ),
        ),
      ],
    );
    final profile = const JellyfinDeviceProfileMapper().map(environment, backend);
    final codecs = (profile['CodecProfiles'] as List<dynamic>).cast<Map<String, dynamic>>();
    final hevc = codecs.singleWhere((entry) => entry['Codec'] == 'hevc');
    expect(hevc['Conditions'].toString(), contains('VideoCodecTag'));
    expect(hevc['Conditions'].toString(), contains('hvc1'));
    expect(profile['MaxStreamingBitrate'], 42000);
  });
}
