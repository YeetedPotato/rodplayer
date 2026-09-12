import 'dart:io' show Platform;

class DeviceCapabilities {
  const DeviceCapabilities._();

  static Map<String, dynamic> currentDeviceProfile() {
    final deviceName = Platform.isAndroid
        ? 'Rod Android'
        : Platform.isIOS
            ? 'Rod iOS'
            : 'Rod Player';

    return <String, dynamic>{
      'Name': deviceName,
      'MaxStreamingBitrate': 140000000,
      'MaxStaticBitrate': 140000000,
      'DirectPlayProfiles': <Map<String, String>>[
        <String, String>{
          'Container': 'mp4,mkv,ts,m2ts',
          'Type': 'Video',
          'VideoCodec': 'h264,hevc',
          'AudioCodec': 'aac,ac3,eac3,truehd,dts,flac',
        },
      ],
      'TranscodingProfiles': <Map<String, String>>[
        <String, String>{
          'Container': 'ts',
          'Type': 'Video',
          'VideoCodec': 'h264,hevc',
          'AudioCodec': 'aac,ac3,eac3',
          'Protocol': 'hls',
        },
      ],
    };
  }
}
