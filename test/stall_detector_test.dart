import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/stall_detector.dart';

void main() {
  test('detects a playing stall after the threshold', () async {
    final detector = StallDetector(
      stallThreshold: const Duration(milliseconds: 30),
      tickInterval: const Duration(milliseconds: 5),
    );
    final events = <StallEvent>[];
    final subscription = detector.events.listen(events.add);

    detector.update(position: Duration.zero, isPlaying: true);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(events, hasLength(1));
    expect(events.single.stalled, isTrue);
    await subscription.cancel();
    await detector.dispose();
  });

  test('emits recovery when the position advances again', () async {
    final detector = StallDetector(
      stallThreshold: const Duration(milliseconds: 25),
      tickInterval: const Duration(milliseconds: 5),
    );
    final events = <StallEvent>[];
    final subscription = detector.events.listen(events.add);

    detector.update(position: const Duration(seconds: 1), isPlaying: true);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    detector.update(position: const Duration(seconds: 2), isPlaying: true);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(events.map((event) => event.stalled), [true, false]);
    await subscription.cancel();
    await detector.dispose();
  });

  test('does not stall while paused', () async {
    final detector = StallDetector(
      stallThreshold: const Duration(milliseconds: 20),
      tickInterval: const Duration(milliseconds: 5),
    );
    final subscription = detector.events.listen((_) {});

    detector.update(position: Duration.zero, isPlaying: false);
    await Future<void>.delayed(const Duration(milliseconds: 45));

    expect(detector.isStalled, isFalse);
    await subscription.cancel();
    await detector.dispose();
  });

  test('disposes timer and stream cleanly', () async {
    final detector = StallDetector(tickInterval: const Duration(milliseconds: 5));
    final stream = detector.events;
    await detector.dispose();
    await detector.dispose();

    expect(await stream.isEmpty, isTrue);
  });
}
