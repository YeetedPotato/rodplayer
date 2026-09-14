import 'package:rodplayer/core/playback/playback_environment.dart';

class JellyfinDeviceProfileMapper {
  const JellyfinDeviceProfileMapper();

  Map<String, dynamic> map(PlaybackEnvironment environment, PlaybackBackendCapabilities backend) {
    final profile = _effectiveProfile(environment, backend);
    return <String, dynamic>{
      'Name': environment.identity.clientName,
      'MaxStreamingBitrate': profile.maxStreamingBitrate,
      'MaxStaticBitrate': profile.maxStreamingBitrate,
      'DirectPlayProfiles': _directPlayProfiles(backend, profile),
      'TranscodingProfiles': _transcodingProfiles(profile),
      'CodecProfiles': <Map<String, dynamic>>[
        ...profile.videoCodecRules.map(_videoCodecProfile),
        ...profile.audioCodecRules.map(_audioCodecProfile),
      ],
      'SubtitleProfiles': _subtitleProfiles(backend, profile),
    };
  }

  EffectiveDeviceProfile _effectiveProfile(PlaybackEnvironment environment, PlaybackBackendCapabilities backend) {
    for (final profile in environment.effectiveProfiles) {
      if (profile.backendId == backend.id) return profile.deviceProfile;
    }
    return EffectiveDeviceProfile(
      maxStreamingBitrate: environment.network.maxStreamingBitrate,
      directPlayRules: backend.directPlayRules,
      transcodingRules: backend.transcodingRules,
      videoCodecRules: backend.videoCodecRules,
      audioCodecRules: backend.audioCodecRules,
      subtitleRules: backend.subtitleRules,
    );
  }

  List<Map<String, dynamic>> _directPlayProfiles(PlaybackBackendCapabilities backend, EffectiveDeviceProfile profile) {
    if (profile.directPlayRules.isNotEmpty) {
      return profile.directPlayRules
          .map((rule) => <String, dynamic>{
                'Container': rule.containers.join(','),
                'Type': rule.type,
                if (rule.videoCodecs.isNotEmpty) 'VideoCodec': rule.videoCodecs.join(','),
                if (rule.audioCodecs.isNotEmpty) 'AudioCodec': rule.audioCodecs.join(','),
              })
          .toList(growable: false);
    }
    return <Map<String, dynamic>>[
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
    ];
  }

  List<Map<String, dynamic>> _transcodingProfiles(EffectiveDeviceProfile profile) {
    final rules = profile.transcodingRules;
    if (rules.isEmpty) {
      return const <Map<String, dynamic>>[
        <String, dynamic>{'Container': 'ts', 'Type': 'Video', 'VideoCodec': 'h264', 'AudioCodec': 'aac,ac3,eac3', 'Protocol': 'http', 'Context': 'Streaming'},
        <String, dynamic>{'Container': 'mp3', 'Type': 'Audio', 'AudioCodec': 'mp3', 'Protocol': 'http', 'Context': 'Streaming'},
      ];
    }
    return rules
        .map((rule) => <String, dynamic>{
              'Container': rule.container,
              'Type': rule.type,
              if (rule.videoCodec != null) 'VideoCodec': rule.videoCodec,
              if (rule.audioCodec != null) 'AudioCodec': rule.audioCodec,
              'Protocol': rule.protocol,
              'Context': rule.context,
              'CopyTimestamps': true,
              'EnableMpegtsM2TsMode': rule.container == 'ts',
              'AllowVideoStreamCopy': rule.allowVideoStreamCopy,
              'AllowAudioStreamCopy': rule.allowAudioStreamCopy,
            })
        .toList(growable: false);
  }

  Map<String, dynamic> _videoCodecProfile(VideoCodecCapabilityRule rule) => <String, dynamic>{
        'Type': 'Video',
        'Codec': rule.codec,
        if (_videoConditions(rule).isNotEmpty) 'Conditions': _videoConditions(rule),
      };

  Map<String, dynamic> _audioCodecProfile(AudioCodecCapabilityRule rule) => <String, dynamic>{
        'Type': 'Audio',
        'Codec': rule.codec,
        if (rule.maxChannels != null)
          'Conditions': <Map<String, dynamic>>[
            <String, dynamic>{'Condition': 'LessThanEqual', 'Property': 'AudioChannels', 'Value': '${rule.maxChannels}', 'IsRequired': false},
          ],
      };

  List<Map<String, dynamic>> _videoConditions(VideoCodecCapabilityRule rule) => <Map<String, dynamic>>[
        if (rule.profiles.isNotEmpty) <String, dynamic>{'Condition': 'EqualsAny', 'Property': 'VideoProfile', 'Value': rule.profiles.join('|'), 'IsRequired': false},
        if (rule.levels.isNotEmpty) <String, dynamic>{'Condition': 'LessThanEqual', 'Property': 'VideoLevel', 'Value': '${rule.levels.reduce((a, b) => a > b ? a : b)}', 'IsRequired': false},
        if (rule.maxBitDepth != null) <String, dynamic>{'Condition': 'LessThanEqual', 'Property': 'VideoBitDepth', 'Value': '${rule.maxBitDepth}', 'IsRequired': false},
        if (rule.videoRangeTypes.isNotEmpty) <String, dynamic>{'Condition': 'EqualsAny', 'Property': 'VideoRangeType', 'Value': rule.videoRangeTypes.join('|'), 'IsRequired': false},
        if (rule.codecTags.isNotEmpty) <String, dynamic>{'Condition': 'EqualsAny', 'Property': 'VideoCodecTag', 'Value': rule.codecTags.join('|'), 'IsRequired': false},
        if (rule.maxBitrate != null) <String, dynamic>{'Condition': 'LessThanEqual', 'Property': 'VideoBitrate', 'Value': '${rule.maxBitrate}', 'IsRequired': false},
        if (rule.maxWidth != null) <String, dynamic>{'Condition': 'LessThanEqual', 'Property': 'Width', 'Value': '${rule.maxWidth}', 'IsRequired': false},
        if (rule.maxHeight != null) <String, dynamic>{'Condition': 'LessThanEqual', 'Property': 'Height', 'Value': '${rule.maxHeight}', 'IsRequired': false},
        if (rule.maxFrameRate != null) <String, dynamic>{'Condition': 'LessThanEqual', 'Property': 'VideoFramerate', 'Value': '${rule.maxFrameRate}', 'IsRequired': false},
      ];

  List<Map<String, dynamic>> _subtitleProfiles(PlaybackBackendCapabilities backend, EffectiveDeviceProfile profile) {
    if (profile.subtitleRules.isNotEmpty) {
      return profile.subtitleRules.map((rule) => <String, dynamic>{'Format': rule.codec, 'Method': rule.deliveryMethod}).toList(growable: false);
    }
    return backend.subtitleCodecs.map((codec) => <String, dynamic>{'Format': codec, 'Method': 'External'}).toList(growable: false);
  }
}
