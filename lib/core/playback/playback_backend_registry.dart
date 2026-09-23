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
    this.mediaKitAvailable = true,
    this.appleNativeAvailable = false,
    this.appleCompatibilityAvailable = false,
    this.androidNativeAvailable = false,
    this.androidCompatibilityAvailable = false,
  });

  final PlaybackBackendCapabilities mediaKitCapabilities;
  final bool mediaKitAvailable;
  final bool appleNativeAvailable;
  final bool appleCompatibilityAvailable;
  final bool androidNativeAvailable;
  final bool androidCompatibilityAvailable;

  List<PlaybackBackendDescriptor> backendsFor(PlatformFamily platformFamily) {
    final descriptors = <PlaybackBackendDescriptor>[
      PlaybackBackendDescriptor(
        id: PlaybackBackendIds.mediaKit,
        displayName: 'Default playback engine',
        availability: mediaKitAvailable ? BackendAvailability.available : BackendAvailability.unavailable,
        priority: 30,
        capabilities: mediaKitCapabilities,
      ),
      ...switch (platformFamily) {
        PlatformFamily.android => _androidBackends(androidNativeAvailable: androidNativeAvailable, androidCompatibilityAvailable: androidCompatibilityAvailable),
        PlatformFamily.ios => _appleBackends(appleNativeAvailable: appleNativeAvailable, appleCompatibilityAvailable: appleCompatibilityAvailable),
        PlatformFamily.macos => _appleBackends(appleNativeAvailable: appleNativeAvailable, appleCompatibilityAvailable: appleCompatibilityAvailable),
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

  static List<PlaybackBackendDescriptor> _appleBackends({required bool appleNativeAvailable, required bool appleCompatibilityAvailable}) => <PlaybackBackendDescriptor>[
        PlaybackBackendDescriptor(
          id: PlaybackBackendIds.appleNative,
          displayName: 'Apple native playback',
          availability: appleNativeAvailable ? BackendAvailability.available : BackendAvailability.unavailable,
          priority: 10,
          capabilities: appleNativeCapabilities,
        ),
        PlaybackBackendDescriptor(
          id: PlaybackBackendIds.appleCompatibility,
          displayName: 'Apple compatibility playback',
          availability: appleCompatibilityAvailable ? BackendAvailability.available : BackendAvailability.unavailable,
          priority: 20,
          capabilities: appleCompatibilityCapabilities,
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

  static const PlaybackBackendCapabilities appleCompatibilityCapabilities = PlaybackBackendCapabilities(
    id: PlaybackBackendIds.appleCompatibility,
    name: 'Apple compatibility playback',
    containers: <String>['mkv', 'mp4', 'mov', 'mpegts', 'avi', 'webm', 'm3u8'],
    videoCodecs: <String>['h264', 'hevc', 'vp9', 'av1', 'mpeg2', 'mpeg4'],
    audioCodecs: <String>['aac', 'ac3', 'eac3', 'flac', 'mp3', 'opus', 'vorbis', 'alac', 'pcm'],
    subtitleCodecs: <String>['srt', 'ass', 'ssa', 'webvtt'],
    softwareDecode: CapabilitySupport.supported,
    hardwareDecode: CapabilitySupport.unknown,
    passthrough: CapabilitySupport.unknown,
    localSubtitleRendering: CapabilitySupport.supported,
    hdrOutputPreservation: CapabilitySupport.unknown,
    directPlayRules: <DirectPlayCapabilityRule>[
      DirectPlayCapabilityRule(containers: <String>['mkv', 'mp4', 'mov', 'mpegts', 'avi', 'webm', 'm3u8'], type: 'Video', videoCodecs: <String>['h264', 'hevc', 'vp9', 'av1', 'mpeg2', 'mpeg4'], audioCodecs: <String>['aac', 'ac3', 'eac3', 'flac', 'mp3', 'opus', 'vorbis', 'alac', 'pcm']),
    ],
    videoCodecRules: <VideoCodecCapabilityRule>[
      VideoCodecCapabilityRule(codec: 'h264'),
      VideoCodecCapabilityRule(codec: 'hevc'),
      VideoCodecCapabilityRule(codec: 'vp9'),
      VideoCodecCapabilityRule(codec: 'av1'),
      VideoCodecCapabilityRule(codec: 'mpeg2'),
      VideoCodecCapabilityRule(codec: 'mpeg4'),
    ],
    audioCodecRules: <AudioCodecCapabilityRule>[
      AudioCodecCapabilityRule(codec: 'aac'),
      AudioCodecCapabilityRule(codec: 'ac3'),
      AudioCodecCapabilityRule(codec: 'eac3'),
      AudioCodecCapabilityRule(codec: 'flac'),
      AudioCodecCapabilityRule(codec: 'mp3'),
      AudioCodecCapabilityRule(codec: 'opus'),
      AudioCodecCapabilityRule(codec: 'vorbis'),
      AudioCodecCapabilityRule(codec: 'alac'),
      AudioCodecCapabilityRule(codec: 'pcm'),
    ],
    subtitleRules: <SubtitleCapabilityRule>[
      SubtitleCapabilityRule(codec: 'srt', deliveryMethod: 'Embed'),
      SubtitleCapabilityRule(codec: 'ass', deliveryMethod: 'Embed'),
      SubtitleCapabilityRule(codec: 'ssa', deliveryMethod: 'Embed'),
      SubtitleCapabilityRule(codec: 'webvtt', deliveryMethod: 'Embed'),
    ],
    transcodingRules: <TranscodingCapabilityRule>[
      TranscodingCapabilityRule(type: 'Video', container: 'm3u8', videoCodec: 'h264', audioCodec: 'aac,ac3,eac3', protocol: 'hls', context: 'Streaming'),
      TranscodingCapabilityRule(type: 'Audio', container: 'mp3', audioCodec: 'mp3', protocol: 'http', context: 'Streaming'),
    ],
  );

  static List<PlaybackBackendDescriptor> _androidBackends({required bool androidNativeAvailable, required bool androidCompatibilityAvailable}) => <PlaybackBackendDescriptor>[
        PlaybackBackendDescriptor(
          id: PlaybackBackendIds.androidNative,
          displayName: 'Android native playback',
          availability: androidNativeAvailable ? BackendAvailability.available : BackendAvailability.unavailable,
          priority: 10,
          capabilities: androidNativeCapabilities,
        ),
        PlaybackBackendDescriptor(
          id: PlaybackBackendIds.androidCompatibility,
          displayName: 'Android compatibility playback',
          availability: androidCompatibilityAvailable ? BackendAvailability.available : BackendAvailability.unavailable,
          priority: 20,
          capabilities: androidCompatibilityCapabilities,
        ),
      ];

  static const PlaybackBackendCapabilities androidNativeCapabilities = PlaybackBackendCapabilities(
    id: PlaybackBackendIds.androidNative,
    name: 'Android native playback',
    containers: <String>['mp4', 'm4v', 'webm', 'm3u8'],
    videoCodecs: <String>['h264', 'hevc', 'vp9', 'av1'],
    audioCodecs: <String>['aac', 'ac3', 'eac3', 'opus', 'vorbis', 'flac', 'mp3'],
    subtitleCodecs: <String>[],
    hardwareDecode: CapabilitySupport.unknown,
    softwareDecode: CapabilitySupport.unknown,
    passthrough: CapabilitySupport.unknown,
    localSubtitleRendering: CapabilitySupport.unknown,
    hdrOutputPreservation: CapabilitySupport.unknown,
    directPlayRules: <DirectPlayCapabilityRule>[
      DirectPlayCapabilityRule(containers: <String>['mp4', 'm4v'], type: 'Video', videoCodecs: <String>['h264', 'hevc'], audioCodecs: <String>['aac', 'ac3', 'eac3', 'mp3']),
      DirectPlayCapabilityRule(containers: <String>['webm'], type: 'Video', videoCodecs: <String>['vp9', 'av1'], audioCodecs: <String>['opus', 'vorbis']),
      DirectPlayCapabilityRule(containers: <String>['m3u8'], type: 'Video', videoCodecs: <String>['h264', 'hevc'], audioCodecs: <String>['aac', 'ac3', 'eac3']),
    ],
    videoCodecRules: <VideoCodecCapabilityRule>[
      VideoCodecCapabilityRule(codec: 'h264'),
      VideoCodecCapabilityRule(codec: 'hevc'),
      VideoCodecCapabilityRule(codec: 'vp9'),
      VideoCodecCapabilityRule(codec: 'av1'),
    ],
    audioCodecRules: <AudioCodecCapabilityRule>[
      AudioCodecCapabilityRule(codec: 'aac'),
      AudioCodecCapabilityRule(codec: 'ac3'),
      AudioCodecCapabilityRule(codec: 'eac3'),
      AudioCodecCapabilityRule(codec: 'opus'),
      AudioCodecCapabilityRule(codec: 'vorbis'),
      AudioCodecCapabilityRule(codec: 'flac'),
      AudioCodecCapabilityRule(codec: 'mp3'),
    ],
    subtitleRules: <SubtitleCapabilityRule>[],
    transcodingRules: <TranscodingCapabilityRule>[
      TranscodingCapabilityRule(type: 'Video', container: 'm3u8', videoCodec: 'h264', audioCodec: 'aac,ac3,eac3', protocol: 'hls', context: 'Streaming'),
      TranscodingCapabilityRule(type: 'Audio', container: 'mp3', audioCodec: 'mp3', protocol: 'http', context: 'Streaming'),
    ],
  );

  static const PlaybackBackendCapabilities androidCompatibilityCapabilities = PlaybackBackendCapabilities(
    id: PlaybackBackendIds.androidCompatibility,
    name: 'Android compatibility playback',
    containers: <String>['mkv', 'mp4', 'm4v', 'mov', 'mpegts', 'avi', 'webm', 'm3u8'],
    videoCodecs: <String>['h264', 'hevc', 'vp9', 'av1', 'mpeg2', 'mpeg4'],
    audioCodecs: <String>['aac', 'ac3', 'eac3', 'flac', 'mp3', 'opus', 'vorbis', 'alac', 'pcm'],
    subtitleCodecs: <String>['srt', 'ass', 'ssa', 'webvtt'],
    softwareDecode: CapabilitySupport.supported,
    hardwareDecode: CapabilitySupport.unknown,
    passthrough: CapabilitySupport.unknown,
    localSubtitleRendering: CapabilitySupport.supported,
    hdrOutputPreservation: CapabilitySupport.unknown,
    directPlayRules: <DirectPlayCapabilityRule>[
      DirectPlayCapabilityRule(containers: <String>['mkv', 'mp4', 'm4v', 'mov', 'mpegts', 'avi', 'webm', 'm3u8'], type: 'Video', videoCodecs: <String>['h264', 'hevc', 'vp9', 'av1', 'mpeg2', 'mpeg4'], audioCodecs: <String>['aac', 'ac3', 'eac3', 'flac', 'mp3', 'opus', 'vorbis', 'alac', 'pcm']),
    ],
    videoCodecRules: <VideoCodecCapabilityRule>[
      VideoCodecCapabilityRule(codec: 'h264'),
      VideoCodecCapabilityRule(codec: 'hevc'),
      VideoCodecCapabilityRule(codec: 'vp9'),
      VideoCodecCapabilityRule(codec: 'av1'),
      VideoCodecCapabilityRule(codec: 'mpeg2'),
      VideoCodecCapabilityRule(codec: 'mpeg4'),
    ],
    audioCodecRules: <AudioCodecCapabilityRule>[
      AudioCodecCapabilityRule(codec: 'aac'),
      AudioCodecCapabilityRule(codec: 'ac3'),
      AudioCodecCapabilityRule(codec: 'eac3'),
      AudioCodecCapabilityRule(codec: 'flac'),
      AudioCodecCapabilityRule(codec: 'mp3'),
      AudioCodecCapabilityRule(codec: 'opus'),
      AudioCodecCapabilityRule(codec: 'vorbis'),
      AudioCodecCapabilityRule(codec: 'alac'),
      AudioCodecCapabilityRule(codec: 'pcm'),
    ],
    subtitleRules: <SubtitleCapabilityRule>[
      SubtitleCapabilityRule(codec: 'srt', deliveryMethod: 'Embed'),
      SubtitleCapabilityRule(codec: 'ass', deliveryMethod: 'Embed'),
      SubtitleCapabilityRule(codec: 'ssa', deliveryMethod: 'Embed'),
      SubtitleCapabilityRule(codec: 'webvtt', deliveryMethod: 'Embed'),
    ],
    transcodingRules: <TranscodingCapabilityRule>[
      TranscodingCapabilityRule(type: 'Video', container: 'm3u8', videoCodec: 'h264', audioCodec: 'aac,ac3,eac3', protocol: 'hls', context: 'Streaming'),
      TranscodingCapabilityRule(type: 'Audio', container: 'mp3', audioCodec: 'mp3', protocol: 'http', context: 'Streaming'),
    ],
  );

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
