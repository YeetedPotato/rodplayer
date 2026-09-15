import 'package:rodplayer/core/playback/playback_backend_registry.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/platform/playback/android_native_playback_runtime.dart';
import 'package:rodplayer/platform/playback/apple_native_playback_runtime.dart';
import 'package:rodplayer/platform/playback/compatibility_playback_runtimes.dart';

class PlatformPlaybackRuntimeSet {
  const PlatformPlaybackRuntimeSet({
    required this.registry,
    required this.backendRegistry,
  });

  final PlaybackRuntimeRegistry registry;
  final PlaybackBackendRegistry backendRegistry;
}

Future<PlatformPlaybackRuntimeSet> createPlatformPlaybackRuntimes() async {
  final appleNative = await AppleNativePlaybackRuntime.create();
  final appleCompatibility = await AppleCompatibilityPlaybackRuntime.create();
  final androidNative = await AndroidNativePlaybackRuntime.create();
  final androidCompatibility = await AndroidCompatibilityPlaybackRuntime.create();
  return PlatformPlaybackRuntimeSet(
    registry: PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[
      MediaKitPlaybackRuntime(),
      appleNative,
      appleCompatibility,
      androidNative,
      androidCompatibility,
    ]),
    backendRegistry: PlaybackBackendRegistry(
      appleNativeAvailable: appleNative.isAvailable,
      appleCompatibilityAvailable: appleCompatibility.isAvailable,
      androidNativeAvailable: androidNative.isAvailable,
      androidCompatibilityAvailable: androidCompatibility.isAvailable,
    ),
  );
}
