import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/device/installation_identity.dart';

enum CapabilitySupport {
  unknown,
  supported,
  unsupported;

  bool get isSupported => this == CapabilitySupport.supported;
}

enum PlatformFamily { android, ios, macos, windows, linux, web, fuchsia, unknown }

enum BackendAvailability { available, unavailable, unknown }

enum NetworkRoute { localLan, remoteDirect, remoteTunnel, offline, unknown }

enum MeteringState { unknown, metered, unmetered }

/// Stable app/device identity is separate from codec and output capability.
class DeviceIdentity {
  const DeviceIdentity({
    required this.installationId,
    required this.clientName,
    required this.appVersion,
    required this.platformFamily,
    required this.deviceName,
    this.deviceModel,
    this.isSynthetic = false,
  });

  final String installationId;
  final String clientName;
  final String appVersion;
  final PlatformFamily platformFamily;
  final String deviceName;
  final String? deviceModel;
  final bool isSynthetic;
}

class PlaybackEnvironment {
  const PlaybackEnvironment({
    required this.identity,
    required this.device,
    required this.compute,
    required this.display,
    required this.audio,
    required this.network,
    required this.backends,
    required this.effectiveProfiles,
  });

  final DeviceIdentity identity;
  final DeviceCapabilities device;
  final ComputeCapabilities compute;
  final DisplayCapabilities display;
  final AudioCapabilities audio;
  final NetworkCapabilities network;
  final List<PlaybackBackendDescriptor> backends;
  final List<EffectivePlaybackProfile> effectiveProfiles;

  PlaybackBackendDescriptor selectPreferredBackend({PlaybackBackendSelector selector = const PlaybackBackendSelector()}) => selector.select(backends);

  EffectivePlaybackProfile effectiveProfileFor(String backendId) => effectiveProfiles.firstWhere(
        (profile) => profile.backendId == backendId,
        orElse: () => throw StateError('No effective playback profile exists for backend "$backendId"'),
      );
}

class DeviceCapabilities {
  const DeviceCapabilities({
    required this.platformLabel,
    this.supportsDpadFocus = false,
    this.supportsKeyboardScrubbing = false,
  });

  final String platformLabel;
  final bool supportsDpadFocus;
  final bool supportsKeyboardScrubbing;
}

class ComputeCapabilities {
  const ComputeCapabilities({
    this.hardwareVideoDecoding = CapabilitySupport.unknown,
    this.softwareVideoDecoding = CapabilitySupport.unknown,
    this.hardwareAcceleration = CapabilitySupport.unknown,
    this.videoCodecs = const <VideoCodecComputeCapability>[],
    this.hdrMetadataDecode = const HdrDecodeCapabilities(),
  });

  final CapabilitySupport hardwareVideoDecoding;
  final CapabilitySupport softwareVideoDecoding;
  final CapabilitySupport hardwareAcceleration;
  final List<VideoCodecComputeCapability> videoCodecs;
  final HdrDecodeCapabilities hdrMetadataDecode;
}

class VideoCodecComputeCapability {
  const VideoCodecComputeCapability({
    required this.codec,
    this.support = CapabilitySupport.unknown,
    this.profiles = const <String>[],
    this.levels = const <int>[],
    this.maxBitDepth,
    this.maxWidth,
    this.maxHeight,
    this.maxFrameRate,
  });

  final String codec;
  final CapabilitySupport support;
  final List<String> profiles;
  final List<int> levels;
  final int? maxBitDepth;
  final int? maxWidth;
  final int? maxHeight;
  final double? maxFrameRate;
}

class HdrDecodeCapabilities {
  const HdrDecodeCapabilities({
    this.hdr10 = CapabilitySupport.unknown,
    this.hdr10PlusMetadata = CapabilitySupport.unknown,
    this.hlg = CapabilitySupport.unknown,
    this.dolbyVision = CapabilitySupport.unknown,
  });

  final CapabilitySupport hdr10;
  final CapabilitySupport hdr10PlusMetadata;
  final CapabilitySupport hlg;
  final CapabilitySupport dolbyVision;
}

/// Display output capability is intentionally distinct from source metadata and decoder support.
class DisplayCapabilities {
  const DisplayCapabilities({
    this.currentWidth,
    this.currentHeight,
    this.refreshRate,
    this.displayId,
    this.displayName,
    this.activeHdr = CapabilitySupport.unknown,
    this.outputColorCapability = CapabilitySupport.unknown,
    this.output = const HdrOutputCapabilities(),
    this.toneMapping = const ToneMappingCapabilities(),
  });

  final int? currentWidth;
  final int? currentHeight;
  final double? refreshRate;
  final String? displayId;
  final String? displayName;
  final CapabilitySupport activeHdr;
  final CapabilitySupport outputColorCapability;
  final HdrOutputCapabilities output;
  final ToneMappingCapabilities toneMapping;
}

class HdrOutputCapabilities {
  const HdrOutputCapabilities({
    this.hdr10 = CapabilitySupport.unknown,
    this.nativeHdr10Plus = CapabilitySupport.unknown,
    this.hlg = CapabilitySupport.unknown,
    this.nativeDolbyVision = CapabilitySupport.unknown,
  });

  final CapabilitySupport hdr10;
  final CapabilitySupport nativeHdr10Plus;
  final CapabilitySupport hlg;
  final CapabilitySupport nativeDolbyVision;
}

class ToneMappingCapabilities {
  const ToneMappingCapabilities({
    this.hdrToHdr = CapabilitySupport.unknown,
    this.hdrToSdr = CapabilitySupport.unknown,
  });

  final CapabilitySupport hdrToHdr;
  final CapabilitySupport hdrToSdr;
}

class AudioCapabilities {
  const AudioCapabilities({
    this.engine = const PlaybackEngineAudioCapabilities(),
    this.device = const DeviceAudioCapabilities(),
    this.route = const CurrentAudioRoute(),
    this.sink = const ConnectedSinkCapabilities(),
    this.effective = const EffectiveAudioCapabilities(),
  });

  final PlaybackEngineAudioCapabilities engine;
  final DeviceAudioCapabilities device;
  final CurrentAudioRoute route;
  final ConnectedSinkCapabilities sink;
  final EffectiveAudioCapabilities effective;
}

class PlaybackEngineAudioCapabilities {
  const PlaybackEngineAudioCapabilities({
    this.decodeCodecs = const <String, CapabilitySupport>{},
    this.passthroughCodecs = const <String, CapabilitySupport>{},
    this.pcmOutput = CapabilitySupport.unknown,
    this.maxChannels,
    this.sampleRates = const <int>[],
  });

  final Map<String, CapabilitySupport> decodeCodecs;
  final Map<String, CapabilitySupport> passthroughCodecs;
  final CapabilitySupport pcmOutput;
  final int? maxChannels;
  final List<int> sampleRates;
}

class DeviceAudioCapabilities {
  const DeviceAudioCapabilities({
    this.pcmOutput = CapabilitySupport.unknown,
    this.passthrough = CapabilitySupport.unknown,
    this.maxChannels,
    this.sampleRates = const <int>[],
  });

  final CapabilitySupport pcmOutput;
  final CapabilitySupport passthrough;
  final int? maxChannels;
  final List<int> sampleRates;
}

class CurrentAudioRoute {
  const CurrentAudioRoute({
    this.name,
    this.passthrough = CapabilitySupport.unknown,
    this.maxChannels,
  });

  final String? name;
  final CapabilitySupport passthrough;
  final int? maxChannels;
}

class ConnectedSinkCapabilities {
  const ConnectedSinkCapabilities({
    this.name,
    this.passthroughCodecs = const <String, CapabilitySupport>{},
    this.maxChannels,
    this.objectAudio = CapabilitySupport.unknown,
  });

  final String? name;
  final Map<String, CapabilitySupport> passthroughCodecs;
  final int? maxChannels;
  final CapabilitySupport objectAudio;
}

/// Audio fidelity and spatial/object metadata can diverge during playback.
class EffectiveAudioCapabilities {
  const EffectiveAudioCapabilities({
    this.fidelity = CapabilitySupport.unknown,
    this.spatialMetadata = CapabilitySupport.unknown,
    this.lossless = CapabilitySupport.unknown,
    this.objectAudio = CapabilitySupport.unknown,
    this.channelLayout,
    this.maxChannels,
  });

  final CapabilitySupport fidelity;
  final CapabilitySupport spatialMetadata;
  final CapabilitySupport lossless;
  final CapabilitySupport objectAudio;
  final String? channelLayout;
  final int? maxChannels;
}

class NetworkCapabilities {
  const NetworkCapabilities({
    this.route = NetworkRoute.unknown,
    this.metering = MeteringState.unknown,
    this.estimatedBandwidthBitsPerSecond,
    this.latencyMillis,
    this.activeServerEndpointType,
    this.maxStreamingBitrate = 120000000,
  });

  final NetworkRoute route;
  final MeteringState metering;
  final int? estimatedBandwidthBitsPerSecond;
  final int? latencyMillis;
  final String? activeServerEndpointType;
  final int maxStreamingBitrate;
}

class PlaybackBackendDescriptor {
  const PlaybackBackendDescriptor({
    required this.id,
    required this.displayName,
    required this.availability,
    required this.priority,
    required this.capabilities,
  });

  final String id;
  final String displayName;
  final BackendAvailability availability;
  final int priority;
  final PlaybackBackendCapabilities capabilities;
}

class PlaybackBackendSelectionException implements Exception {
  const PlaybackBackendSelectionException(this.message);

  final String message;

  @override
  String toString() => 'PlaybackBackendSelectionException: $message';
}

/// Selects the best currently usable backend. Lower priority values win.
class PlaybackBackendSelector {
  const PlaybackBackendSelector();

  PlaybackBackendDescriptor select(List<PlaybackBackendDescriptor> backends) {
    final available = backends.where((backend) => backend.availability == BackendAvailability.available).toList(growable: false);
    if (available.isEmpty) {
      throw const PlaybackBackendSelectionException('No available playback backend');
    }
    available.sort((a, b) {
      final priority = a.priority.compareTo(b.priority);
      if (priority != 0) return priority;
      return a.id.compareTo(b.id);
    });
    return available.first;
  }
}

class PlaybackBackendCapabilities {
  const PlaybackBackendCapabilities({
    required this.id,
    required this.name,
    this.containers = const <String>[],
    this.videoCodecs = const <String>[],
    this.audioCodecs = const <String>[],
    this.subtitleCodecs = const <String>[],
    this.unsupportedVideoCodecs = const <String>[],
    this.unsupportedAudioCodecs = const <String>[],
    this.directPlayRules = const <DirectPlayCapabilityRule>[],
    this.videoCodecRules = const <VideoCodecCapabilityRule>[],
    this.audioCodecRules = const <AudioCodecCapabilityRule>[],
    this.subtitleRules = const <SubtitleCapabilityRule>[],
    this.transcodingRules = const <TranscodingCapabilityRule>[],
    this.hardwareDecode = CapabilitySupport.unknown,
    this.softwareDecode = CapabilitySupport.unknown,
    this.passthrough = CapabilitySupport.unknown,
    this.localSubtitleRendering = CapabilitySupport.unknown,
    this.hdrOutputPreservation = CapabilitySupport.unknown,
    this.imageSubtitleRendering = CapabilitySupport.unknown,
    this.assSubtitleRendering = CapabilitySupport.unknown,
  });

  final String id;
  final String name;
  final List<String> containers;
  final List<String> videoCodecs;
  final List<String> audioCodecs;
  final List<String> subtitleCodecs;
  final List<String> unsupportedVideoCodecs;
  final List<String> unsupportedAudioCodecs;
  final List<DirectPlayCapabilityRule> directPlayRules;
  final List<VideoCodecCapabilityRule> videoCodecRules;
  final List<AudioCodecCapabilityRule> audioCodecRules;
  final List<SubtitleCapabilityRule> subtitleRules;
  final List<TranscodingCapabilityRule> transcodingRules;
  final CapabilitySupport hardwareDecode;
  final CapabilitySupport softwareDecode;
  final CapabilitySupport passthrough;
  final CapabilitySupport localSubtitleRendering;
  final CapabilitySupport hdrOutputPreservation;
  final CapabilitySupport imageSubtitleRendering;
  final CapabilitySupport assSubtitleRendering;

  bool supportsContainer(String container) => containers.contains(container.toLowerCase());

  bool supportsVideoCodec(String codec) => videoCodecSupport(codec).isSupported;

  bool supportsAudioCodec(String codec) => audioCodecSupport(codec).isSupported;

  CapabilitySupport videoCodecSupport(String codec) => _supportFor(codec, confirmed: videoCodecs, unsupported: unsupportedVideoCodecs);

  CapabilitySupport audioCodecSupport(String codec) => _supportFor(codec, confirmed: audioCodecs, unsupported: unsupportedAudioCodecs);

  static CapabilitySupport _supportFor(String value, {required List<String> confirmed, required List<String> unsupported}) {
    final normalized = value.toLowerCase();
    if (confirmed.any((codec) => codec.toLowerCase() == normalized)) return CapabilitySupport.supported;
    if (unsupported.any((codec) => codec.toLowerCase() == normalized)) return CapabilitySupport.unsupported;
    return CapabilitySupport.unknown;
  }
}

class DirectPlayCapabilityRule {
  const DirectPlayCapabilityRule({
    required this.containers,
    required this.type,
    this.videoCodecs = const <String>[],
    this.audioCodecs = const <String>[],
  });

  final List<String> containers;
  final String type;
  final List<String> videoCodecs;
  final List<String> audioCodecs;
}

class VideoCodecCapabilityRule {
  const VideoCodecCapabilityRule({
    required this.codec,
    this.profiles = const <String>[],
    this.levels = const <int>[],
    this.maxBitDepth,
    this.videoRangeTypes = const <String>[],
    this.codecTags = const <String>[],
    this.maxBitrate,
    this.maxWidth,
    this.maxHeight,
    this.maxFrameRate,
  });

  final String codec;
  final List<String> profiles;
  final List<int> levels;
  final int? maxBitDepth;
  final List<String> videoRangeTypes;
  final List<String> codecTags;
  final int? maxBitrate;
  final int? maxWidth;
  final int? maxHeight;
  final double? maxFrameRate;
}

class AudioCodecCapabilityRule {
  const AudioCodecCapabilityRule({required this.codec, this.maxChannels});

  final String codec;
  final int? maxChannels;
}

class SubtitleCapabilityRule {
  const SubtitleCapabilityRule({required this.codec, required this.deliveryMethod});

  final String codec;
  final String deliveryMethod;
}

class TranscodingCapabilityRule {
  const TranscodingCapabilityRule({
    required this.type,
    required this.container,
    required this.protocol,
    required this.context,
    this.videoCodec,
    this.audioCodec,
    this.allowVideoStreamCopy = true,
    this.allowAudioStreamCopy = true,
  });

  final String type;
  final String container;
  final String protocol;
  final String context;
  final String? videoCodec;
  final String? audioCodec;
  final bool allowVideoStreamCopy;
  final bool allowAudioStreamCopy;
}

class EffectivePlaybackProfile {
  const EffectivePlaybackProfile({
    required this.backendId,
    required this.deviceProfile,
    required this.capabilities,
  });

  final String backendId;
  final PlaybackBackendCapabilities capabilities;
  final EffectiveDeviceProfile deviceProfile;
}

/// Backend/environment-derived profile data consumed by Jellyfin mappers.
class EffectiveDeviceProfile {
  const EffectiveDeviceProfile({
    required this.maxStreamingBitrate,
    required this.directPlayRules,
    required this.transcodingRules,
    required this.videoCodecRules,
    required this.audioCodecRules,
    required this.subtitleRules,
  });

  final int maxStreamingBitrate;
  final List<DirectPlayCapabilityRule> directPlayRules;
  final List<TranscodingCapabilityRule> transcodingRules;
  final List<VideoCodecCapabilityRule> videoCodecRules;
  final List<AudioCodecCapabilityRule> audioCodecRules;
  final List<SubtitleCapabilityRule> subtitleRules;
}

abstract interface class PlaybackEnvironmentProvider {
  Future<PlaybackEnvironment> load();
}

abstract interface class EffectivePlaybackProfileResolver {
  EffectivePlaybackProfile resolve(PlaybackEnvironment environment, PlaybackBackendDescriptor backend);
}

/// Temporary bridge for the current media_kit path.
///
/// These Jellyfin profile rules are legacy conservative compatibility assumptions preserved
/// from Phase 1 so playback behavior does not regress. They are not runtime-proven OS,
/// display, audio route, or output-chain probe results.
class LegacyConservativePlaybackProfileResolver implements EffectivePlaybackProfileResolver {
  const LegacyConservativePlaybackProfileResolver();

  @override
  EffectivePlaybackProfile resolve(PlaybackEnvironment environment, PlaybackBackendDescriptor backend) => EffectivePlaybackProfile(
        backendId: backend.id,
        capabilities: backend.capabilities,
        deviceProfile: EffectiveDeviceProfile(
          maxStreamingBitrate: environment.network.maxStreamingBitrate,
          directPlayRules: backend.capabilities.directPlayRules,
          transcodingRules: backend.capabilities.transcodingRules,
          videoCodecRules: backend.capabilities.videoCodecRules,
          audioCodecRules: backend.capabilities.audioCodecRules,
          subtitleRules: backend.capabilities.subtitleRules,
        ),
      );
}

class ConservativePlaybackEnvironmentProvider implements PlaybackEnvironmentProvider {
  const ConservativePlaybackEnvironmentProvider({
    this.identity,
    this.identityStore,
    this.profileResolver = const LegacyConservativePlaybackProfileResolver(),
  });

  final InstallationIdentity? identity;
  final InstallationIdentityStore? identityStore;
  final EffectivePlaybackProfileResolver profileResolver;

  @override
  Future<PlaybackEnvironment> load() async {
    final identity = await _loadIdentity();
    const backend = PlaybackBackendDescriptor(
      id: 'media_kit',
      displayName: 'Default playback engine',
      availability: BackendAvailability.available,
      priority: 0,
      capabilities: ConservativePlaybackEnvironmentProvider.mediaKitCapabilities,
    );
    const network = NetworkCapabilities();
    final environmentWithoutProfiles = PlaybackEnvironment(
      identity: identity,
      device: DeviceCapabilities(
        platformLabel: _platformLabel(),
        supportsDpadFocus: defaultTargetPlatform == TargetPlatform.android,
        supportsKeyboardScrubbing: defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux,
      ),
      compute: const ComputeCapabilities(),
      display: const DisplayCapabilities(),
      audio: const AudioCapabilities(),
      network: network,
      backends: const <PlaybackBackendDescriptor>[backend],
      effectiveProfiles: const <EffectivePlaybackProfile>[],
    );
    return PlaybackEnvironment(
      identity: environmentWithoutProfiles.identity,
      device: environmentWithoutProfiles.device,
      compute: environmentWithoutProfiles.compute,
      display: environmentWithoutProfiles.display,
      audio: environmentWithoutProfiles.audio,
      network: environmentWithoutProfiles.network,
      backends: environmentWithoutProfiles.backends,
      effectiveProfiles: <EffectivePlaybackProfile>[
        profileResolver.resolve(environmentWithoutProfiles, backend),
      ],
    );
  }

  PlaybackBackendCapabilities loadBackend() => mediaKitCapabilities;

  static const PlaybackBackendCapabilities mediaKitCapabilities = PlaybackBackendCapabilities(
    id: 'media_kit',
    name: 'Default playback engine',
    containers: <String>['mp4', 'mkv', 'mov', 'webm', 'ts', 'm2ts'],
    videoCodecs: <String>['h264', 'hevc', 'vp9', 'av1'],
    audioCodecs: <String>['aac', 'ac3', 'eac3', 'flac', 'opus', 'vorbis', 'mp3'],
    subtitleCodecs: <String>['srt', 'ass', 'ssa', 'subrip', 'webvtt', 'pgssub'],
    localSubtitleRendering: CapabilitySupport.unknown,
    imageSubtitleRendering: CapabilitySupport.unknown,
    assSubtitleRendering: CapabilitySupport.unknown,
    directPlayRules: <DirectPlayCapabilityRule>[
      DirectPlayCapabilityRule(containers: <String>['mp4', 'mov'], type: 'Video', videoCodecs: <String>['h264', 'hevc'], audioCodecs: <String>['aac', 'ac3', 'eac3', 'mp3']),
      DirectPlayCapabilityRule(containers: <String>['mkv'], type: 'Video', videoCodecs: <String>['h264', 'hevc', 'vp9', 'av1'], audioCodecs: <String>['aac', 'ac3', 'eac3', 'flac', 'opus', 'vorbis', 'mp3']),
      DirectPlayCapabilityRule(containers: <String>['webm'], type: 'Video', videoCodecs: <String>['vp9', 'av1'], audioCodecs: <String>['opus', 'vorbis']),
      DirectPlayCapabilityRule(containers: <String>['ts', 'm2ts'], type: 'Video', videoCodecs: <String>['h264', 'hevc'], audioCodecs: <String>['aac', 'ac3', 'eac3']),
      DirectPlayCapabilityRule(containers: <String>['mp3', 'flac', 'aac', 'opus'], type: 'Audio', audioCodecs: <String>['mp3', 'flac', 'aac', 'opus']),
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
      AudioCodecCapabilityRule(codec: 'flac'),
      AudioCodecCapabilityRule(codec: 'opus'),
      AudioCodecCapabilityRule(codec: 'vorbis'),
      AudioCodecCapabilityRule(codec: 'mp3'),
    ],
    subtitleRules: <SubtitleCapabilityRule>[
      SubtitleCapabilityRule(codec: 'srt', deliveryMethod: 'External'),
      SubtitleCapabilityRule(codec: 'subrip', deliveryMethod: 'External'),
      SubtitleCapabilityRule(codec: 'webvtt', deliveryMethod: 'External'),
      SubtitleCapabilityRule(codec: 'ass', deliveryMethod: 'External'),
      SubtitleCapabilityRule(codec: 'ssa', deliveryMethod: 'External'),
      SubtitleCapabilityRule(codec: 'pgssub', deliveryMethod: 'Embed'),
    ],
    transcodingRules: <TranscodingCapabilityRule>[
      TranscodingCapabilityRule(type: 'Video', container: 'ts', videoCodec: 'h264', audioCodec: 'aac,ac3,eac3', protocol: 'http', context: 'Streaming'),
      TranscodingCapabilityRule(type: 'Audio', container: 'mp3', audioCodec: 'mp3', protocol: 'http', context: 'Streaming'),
    ],
  );

  Future<DeviceIdentity> _loadIdentity() async {
    final provided = identity;
    if (provided != null) {
      return _deviceIdentityFrom(provided);
    }
    final persisted = identityStore == null ? null : await identityStore!.load();
    if (persisted != null) {
      return _deviceIdentityFrom(persisted);
    }
    return DeviceIdentity(
      installationId: 'unknown',
      clientName: 'RodPlayer',
      appVersion: 'unknown',
      platformFamily: _platformFamily(),
      deviceName: _platformLabel(),
      isSynthetic: true,
    );
  }

  static DeviceIdentity _deviceIdentityFrom(InstallationIdentity identity) => DeviceIdentity(
        installationId: identity.deviceId,
        clientName: identity.clientName,
        appVersion: identity.appVersion,
        platformFamily: _platformFamily(),
        deviceName: identity.deviceName,
      );

  static String _platformLabel() {
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

  static PlatformFamily _platformFamily() {
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
}
