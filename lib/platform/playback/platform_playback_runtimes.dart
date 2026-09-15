import 'package:rodplayer/core/playback/playback_backend_registry.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/platform/playback/android_native_playback_runtime.dart';
import 'package:rodplayer/platform/playback/apple_native_playback_runtime.dart';

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
  final androidNative = await AndroidNativePlaybackRuntime.create();
  return PlatformPlaybackRuntimeSet(
    registry: PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[
      MediaKitPlaybackRuntime(),
      appleNative,
      androidNative,
    ]),
    backendRegistry: PlaybackBackendRegistry(
      appleNativeAvailable: appleNative.isAvailable,
      androidNativeAvailable: androidNative.isAvailable,
    ),
  );
}
