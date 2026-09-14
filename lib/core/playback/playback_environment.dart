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
    required this.containers,
    required this.videoCodecs,
    required this.audioCodecs,
    required this.subtitleCodecs,
  });

  final String id;
  final String name;
  final List<String> containers;
  final List<String> videoCodecs;
  final List<String> audioCodecs;
  final List<String> subtitleCodecs;
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
