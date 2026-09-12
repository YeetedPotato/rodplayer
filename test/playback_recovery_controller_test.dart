import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/playback_decision.dart';
import 'package:rodplayer/core/playback/playback_recovery_controller.dart';

void main() {
  const fallback = PlaybackDecision(
    method: PlayMethod.directStream,
    reason: 'server supplied fallback',
    url: Uri.parse('https://media/fallback'),
  );

  test('retries with exponential backoff and recovers', () async {
    final waits = <Duration>[];
    var attempts = 0;
    final controller = PlaybackRecoveryController(
      maxRetries: 3,
      initialBackoff: const Duration(milliseconds: 10),
      sleep: (duration) async => waits.add(duration),
    );
    await controller.handleFailure(
      reason: 'network stall',
      retryCurrent: () async => ++attempts == 3,
      fallback: () async => fallback,
    );

    expect(attempts, 3);
    expect(waits, [
      const Duration(milliseconds: 10),
      const Duration(milliseconds: 20),
      const Duration(milliseconds: 40),
    ]);
    expect(controller.state.phase, RecoveryPhase.recovered);
    expect(controller.state.reason, contains('retry 3'));
    await controller.dispose();
  });

  test('falls back after direct play exhausts retries', () async {
    final phases = <RecoveryPhase>[];
    var fallbackCalls = 0;
    final controller = PlaybackRecoveryController(
      maxRetries: 2,
      sleep: (_) async {},
    );
    final subscription = controller.states.listen((state) => phases.add(state.phase));
    await controller.handleFailure(
      reason: 'decoder error',
      retryCurrent: () async => false,
      fallback: () async {
        fallbackCalls++;
        return fallback;
      },
    );

    expect(fallbackCalls, 1);
    expect(phases, [RecoveryPhase.retrying, RecoveryPhase.retrying, RecoveryPhase.fallingBack, RecoveryPhase.recovered]);
    expect(controller.state.reason, contains('Fallback selected: directStream'));
    await subscription.cancel();
    await controller.dispose();
  });

  test('reports terminal failure when fallback is unavailable', () async {
    final controller = PlaybackRecoveryController(maxRetries: 0, sleep: (_) async {});
    await controller.handleFailure(
      reason: 'playback error',
      retryCurrent: () async => false,
      fallback: () async => const PlaybackDecision(method: PlayMethod.directPlay, reason: 'no playable URL'),
    );

    expect(controller.state.phase, RecoveryPhase.failed);
    expect(controller.state.reason, contains('Fallback unavailable'));
    await controller.dispose();
  });
}
