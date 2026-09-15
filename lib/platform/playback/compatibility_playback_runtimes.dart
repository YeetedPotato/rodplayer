import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rodplayer/core/playback/playback_backend_registry.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';

abstract interface class CompatibilityPlaybackBridge {
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
  Stream<CompatibilityPlaybackEvent> events(String handle);
}

class CompatibilityPlaybackEvent {
  const CompatibilityPlaybackEvent({
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

  static CompatibilityPlaybackEvent? fromPayload(Object? payload) {
    if (payload is! Map) return null;
    final handle = payload['handle'];
    if (handle is! String || handle.isEmpty) return null;
    return CompatibilityPlaybackEvent(
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

class MethodChannelCompatibilityPlaybackBridge implements CompatibilityPlaybackBridge {
  const MethodChannelCompatibilityPlaybackBridge({
    required this.platform,
    required this.methodChannelName,
    required this.eventChannelName,
  });

  final TargetPlatform platform;
  final String methodChannelName;
  final String eventChannelName;

  MethodChannel get _channel => MethodChannel(methodChannelName);
  EventChannel get _eventChannel => EventChannel(eventChannelName);

  @override
  bool get isHostAvailable => false;

  @override
  Future<bool> confirmHostAvailable() async {
    if (kIsWeb || defaultTargetPlatform != platform) return false;
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
    if (handle == null || handle.isEmpty) throw StateError('$methodChannelName returned no player handle');
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
  Stream<CompatibilityPlaybackEvent> events(String handle) => _eventChannel.receiveBroadcastStream(<String, Object?>{'handle': handle}).map(CompatibilityPlaybackEvent.fromPayload).where((event) => event?.handle == handle).cast<CompatibilityPlaybackEvent>();

  Future<void> _invoke(String method, String handle, [Map<String, Object?> arguments = const <String, Object?>{}]) =>
      _channel.invokeMethod<void>(method, <String, Object?>{'handle': handle, ...arguments});
}

class CompatibilityPlaybackEngine implements PlaybackEngine {
  CompatibilityPlaybackEngine({required this.id, required this.bridge});

  @override
  final String id;
  final CompatibilityPlaybackBridge bridge;

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
  StreamSubscription<CompatibilityPlaybackEvent>? _events;
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

  void _handleEvent(CompatibilityPlaybackEvent event) {
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
  Future<void> setMuted(bool muted) => _withHandle((handle) => bridge.setMuted(handle, muted));

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

class CompatibilityPlaybackVideoSurface implements PlaybackVideoSurface {
  const CompatibilityPlaybackVideoSurface({required this.handle, required this.viewType, required this.platform});

  final String handle;
  final String viewType;
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS && platform == TargetPlatform.iOS) {
      return UiKitView(viewType: viewType, creationParams: <String, Object?>{'handle': handle}, creationParamsCodec: const StandardMessageCodec());
    }
    if (defaultTargetPlatform == TargetPlatform.macOS && platform == TargetPlatform.macOS) {
      return AppKitView(viewType: viewType, creationParams: <String, Object?>{'handle': handle}, creationParamsCodec: const StandardMessageCodec());
    }
    if (defaultTargetPlatform == TargetPlatform.android && platform == TargetPlatform.android) {
      return AndroidView(viewType: viewType, creationParams: <String, Object?>{'handle': handle}, creationParamsCodec: const StandardMessageCodec());
    }
    return const SizedBox.shrink();
  }
}

class AppleCompatibilityPlaybackRuntime extends _CompatibilityPlaybackRuntime {
  AppleCompatibilityPlaybackRuntime({CompatibilityPlaybackBridge? bridge, super.confirmedHostAvailable})
      : super(
          backendId: PlaybackBackendIds.appleCompatibility,
          bridge: bridge ??
              MethodChannelCompatibilityPlaybackBridge(
                platform: defaultTargetPlatform == TargetPlatform.macOS ? TargetPlatform.macOS : TargetPlatform.iOS,
                methodChannelName: 'rodplayer/apple_compatibility_playback',
                eventChannelName: 'rodplayer/apple_compatibility_playback_events',
              ),
          viewType: 'rodplayer/apple_compatibility_playback_view',
          platform: defaultTargetPlatform == TargetPlatform.macOS ? TargetPlatform.macOS : TargetPlatform.iOS,
        );

  static Future<AppleCompatibilityPlaybackRuntime> create({CompatibilityPlaybackBridge? bridge}) async {
    final resolved = bridge ??
        MethodChannelCompatibilityPlaybackBridge(
          platform: defaultTargetPlatform == TargetPlatform.macOS ? TargetPlatform.macOS : TargetPlatform.iOS,
          methodChannelName: 'rodplayer/apple_compatibility_playback',
          eventChannelName: 'rodplayer/apple_compatibility_playback_events',
        );
    return AppleCompatibilityPlaybackRuntime(bridge: resolved, confirmedHostAvailable: await resolved.confirmHostAvailable());
  }
}

class AndroidCompatibilityPlaybackRuntime extends _CompatibilityPlaybackRuntime {
  AndroidCompatibilityPlaybackRuntime({CompatibilityPlaybackBridge? bridge, super.confirmedHostAvailable})
      : super(
          backendId: PlaybackBackendIds.androidCompatibility,
          bridge: bridge ?? const MethodChannelCompatibilityPlaybackBridge(platform: TargetPlatform.android, methodChannelName: 'rodplayer/android_compatibility_playback', eventChannelName: 'rodplayer/android_compatibility_playback_events'),
          viewType: 'rodplayer/android_compatibility_playback_view',
          platform: TargetPlatform.android,
        );

  static Future<AndroidCompatibilityPlaybackRuntime> create({CompatibilityPlaybackBridge? bridge}) async {
    final resolved = bridge ?? const MethodChannelCompatibilityPlaybackBridge(platform: TargetPlatform.android, methodChannelName: 'rodplayer/android_compatibility_playback', eventChannelName: 'rodplayer/android_compatibility_playback_events');
    return AndroidCompatibilityPlaybackRuntime(bridge: resolved, confirmedHostAvailable: await resolved.confirmHostAvailable());
  }
}

abstract class _CompatibilityPlaybackRuntime implements PlaybackBackendRuntime {
  _CompatibilityPlaybackRuntime({
    required this.backendId,
    required this.bridge,
    required this.viewType,
    required this.platform,
    this.confirmedHostAvailable,
  });

  @override
  final String backendId;
  final CompatibilityPlaybackBridge bridge;
  final String viewType;
  final TargetPlatform platform;
  final bool? confirmedHostAvailable;

  @override
  bool get isAvailable => confirmedHostAvailable ?? bridge.isHostAvailable;

  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async {
    final engine = CompatibilityPlaybackEngine(id: backendId, bridge: bridge);
    try {
      await engine.load(plan);
    } on Object {
      await engine.dispose();
      rethrow;
    }
    final handle = engine.handle;
    if (handle == null) throw StateError('$backendId did not create a video handle');
    return PlaybackRuntimeSession(
      runtimeId: backendId,
      plan: plan,
      engine: engine,
      surface: CompatibilityPlaybackVideoSurface(handle: handle, viewType: viewType, platform: platform),
    );
  }
}
