import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/playback_coordinator.dart';
import 'package:rodplayer/core/playback/playback_decision.dart';
import 'package:rodplayer/core/playback/playback_recovery_controller.dart';
import 'package:rodplayer/core/playback/stall_detector.dart';
import 'package:rodplayer/core/playback/stream_token_provider.dart';

void main() {
  late StallDetector detector;
  late PlaybackRecoveryController recovery;

  setUp(() {
    detector = StallDetector(
      stallThreshold: const Duration(milliseconds: 10),
      tickInterval: const Duration(milliseconds: 5),
    );
    recovery = PlaybackRecoveryController(
      maxRetries: 0,
      sleep: (_) async {},
    );
  });

  tearDown(() async {
    await detector.dispose();
    await recovery.dispose();
  });

  PlaybackCoordinator coordinator({Future<String> Function()? refresh}) => PlaybackCoordinator(
        stallDetector: detector,
        recoveryController: recovery,
        tokenProvider: StreamTokenProvider(refreshToken: refresh ?? () async => 'token'),
        retryCurrent: () async => true,
        fallback: () async => const PlaybackDecision(
          method: PlayMethod.transcode,
          reason: 'unsupported',
        ),
      );

  test('stall triggers recovery', () async {
    final statuses = <String>[];
    final c = coordinator();
    final subscription = c.statuses.listen(statuses.add);
    c.attach();
    detector.update(position: Duration.zero, isPlaying: true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(statuses, contains('Stall detected, attempting recovery...'));
    await subscription.cancel();
    await c.dispose();
  });

  test('stall flows through the recovery controller to recovered state', () async {
    await recovery.dispose();
    recovery = PlaybackRecoveryController(maxRetries: 1, sleep: (_) async {});
    final states = <RecoveryState>[];
    final c = PlaybackCoordinator(
      stallDetector: detector,
      recoveryController: recovery,
      tokenProvider: StreamTokenProvider(refreshToken: () async => 'token'),
      retryCurrent: () async => false,
      fallback: () async => const PlaybackDecision(method: PlayMethod.transcode, reason: 'fallback'),
    );
    final subscription = recovery.states.listen(states.add);
    c.attach();
    detector.update(position: Duration.zero, isPlaying: true);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    await Future<void>.delayed(Duration.zero);

    expect(states.map((state) => state.phase), contains(RecoveryPhase.retrying));
    expect(states.map((state) => state.phase), contains(RecoveryPhase.recovered));
    await subscription.cancel();
    await c.dispose();
  });

  test('auth failure refreshes the token', () async {
    var refreshed = false;
    final c = coordinator(refresh: () async {
      refreshed = true;
      return 'refreshed';
    });
    await c.handleStreamFailure(statusCode: 401);
    expect(refreshed, isTrue);
    await c.dispose();
  });

  test('failed retry selects the fallback transition', () async {
    var fallbackCalled = false;
    final c = PlaybackCoordinator(
      stallDetector: detector,
      recoveryController: recovery,
      tokenProvider: StreamTokenProvider(refreshToken: () async => 'token'),
      retryCurrent: () async => false,
      fallback: () async {
        fallbackCalled = true;
        return const PlaybackDecision(method: PlayMethod.transcode, reason: 'fallback');
      },
    );
    await c.handleStreamFailure(networkDrop: true);
    expect(fallbackCalled, isTrue);
    await c.dispose();
  });
}
