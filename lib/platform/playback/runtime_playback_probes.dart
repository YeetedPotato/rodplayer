import 'dart:ui' as ui;

import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';

class FlutterDisplayCapabilityProbe implements DisplayCapabilityProbe {
  const FlutterDisplayCapabilityProbe();

  @override
  Future<DisplayCapabilities> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return previous?.display ?? const DisplayCapabilities();
    final view = views.first;
    final pixelRatio = view.devicePixelRatio;
    final physicalSize = view.physicalSize;
    final logicalWidth = physicalSize.width / pixelRatio;
    final logicalHeight = physicalSize.height / pixelRatio;
    return DisplayCapabilities(
      currentWidth: logicalWidth.round(),
      currentHeight: logicalHeight.round(),
      pixelRatio: pixelRatio,
      displayId: 'flutter-view-0',
      displayName: 'Flutter view',
      activeHdr: CapabilitySupport.unknown,
      outputColorCapability: CapabilitySupport.unknown,
      output: const HdrOutputCapabilities(),
      toneMapping: const ToneMappingCapabilities(),
    );
  }
}

RuntimePlaybackEnvironmentProvider createDefaultRuntimePlaybackEnvironmentProvider({
  InstallationIdentity? identity,
  InstallationIdentityStore? identityStore,
  RuntimeNetworkContext? networkContext,
  PlaybackProbeDiagnosticSink? onDiagnostic,
}) =>
    RuntimePlaybackEnvironmentProvider(
      identityProbe: PersistentDeviceIdentityProbe(identity: identity, identityStore: identityStore),
      displayProbe: const FlutterDisplayCapabilityProbe(),
      networkContext: networkContext,
      onDiagnostic: onDiagnostic,
    );
