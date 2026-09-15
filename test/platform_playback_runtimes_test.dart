import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/playback_backend_registry.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/platform/playback/platform_playback_runtimes.dart';

import 'fakes/test_playback_engine.dart';

void main() {
  test('optional Apple runtime probe failure is isolated', () async {
    final runtimes = await createPlatformPlaybackRuntimes(
      appleNativeFactory: () async => throw StateError('avplayer probe failed'),
      appleCompatibilityFactory: () async => const _Runtime(PlaybackBackendIds.appleCompatibility),
      androidNativeFactory: () async => const _UnavailableRuntime(PlaybackBackendIds.androidNative),
      androidCompatibilityFactory: () async => const _UnavailableRuntime(PlaybackBackendIds.androidCompatibility),
    );

    expect(runtimes.registry.canExecute(PlaybackBackendIds.mediaKit), isTrue);
    expect(runtimes.backendRegistry.appleNativeAvailable, isFalse);
    expect(runtimes.backendRegistry.appleCompatibilityAvailable, isTrue);
    expect(runtimes.probeFailures[PlaybackBackendIds.appleNative], isA<StateError>());
  });

  test('optional Android runtime probe failure is isolated', () async {
    final runtimes = await createPlatformPlaybackRuntimes(
      appleNativeFactory: () async => const _UnavailableRuntime(PlaybackBackendIds.appleNative),
      appleCompatibilityFactory: () async => const _UnavailableRuntime(PlaybackBackendIds.appleCompatibility),
      androidNativeFactory: () async => const _Runtime(PlaybackBackendIds.androidNative),
      androidCompatibilityFactory: () async => throw StateError('libmpv probe failed'),
    );

    expect(runtimes.registry.canExecute(PlaybackBackendIds.mediaKit), isTrue);
    expect(runtimes.backendRegistry.androidNativeAvailable, isTrue);
    expect(runtimes.backendRegistry.androidCompatibilityAvailable, isFalse);
    expect(runtimes.probeFailures[PlaybackBackendIds.androidCompatibility], isA<StateError>());
  });
}

class _Runtime implements PlaybackBackendRuntime {
  const _Runtime(this.backendId);

  @override
  final String backendId;

  @override
  bool get isAvailable => true;

  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async {
    final engine = TestPlaybackEngine(id: backendId);
    await engine.load(plan);
    return PlaybackRuntimeSession(runtimeId: backendId, plan: plan, engine: engine);
  }
}

class _UnavailableRuntime extends _Runtime {
  const _UnavailableRuntime(super.backendId);

  @override
  bool get isAvailable => false;
}
