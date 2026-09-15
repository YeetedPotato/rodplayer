import 'dart:async';

import 'package:flutter/services.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';
import 'package:rodplayer/platform/playback/native/native_playback_capability_models.dart';

abstract interface class NativePlaybackCapabilityBridge {
  Future<NativeComputeProbeResult?> probeCompute();
  Future<NativeDisplayProbeResult?> probeDisplay();
  Future<NativeAudioProbeResult?> probeAudio();
}

class MethodChannelPlaybackEnvironmentEventSource implements PlaybackEnvironmentEventSource {
  MethodChannelPlaybackEnvironmentEventSource({
    EventChannel channel = const EventChannel('rodplayer/playback_capability_events'),
  }) {
    _subscription = channel.receiveBroadcastStream().listen(_handleEvent, onError: _handleError);
  }

  late final StreamSubscription<dynamic> _subscription;
  final _controller = StreamController<PlaybackEnvironmentRefreshReason>.broadcast();

  @override
  Stream<PlaybackEnvironmentRefreshReason> get refreshReasons => _controller.stream;

  @override
  Future<void> dispose() async {
    await _subscription.cancel();
    await _controller.close();
  }

  void _handleEvent(Object? event) {
    final reason = _reasonFromEvent(event);
    if (reason != null) _controller.add(reason);
  }

  void _handleError(Object _) {}

  PlaybackEnvironmentRefreshReason? _reasonFromEvent(Object? event) {
    if (event is! String) return null;
    return switch (event) {
      'displayChanged' => PlaybackEnvironmentRefreshReason.displayChanged,
      'audioRouteChanged' => PlaybackEnvironmentRefreshReason.audioRouteChanged,
      'resume' => PlaybackEnvironmentRefreshReason.resume,
      'backendAvailabilityChanged' => PlaybackEnvironmentRefreshReason.backendAvailabilityChanged,
      _ => null,
    };
  }
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
