import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';
import 'package:rodplayer/platform/playback/native/native_playback_capability_adapters.dart';
import 'package:rodplayer/platform/playback/native/native_playback_capability_bridge.dart';

class NativeComputeCapabilityProbe implements ComputeCapabilityProbe {
  const NativeComputeCapabilityProbe({
    required this.bridge,
    this.adapter = const NativeComputeCapabilityAdapter(),
  });

  final NativePlaybackCapabilityBridge bridge;
  final NativeComputeCapabilityAdapter adapter;

  @override
  Future<PlaybackProbeUpdate<ComputeCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      adapter.convert(await bridge.probeCompute());
}

class NativeDisplayCapabilityProbe implements DisplayCapabilityProbe {
  const NativeDisplayCapabilityProbe({
    required this.bridge,
    this.adapter = const NativeDisplayCapabilityAdapter(),
  });

  final NativePlaybackCapabilityBridge bridge;
  final NativeDisplayCapabilityAdapter adapter;

  @override
  Future<PlaybackProbeUpdate<DisplayCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      adapter.convert(await bridge.probeDisplay());
}

class NativeAudioCapabilityProbe implements AudioCapabilityProbe {
  const NativeAudioCapabilityProbe({
    required this.bridge,
    this.adapter = const NativeAudioCapabilityAdapter(),
  });

  final NativePlaybackCapabilityBridge bridge;
  final NativeAudioCapabilityAdapter adapter;

  @override
  Future<PlaybackProbeUpdate<AudioCapabilities>> probe({
    PlaybackEnvironment? previous,
    required PlaybackEnvironmentRefreshReason reason,
  }) async =>
      adapter.convert(await bridge.probeAudio());
}
