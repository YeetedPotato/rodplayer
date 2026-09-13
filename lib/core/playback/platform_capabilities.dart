import 'package:flutter/foundation.dart';

enum PlatformProfile { ios, fireTv, androidTv, androidMobile, macos, windows, web }

class DeviceCapabilities {
  const DeviceCapabilities({required this.profile, required this.videoCodecs, required this.audioCodecs, required this.containers, this.maxStreamingBitrate = 140000000, this.supportsHdr10 = false, this.supportsDolbyVision = false, this.supportsAv1 = false, this.supportsDpadFocus = false, this.supportsKeyboardScrubbing = false, this.hardwareAcceleration = false, this.audioPassthrough = const <String>[], this.subtitleCodecs = const ['srt', 'ass', 'ssa', 'subrip', 'webvtt']});
  final PlatformProfile profile;
  final List<String> videoCodecs;
  final List<String> audioCodecs;
  final List<String> containers;
  final int maxStreamingBitrate;
  final bool supportsHdr10;
  final bool supportsDolbyVision;
  final bool supportsAv1;
  final bool supportsDpadFocus;
  final bool supportsKeyboardScrubbing;
  final bool hardwareAcceleration;
  final List<String> audioPassthrough;
  final List<String> subtitleCodecs;

  Map<String, dynamic> toDeviceProfile() => {'Name': 'RodPlayer ${profile.name}', 'MaxStreamingBitrate': maxStreamingBitrate, 'MaxStaticBitrate': maxStreamingBitrate, 'VideoCodecs': videoCodecs, 'AudioCodecs': audioCodecs, 'Containers': containers, 'SupportsHDR10': supportsHdr10, 'SupportsDolbyVision': supportsDolbyVision, 'SupportsAV1': supportsAv1, 'SupportsDpadFocus': supportsDpadFocus, 'SupportsKeyboardScrubbing': supportsKeyboardScrubbing, 'HardwareAcceleration': hardwareAcceleration, 'AudioPassthrough': audioPassthrough, 'DirectPlayProfiles': [{'Container': containers.join(','), 'Type': 'Video', 'VideoCodec': videoCodecs.join(','), 'AudioCodec': audioCodecs.join(',')}], 'TranscodingProfiles': [{'Container': 'ts', 'Type': 'Video', 'VideoCodec': 'h264,hevc', 'AudioCodec': 'aac,ac3,eac3', 'Protocol': 'http', 'Context': 'Streaming'}]};

  static DeviceCapabilities forProfile(PlatformProfile profile) => switch (profile) {
    PlatformProfile.ios => const DeviceCapabilities(profile: PlatformProfile.ios, videoCodecs: ['h264', 'hevc', 'av1'], audioCodecs: ['aac', 'ac3', 'eac3'], containers: ['mp4', 'mov', 'mkv'], supportsHdr10: true, supportsDolbyVision: true, supportsAv1: true),
    PlatformProfile.fireTv => const DeviceCapabilities(profile: PlatformProfile.fireTv, videoCodecs: ['h264', 'hevc'], audioCodecs: ['aac', 'ac3', 'eac3'], containers: ['mp4', 'mkv', 'ts', 'm2ts'], maxStreamingBitrate: 200000000, supportsDpadFocus: true, audioPassthrough: ['ac3', 'eac3', 'dts', 'truehd']),
    PlatformProfile.androidTv => const DeviceCapabilities(profile: PlatformProfile.androidTv, videoCodecs: ['h264', 'hevc'], audioCodecs: ['aac', 'ac3', 'eac3'], containers: ['mp4', 'mkv', 'ts'], maxStreamingBitrate: 180000000, supportsDpadFocus: true, audioPassthrough: ['ac3', 'eac3', 'dts']),
    PlatformProfile.androidMobile => const DeviceCapabilities(profile: PlatformProfile.androidMobile, videoCodecs: ['h264', 'hevc'], audioCodecs: ['aac', 'ac3', 'eac3'], containers: ['mp4', 'mkv', 'ts'], maxStreamingBitrate: 100000000),
    PlatformProfile.macos => const DeviceCapabilities(profile: PlatformProfile.macos, videoCodecs: ['h264', 'hevc', 'av1', 'vp9', 'vp8', 'mpeg2video'], audioCodecs: ['aac', 'ac3', 'eac3', 'truehd', 'dts', 'flac', 'alac'], containers: ['mp4', 'mkv', 'mov', 'ts', 'm2ts'], maxStreamingBitrate: 400000000, supportsHdr10: true, supportsDolbyVision: true, supportsKeyboardScrubbing: true, hardwareAcceleration: true, audioPassthrough: ['ac3', 'eac3', 'dts', 'truehd']),
    PlatformProfile.windows => const DeviceCapabilities(profile: PlatformProfile.windows, videoCodecs: ['h264', 'hevc', 'av1', 'vp9', 'vp8', 'mpeg2video', 'mpeg4'], audioCodecs: ['aac', 'ac3', 'eac3', 'truehd', 'dts', 'flac', 'alac', 'opus'], containers: ['mp4', 'mkv', 'mov', 'webm', 'ts', 'm2ts', 'avi'], maxStreamingBitrate: 400000000, supportsHdr10: true, hardwareAcceleration: true, audioPassthrough: ['ac3', 'eac3', 'dts', 'truehd']),
    PlatformProfile.web => const DeviceCapabilities(profile: PlatformProfile.web, videoCodecs: ['h264', 'vp9', 'av1'], audioCodecs: ['aac', 'opus', 'vorbis'], containers: ['mp4', 'webm', 'm3u8']),
  };

  static PlatformProfile currentProfile() => kIsWeb ? PlatformProfile.web : defaultTargetPlatform == TargetPlatform.iOS ? PlatformProfile.ios : defaultTargetPlatform == TargetPlatform.macOS ? PlatformProfile.macos : defaultTargetPlatform == TargetPlatform.windows ? PlatformProfile.windows : PlatformProfile.androidMobile;
  static Map<String, dynamic> currentDeviceProfile() => forProfile(currentProfile()).toDeviceProfile();
}
