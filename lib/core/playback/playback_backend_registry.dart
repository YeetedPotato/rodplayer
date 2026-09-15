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
    this.appleNativeAvailable = false,
  });

  final PlaybackBackendCapabilities mediaKitCapabilities;
  final bool appleNativeAvailable;

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
        PlatformFamily.ios => _appleBackends(appleNativeAvailable: appleNativeAvailable),
        PlatformFamily.macos => _appleBackends(appleNativeAvailable: appleNativeAvailable),
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

  static List<PlaybackBackendDescriptor> _appleBackends({required bool appleNativeAvailable}) => <PlaybackBackendDescriptor>[
        PlaybackBackendDescriptor(
          id: PlaybackBackendIds.appleNative,
          displayName: 'Apple native playback',
          availability: appleNativeAvailable ? BackendAvailability.available : BackendAvailability.unavailable,
          priority: 10,
          capabilities: appleNativeCapabilities,
        ),
        const PlaybackBackendDescriptor(
          id: PlaybackBackendIds.appleCompatibility,
          displayName: 'Apple compatibility playback',
          availability: BackendAvailability.unavailable,
          priority: 20,
          capabilities: PlaybackBackendCapabilities(id: PlaybackBackendIds.appleCompatibility, name: 'Apple compatibility playback'),
        ),
      ];

  static const PlaybackBackendCapabilities appleNativeCapabilities = PlaybackBackendCapabilities(
    id: PlaybackBackendIds.appleNative,
    name: 'Apple native playback',
    containers: <String>['mp4', 'mov', 'm4v', 'm3u8'],
    videoCodecs: <String>['h264', 'hevc'],
    audioCodecs: <String>['aac', 'ac3', 'eac3', 'mp3'],
    subtitleCodecs: <String>[],
    hardwareDecode: CapabilitySupport.unknown,
    softwareDecode: CapabilitySupport.unknown,
    passthrough: CapabilitySupport.unknown,
    localSubtitleRendering: CapabilitySupport.unknown,
    hdrOutputPreservation: CapabilitySupport.unknown,
    directPlayRules: <DirectPlayCapabilityRule>[
      DirectPlayCapabilityRule(containers: <String>['mp4', 'mov', 'm4v'], type: 'Video', videoCodecs: <String>['h264', 'hevc'], audioCodecs: <String>['aac', 'ac3', 'eac3', 'mp3']),
      DirectPlayCapabilityRule(containers: <String>['m3u8'], type: 'Video', videoCodecs: <String>['h264', 'hevc'], audioCodecs: <String>['aac', 'ac3', 'eac3']),
    ],
    videoCodecRules: <VideoCodecCapabilityRule>[
      VideoCodecCapabilityRule(codec: 'h264'),
      VideoCodecCapabilityRule(codec: 'hevc'),
    ],
    audioCodecRules: <AudioCodecCapabilityRule>[
      AudioCodecCapabilityRule(codec: 'aac'),
      AudioCodecCapabilityRule(codec: 'ac3'),
      AudioCodecCapabilityRule(codec: 'eac3'),
      AudioCodecCapabilityRule(codec: 'mp3'),
    ],
    subtitleRules: <SubtitleCapabilityRule>[],
    transcodingRules: <TranscodingCapabilityRule>[
      TranscodingCapabilityRule(type: 'Video', container: 'm3u8', videoCodec: 'h264', audioCodec: 'aac,ac3,eac3', protocol: 'hls', context: 'Streaming'),
      TranscodingCapabilityRule(type: 'Audio', container: 'mp3', audioCodec: 'mp3', protocol: 'http', context: 'Streaming'),
    ],
  );

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
