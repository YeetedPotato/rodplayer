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
import 'package:rodplayer/core/player/playback_video_surface.dart';
import 'package:rodplayer/platform/playback/compatibility_playback_runtimes.dart';

void main() {
  test('compatibility runtimes require host handshake', () async {
    final appleMissing = await AppleCompatibilityPlaybackRuntime.create(bridge: _FakeBridge(available: true, handshake: false));
    final applePresent = await AppleCompatibilityPlaybackRuntime.create(bridge: _FakeBridge(available: false, handshake: true));
    final androidMissing = await AndroidCompatibilityPlaybackRuntime.create(bridge: _FakeBridge(available: true, handshake: false));
    final androidPresent = await AndroidCompatibilityPlaybackRuntime.create(bridge: _FakeBridge(available: false, handshake: true));

    expect(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[appleMissing]).canExecute('apple_compatibility'), isFalse);
    expect(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[applePresent]).canExecute('apple_compatibility'), isTrue);
    expect(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[androidMissing]).canExecute('android_compatibility'), isFalse);
    expect(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[androidPresent]).canExecute('android_compatibility'), isTrue);
  });

  test('authoritative playback URI reaches compatibility runtime unchanged', () async {
    final bridge = _FakeBridge(available: true);
    final runtime = AndroidCompatibilityPlaybackRuntime(bridge: bridge, confirmedHostAvailable: true);
    final uri = Uri.parse('https://server/transcode/source.m3u8?tag=abc');

    await runtime.open(_plan(engineId: 'android_compatibility', uri: uri, method: PlayMethod.transcode));

    expect(bridge.createdUris, <Uri>[uri]);
  });

  test('commands and events normalize through compatibility engine', () async {
    final bridge = _FakeBridge(available: true);
    final runtime = AppleCompatibilityPlaybackRuntime(bridge: bridge, confirmedHostAvailable: true);
    final session = await runtime.open(_plan(engineId: 'apple_compatibility'));
    final engine = session.engine as CompatibilityPlaybackEngine;

    await engine.pause();
    await engine.play();
    await engine.seek(const Duration(seconds: 5));
    await engine.setVolume(33);
    await engine.setMuted(true);
    await engine.stop();
    bridge.emit(const CompatibilityPlaybackEvent(handle: 'h1', playing: true, buffering: true, position: Duration(seconds: 2), duration: Duration(seconds: 9), volume: 33, error: 'native failed'));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.commands, containsAll(<String>['pause:h1', 'play:h1', 'seek:h1:5000', 'volume:h1:33.0', 'mute:h1:true', 'stop:h1']));
    expect(engine.playing.value, isTrue);
    expect(engine.buffering.value, isTrue);
    expect(engine.position, const Duration(seconds: 2));
    expect(engine.duration, const Duration(seconds: 9));
    expect(engine.error.value, 'native failed');
    expect(session.surface, isA<PlaybackVideoSurface>());
    expect(session.advanced, isNull);
    expect(session.advancedCapabilities.chapterNavigation, CapabilitySupport.unsupported);
  });

  test('dispose is idempotent and late events are ignored', () async {
    final bridge = _FakeBridge(available: true);
    final session = await AndroidCompatibilityPlaybackRuntime(bridge: bridge, confirmedHostAvailable: true).open(_plan(engineId: 'android_compatibility'));

    await session.engine.dispose();
    await session.engine.dispose();
    bridge.emit(const CompatibilityPlaybackEvent(handle: 'h1', playing: true));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.commands.where((command) => command == 'dispose:h1'), hasLength(1));
  });

  test('compatibility runtime handles stay independent', () async {
    final bridge = _FakeBridge(available: true);
    final runtime = AndroidCompatibilityPlaybackRuntime(bridge: bridge, confirmedHostAvailable: true);
    final first = await runtime.open(_plan(engineId: 'android_compatibility', uri: Uri.parse('https://media/first')));
    final second = await runtime.open(_plan(engineId: 'android_compatibility', uri: Uri.parse('https://media/second')));

    await first.engine.dispose();
    await second.engine.play();

    expect(bridge.createdUris, <Uri>[Uri.parse('https://media/first'), Uri.parse('https://media/second')]);
    expect(bridge.commands, contains('dispose:h1'));
    expect(bridge.commands, contains('play:h2'));
    expect(bridge.commands, isNot(contains('dispose:h2')));
  });


  test('compatibility profiles are separate and conservative', () {
    final apple = const PlaybackBackendRegistry(appleCompatibilityAvailable: true).backendsFor(PlatformFamily.ios);
    final android = const PlaybackBackendRegistry(androidCompatibilityAvailable: true).backendsFor(PlatformFamily.android);

    expect(apple.singleWhere((backend) => backend.id == 'apple_compatibility').capabilities.id, isNot(apple.singleWhere((backend) => backend.id == 'apple_native').capabilities.id));
    expect(android.singleWhere((backend) => backend.id == 'android_compatibility').capabilities.id, isNot(android.singleWhere((backend) => backend.id == 'android_native').capabilities.id));
    expect(apple.singleWhere((backend) => backend.id == 'apple_compatibility').capabilities.hardwareDecode, CapabilitySupport.unknown);
    expect(android.singleWhere((backend) => backend.id == 'android_compatibility').capabilities.passthrough, CapabilitySupport.unknown);
  });

  test('compatibility direct play can beat native full transcode while media kit remains executable', () {
    final compatibility = _candidate('android_compatibility', PlayMethod.directPlay);
    final native = _candidate('android_native', PlayMethod.transcode);
    final candidates = <PlaybackBackendCandidate>[native, compatibility]..sort(_compareForTest);

    expect(candidates.first.backend.id, 'android_compatibility');
    expect(const PlaybackRuntimeRegistry().canExecute('media_kit'), isTrue);
  });

  test('native source templates register compatibility dependency and teardown', () {
    final patcher = File('tool/apply_native_hosts.py').readAsStringSync();
    final workflow = File('.github/workflows/build-multiplatform.yml').readAsStringSync();
    final android = File('tool/native_hosts/android/MainActivity.kt').readAsStringSync();
    final ios = File('tool/native_hosts/ios/AppDelegate.swift').readAsStringSync();
    final macos = File('tool/native_hosts/macos/MainFlutterWindow.swift').readAsStringSync();

    expect(patcher, contains('MobileVLCKit'));
    expect(patcher, contains('dev.jdtech.mpv:libmpv:1.0.0'));
    expect(android, contains('rodplayer/android_compatibility_playback'));
    expect(android, contains('dev.jdtech.mpv.MPVLib'));
    expect(android, contains('private val mpv: MPVLib'));
    expect(android, contains('MPVLib.create(context)'));
    expect(android, contains('mpv.destroy()'));
    expect(android, contains('sessions[handle] = AndroidCompatibilityPlaybackSession'));
    expect(android, isNot(contains('MPVLib.destroy()')));
    expect(ios, contains('rodplayer/apple_compatibility_playback'));
    expect(ios, contains('VLCMediaPlayer'));
    expect(macos, contains('rodplayer/apple_compatibility_playback'));
    expect(macos, contains('VLCKit'));
    expect(patcher, contains('rodplayer_patch_vlckit_coregraphics'));
    expect(ios, contains('let applePlaybackRegistrar = registrar(forPlugin:'));
    expect(ios, contains('let compatibilityPlaybackRegistrar = registrar(forPlugin:'));
    expect(ios, contains('else {\n      return false\n    }'));
    expect(workflow, contains(r'status=${PIPESTATUS[0]}'));
    expect(workflow, contains(r'test -x "$app/Contents/MacOS/rodplayer"'));
  });

  test('native template handshake does not create playback context', () {
    final android = File('tool/native_hosts/android/MainActivity.kt').readAsStringSync();

    expect(android, contains('Class.forName("dev.jdtech.mpv.MPVLib")'));
    expect(android, isNot(contains('"ping" -> result.success(runCatching { MPVLib.create(context)')));
  });
}

PlaybackPlan _plan({required String engineId, Uri? uri, PlayMethod method = PlayMethod.directPlay}) => PlaybackPlan(
      itemId: 'item',
      mediaSourceId: 'source',
      playSessionId: 'play',
      playMethod: method,
      playbackUri: uri ?? Uri.parse('https://media/source'),
      engineId: engineId,
      source: MediaSourceInfo.fromJson(<String, dynamic>{'Id': 'source', 'MediaStreams': <dynamic>[]}),
    );

PlaybackBackendCandidate _candidate(String id, PlayMethod method) {
  final backend = PlaybackBackendDescriptor(id: id, displayName: id, availability: BackendAvailability.available, priority: id.contains('native') ? 10 : 20, capabilities: PlaybackBackendCapabilities(id: id, name: id));
  final plan = _plan(engineId: id, method: method);
  final profile = EffectivePlaybackProfile(
    backendId: id,
    capabilities: backend.capabilities,
    deviceProfile: const EffectiveDeviceProfile(maxStreamingBitrate: 1, directPlayRules: <DirectPlayCapabilityRule>[], transcodingRules: <TranscodingCapabilityRule>[], videoCodecRules: <VideoCodecCapabilityRule>[], audioCodecRules: <AudioCodecCapabilityRule>[], subtitleRules: <SubtitleCapabilityRule>[]),
  );
  return PlaybackBackendCandidate(backend: backend, effectiveProfile: profile, plan: plan, score: const PlaybackPlanScorer().score(plan, profile));
}

int _compareForTest(PlaybackBackendCandidate a, PlaybackBackendCandidate b) {
  final score = b.score!.total.compareTo(a.score!.total);
  if (score != 0) return score;
  final priority = a.backend.priority.compareTo(b.backend.priority);
  if (priority != 0) return priority;
  return a.backend.id.compareTo(b.backend.id);
}

class _FakeBridge implements CompatibilityPlaybackBridge {
  _FakeBridge({required this.available, bool? handshake}) : handshake = handshake ?? available;

  final bool available;
  final bool handshake;
  final createdUris = <Uri>[];
  final commands = <String>[];
  final _events = StreamController<CompatibilityPlaybackEvent>.broadcast();
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
  Stream<CompatibilityPlaybackEvent> events(String handle) => _events.stream;
  void emit(CompatibilityPlaybackEvent event) => _events.add(event);
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
