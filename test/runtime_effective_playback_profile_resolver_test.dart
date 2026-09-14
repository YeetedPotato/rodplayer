import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/runtime_effective_playback_profile_resolver.dart';

void main() {
  test('support intersection truth table', () {
    expect(RuntimeCapabilityIntersection.combine(<CapabilitySupport>[CapabilitySupport.supported, CapabilitySupport.supported]), CapabilitySupport.supported);
    expect(RuntimeCapabilityIntersection.combine(<CapabilitySupport>[CapabilitySupport.supported, CapabilitySupport.unknown]), CapabilitySupport.unknown);
    expect(RuntimeCapabilityIntersection.combine(<CapabilitySupport>[CapabilitySupport.supported, CapabilitySupport.unsupported]), CapabilitySupport.unsupported);
    expect(RuntimeCapabilityIntersection.combine(<CapabilitySupport>[CapabilitySupport.unknown, CapabilitySupport.unsupported]), CapabilitySupport.unsupported);
  });

  test('runtime resolver includes only codecs supported by backend and device', () {
    const backend = PlaybackBackendDescriptor(
      id: 'test',
      displayName: 'Test',
      availability: BackendAvailability.available,
      priority: 0,
      capabilities: PlaybackBackendCapabilities(
        id: 'test',
        name: 'Test',
        videoCodecs: <String>['h264', 'hevc'],
        audioCodecs: <String>['aac'],
        videoCodecRules: <VideoCodecCapabilityRule>[
          VideoCodecCapabilityRule(codec: 'h264'),
          VideoCodecCapabilityRule(codec: 'hevc'),
        ],
        audioCodecRules: <AudioCodecCapabilityRule>[
          AudioCodecCapabilityRule(codec: 'aac'),
        ],
      ),
    );
    final profile = const RuntimeEffectivePlaybackProfileResolver().resolve(_environment(
      compute: const ComputeCapabilities(videoCodecs: <VideoCodecComputeCapability>[
        VideoCodecComputeCapability(codec: 'h264', support: CapabilitySupport.supported),
        VideoCodecComputeCapability(codec: 'hevc', support: CapabilitySupport.unknown),
      ]),
      audio: const AudioCapabilities(engine: PlaybackEngineAudioCapabilities(decodeCodecs: <String, CapabilitySupport>{'aac': CapabilitySupport.supported})),
      backend: backend,
    ), backend);

    expect(profile.deviceProfile.videoCodecRules.map((rule) => rule.codec), <String>['h264']);
    expect(profile.deviceProfile.audioCodecRules.map((rule) => rule.codec), <String>['aac']);
  });

  test('HDR decode support does not imply HDR output', () {
    final support = const RuntimeEffectivePlaybackProfileResolver().hdrOutputSupport(
      _environment(
        compute: const ComputeCapabilities(hdrMetadataDecode: HdrDecodeCapabilities(hdr10: CapabilitySupport.supported)),
        display: const DisplayCapabilities(output: HdrOutputCapabilities(hdr10: CapabilitySupport.unknown)),
      ),
      CapabilitySupport.supported,
    );

    expect(support, CapabilitySupport.unknown);
  });

  test('audio decode support does not imply passthrough', () {
    final support = const RuntimeEffectivePlaybackProfileResolver().audioPassthroughSupport(
      _environment(
        audio: const AudioCapabilities(
          engine: PlaybackEngineAudioCapabilities(decodeCodecs: <String, CapabilitySupport>{'truehd': CapabilitySupport.supported}),
          device: DeviceAudioCapabilities(passthrough: CapabilitySupport.unknown),
          route: CurrentAudioRoute(passthrough: CapabilitySupport.unknown),
        ),
      ),
      const PlaybackBackendCapabilities(
        id: 'test',
        name: 'Test',
        audioCodecs: <String>['truehd'],
        passthrough: CapabilitySupport.supported,
      ),
      'truehd',
    );

    expect(support, CapabilitySupport.unknown);
  });

  test('legacy conservative resolver still returns media kit compatibility profile', () {
    const backend = PlaybackBackendDescriptor(
      id: 'media_kit',
      displayName: 'Default playback engine',
      availability: BackendAvailability.available,
      priority: 0,
      capabilities: ConservativePlaybackEnvironmentProvider.mediaKitCapabilities,
    );
    final profile = const LegacyConservativePlaybackProfileResolver().resolve(_environment(backend: backend), backend);

    expect(profile.deviceProfile.directPlayRules, isNotEmpty);
    expect(profile.deviceProfile.videoCodecRules, isNotEmpty);
  });
}

PlaybackEnvironment _environment({
  ComputeCapabilities compute = const ComputeCapabilities(),
  DisplayCapabilities display = const DisplayCapabilities(),
  AudioCapabilities audio = const AudioCapabilities(),
  PlaybackBackendDescriptor backend = const PlaybackBackendDescriptor(
    id: 'test',
    displayName: 'Test',
    availability: BackendAvailability.available,
    priority: 0,
    capabilities: PlaybackBackendCapabilities(id: 'test', name: 'Test'),
  ),
}) =>
    PlaybackEnvironment(
      identity: const DeviceIdentity(
        installationId: 'test',
        clientName: 'RodPlayer',
        appVersion: 'test',
        platformFamily: PlatformFamily.unknown,
        deviceName: 'Test device',
      ),
      device: const DeviceCapabilities(platformLabel: 'Test'),
      compute: compute,
      display: display,
      audio: audio,
      network: const NetworkCapabilities(),
      backends: <PlaybackBackendDescriptor>[backend],
      effectiveProfiles: const <EffectivePlaybackProfile>[],
    );
