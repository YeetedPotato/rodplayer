import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rodplayer/core/playback/playback_backend_registry.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';

abstract interface class AndroidNativePlaybackBridge {
  bool get isHostAvailable;
  Future<bool> confirmHostAvailable();
  Future<String> create(Uri uri);
  Future<void> play(String handle);
  Future<void> pause(String handle);
  Future<void> seek(String handle, Duration position);
  Future<void> stop(String handle);
  Future<void> setVolume(String handle, double value);
  Future<void> setMuted(String handle, bool muted);
  Future<void> dispose(String handle);
  Stream<AndroidNativePlaybackEvent> events(String handle);
}

class AndroidNativePlaybackEvent {
  const AndroidNativePlaybackEvent({
    required this.handle,
    this.playing,
    this.buffering,
    this.position,
    this.duration,
    this.volume,
    this.muted,
    this.error,
    this.ended,
  });

  final String handle;
  final bool? playing;
  final bool? buffering;
  final Duration? position;
  final Duration? duration;
  final double? volume;
  final bool? muted;
  final String? error;
  final bool? ended;

  static AndroidNativePlaybackEvent? fromPayload(Object? payload) {
    if (payload is! Map) return null;
    final handle = payload['handle'];
    if (handle is! String || handle.isEmpty) return null;
    return AndroidNativePlaybackEvent(
      handle: handle,
      playing: payload['playing'] as bool?,
      buffering: payload['buffering'] as bool?,
      position: _duration(payload['positionMillis']),
      duration: _duration(payload['durationMillis']),
      volume: (payload['volume'] as num?)?.toDouble(),
      muted: payload['muted'] as bool?,
      error: payload['error'] as String?,
      ended: payload['ended'] as bool?,
    );
  }

  static Duration? _duration(Object? value) => value is num ? Duration(milliseconds: value.round()) : null;
}

class MethodChannelAndroidNativePlaybackBridge implements AndroidNativePlaybackBridge {
  const MethodChannelAndroidNativePlaybackBridge({
    MethodChannel channel = const MethodChannel('rodplayer/android_playback'),
    EventChannel eventChannel = const EventChannel('rodplayer/android_playback_events'),
  })  : _channel = channel,
        _eventChannel = eventChannel;

  final MethodChannel _channel;
  final EventChannel _eventChannel;

  @override
  bool get isHostAvailable => false;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> confirmHostAvailable() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('ping') == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String> create(Uri uri) async {
    final handle = await _channel.invokeMethod<String>('create', <String, Object?>{'url': uri.toString()});
    if (handle == null || handle.isEmpty) throw StateError('Android native playback host returned no player handle');
    return handle;
  }

  @override
  Future<void> play(String handle) => _invoke('play', handle);

  @override
  Future<void> pause(String handle) => _invoke('pause', handle);

  @override
  Future<void> seek(String handle, Duration position) => _invoke('seek', handle, <String, Object?>{'positionMillis': position.inMilliseconds});

  @override
  Future<void> stop(String handle) => _invoke('stop', handle);

  @override
  Future<void> setVolume(String handle, double value) => _invoke('volume', handle, <String, Object?>{'volume': value.clamp(0, 100).toDouble()});

  @override
  Future<void> setMuted(String handle, bool muted) => _invoke('mute', handle, <String, Object?>{'muted': muted});

  @override
  Future<void> dispose(String handle) => _invoke('dispose', handle);

  @override
  Stream<AndroidNativePlaybackEvent> events(String handle) => _eventChannel.receiveBroadcastStream(<String, Object?>{'handle': handle}).map(AndroidNativePlaybackEvent.fromPayload).where((event) => event?.handle == handle).cast<AndroidNativePlaybackEvent>();

  Future<void> _invoke(String method, String handle, [Map<String, Object?> arguments = const <String, Object?>{}]) =>
      _channel.invokeMethod<void>(method, <String, Object?>{'handle': handle, ...arguments});
}

class AndroidNativePlaybackEngine implements PlaybackEngine {
  AndroidNativePlaybackEngine({required this.bridge});

  final AndroidNativePlaybackBridge bridge;

  @override
  String get id => PlaybackBackendIds.androidNative;
  @override
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  @override
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  @override
  final ValueNotifier<bool> buffering = ValueNotifier<bool>(false);
  @override
  final ValueNotifier<Duration> positionListenable = ValueNotifier<Duration>(Duration.zero);
  @override
  final ValueNotifier<Duration> durationListenable = ValueNotifier<Duration>(Duration.zero);
  @override
  final ValueNotifier<double> volume = ValueNotifier<double>(100);
  final _statuses = StreamController<String>.broadcast();
  StreamSubscription<AndroidNativePlaybackEvent>? _events;
  String? _handle;
  PlaybackPlan? _plan;
  var _disposed = false;

  String? get handle => _handle;

  @override
  Stream<String> get statuses => _statuses.stream;
  @override
  Duration get position => positionListenable.value;
  @override
  Duration get duration => durationListenable.value;

  @override
  Future<void> load(PlaybackPlan plan) async {
    if (_disposed) return;
    _plan = plan;
    final handle = await bridge.create(plan.playbackUri);
    if (_disposed) {
      await bridge.dispose(handle);
      return;
    }
    _handle = handle;
    _events = bridge.events(handle).listen(_handleEvent, onError: (Object eventError) {
      if (!_disposed) error.value = eventError.toString();
    });
    await bridge.play(handle);
  }

  void _handleEvent(AndroidNativePlaybackEvent event) {
    if (_disposed || event.handle != _handle) return;
    final eventError = event.error;
    if (eventError != null && eventError.isNotEmpty) error.value = eventError;
    final eventPlaying = event.playing;
    if (eventPlaying != null) playing.value = eventPlaying;
    final eventBuffering = event.buffering;
    if (eventBuffering != null) buffering.value = eventBuffering;
    final eventPosition = event.position;
    if (eventPosition != null) positionListenable.value = eventPosition;
    final eventDuration = event.duration;
    if (eventDuration != null) durationListenable.value = eventDuration;
    final eventVolume = event.volume;
    if (eventVolume != null) volume.value = eventVolume;
    if (event.ended == true) {
      playing.value = false;
      buffering.value = false;
      _statuses.add('Playback completed');
    }
  }

  @override
  Future<void> play() => _withHandle(bridge.play);

  @override
  Future<void> pause() => _withHandle(bridge.pause);

  @override
  Future<void> playOrPause() => playing.value ? pause() : play();

  @override
  Future<void> seek(Duration position) => _withHandle((handle) => bridge.seek(handle, position));

  @override
  Future<void> setVolume(double value) => _withHandle((handle) async {
        volume.value = value.clamp(0, 100).toDouble();
        await bridge.setVolume(handle, volume.value);
      });

  @override
  Future<void> retry() async {
    final plan = _plan;
    if (_disposed || plan == null) return;
    await stop();
    await _events?.cancel();
    _events = null;
    final handle = _handle;
    if (handle != null) await bridge.dispose(handle);
    _handle = null;
    await load(plan);
  }

  @override
  Future<void> stop() => _withHandle(bridge.stop);

  Future<void> setMuted(bool muted) => _withHandle((handle) => bridge.setMuted(handle, muted));

  Future<void> _withHandle(Future<void> Function(String handle) action) async {
    final handle = _handle;
    if (_disposed || handle == null) return;
    await action(handle);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _events?.cancel();
    final handle = _handle;
    _handle = null;
    if (handle != null) await bridge.dispose(handle);
    await _statuses.close();
    error.dispose();
    playing.dispose();
    buffering.dispose();
    positionListenable.dispose();
    durationListenable.dispose();
    volume.dispose();
  }
}

class AndroidNativePlaybackVideoSurface implements PlaybackVideoSurface {
  const AndroidNativePlaybackVideoSurface(this.handle);

  static const viewType = 'rodplayer/android_playback_view';
  final String handle;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) return const SizedBox.shrink();
    return AndroidView(viewType: viewType, creationParams: <String, Object?>{'handle': handle}, creationParamsCodec: const StandardMessageCodec());
  }
}

class AndroidNativePlaybackRuntime implements PlaybackBackendRuntime {
  AndroidNativePlaybackRuntime({
    AndroidNativePlaybackBridge bridge = const MethodChannelAndroidNativePlaybackBridge(),
    bool? confirmedHostAvailable,
  })  : bridge = bridge,
        _confirmedHostAvailable = confirmedHostAvailable;

  static Future<AndroidNativePlaybackRuntime> create({
    AndroidNativePlaybackBridge bridge = const MethodChannelAndroidNativePlaybackBridge(),
  }) async =>
      AndroidNativePlaybackRuntime(
        bridge: bridge,
        confirmedHostAvailable: await bridge.confirmHostAvailable(),
      );

  final AndroidNativePlaybackBridge bridge;
  final bool? _confirmedHostAvailable;

  @override
  String get backendId => PlaybackBackendIds.androidNative;

  @override
  bool get isAvailable => _confirmedHostAvailable ?? bridge.isHostAvailable;

  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async {
    final engine = AndroidNativePlaybackEngine(bridge: bridge);
    try {
      await engine.load(plan);
    } on Object {
      await engine.dispose();
      rethrow;
    }
    final handle = engine.handle;
    if (handle == null) throw StateError('Android native playback did not create a video handle');
    return PlaybackRuntimeSession(
      runtimeId: backendId,
      plan: plan,
      engine: engine,
      surface: AndroidNativePlaybackVideoSurface(handle),
    );
  }
}
