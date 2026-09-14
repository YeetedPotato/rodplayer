import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

void main() {
  test('temporary environment exposes conservative backend capabilities', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();
    expect(environment.device.platformLabel, isNot('FireTV'));
    expect(environment.primaryBackend.id, 'media_kit');
    expect(environment.primaryBackend.availability, BackendAvailability.available);
    expect(environment.primaryBackend.capabilities.videoCodecs, isNotEmpty);
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
    expect(backend.passthrough, CapabilitySupport.unknown);
  });

  test('effective capability profile is derived from backend and environment', () async {
    final environment = await const ConservativePlaybackEnvironmentProvider().load();
    final profile = environment.effectiveProfiles.single;

    expect(profile.backendId, environment.primaryBackend.capabilities.id);
    expect(profile.capabilities, same(environment.primaryBackend.capabilities));
    expect(profile.deviceProfile.maxStreamingBitrate, environment.network.maxStreamingBitrate);
    expect(profile.deviceProfile.directPlayRules, environment.primaryBackend.capabilities.directPlayRules);
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
  });
}
