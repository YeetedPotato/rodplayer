import 'dart:async';

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

  test('unreported probe field preserves previous known state', () async {
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      networkProbe: const ContextNetworkCapabilityProbe(),
      networkContext: const RuntimeNetworkContext(route: NetworkRoute.localLan),
    );
    final first = await provider.load();
    provider.networkContext = null;

    final second = await provider.refresh(PlaybackEnvironmentRefreshReason.manual);

    expect(first.network.route, NetworkRoute.localLan);
    expect(second.network.route, NetworkRoute.localLan);
  });

  test('probe can explicitly replace known state with unknown', () async {
    final probe = _MutableNetworkProbe(const PlaybackProbeUpdate<NetworkCapabilities>.reported(NetworkCapabilities(route: NetworkRoute.localLan)));
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      networkProbe: probe,
    );
    final first = await provider.load();
    probe.update = const PlaybackProbeUpdate<NetworkCapabilities>.reported(NetworkCapabilities(route: NetworkRoute.unknown));

    final second = await provider.refresh(PlaybackEnvironmentRefreshReason.networkChanged);

    expect(first.network.route, NetworkRoute.localLan);
    expect(second.network.route, NetworkRoute.unknown);
  });

  test('supported and unsupported are explicitly replaceable', () async {
    final probe = _MutableComputeProbe(
      const PlaybackProbeUpdate<ComputeCapabilities>.reported(
        ComputeCapabilities(hardwareVideoDecoding: CapabilitySupport.supported),
      ),
    );
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      computeProbe: probe,
    );
    final first = await provider.load();
    probe.update = const PlaybackProbeUpdate<ComputeCapabilities>.reported(
      ComputeCapabilities(hardwareVideoDecoding: CapabilitySupport.unsupported),
    );

    final second = await provider.refresh(PlaybackEnvironmentRefreshReason.manual);

    expect(first.compute.hardwareVideoDecoding, CapabilitySupport.supported);
    expect(second.compute.hardwareVideoDecoding, CapabilitySupport.unsupported);
  });

  test('one domain update does not mutate unrelated domains', () async {
    final displayProbe = _MutableDisplayProbe(
      const PlaybackProbeUpdate<DisplayCapabilities>.reported(DisplayCapabilities(currentWidth: 100)),
    );
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      computeProbe: const _ComputeProbe(
        ComputeCapabilities(hardwareVideoDecoding: CapabilitySupport.supported),
      ),
      displayProbe: displayProbe,
    );
    final first = await provider.load();
    displayProbe.update = const PlaybackProbeUpdate<DisplayCapabilities>.reported(DisplayCapabilities(currentWidth: 200));

    final second = await provider.refresh(PlaybackEnvironmentRefreshReason.displayChanged);

    expect(first.compute.hardwareVideoDecoding, CapabilitySupport.supported);
    expect(second.compute.hardwareVideoDecoding, CapabilitySupport.supported);
    expect(second.display.currentWidth, 200);
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

  test('event source refreshes with mapped reason', () async {
    final source = _TestEventSource();
    final controller = await PlaybackEnvironmentController.create(
      provider: RuntimePlaybackEnvironmentProvider(identityProbe: const _IdentityProbe('device-1')),
    );
    controller.attachEventSource(source);

    source.add(PlaybackEnvironmentRefreshReason.resume);
    await Future<void>.delayed(Duration.zero);

    expect(controller.lastRefreshReason, PlaybackEnvironmentRefreshReason.resume);
    await source.dispose();
    controller.dispose();
  });

  test('overlapping refreshes are serialized with the latest pending reason', () async {
    final provider = _SlowRuntimeProvider();
    final controller = await PlaybackEnvironmentController.create(provider: provider);

    final first = controller.refresh(PlaybackEnvironmentRefreshReason.displayChanged);
    final second = controller.refresh(PlaybackEnvironmentRefreshReason.audioRouteChanged);
    provider.completeOne();
    await Future<void>.delayed(Duration.zero);
    provider.completeOne();
    await Future.wait(<Future<void>>[first, second]);

    expect(provider.reasons, <PlaybackEnvironmentRefreshReason>[
      PlaybackEnvironmentRefreshReason.initialLoad,
      PlaybackEnvironmentRefreshReason.displayChanged,
      PlaybackEnvironmentRefreshReason.audioRouteChanged,
    ]);
    expect(controller.lastRefreshReason, PlaybackEnvironmentRefreshReason.audioRouteChanged);
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

  test('resolver failure on second refresh retains previous effective profile', () async {
    final resolver = _FailingAfterFirstResolver();
    final diagnostics = <PlaybackProbeDiagnostic>[];
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      profileResolver: resolver,
      onDiagnostic: diagnostics.add,
    );

    final first = await provider.load();
    final second = await provider.refresh(PlaybackEnvironmentRefreshReason.manual);

    expect(first.effectiveProfileFor('media_kit').deviceProfile.maxStreamingBitrate, 4321);
    expect(second.effectiveProfileFor('media_kit').deviceProfile.maxStreamingBitrate, 4321);
    expect(diagnostics.single.domain, PlaybackProbeDomain.effectiveProfile);
  });

  test('resolver failure on first load fabricates no effective profile', () async {
    final diagnostics = <PlaybackProbeDiagnostic>[];
    final provider = RuntimePlaybackEnvironmentProvider(
      identityProbe: const _IdentityProbe('device-1'),
      profileResolver: const _AlwaysFailingResolver(),
      onDiagnostic: diagnostics.add,
    );

    final environment = await provider.load();

    expect(environment.effectiveProfiles, isEmpty);
    expect(() => environment.effectiveProfileFor('media_kit'), throwsA(isA<StateError>()));
    expect(diagnostics.single.domain, PlaybackProbeDomain.effectiveProfile);
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
  Future<PlaybackProbeUpdate<ComputeCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      PlaybackProbeUpdate<ComputeCapabilities>.reported(capabilities);
}

class _DisplayProbe implements DisplayCapabilityProbe {
  const _DisplayProbe(this.capabilities);

  final DisplayCapabilities capabilities;

  @override
  Future<PlaybackProbeUpdate<DisplayCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      PlaybackProbeUpdate<DisplayCapabilities>.reported(capabilities);
}

class _ChangingDisplayProbe implements DisplayCapabilityProbe {
  int _count = 0;

  @override
  Future<PlaybackProbeUpdate<DisplayCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async {
    _count += 1;
    return PlaybackProbeUpdate<DisplayCapabilities>.reported(DisplayCapabilities(currentWidth: 99 + _count, currentHeight: 200));
  }
}

class _ThrowingDisplayProbe implements DisplayCapabilityProbe {
  const _ThrowingDisplayProbe();

  @override
  Future<PlaybackProbeUpdate<DisplayCapabilities>> probe({
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
  Future<PlaybackProbeUpdate<AudioCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      PlaybackProbeUpdate<AudioCapabilities>.reported(capabilities);
}

class _MutableComputeProbe implements ComputeCapabilityProbe {
  _MutableComputeProbe(this.update);

  PlaybackProbeUpdate<ComputeCapabilities> update;

  @override
  Future<PlaybackProbeUpdate<ComputeCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      update;
}

class _MutableDisplayProbe implements DisplayCapabilityProbe {
  _MutableDisplayProbe(this.update);

  PlaybackProbeUpdate<DisplayCapabilities> update;

  @override
  Future<PlaybackProbeUpdate<DisplayCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      update;
}

class _MutableNetworkProbe implements NetworkCapabilityProbe {
  _MutableNetworkProbe(this.update);

  PlaybackProbeUpdate<NetworkCapabilities> update;

  @override
  Future<PlaybackProbeUpdate<NetworkCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
    RuntimeNetworkContext? context,
  }) async =>
      update;
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

class _TestEventSource implements PlaybackEnvironmentEventSource {
  final _controller = StreamController<PlaybackEnvironmentRefreshReason>.broadcast();

  void add(PlaybackEnvironmentRefreshReason reason) => _controller.add(reason);

  @override
  Stream<PlaybackEnvironmentRefreshReason> get refreshReasons => _controller.stream;

  @override
  Future<void> dispose() => _controller.close();
}

class _SlowRuntimeProvider extends RuntimePlaybackEnvironmentProvider {
  _SlowRuntimeProvider() : super(identityProbe: const _IdentityProbe('device-1'));

  final reasons = <PlaybackEnvironmentRefreshReason>[];
  final _completers = <Completer<void>>[];

  @override
  Future<PlaybackEnvironment> refresh(PlaybackEnvironmentRefreshReason reason) async {
    reasons.add(reason);
    if (reason != PlaybackEnvironmentRefreshReason.initialLoad) {
      final completer = Completer<void>();
      _completers.add(completer);
      await completer.future;
    }
    return super.refresh(reason);
  }

  void completeOne() {
    _completers.removeAt(0).complete();
  }
}

class _FailingAfterFirstResolver implements EffectivePlaybackProfileResolver {
  var _calls = 0;

  @override
  EffectivePlaybackProfile resolve(PlaybackEnvironment environment, PlaybackBackendDescriptor backend) {
    _calls += 1;
    if (_calls > 1) throw StateError('profile unavailable');
    return _profile(backend, 4321);
  }
}

class _AlwaysFailingResolver implements EffectivePlaybackProfileResolver {
  const _AlwaysFailingResolver();

  @override
  EffectivePlaybackProfile resolve(PlaybackEnvironment environment, PlaybackBackendDescriptor backend) {
    throw StateError('profile unavailable');
  }
}

EffectivePlaybackProfile _profile(PlaybackBackendDescriptor backend, int maxStreamingBitrate) => EffectivePlaybackProfile(
      backendId: backend.id,
      capabilities: backend.capabilities,
      deviceProfile: EffectiveDeviceProfile(
        maxStreamingBitrate: maxStreamingBitrate,
        directPlayRules: const <DirectPlayCapabilityRule>[],
        transcodingRules: const <TranscodingCapabilityRule>[],
        videoCodecRules: const <VideoCodecCapabilityRule>[],
        audioCodecRules: const <AudioCodecCapabilityRule>[],
        subtitleRules: const <SubtitleCapabilityRule>[],
      ),
    );
