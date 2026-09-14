import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';

class PlaybackBackendIds {
  const PlaybackBackendIds._();

  static const mediaKit = 'media_kit';
  static const appleNative = 'apple_native';
  static const appleCompatibility = 'apple_compatibility';
  static const androidNative = 'android_native';
  static const androidCompatibility = 'android_compatibility';
  static const windowsMpv = 'windows_mpv';
}

class PlaybackBackendRegistry {
  const PlaybackBackendRegistry({
    this.mediaKitCapabilities = ConservativePlaybackEnvironmentProvider.mediaKitCapabilities,
  });

  final PlaybackBackendCapabilities mediaKitCapabilities;

  List<PlaybackBackendDescriptor> backendsFor(PlatformFamily platformFamily) {
    final descriptors = <PlaybackBackendDescriptor>[
      PlaybackBackendDescriptor(
        id: PlaybackBackendIds.mediaKit,
        displayName: 'Default playback engine',
        availability: BackendAvailability.available,
        priority: 0,
        capabilities: mediaKitCapabilities,
      ),
      ...switch (platformFamily) {
        PlatformFamily.android => _androidBackends(),
        PlatformFamily.ios => _appleBackends(),
        PlatformFamily.macos => _appleBackends(),
        PlatformFamily.windows => _windowsBackends(),
        _ => const <PlaybackBackendDescriptor>[],
      },
    ];
    descriptors.sort((a, b) {
      final priority = a.priority.compareTo(b.priority);
      if (priority != 0) return priority;
      return a.id.compareTo(b.id);
    });
    return descriptors;
  }

  static List<PlaybackBackendDescriptor> _appleBackends() => const <PlaybackBackendDescriptor>[
        PlaybackBackendDescriptor(
          id: PlaybackBackendIds.appleNative,
          displayName: 'Apple native playback',
          availability: BackendAvailability.unavailable,
          priority: 10,
          capabilities: PlaybackBackendCapabilities(id: PlaybackBackendIds.appleNative, name: 'Apple native playback'),
        ),
        PlaybackBackendDescriptor(
          id: PlaybackBackendIds.appleCompatibility,
          displayName: 'Apple compatibility playback',
          availability: BackendAvailability.unavailable,
          priority: 20,
          capabilities: PlaybackBackendCapabilities(id: PlaybackBackendIds.appleCompatibility, name: 'Apple compatibility playback'),
        ),
      ];

  static List<PlaybackBackendDescriptor> _androidBackends() => const <PlaybackBackendDescriptor>[
        PlaybackBackendDescriptor(
          id: PlaybackBackendIds.androidNative,
          displayName: 'Android native playback',
          availability: BackendAvailability.unavailable,
          priority: 10,
          capabilities: PlaybackBackendCapabilities(id: PlaybackBackendIds.androidNative, name: 'Android native playback'),
        ),
        PlaybackBackendDescriptor(
          id: PlaybackBackendIds.androidCompatibility,
          displayName: 'Android compatibility playback',
          availability: BackendAvailability.unavailable,
          priority: 20,
          capabilities: PlaybackBackendCapabilities(id: PlaybackBackendIds.androidCompatibility, name: 'Android compatibility playback'),
        ),
      ];

  static List<PlaybackBackendDescriptor> _windowsBackends() => const <PlaybackBackendDescriptor>[
        PlaybackBackendDescriptor(
          id: PlaybackBackendIds.windowsMpv,
          displayName: 'Windows native MPV playback',
          availability: BackendAvailability.unavailable,
          priority: 10,
          capabilities: PlaybackBackendCapabilities(id: PlaybackBackendIds.windowsMpv, name: 'Windows native MPV playback'),
        ),
      ];
}

class RegistryPlaybackBackendProbe implements PlaybackBackendProbe {
  const RegistryPlaybackBackendProbe({
    required this.platformFamily,
    this.registry = const PlaybackBackendRegistry(),
  });

  final PlatformFamily platformFamily;
  final PlaybackBackendRegistry registry;

  @override
  Future<List<PlaybackBackendDescriptor>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      registry.backendsFor(platformFamily);
}
