import 'dart:ui' as ui;

import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/playback/playback_backend_registry.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';
import 'package:rodplayer/platform/playback/native/native_playback_capability_bridge.dart';
import 'package:rodplayer/platform/playback/native/native_playback_capability_probes.dart';

class FlutterDisplayCapabilityProbe implements DisplayCapabilityProbe {
  const FlutterDisplayCapabilityProbe();

  @override
  Future<PlaybackProbeUpdate<DisplayCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return const PlaybackProbeUpdate<DisplayCapabilities>.unreported();
    final view = views.first;
    final pixelRatio = view.devicePixelRatio;
    final physicalSize = view.physicalSize;
    final logicalWidth = physicalSize.width / pixelRatio;
    final logicalHeight = physicalSize.height / pixelRatio;
    return PlaybackProbeUpdate<DisplayCapabilities>.reported(DisplayCapabilities(
      currentWidth: logicalWidth.round(),
      currentHeight: logicalHeight.round(),
      pixelRatio: pixelRatio,
      displayId: 'flutter-view-0',
      displayName: 'Flutter view',
      activeHdr: CapabilitySupport.unknown,
      outputColorCapability: CapabilitySupport.unknown,
      output: const HdrOutputCapabilities(),
      toneMapping: const ToneMappingCapabilities(),
    ));
  }
}

class CascadingDisplayCapabilityProbe implements DisplayCapabilityProbe {
  const CascadingDisplayCapabilityProbe(this.probes);

  final List<DisplayCapabilityProbe> probes;

  @override
  Future<PlaybackProbeUpdate<DisplayCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async {
    for (final probe in probes) {
      final result = await probe.probe(previous: previous, reason: reason);
      if (result.isReported) return result;
    }
    return const PlaybackProbeUpdate<DisplayCapabilities>.unreported();
  }
}

RuntimePlaybackEnvironmentProvider createDefaultRuntimePlaybackEnvironmentProvider({
  InstallationIdentity? identity,
  InstallationIdentityStore? identityStore,
  RuntimeNetworkContext? networkContext,
  PlaybackProbeDiagnosticSink? onDiagnostic,
  NativePlaybackCapabilityBridge bridge = const MethodChannelNativePlaybackCapabilityBridge(),
  PlaybackBackendRegistry playbackBackendRegistry = const PlaybackBackendRegistry(),
}) =>
    RuntimePlaybackEnvironmentProvider(
      identityProbe: PersistentDeviceIdentityProbe(identity: identity, identityStore: identityStore),
      computeProbe: NativeComputeCapabilityProbe(bridge: bridge),
      displayProbe: CascadingDisplayCapabilityProbe(<DisplayCapabilityProbe>[
        NativeDisplayCapabilityProbe(bridge: bridge),
        const FlutterDisplayCapabilityProbe(),
      ]),
      audioProbe: NativeAudioCapabilityProbe(bridge: bridge),
      backendProbe: RegistryPlaybackBackendProbe(platformFamily: platformFamilyForCurrentTarget(), registry: playbackBackendRegistry),
      networkContext: networkContext,
      onDiagnostic: onDiagnostic,
    );
