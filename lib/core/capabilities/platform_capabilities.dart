import 'package:flutter/foundation.dart';

class DeviceCapabilities {
  const DeviceCapabilities._();

  static Map<String, dynamic> currentDeviceProfile() {
    final deviceName = kIsWeb
        ? 'Remux Web'
        : defaultTargetPlatform == TargetPlatform.android
            ? 'Remux Android'
            : defaultTargetPlatform == TargetPlatform.iOS
                ? 'Remux iOS'
                : defaultTargetPlatform == TargetPlatform.macOS
                    ? 'Remux macOS'
                    : defaultTargetPlatform == TargetPlatform.windows
                        ? 'Remux Windows'
                        : 'Remux Desktop';

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
