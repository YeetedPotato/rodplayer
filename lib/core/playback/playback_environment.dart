import 'package:flutter/foundation.dart';

class PlaybackEnvironment {
  const PlaybackEnvironment({
    required this.device,
    required this.display,
    required this.audio,
    required this.network,
    required this.backends,
  });

  final DeviceCapabilities device;
  final DisplayCapabilities display;
  final AudioCapabilities audio;
  final NetworkCapabilities network;
  final List<PlaybackBackendCapabilities> backends;

  PlaybackBackendCapabilities get primaryBackend => backends.first;
}

class DeviceCapabilities {
  const DeviceCapabilities({required this.platformLabel, this.supportsDpadFocus = false, this.supportsKeyboardScrubbing = false});
  final String platformLabel;
  final bool supportsDpadFocus;
  final bool supportsKeyboardScrubbing;
}

class DisplayCapabilities {
  const DisplayCapabilities({this.canRenderHdr = false});
  final bool canRenderHdr;
}

class AudioCapabilities {
  const AudioCapabilities({this.passthroughCodecs = const <String>[]});
  final List<String> passthroughCodecs;
}

class NetworkCapabilities {
  const NetworkCapabilities({this.maxStreamingBitrate = 120000000});
  final int maxStreamingBitrate;
}

class PlaybackBackendCapabilities {
  const PlaybackBackendCapabilities({
    required this.id,
    required this.name,
    this.containers = const <String>[],
    this.videoCodecs = const <String>[],
    this.audioCodecs = const <String>[],
    this.subtitleCodecs = const <String>[],
    this.directPlayRules = const <DirectPlayCapabilityRule>[],
    this.videoCodecRules = const <VideoCodecCapabilityRule>[],
    this.audioCodecRules = const <AudioCodecCapabilityRule>[],
    this.subtitleRules = const <SubtitleCapabilityRule>[],
    this.transcodingRules = const <TranscodingCapabilityRule>[],
  });

  final String id;
  final String name;
  final List<String> containers;
  final List<String> videoCodecs;
  final List<String> audioCodecs;
  final List<String> subtitleCodecs;
  final List<DirectPlayCapabilityRule> directPlayRules;
  final List<VideoCodecCapabilityRule> videoCodecRules;
  final List<AudioCodecCapabilityRule> audioCodecRules;
  final List<SubtitleCapabilityRule> subtitleRules;
  final List<TranscodingCapabilityRule> transcodingRules;
}

class DirectPlayCapabilityRule {
  const DirectPlayCapabilityRule({required this.containers, required this.type, this.videoCodecs = const <String>[], this.audioCodecs = const <String>[]});
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

abstract interface class PlaybackEnvironmentProvider {
  Future<PlaybackEnvironment> load();
}

class ConservativePlaybackEnvironmentProvider implements PlaybackEnvironmentProvider {
  const ConservativePlaybackEnvironmentProvider();

  @override
  Future<PlaybackEnvironment> load() async => PlaybackEnvironment(
        device: DeviceCapabilities(
          platformLabel: _platformLabel(),
          supportsDpadFocus: defaultTargetPlatform == TargetPlatform.android,
          supportsKeyboardScrubbing: defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux,
        ),
        display: const DisplayCapabilities(),
        audio: const AudioCapabilities(),
        network: const NetworkCapabilities(),
        backends: const <PlaybackBackendCapabilities>[
          PlaybackBackendCapabilities(
            id: 'media_kit',
            name: 'media_kit',
            containers: <String>['mp4', 'mkv', 'mov', 'webm', 'ts', 'm2ts'],
            videoCodecs: <String>['h264', 'hevc', 'vp9', 'av1'],
            audioCodecs: <String>['aac', 'ac3', 'eac3', 'flac', 'opus', 'vorbis', 'mp3'],
            subtitleCodecs: <String>['srt', 'ass', 'ssa', 'subrip', 'webvtt', 'pgssub'],
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
          ),
        ],
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
}
