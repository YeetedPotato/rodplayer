import 'package:rodplayer/core/playback/playback_environment.dart';

class JellyfinDeviceProfileMapper {
  const JellyfinDeviceProfileMapper();

  Map<String, dynamic> map(PlaybackEnvironment environment, PlaybackBackendCapabilities backend) => <String, dynamic>{
        'Name': 'RodPlayer',
        'MaxStreamingBitrate': environment.network.maxStreamingBitrate,
        'MaxStaticBitrate': environment.network.maxStreamingBitrate,
        'DirectPlayProfiles': <Map<String, dynamic>>[
          <String, dynamic>{
            'Container': backend.containers.join(','),
            'Type': 'Video',
            'VideoCodec': backend.videoCodecs.join(','),
            'AudioCodec': backend.audioCodecs.join(','),
          },
          <String, dynamic>{
            'Container': backend.containers.join(','),
            'Type': 'Audio',
            'AudioCodec': backend.audioCodecs.join(','),
          },
        ],
        'TranscodingProfiles': const <Map<String, dynamic>>[
          <String, dynamic>{'Container': 'ts', 'Type': 'Video', 'VideoCodec': 'h264', 'AudioCodec': 'aac,ac3,eac3', 'Protocol': 'http', 'Context': 'Streaming'},
          <String, dynamic>{'Container': 'mp3', 'Type': 'Audio', 'AudioCodec': 'mp3', 'Protocol': 'http', 'Context': 'Streaming'},
        ],
        'CodecProfiles': <Map<String, dynamic>>[
          <String, dynamic>{'Type': 'Video', 'Codec': backend.videoCodecs.join(',')},
          <String, dynamic>{'Type': 'Audio', 'Codec': backend.audioCodecs.join(',')},
        ],
        'SubtitleProfiles': backend.subtitleCodecs.map((codec) => <String, dynamic>{'Format': codec, 'Method': codec == 'pgssub' ? 'Embed' : 'External'}).toList(growable: false),
      };
}
