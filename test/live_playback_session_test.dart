import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/live_tv/live_playback_session.dart';

void main() {
  group('LiveTimeline', () {
    test('unseekable live has no seek target', () {
      const timeline = LiveTimeline(seekability: LiveSeekability.unseekable);
      expect(timeline.hasWindow, isFalse);
      expect(timeline.clamp(const Duration(seconds: 40)), isNull);
      expect(timeline.goLive().position, isNull);
    });

    test('seekable live clamps within moving capture bounds', () {
      const timeline = LiveTimeline(
        seekability: LiveSeekability.seekable,
        windowStart: Duration(seconds: 10),
        liveEdge: Duration(seconds: 100),
        position: Duration(seconds: 40),
      );
      expect(
        timeline.clamp(const Duration(seconds: 0)),
        const Duration(seconds: 10),
      );
      expect(
        timeline.clamp(const Duration(seconds: 101)),
        const Duration(seconds: 100),
      );
      final moved = timeline.moveWindow(
        start: const Duration(seconds: 50),
        edge: const Duration(seconds: 110),
      );
      expect(moved.position, const Duration(seconds: 50));
      expect(moved.goLive().position, const Duration(seconds: 110));
    });

    test('recovery decisions are finite and typed', () {
      expect(
        liveRecoveryAction(LiveRecoveryReason.temporaryNetworkInterruption),
        LiveRecoveryAction.waitForConnection,
      );
      expect(
        liveRecoveryAction(LiveRecoveryReason.serverTuneFailure),
        LiveRecoveryAction.stop,
      );
      expect(
        liveRecoveryAction(LiveRecoveryReason.expiredSource),
        LiveRecoveryAction.retune,
      );
      expect(
        liveRecoveryAction(LiveRecoveryReason.unseekableSource),
        LiveRecoveryAction.goLive,
      );
      expect(
        liveRecoveryAction(LiveRecoveryReason.captureWindowMoved),
        LiveRecoveryAction.rebuffer,
      );
    });
  });

  test(
    'retune keeps working channel until success and ignores late result',
    () async {
      final gates = <String, Completer<_Candidate>>{};
      final opened = <String>[];
      var inFlight = 0;
      var maxInFlight = 0;
      final coordinator = LiveChannelRetuneCoordinator<_Candidate>(
        open: (id) async {
          opened.add(id);
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          try {
            return await (gates[id] ??= Completer<_Candidate>()).future;
          } finally {
            inFlight--;
          }
        },
      );
      final initial = _Candidate('A');
      coordinator.current = initial;

      final b = coordinator.retune('B');
      final c = coordinator.retune('C');
      expect(await b, isFalse);
      expect(opened, <String>['B']);
      final bCandidate = _Candidate('B');
      gates['B']!.complete(bCandidate);
      await Future<void>.delayed(Duration.zero);
      expect(bCandidate.closed, 1);
      expect(coordinator.current, same(initial));
      expect(opened, <String>['B', 'C']);

      final cCandidate = _Candidate('C');
      gates['C']!.complete(cCandidate);
      expect(await c, isTrue);
      expect(coordinator.current, same(cCandidate));
      expect(maxInFlight, 1);
      expect(initial.closed, 1);

      await coordinator.dispose();
      expect(cCandidate.closed, 1);
    },
  );

  test(
    'dispose drains an in-flight retune and closes its late candidate once',
    () async {
      final gate = Completer<_Candidate>();
      final current = _Candidate('A');
      final coordinator = LiveChannelRetuneCoordinator<_Candidate>(
        open: (_) => gate.future,
      )..current = current;
      final request = coordinator.retune('B');
      var disposed = false;
      final disposal = coordinator.dispose().then((_) => disposed = true);
      expect(await request, isFalse);
      expect(disposed, isFalse);
      final candidate = _Candidate('B');
      gate.complete(candidate);
      await disposal;
      await coordinator.dispose();
      expect(coordinator.current, isNull);
      expect(current.closed, 1);
      expect(candidate.closed, 1);
    },
  );

  test('failed retune leaves current channel intact', () async {
    final current = _Candidate('A');
    final coordinator = LiveChannelRetuneCoordinator<_Candidate>(
      open: (_) => Future<_Candidate>.error(StateError('tune failed')),
    )..current = current;
    await expectLater(coordinator.retune('B'), throwsStateError);
    expect(coordinator.current, same(current));
    expect(current.closed, 0);
    await coordinator.dispose();
  });
}

final class _Candidate implements LivePlaybackCandidate {
  _Candidate(this.channelId);
  @override
  final String channelId;
  int closed = 0;
  @override
  Future<void> close() async => closed++;
}
