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
    this.probeFailures = const <String, Object>{},
  });

  final PlaybackRuntimeRegistry registry;
  final PlaybackBackendRegistry backendRegistry;
  final Map<String, Object> probeFailures;
}

typedef PlaybackRuntimeFactory = Future<PlaybackBackendRuntime> Function();

Future<PlatformPlaybackRuntimeSet> createPlatformPlaybackRuntimes({
  PlaybackRuntimeFactory? appleNativeFactory,
  PlaybackRuntimeFactory? appleCompatibilityFactory,
  PlaybackRuntimeFactory? androidNativeFactory,
  PlaybackRuntimeFactory? androidCompatibilityFactory,
}) async {
  final probeFailures = <String, Object>{};
  final appleNative = await _optionalRuntime(PlaybackBackendIds.appleNative, appleNativeFactory ?? () => AppleNativePlaybackRuntime.create(), probeFailures);
  final appleCompatibility = await _optionalRuntime(PlaybackBackendIds.appleCompatibility, appleCompatibilityFactory ?? () => AppleCompatibilityPlaybackRuntime.create(), probeFailures);
  final androidNative = await _optionalRuntime(PlaybackBackendIds.androidNative, androidNativeFactory ?? () => AndroidNativePlaybackRuntime.create(), probeFailures);
  final androidCompatibility = await _optionalRuntime(PlaybackBackendIds.androidCompatibility, androidCompatibilityFactory ?? () => AndroidCompatibilityPlaybackRuntime.create(), probeFailures);
  final optionalRuntimes = <PlaybackBackendRuntime>[
    if (appleNative != null) appleNative,
    if (appleCompatibility != null) appleCompatibility,
    if (androidNative != null) androidNative,
    if (androidCompatibility != null) androidCompatibility,
  ];
  return PlatformPlaybackRuntimeSet(
    registry: PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[
      MediaKitPlaybackRuntime(),
      ...optionalRuntimes,
    ]),
    backendRegistry: PlaybackBackendRegistry(
      appleNativeAvailable: appleNative?.isAvailable ?? false,
      appleCompatibilityAvailable: appleCompatibility?.isAvailable ?? false,
      androidNativeAvailable: androidNative?.isAvailable ?? false,
      androidCompatibilityAvailable: androidCompatibility?.isAvailable ?? false,
    ),
    probeFailures: Map<String, Object>.unmodifiable(probeFailures),
  );
}

Future<PlaybackBackendRuntime?> _optionalRuntime(String backendId, PlaybackRuntimeFactory create, Map<String, Object> failures) async {
  try {
    return await create();
  } on Object catch (error) {
    failures[backendId] = error;
    return null;
  }
}
