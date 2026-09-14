import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

enum PlaybackEnvironmentRefreshReason {
  initialLoad,
  manual,
  displayChanged,
  audioRouteChanged,
  networkChanged,
  backendAvailabilityChanged,
  resume,
}

enum PlaybackProbeDomain {
  identity,
  compute,
  display,
  audio,
  network,
  backend,
  effectiveProfile,
}

class RuntimeNetworkContext {
  const RuntimeNetworkContext({
    this.activeServerEndpointType,
    this.route,
    this.metering,
    this.estimatedBandwidthBitsPerSecond,
    this.latencyMillis,
    this.maxStreamingBitrate,
  });

  final String? activeServerEndpointType;
  final NetworkRoute? route;
  final MeteringState? metering;
  final int? estimatedBandwidthBitsPerSecond;
  final int? latencyMillis;
  final int? maxStreamingBitrate;
}

class PlaybackProbeDiagnostic {
  const PlaybackProbeDiagnostic({
    required this.domain,
    required this.message,
    this.error,
  });

  final PlaybackProbeDomain domain;
  final String message;
  final Object? error;
}

typedef PlaybackProbeDiagnosticSink = void Function(PlaybackProbeDiagnostic diagnostic);

class PlaybackProbeUpdate<T> {
  const PlaybackProbeUpdate.reported(this.value) : isReported = true;

  const PlaybackProbeUpdate.unreported()
      : isReported = false,
        value = null;

  final bool isReported;
  final T? value;
}

abstract interface class DeviceIdentityProbe {
  Future<DeviceIdentity> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  });
}

abstract interface class ComputeCapabilityProbe {
  Future<PlaybackProbeUpdate<ComputeCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  });
}

abstract interface class DisplayCapabilityProbe {
  Future<PlaybackProbeUpdate<DisplayCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  });
}

abstract interface class AudioCapabilityProbe {
  Future<PlaybackProbeUpdate<AudioCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  });
}

abstract interface class NetworkCapabilityProbe {
  Future<PlaybackProbeUpdate<NetworkCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
    RuntimeNetworkContext? context,
  });
}

abstract interface class PlaybackBackendProbe {
  Future<List<PlaybackBackendDescriptor>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  });
}

abstract interface class PlaybackEnvironmentEventSource {
  Stream<PlaybackEnvironmentRefreshReason> get refreshReasons;
  Future<void> dispose();
}

class EmptyPlaybackEnvironmentEventSource implements PlaybackEnvironmentEventSource {
  const EmptyPlaybackEnvironmentEventSource();

  @override
  Stream<PlaybackEnvironmentRefreshReason> get refreshReasons => const Stream<PlaybackEnvironmentRefreshReason>.empty();

  @override
  Future<void> dispose() async {}
}

class PersistentDeviceIdentityProbe implements DeviceIdentityProbe {
  const PersistentDeviceIdentityProbe({this.identity, this.identityStore});

  final InstallationIdentity? identity;
  final InstallationIdentityStore? identityStore;

  @override
  Future<DeviceIdentity> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async {
    final provided = identity;
    if (provided != null) return _fromInstallationIdentity(provided);
    final store = identityStore;
    if (store != null) return _fromInstallationIdentity(await store.load());
    return previous?.identity ?? _syntheticIdentity();
  }

  static DeviceIdentity _fromInstallationIdentity(InstallationIdentity identity) => DeviceIdentity(
        installationId: identity.deviceId,
        clientName: identity.clientName,
        appVersion: identity.appVersion,
        platformFamily: platformFamilyForCurrentTarget(),
        deviceName: identity.deviceName,
      );
}

class UnknownComputeCapabilityProbe implements ComputeCapabilityProbe {
  const UnknownComputeCapabilityProbe();

  @override
  Future<PlaybackProbeUpdate<ComputeCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      const PlaybackProbeUpdate<ComputeCapabilities>.unreported();
}

class UnknownDisplayCapabilityProbe implements DisplayCapabilityProbe {
  const UnknownDisplayCapabilityProbe();

  @override
  Future<PlaybackProbeUpdate<DisplayCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      const PlaybackProbeUpdate<DisplayCapabilities>.unreported();
}

class UnknownAudioCapabilityProbe implements AudioCapabilityProbe {
  const UnknownAudioCapabilityProbe();

  @override
  Future<PlaybackProbeUpdate<AudioCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      const PlaybackProbeUpdate<AudioCapabilities>.unreported();
}

class ContextNetworkCapabilityProbe implements NetworkCapabilityProbe {
  const ContextNetworkCapabilityProbe();

  @override
  Future<PlaybackProbeUpdate<NetworkCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
    RuntimeNetworkContext? context,
  }) async {
    if (context == null) return const PlaybackProbeUpdate<NetworkCapabilities>.unreported();
    return PlaybackProbeUpdate<NetworkCapabilities>.reported(NetworkCapabilities(
        route: context.route ?? NetworkRoute.unknown,
        metering: context.metering ?? MeteringState.unknown,
        estimatedBandwidthBitsPerSecond: context.estimatedBandwidthBitsPerSecond,
        latencyMillis: context.latencyMillis,
        activeServerEndpointType: context.activeServerEndpointType,
        maxStreamingBitrate: context.maxStreamingBitrate ?? previous?.network.maxStreamingBitrate ?? const NetworkCapabilities().maxStreamingBitrate,
      ));
  }
}

class MediaKitPlaybackBackendProbe implements PlaybackBackendProbe {
  const MediaKitPlaybackBackendProbe();

  @override
  Future<List<PlaybackBackendDescriptor>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      const <PlaybackBackendDescriptor>[
        PlaybackBackendDescriptor(
          id: 'media_kit',
          displayName: 'Default playback engine',
          availability: BackendAvailability.available,
          priority: 0,
          capabilities: ConservativePlaybackEnvironmentProvider.mediaKitCapabilities,
        ),
      ];
}

class RuntimePlaybackEnvironmentProvider implements PlaybackEnvironmentProvider {
  RuntimePlaybackEnvironmentProvider({
    required this.identityProbe,
    this.computeProbe = const UnknownComputeCapabilityProbe(),
    this.displayProbe = const UnknownDisplayCapabilityProbe(),
    this.audioProbe = const UnknownAudioCapabilityProbe(),
    this.networkProbe = const ContextNetworkCapabilityProbe(),
    this.backendProbe = const MediaKitPlaybackBackendProbe(),
    this.profileResolver = const LegacyConservativePlaybackProfileResolver(),
    this.networkContext,
    this.onDiagnostic,
  });

  final DeviceIdentityProbe identityProbe;
  final ComputeCapabilityProbe computeProbe;
  final DisplayCapabilityProbe displayProbe;
  final AudioCapabilityProbe audioProbe;
  final NetworkCapabilityProbe networkProbe;
  final PlaybackBackendProbe backendProbe;
  final EffectivePlaybackProfileResolver profileResolver;
  final PlaybackProbeDiagnosticSink? onDiagnostic;
  RuntimeNetworkContext? networkContext;

  PlaybackEnvironment? _lastEnvironment;

  @override
  Future<PlaybackEnvironment> load() => refresh(PlaybackEnvironmentRefreshReason.initialLoad);

  Future<PlaybackEnvironment> refresh(PlaybackEnvironmentRefreshReason reason) async {
    final previous = _lastEnvironment;
    final identity = await _probe(
      PlaybackProbeDomain.identity,
      previous?.identity ?? _syntheticIdentity(),
      () => identityProbe.probe(previous: previous, reason: reason),
    );
    final compute = await _probeUpdate(
      PlaybackProbeDomain.compute,
      previous?.compute ?? const ComputeCapabilities(),
      () => computeProbe.probe(previous: previous, reason: reason),
    );
    final display = await _probeUpdate(
      PlaybackProbeDomain.display,
      previous?.display ?? const DisplayCapabilities(),
      () => displayProbe.probe(previous: previous, reason: reason),
    );
    final audio = await _probeUpdate(
      PlaybackProbeDomain.audio,
      previous?.audio ?? const AudioCapabilities(),
      () => audioProbe.probe(previous: previous, reason: reason),
    );
    final network = await _probeUpdate(
      PlaybackProbeDomain.network,
      previous?.network ?? const NetworkCapabilities(),
      () => networkProbe.probe(previous: previous, reason: reason, context: networkContext),
    );
    final fallbackBackends = previous?.backends ?? await const MediaKitPlaybackBackendProbe().probe(previous: null, reason: PlaybackEnvironmentRefreshReason.initialLoad);
    final backends = await _probe(
      PlaybackProbeDomain.backend,
      fallbackBackends,
      () => backendProbe.probe(previous: previous, reason: reason),
    );

    final environmentWithoutProfiles = PlaybackEnvironment(
      identity: identity,
      device: deviceCapabilitiesForIdentity(identity),
      compute: compute,
      display: display,
      audio: audio,
      network: network,
      backends: backends,
      effectiveProfiles: const <EffectivePlaybackProfile>[],
    );
    final effectiveProfiles = <EffectivePlaybackProfile>[];
    for (final backend in backends) {
      try {
        effectiveProfiles.add(profileResolver.resolve(environmentWithoutProfiles, backend));
      } on Object catch (error) {
        _diagnose(PlaybackProbeDomain.effectiveProfile, 'Effective playback profile resolution failed for ${backend.id}', error);
        final previousProfile = _previousEffectiveProfile(previous, backend.id);
        if (previousProfile != null) {
          effectiveProfiles.add(previousProfile);
        }
      }
    }
    final environment = environmentWithoutProfiles.copyWith(effectiveProfiles: effectiveProfiles);
    _lastEnvironment = environment;
    return environment;
  }

  Future<T> _probe<T>(PlaybackProbeDomain domain, T fallback, Future<T> Function() run) async {
    try {
      return await run();
    } on Object catch (error) {
      _diagnose(domain, 'Runtime playback probe failed; retaining previous value or unknown fallback', error);
      return fallback;
    }
  }

  Future<T> _probeUpdate<T>(PlaybackProbeDomain domain, T fallback, Future<PlaybackProbeUpdate<T>> Function() run) async {
    try {
      final update = await run();
      return update.isReported ? update.value as T : fallback;
    } on Object catch (error) {
      _diagnose(domain, 'Runtime playback probe failed; retaining previous value or unknown fallback', error);
      return fallback;
    }
  }

  EffectivePlaybackProfile? _previousEffectiveProfile(PlaybackEnvironment? previous, String backendId) {
    if (previous == null) return null;
    for (final profile in previous.effectiveProfiles) {
      if (profile.backendId == backendId) return profile;
    }
    return null;
  }

  void _diagnose(PlaybackProbeDomain domain, String message, Object error) {
    onDiagnostic?.call(PlaybackProbeDiagnostic(domain: domain, message: message, error: error));
  }
}

class PlaybackEnvironmentController {
  PlaybackEnvironmentController({
    required this.provider,
    required PlaybackEnvironment initialEnvironment,
    this.lastRefreshReason = PlaybackEnvironmentRefreshReason.initialLoad,
  }) : environment = ValueNotifier<PlaybackEnvironment>(initialEnvironment);

  final RuntimePlaybackEnvironmentProvider provider;
  final ValueNotifier<PlaybackEnvironment> environment;
  PlaybackEnvironmentRefreshReason lastRefreshReason;
  StreamSubscription<PlaybackEnvironmentRefreshReason>? _eventSubscription;
  Future<void>? _refreshInFlight;
  PlaybackEnvironmentRefreshReason? _pendingRefreshReason;

  PlaybackEnvironment get current => environment.value;

  static Future<PlaybackEnvironmentController> create({
    required RuntimePlaybackEnvironmentProvider provider,
  }) async {
    final initial = await provider.load();
    return PlaybackEnvironmentController(provider: provider, initialEnvironment: initial);
  }

  Future<void> refresh(PlaybackEnvironmentRefreshReason reason) async {
    if (_refreshInFlight != null) {
      _pendingRefreshReason = reason;
      await _refreshInFlight;
      return;
    }
    lastRefreshReason = reason;
    _refreshInFlight = provider.refresh(reason).then((value) {
      environment.value = value;
    });
    await _refreshInFlight;
    _refreshInFlight = null;
    final pending = _pendingRefreshReason;
    _pendingRefreshReason = null;
    if (pending != null) await refresh(pending);
  }

  void attachEventSource(PlaybackEnvironmentEventSource source) {
    _eventSubscription?.cancel();
    _eventSubscription = source.refreshReasons.listen((reason) {
      unawaited(refresh(reason));
    });
  }

  void dispose() {
    _eventSubscription?.cancel();
    environment.dispose();
  }
}

DeviceCapabilities deviceCapabilitiesForIdentity(DeviceIdentity identity) => DeviceCapabilities(
      platformLabel: identity.deviceName,
      supportsDpadFocus: defaultTargetPlatform == TargetPlatform.android,
      supportsKeyboardScrubbing: defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux,
    );

PlatformFamily platformFamilyForCurrentTarget() {
  if (kIsWeb) return PlatformFamily.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => PlatformFamily.android,
    TargetPlatform.iOS => PlatformFamily.ios,
    TargetPlatform.macOS => PlatformFamily.macos,
    TargetPlatform.windows => PlatformFamily.windows,
    TargetPlatform.linux => PlatformFamily.linux,
    TargetPlatform.fuchsia => PlatformFamily.fuchsia,
  };
}

DeviceIdentity _syntheticIdentity() => DeviceIdentity(
      installationId: 'unknown',
      clientName: 'RodPlayer',
      appVersion: 'unknown',
      platformFamily: platformFamilyForCurrentTarget(),
      deviceName: _platformLabel(),
      isSynthetic: true,
    );

String _platformLabel() {
  if (kIsWeb) return 'Web device';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android device',
    TargetPlatform.iOS => 'iOS device',
    TargetPlatform.macOS => 'macOS device',
    TargetPlatform.windows => 'Windows device',
    TargetPlatform.linux => 'Linux device',
    TargetPlatform.fuchsia => 'Fuchsia device',
  };
}
