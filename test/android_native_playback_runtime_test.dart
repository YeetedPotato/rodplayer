import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_backend_registry.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/platform/playback/android_native_playback_runtime.dart';

void main() {
  test('android native runtime availability follows host handshake', () async {
    final missing = await AndroidNativePlaybackRuntime.create(bridge: _FakeAndroidBridge(available: true, handshake: false));
    final present = await AndroidNativePlaybackRuntime.create(bridge: _FakeAndroidBridge(available: false, handshake: true));
    final nonAndroid = AndroidNativePlaybackRuntime(bridge: _FakeAndroidBridge(available: true), confirmedHostAvailable: false);

    expect(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[missing]).canExecute('android_native'), isFalse);
    expect(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[present]).canExecute('android_native'), isTrue);
    expect(nonAndroid.isAvailable, isFalse);
  });

  test('android backend availability remains handshake controlled', () {
    final unavailable = const PlaybackBackendRegistry().backendsFor(PlatformFamily.android).firstWhere((backend) => backend.id == 'android_native');
    final available = const PlaybackBackendRegistry(androidNativeAvailable: true).backendsFor(PlatformFamily.android).firstWhere((backend) => backend.id == 'android_native');
    final nonAndroid = const PlaybackBackendRegistry(androidNativeAvailable: true).backendsFor(PlatformFamily.windows);

    expect(unavailable.availability, BackendAvailability.unavailable);
    expect(available.availability, BackendAvailability.available);
    expect(nonAndroid.where((backend) => backend.id == 'android_native'), isEmpty);
  });

  test('authoritative playback URIs reach runtime unchanged', () async {
    final bridge = _FakeAndroidBridge(available: true);
    final runtime = AndroidNativePlaybackRuntime(bridge: bridge);
    final uris = <Uri>[
      Uri.parse('https://server/direct/source.mp4?api_key=one'),
      Uri.parse('https://server/direct-stream/source.m3u8?static=true'),
      Uri.parse('https://server/transcode/source.m3u8?tag=abc'),
    ];

    for (final uri in uris) {
      await runtime.open(_plan(uri: uri, method: PlayMethod.transcode));
    }

    expect(bridge.createdUris, uris);
  });

  test('playback commands map through bridge', () async {
    final bridge = _FakeAndroidBridge(available: true);
    final engine = AndroidNativePlaybackEngine(bridge: bridge);
    await engine.load(_plan());

    await engine.pause();
    await engine.play();
    await engine.seek(const Duration(seconds: 9));
    await engine.setVolume(42);
    await engine.setMuted(true);
    await engine.stop();

    expect(bridge.commands, containsAll(<String>['pause:h1', 'play:h1', 'seek:h1:9000', 'volume:h1:42.0', 'mute:h1:true', 'stop:h1']));
  });

  test('native state events and errors normalize to PlaybackEngine', () async {
    final bridge = _FakeAndroidBridge(available: true);
    final engine = AndroidNativePlaybackEngine(bridge: bridge);
    await engine.load(_plan());

    bridge.emit(const AndroidNativePlaybackEvent(
      handle: 'h1',
      playing: true,
      buffering: true,
      position: Duration(seconds: 3),
      duration: Duration(minutes: 2),
      volume: 71,
      error: 'ERROR_CODE_IO: failed',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(engine.playing.value, isTrue);
    expect(engine.buffering.value, isTrue);
    expect(engine.position, const Duration(seconds: 3));
    expect(engine.duration, const Duration(minutes: 2));
    expect(engine.volume.value, 71);
    expect(engine.error.value, 'ERROR_CODE_IO: failed');
  });

  test('dispose is idempotent and ignores late events', () async {
    final bridge = _FakeAndroidBridge(available: true);
    final engine = AndroidNativePlaybackEngine(bridge: bridge);
    await engine.load(_plan());

    await engine.dispose();
    await engine.dispose();
    bridge.emit(const AndroidNativePlaybackEvent(handle: 'h1', playing: true));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.commands.where((command) => command == 'dispose:h1'), hasLength(1));
  });

  test('runtime errors propagate generically and surface stays generic', () async {
    final runtime = AndroidNativePlaybackRuntime(bridge: _FailingAndroidBridge());

    await expectLater(runtime.open(_plan()), throwsA(isA<StateError>()));

    final session = await AndroidNativePlaybackRuntime(bridge: _FakeAndroidBridge(available: true)).open(_plan());
    expect(session.surface, isA<AndroidNativePlaybackVideoSurface>());
    expect(session.advanced, isNull);
    expect(session.advancedCapabilities.playbackRate, CapabilitySupport.unsupported);
  });

  test('android native can compete with media kit through existing scorer', () {
    final android = _candidate('android_native', 10, CapabilitySupport.supported);
    final mediaKit = _candidate('media_kit', 0, CapabilitySupport.unknown);
    final candidates = <PlaybackBackendCandidate>[mediaKit, android]..sort(_compareForTest);

    expect(candidates.first.backend.id, 'android_native');
  });

  test('backend profile isolation and conservative capabilities remain intact', () {
    final android = const PlaybackBackendRegistry(androidNativeAvailable: true).backendsFor(PlatformFamily.android).firstWhere((backend) => backend.id == 'android_native');
    final mediaKit = const PlaybackBackendRegistry(androidNativeAvailable: true).backendsFor(PlatformFamily.android).firstWhere((backend) => backend.id == 'media_kit');

    expect(android.capabilities.id, isNot(mediaKit.capabilities.id));
    expect(android.capabilities.subtitleRules, isEmpty);
    expect(android.capabilities.hdrOutputPreservation, CapabilitySupport.unknown);
    expect(android.capabilities.passthrough, CapabilitySupport.unknown);
  });

  test('Android packaging can explicitly disable media kit fallback', () {
    final backends = const PlaybackBackendRegistry(
      mediaKitAvailable: false,
    ).backendsFor(PlatformFamily.android);

    expect(
      backends.singleWhere((backend) => backend.id == PlaybackBackendIds.mediaKit).availability,
      BackendAvailability.unavailable,
    );
  });

  test('android host template registers Media3 playback integration', () {
    final source = File('tool/native_hosts/android/MainActivity.kt').readAsStringSync();
    final patcher = File('tool/apply_native_hosts.py').readAsStringSync();

    expect(source, contains('androidx.media3.exoplayer.ExoPlayer'));
    expect(source, contains('rodplayer/android_playback'));
    expect(source, contains('rodplayer/android_playback_events'));
    expect(source, contains('rodplayer/android_playback_view'));
    expect(source, contains('"ping" -> result.success(true)'));
    expect(source, contains('private var muted = false'));
    expect(source, contains('private var desiredVolume = 1f'));
    expect(source, contains('if (!muted) player.volume = desiredVolume'));
    expect(source, contains('player.volume = if (muted) 0f else desiredVolume'));
    expect(source, isNot(contains('coerceAtLeast(1f)')));
    expect(source, contains('player.release()'));
    expect(patcher, contains('androidx.media3:media3-exoplayer'));
    expect(patcher, contains('androidx.media3:media3-ui'));
    expect(patcher, contains('"minSdk = flutter.minSdkVersion"'));
    expect(patcher, contains('"minSdk = 26"'));
  });
}

PlaybackPlan _plan({Uri? uri, PlayMethod method = PlayMethod.directPlay}) => PlaybackPlan(
      itemId: 'item',
      mediaSourceId: 'source',
      playSessionId: 'play',
      playMethod: method,
      playbackUri: uri ?? Uri.parse('https://media/source'),
      engineId: 'android_native',
      source: MediaSourceInfo.fromJson(<String, dynamic>{'Id': 'source', 'MediaStreams': <dynamic>[]}),
    );

PlaybackBackendCandidate _candidate(String id, int priority, CapabilitySupport hardwareDecode) {
  final backend = PlaybackBackendDescriptor(
    id: id,
    displayName: id,
    availability: BackendAvailability.available,
    priority: priority,
    capabilities: PlaybackBackendCapabilities(id: id, name: id, hardwareDecode: hardwareDecode),
  );
  final profile = EffectivePlaybackProfile(
    backendId: id,
    capabilities: backend.capabilities,
    deviceProfile: const EffectiveDeviceProfile(maxStreamingBitrate: 1, directPlayRules: <DirectPlayCapabilityRule>[], transcodingRules: <TranscodingCapabilityRule>[], videoCodecRules: <VideoCodecCapabilityRule>[], audioCodecRules: <AudioCodecCapabilityRule>[], subtitleRules: <SubtitleCapabilityRule>[]),
  );
  final plan = _plan(uri: Uri.parse('https://media/$id'));
  final score = const PlaybackPlanScorer().score(plan, profile);
  return PlaybackBackendCandidate(backend: backend, effectiveProfile: profile, plan: plan, score: score);
}

int _compareForTest(PlaybackBackendCandidate a, PlaybackBackendCandidate b) {
  final score = b.score!.total.compareTo(a.score!.total);
  if (score != 0) return score;
  final priority = a.backend.priority.compareTo(b.backend.priority);
  if (priority != 0) return priority;
  return a.backend.id.compareTo(b.backend.id);
}

class _FakeAndroidBridge implements AndroidNativePlaybackBridge {
  _FakeAndroidBridge({required this.available, bool? handshake}) : handshake = handshake ?? available;

  final bool available;
  final bool handshake;
  final createdUris = <Uri>[];
  final commands = <String>[];
  final _events = StreamController<AndroidNativePlaybackEvent>.broadcast();
  var _next = 0;

  @override
  bool get isHostAvailable => available;

  @override
  Future<bool> confirmHostAvailable() async => handshake;

  @override
  Future<String> create(Uri uri) async {
    createdUris.add(uri);
    _next += 1;
    return 'h$_next';
  }

  @override
  Stream<AndroidNativePlaybackEvent> events(String handle) => _events.stream;

  void emit(AndroidNativePlaybackEvent event) => _events.add(event);

  @override
  Future<void> dispose(String handle) async => commands.add('dispose:$handle');

  @override
  Future<void> pause(String handle) async => commands.add('pause:$handle');

  @override
  Future<void> play(String handle) async => commands.add('play:$handle');

  @override
  Future<void> seek(String handle, Duration position) async => commands.add('seek:$handle:${position.inMilliseconds}');

  @override
  Future<void> setMuted(String handle, bool muted) async => commands.add('mute:$handle:$muted');

  @override
  Future<void> setVolume(String handle, double value) async => commands.add('volume:$handle:$value');

  @override
  Future<void> stop(String handle) async => commands.add('stop:$handle');
}

class _FailingAndroidBridge extends _FakeAndroidBridge {
  _FailingAndroidBridge() : super(available: true);

  @override
  Future<String> create(Uri uri) async => throw StateError('native open failed');
}
