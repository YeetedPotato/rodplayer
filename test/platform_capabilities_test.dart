import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

void main() {
  test('temporary environment exposes conservative backend capabilities', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();
    expect(environment.device.platformLabel, isNot('FireTV'));
    final backend = environment.selectPreferredBackend();
    expect(backend.id, 'media_kit');
    expect(backend.availability, BackendAvailability.available);
    expect(backend.capabilities.videoCodecs, isNotEmpty);
  });

  test('unknown capability is not treated as supported', () {
    expect(CapabilitySupport.unknown.isSupported, isFalse);
    expect(CapabilitySupport.unsupported.isSupported, isFalse);
    expect(CapabilitySupport.supported.isSupported, isTrue);
    expect(CapabilitySupport.unknown, isNot(CapabilitySupport.unsupported));
  });

  test('display decode capability and output capability remain separate', () {
    const compute = ComputeCapabilities(hdrMetadataDecode: HdrDecodeCapabilities(hdr10: CapabilitySupport.supported));
    const display = DisplayCapabilities(output: HdrOutputCapabilities(hdr10: CapabilitySupport.unknown));

    expect(compute.hdrMetadataDecode.hdr10, CapabilitySupport.supported);
    expect(display.output.hdr10, CapabilitySupport.unknown);
  });

  test('audio fidelity and spatial metadata remain separate', () {
    const effectiveAudio = EffectiveAudioCapabilities(
      fidelity: CapabilitySupport.supported,
      spatialMetadata: CapabilitySupport.unsupported,
      lossless: CapabilitySupport.supported,
      objectAudio: CapabilitySupport.unsupported,
      channelLayout: '7.1 PCM',
      maxChannels: 8,
    );

    expect(effectiveAudio.fidelity, CapabilitySupport.supported);
    expect(effectiveAudio.spatialMetadata, CapabilitySupport.unsupported);
    expect(effectiveAudio.lossless, CapabilitySupport.supported);
    expect(effectiveAudio.objectAudio, CapabilitySupport.unsupported);
  });

  test('backend capabilities can be queried without server-brand conditionals', () {
    final backend = const ConservativePlaybackEnvironmentProvider().loadBackend();
    expect(backend.supportsContainer('mkv'), isTrue);
    expect(backend.supportsVideoCodec('h264'), isTrue);
    expect(backend.supportsAudioCodec('aac'), isTrue);
    expect(backend.videoCodecSupport('h264'), CapabilitySupport.supported);
    expect(backend.videoCodecSupport('mpeg2video'), CapabilitySupport.unknown);
    expect(backend.passthrough, CapabilitySupport.unknown);
  });

  test('backend codec support distinguishes supported unsupported and unknown', () {
    const backend = PlaybackBackendCapabilities(
      id: 'test',
      name: 'Test',
      videoCodecs: <String>['h264'],
      audioCodecs: <String>['aac'],
      unsupportedVideoCodecs: <String>['vc1'],
      unsupportedAudioCodecs: <String>['truehd'],
    );

    expect(backend.videoCodecSupport('h264'), CapabilitySupport.supported);
    expect(backend.videoCodecSupport('vc1'), CapabilitySupport.unsupported);
    expect(backend.videoCodecSupport('av1'), CapabilitySupport.unknown);
    expect(backend.audioCodecSupport('aac'), CapabilitySupport.supported);
    expect(backend.audioCodecSupport('truehd'), CapabilitySupport.unsupported);
    expect(backend.audioCodecSupport('dts'), CapabilitySupport.unknown);
  });

  test('unavailable first backend is not selected', () {
    const selected = PlaybackBackendDescriptor(
      id: 'available',
      displayName: 'Available',
      availability: BackendAvailability.available,
      priority: 10,
      capabilities: PlaybackBackendCapabilities(id: 'available', name: 'Available'),
    );
    final backend = const PlaybackBackendSelector().select(const <PlaybackBackendDescriptor>[
      PlaybackBackendDescriptor(
        id: 'unavailable',
        displayName: 'Unavailable',
        availability: BackendAvailability.unavailable,
        priority: 0,
        capabilities: PlaybackBackendCapabilities(id: 'unavailable', name: 'Unavailable'),
      ),
      selected,
    ]);

    expect(backend, selected);
  });

  test('priority affects backend selection with lower values preferred', () {
    final backend = const PlaybackBackendSelector().select(const <PlaybackBackendDescriptor>[
      PlaybackBackendDescriptor(
        id: 'slow',
        displayName: 'Slow',
        availability: BackendAvailability.available,
        priority: 20,
        capabilities: PlaybackBackendCapabilities(id: 'slow', name: 'Slow'),
      ),
      PlaybackBackendDescriptor(
        id: 'fast',
        displayName: 'Fast',
        availability: BackendAvailability.available,
        priority: 5,
        capabilities: PlaybackBackendCapabilities(id: 'fast', name: 'Fast'),
      ),
    ]);

    expect(backend.id, 'fast');
  });

  test('backend selection tie is deterministic by backend id', () {
    final backend = const PlaybackBackendSelector().select(const <PlaybackBackendDescriptor>[
      PlaybackBackendDescriptor(
        id: 'z-backend',
        displayName: 'Z',
        availability: BackendAvailability.available,
        priority: 0,
        capabilities: PlaybackBackendCapabilities(id: 'z-backend', name: 'Z'),
      ),
      PlaybackBackendDescriptor(
        id: 'a-backend',
        displayName: 'A',
        availability: BackendAvailability.available,
        priority: 0,
        capabilities: PlaybackBackendCapabilities(id: 'a-backend', name: 'A'),
      ),
    ]);

    expect(backend.id, 'a-backend');
  });

  test('no available backend produces explicit selection failure', () {
    expect(
      () => const PlaybackBackendSelector().select(const <PlaybackBackendDescriptor>[
        PlaybackBackendDescriptor(
          id: 'unknown',
          displayName: 'Unknown',
          availability: BackendAvailability.unknown,
          priority: 0,
          capabilities: PlaybackBackendCapabilities(id: 'unknown', name: 'Unknown'),
        ),
        PlaybackBackendDescriptor(
          id: 'unavailable',
          displayName: 'Unavailable',
          availability: BackendAvailability.unavailable,
          priority: 0,
          capabilities: PlaybackBackendCapabilities(id: 'unavailable', name: 'Unavailable'),
        ),
      ]),
      throwsA(isA<PlaybackBackendSelectionException>()),
    );
  });

  test('effective capability profile is derived from backend and environment', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();
    final profile = environment.effectiveProfiles.single;

    final backend = environment.selectPreferredBackend();
    expect(profile.backendId, backend.capabilities.id);
    expect(profile.capabilities, same(backend.capabilities));
    expect(profile.deviceProfile.maxStreamingBitrate, environment.network.maxStreamingBitrate);
    expect(profile.deviceProfile.directPlayRules, backend.capabilities.directPlayRules);
  });

  test('environment reuses persistent installation identity when supplied', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider(
      identity: InstallationIdentity(
        deviceId: 'install-1',
        clientName: 'RodPlayer',
        deviceName: 'Living room PC',
        appVersion: '1.2.3',
      ),
    ).load();

    expect(environment.identity.installationId, 'install-1');
    expect(environment.identity.clientName, 'RodPlayer');
    expect(environment.identity.deviceName, 'Living room PC');
    expect(environment.identity.appVersion, '1.2.3');
    expect(environment.identity.isSynthetic, isFalse);
  });

  test('environment fallback identity is explicit synthetic placeholder', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();

    expect(environment.identity.installationId, 'unknown');
    expect(environment.identity.isSynthetic, isTrue);
  });
}
