import 'package:flutter/services.dart';
import 'package:rodplayer/platform/playback/native/native_playback_capability_models.dart';

abstract interface class NativePlaybackCapabilityBridge {
  Future<NativeComputeProbeResult?> probeCompute();
  Future<NativeDisplayProbeResult?> probeDisplay();
  Future<NativeAudioProbeResult?> probeAudio();
}

class MethodChannelNativePlaybackCapabilityBridge implements NativePlaybackCapabilityBridge {
  const MethodChannelNativePlaybackCapabilityBridge({
    MethodChannel channel = const MethodChannel('rodplayer/playback_capabilities'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<NativeComputeProbeResult?> probeCompute() async {
    final payload = await _invoke('probeCompute');
    return NativeComputeProbeResult.fromJson(payload);
  }

  @override
  Future<NativeDisplayProbeResult?> probeDisplay() async {
    final payload = await _invoke('probeDisplay');
    return NativeDisplayProbeResult.fromJson(payload);
  }

  @override
  Future<NativeAudioProbeResult?> probeAudio() async {
    final payload = await _invoke('probeAudio');
    return NativeAudioProbeResult.fromJson(payload);
  }

  Future<Object?> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<Object?>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FormatException {
      return null;
    }
  }
}
