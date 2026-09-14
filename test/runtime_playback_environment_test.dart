import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';

void main() {
  test('runtime provider composes independent probes', () async {
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      computeProbe: const _ComputeProbe(ComputeCapabilities(hardwareVideoDecoding: CapabilitySupport.unknown)),
      displayProbe: const _DisplayProbe(DisplayCapabilities(currentWidth: 1920, currentHeight: 1080, pixelRatio: 2)),
      audioProbe: const _AudioProbe(AudioCapabilities(effective: EffectiveAudioCapabilities(fidelity: CapabilitySupport.supported, spatialMetadata: CapabilitySupport.unknown))),
      networkProbe: const ContextNetworkCapabilityProbe(),
      networkContext: const RuntimeNetworkContext(route: NetworkRoute.offline, activeServerEndpointType: 'test-offline'),
    );

    final environment = await provider.load();

    expect(environment.identity.installationId, 'device-1');
    expect(environment.compute.hardwareVideoDecoding, CapabilitySupport.unknown);
    expect(environment.display.currentWidth, 1920);
    expect(environment.display.output.hdr10, CapabilitySupport.unknown);
    expect(environment.audio.effective.fidelity, CapabilitySupport.supported);
    expect(environment.audio.effective.spatialMetadata, CapabilitySupport.unknown);
    expect(environment.network.route, NetworkRoute.offline);
    expect(environment.selectPreferredBackend().id, 'media_kit');
  });

  test('persistent installation identity survives refresh', () async {
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('stable-device'),
      displayProbe: _ChangingDisplayProbe(),
    );

    final first = await provider.load();
    final second = await provider.refresh(PlaybackEnvironmentRefreshReason.displayChanged);

    expect(first.identity.installationId, 'stable-device');
    expect(second.identity.installationId, 'stable-device');
    expect(first.display.currentWidth, 100);
    expect(second.display.currentWidth, 101);
  });

  test('failed one-domain probe does not prevent environment creation', () async {
    final diagnostics = <PlaybackProbeDiagnostic>[];
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      displayProbe: const _ThrowingDisplayProbe(),
      audioProbe: const _AudioProbe(AudioCapabilities(effective: EffectiveAudioCapabilities(fidelity: CapabilitySupport.supported))),
      onDiagnostic: diagnostics.add,
    );

    final environment = await provider.load();

    expect(environment.display.currentWidth, isNull);
    expect(environment.display.output.hdr10, CapabilitySupport.unknown);
    expect(environment.audio.effective.fidelity, CapabilitySupport.supported);
    expect(diagnostics.single.domain, PlaybackProbeDomain.display);
  });

  test('unknown supported and unsupported remain distinct after refresh', () async {
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      computeProbe: const _ComputeProbe(
        ComputeCapabilities(
          videoCodecs: <VideoCodecComputeCapability>[
            VideoCodecComputeCapability(codec: 'h264', support: CapabilitySupport.supported),
            VideoCodecComputeCapability(codec: 'vc1', support: CapabilitySupport.unsupported),
            VideoCodecComputeCapability(codec: 'av1', support: CapabilitySupport.unknown),
          ],
        ),
      ),
    );

    final environment = await provider.refresh(PlaybackEnvironmentRefreshReason.manual);
    final codecs = environment.compute.videoCodecs;

    expect(codecs.singleWhere((codec) => codec.codec == 'h264').support, CapabilitySupport.supported);
    expect(codecs.singleWhere((codec) => codec.codec == 'vc1').support, CapabilitySupport.unsupported);
    expect(codecs.singleWhere((codec) => codec.codec == 'av1').support, CapabilitySupport.unknown);
  });

  test('refresh publishes a new environment snapshot and reason', () async {
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      displayProbe: _ChangingDisplayProbe(),
    );
    final controller = await PlaybackEnvironmentController.create(provider: provider);
    final snapshots = <PlaybackEnvironment>[];
    controller.environment.addListener(() => snapshots.add(controller.current));

    await controller.refresh(PlaybackEnvironmentRefreshReason.displayChanged);

    expect(snapshots, hasLength(1));
    expect(snapshots.single.display.currentWidth, 101);
    expect(controller.lastRefreshReason, PlaybackEnvironmentRefreshReason.displayChanged);
    controller.dispose();
  });

  test('effective profile resolver continues to be used', () async {
    final resolver = _RecordingResolver();
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      profileResolver: resolver,
    );

    final environment = await provider.load();

    expect(resolver.calls, 1);
    expect(environment.effectiveProfileFor('media_kit').deviceProfile.maxStreamingBitrate, 1234);
  });

  test('legacy conservative profile remains compatible', () async {
    final environment = await RuntimePlaybackEnvironmentProvider(identityProbe: const _IdentityProbe('device-1')).load();
    final profile = environment.effectiveProfileFor('media_kit').deviceProfile;

    expect(profile.directPlayRules.any((rule) => rule.containers.contains('mkv')), isTrue);
    expect(profile.videoCodecRules.any((rule) => rule.codec == 'h264'), isTrue);
    expect(profile.subtitleRules.any((rule) => rule.codec == 'pgssub'), isTrue);
  });

  test('display decode and output distinction survives refresh', () async {
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      computeProbe: const _ComputeProbe(ComputeCapabilities(hdrMetadataDecode: HdrDecodeCapabilities(hdr10: CapabilitySupport.supported))),
      displayProbe: const _DisplayProbe(DisplayCapabilities(output: HdrOutputCapabilities(hdr10: CapabilitySupport.unknown))),
    );

    final environment = await provider.refresh(PlaybackEnvironmentRefreshReason.displayChanged);

    expect(environment.compute.hdrMetadataDecode.hdr10, CapabilitySupport.supported);
    expect(environment.display.output.hdr10, CapabilitySupport.unknown);
  });

  test('audio fidelity and spatial metadata distinction survives refresh', () async {
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      audioProbe: const _AudioProbe(
        AudioCapabilities(
          effective: EffectiveAudioCapabilities(
            fidelity: CapabilitySupport.supported,
            spatialMetadata: CapabilitySupport.unsupported,
          ),
        ),
      ),
    );

    final environment = await provider.refresh(PlaybackEnvironmentRefreshReason.audioRouteChanged);

    expect(environment.audio.effective.fidelity, CapabilitySupport.supported);
    expect(environment.audio.effective.spatialMetadata, CapabilitySupport.unsupported);
  });
}

class _IdentityProbe implements DeviceIdentityProbe {
  const _IdentityProbe(this.installationId);

  final String installationId;

  @override
  Future<DeviceIdentity> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      DeviceIdentity(
        installationId: installationId,
        clientName: 'RodPlayer',
        appVersion: 'test',
        platformFamily: PlatformFamily.unknown,
        deviceName: 'Test device',
      );
}

class _ComputeProbe implements ComputeCapabilityProbe {
  const _ComputeProbe(this.capabilities);

  final ComputeCapabilities capabilities;

  @override
  Future<ComputeCapabilities> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      capabilities;
}

class _DisplayProbe implements DisplayCapabilityProbe {
  const _DisplayProbe(this.capabilities);

  final DisplayCapabilities capabilities;

  @override
  Future<DisplayCapabilities> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      capabilities;
}

class _ChangingDisplayProbe implements DisplayCapabilityProbe {
  int _count = 0;

  @override
  Future<DisplayCapabilities> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async {
    _count += 1;
    return DisplayCapabilities(currentWidth: 99 + _count, currentHeight: 200);
  }
}

class _ThrowingDisplayProbe implements DisplayCapabilityProbe {
  const _ThrowingDisplayProbe();

  @override
  Future<DisplayCapabilities> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async {
    throw StateError('display unavailable');
  }
}

class _AudioProbe implements AudioCapabilityProbe {
  const _AudioProbe(this.capabilities);

  final AudioCapabilities capabilities;

  @override
  Future<AudioCapabilities> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      capabilities;
}

class _RecordingResolver implements EffectivePlaybackProfileResolver {
  int calls = 0;

  @override
  EffectivePlaybackProfile resolve(PlaybackEnvironment environment, PlaybackBackendDescriptor backend) {
    calls += 1;
    return EffectivePlaybackProfile(
      backendId: backend.id,
      capabilities: backend.capabilities,
      deviceProfile: const EffectiveDeviceProfile(
        maxStreamingBitrate: 1234,
        directPlayRules: <DirectPlayCapabilityRule>[],
        transcodingRules: <TranscodingCapabilityRule>[],
        videoCodecRules: <VideoCodecCapabilityRule>[],
        audioCodecRules: <AudioCodecCapabilityRule>[],
        subtitleRules: <SubtitleCapabilityRule>[],
      ),
    );
  }
}
