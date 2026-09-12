import 'dart:io';

enum PlatformProfile { ios, fireTv4kMax, fireTvLite, macos, windows }

class DeviceCapabilities {
  const DeviceCapabilities({required this.profile, required this.videoCodecs, required this.audioCodecs, required this.containers, this.maxStreamingBitrate = 140000000, this.subtitleCodecs = const ['srt', 'ass', 'ssa', 'subrip', 'webvtt']});
  final PlatformProfile profile;
  final List<String> videoCodecs;
  final List<String> audioCodecs;
  final List<String> containers;
  final int maxStreamingBitrate;
  final List<String> subtitleCodecs;

  Map<String, dynamic> toDeviceProfile() => {
    'Name': 'Remux ${profile.name}', 'MaxStreamingBitrate': maxStreamingBitrate,
    'MaxStaticBitrate': maxStreamingBitrate, 'DirectPlayProfiles': [{
      'Container': containers.join(','), 'Type': 'Video',
      'VideoCodec': videoCodecs.join(','), 'AudioCodec': audioCodecs.join(','),
    }],
    'CodecProfiles': [],
    'SubtitleProfiles': [for (final format in subtitleCodecs) {'Format': format, 'Method': 'External'}],
    'TranscodingProfiles': [{'Container': 'ts', 'Type': 'Video', 'VideoCodec': 'h264,hevc', 'AudioCodec': 'aac,ac3,eac3', 'Protocol': 'http', 'Context': 'Streaming'}],
  };

  static DeviceCapabilities forProfile(PlatformProfile profile) => switch (profile) {
    PlatformProfile.ios => const DeviceCapabilities(profile: PlatformProfile.ios, videoCodecs: ['h264', 'hevc'], audioCodecs: ['aac', 'ac3', 'eac3', 'alac'], containers: ['mp4', 'mov', 'm4v', 'mkv', 'ts']),
    PlatformProfile.fireTv4kMax => const DeviceCapabilities(profile: PlatformProfile.fireTv4kMax, videoCodecs: ['h264', 'hevc'], audioCodecs: ['aac', 'ac3', 'eac3', 'truehd', 'dts', 'flac'], containers: ['mp4', 'mkv', 'ts', 'm2ts'], maxStreamingBitrate: 200000000),
    PlatformProfile.fireTvLite => const DeviceCapabilities(profile: PlatformProfile.fireTvLite, videoCodecs: ['h264', 'hevc'], audioCodecs: ['aac', 'ac3', 'eac3'], containers: ['mp4', 'mkv', 'ts'], maxStreamingBitrate: 100000000),
    PlatformProfile.macos => const DeviceCapabilities(profile: PlatformProfile.macos, videoCodecs: ['h264', 'hevc'], audioCodecs: ['aac', 'ac3', 'eac3', 'truehd', 'dts', 'flac', 'alac'], containers: ['mp4', 'mkv', 'mov', 'ts', 'm2ts'], maxStreamingBitrate: 200000000),
    PlatformProfile.windows => const DeviceCapabilities(profile: PlatformProfile.windows, videoCodecs: ['h264', 'hevc'], audioCodecs: ['aac', 'ac3', 'eac3', 'truehd', 'dts', 'flac'], containers: ['mp4', 'mkv', 'webm', 'ts', 'm2ts'], maxStreamingBitrate: 200000000),
  };

  static PlatformProfile currentProfile() => Platform.isIOS ? PlatformProfile.ios : Platform.isMacOS ? PlatformProfile.macos : Platform.isWindows ? PlatformProfile.windows : PlatformProfile.fireTv4kMax;
  static Map<String, dynamic> currentDeviceProfile() => forProfile(currentProfile()).toDeviceProfile();
}