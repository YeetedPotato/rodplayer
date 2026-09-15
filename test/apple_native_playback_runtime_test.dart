import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_backend_registry.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/platform/playback/apple_native_playback_runtime.dart';

void main() {
  test('apple native runtime registers only when host is executable', () {
    final available = AppleNativePlaybackRuntime(bridge: _FakeAppleBridge(available: true));
    final unavailable = AppleNativePlaybackRuntime(bridge: _FakeAppleBridge(available: false));

    expect(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[available]).canExecute('apple_native'), isTrue);
    expect(PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[unavailable]).canExecute('apple_native'), isFalse);
  });

  test('apple backend availability remains truthful', () {
    final unavailable = const PlaybackBackendRegistry().backendsFor(PlatformFamily.ios).firstWhere((backend) => backend.id == 'apple_native');
    final available = const PlaybackBackendRegistry(appleNativeAvailable: true).backendsFor(PlatformFamily.ios).firstWhere((backend) => backend.id == 'apple_native');
    final nonApple = const PlaybackBackendRegistry(appleNativeAvailable: true).backendsFor(PlatformFamily.windows);

    expect(unavailable.availability, BackendAvailability.unavailable);
    expect(available.availability, BackendAvailability.available);
    expect(nonApple.where((backend) => backend.id == 'apple_native'), isEmpty);
  });

  test('selected plan and authoritative URI reach Apple runtime unchanged', () async {
    final bridge = _FakeAppleBridge(available: true);
    final runtime = AppleNativePlaybackRuntime(bridge: bridge);
    final uri = Uri.parse('https://server/Items/1/master.m3u8?directstream=true');
    final plan = _plan(uri: uri, method: PlayMethod.transcode);

    final session = await runtime.open(plan);

    expect(session.plan, same(plan));
    expect(bridge.createdUris, <Uri>[uri]);
    expect(bridge.createdUris.single.toString(), contains('directstream=true'));
    expect(session.surface, isA<AppleNativePlaybackVideoSurface>());
  });

  test('playback commands map through bridge', () async {
    final bridge = _FakeAppleBridge(available: true);
    final engine = AppleNativePlaybackEngine(bridge: bridge);
    await engine.load(_plan());

    await engine.pause();
    await engine.play();
    await engine.seek(const Duration(seconds: 9));
    await engine.setVolume(42);
    await engine.stop();

    expect(bridge.commands, containsAll(<String>['pause:h1', 'play:h1', 'seek:h1:9000', 'volume:h1:42.0', 'stop:h1']));
  });

  test('position duration state and errors normalize to PlaybackEngine', () async {
    final bridge = _FakeAppleBridge(available: true);
    final engine = AppleNativePlaybackEngine(bridge: bridge);
    await engine.load(_plan());

    bridge.emit(const AppleNativePlaybackEvent(
      handle: 'h1',
      playing: true,
      buffering: true,
      position: Duration(seconds: 3),
      duration: Duration(minutes: 2),
      volume: 71,
      error: 'native failed',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(engine.playing.value, isTrue);
    expect(engine.buffering.value, isTrue);
    expect(engine.position, const Duration(seconds: 3));
    expect(engine.duration, const Duration(minutes: 2));
    expect(engine.volume.value, 71);
    expect(engine.error.value, 'native failed');
  });

  test('dispose is idempotent and ignores late events', () async {
    final bridge = _FakeAppleBridge(available: true);
    final engine = AppleNativePlaybackEngine(bridge: bridge);
    await engine.load(_plan());

    await engine.dispose();
    await engine.dispose();
    bridge.emit(const AppleNativePlaybackEvent(handle: 'h1', playing: true));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.commands.where((command) => command == 'dispose:h1'), hasLength(1));
  });

  test('native runtime errors propagate generically', () async {
    final runtime = AppleNativePlaybackRuntime(bridge: _FailingAppleBridge());

    await expectLater(runtime.open(_plan()), throwsA(isA<StateError>()));
  });

  test('apple native can compete with media kit through existing scorer', () {
    final apple = _candidate('apple_native', 10, CapabilitySupport.supported);
    final mediaKit = _candidate('media_kit', 0, CapabilitySupport.unknown);
    final candidates = <PlaybackBackendCandidate>[mediaKit, apple]..sort(_compareForTest);

    expect(candidates.first.backend.id, 'apple_native');
  });

  test('backend profile isolation and unknown capabilities stay conservative', () {
    final apple = const PlaybackBackendRegistry(appleNativeAvailable: true).backendsFor(PlatformFamily.macos).firstWhere((backend) => backend.id == 'apple_native');
    final mediaKit = const PlaybackBackendRegistry(appleNativeAvailable: true).backendsFor(PlatformFamily.macos).firstWhere((backend) => backend.id == 'media_kit');

    expect(apple.capabilities.id, isNot(mediaKit.capabilities.id));
    expect(apple.capabilities.hardwareDecode, CapabilitySupport.unknown);
    expect(apple.capabilities.passthrough, CapabilitySupport.unknown);
    expect(apple.capabilities.hdrOutputPreservation, CapabilitySupport.unknown);
  });

  test('media kit remains usable when Apple native is unavailable', () {
    final registry = PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[MediaKitPlaybackRuntime(), AppleNativePlaybackRuntime(bridge: _FakeAppleBridge(available: false))]);

    expect(registry.canExecute('apple_native'), isFalse);
    expect(registry.canExecute('media_kit'), isTrue);
  });
}

PlaybackPlan _plan({Uri? uri, PlayMethod method = PlayMethod.directPlay}) => PlaybackPlan(
      itemId: 'item',
      mediaSourceId: 'source',
      playSessionId: 'play',
      playMethod: method,
      playbackUri: uri ?? Uri.parse('https://media/source'),
      engineId: 'apple_native',
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

class _FakeAppleBridge implements AppleNativePlaybackBridge {
  _FakeAppleBridge({required this.available});

  final bool available;
  final createdUris = <Uri>[];
  final commands = <String>[];
  final _events = StreamController<AppleNativePlaybackEvent>.broadcast();
  var _next = 0;

  @override
  bool get isHostAvailable => available;

  @override
  Future<String> create(Uri uri) async {
    createdUris.add(uri);
    _next += 1;
    return 'h$_next';
  }

  @override
  Stream<AppleNativePlaybackEvent> events(String handle) => _events.stream;

  void emit(AppleNativePlaybackEvent event) => _events.add(event);

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

class _FailingAppleBridge extends _FakeAppleBridge {
  _FailingAppleBridge() : super(available: true);

  @override
  Future<String> create(Uri uri) async => throw StateError('native open failed');
}
