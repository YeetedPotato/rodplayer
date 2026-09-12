import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/playback/playback_session.dart';
import 'package:rodplayer/core/playback/resume_manager.dart';

void main() {
  const duration = Duration(minutes: 100);

  test('starts over below five percent and resumes at five percent', () {
    expect(ResumeManager.calculate(position: const Duration(minutes: 4), duration: duration).action, ResumeAction.startOver);
    expect(ResumeManager.calculate(position: const Duration(minutes: 5), duration: duration).action, ResumeAction.resume);
  });

  test('marks playback watched above ninety percent', () {
    final decision = ResumeManager.calculate(position: const Duration(minutes: 91), duration: duration);
    expect(decision.action, ResumeAction.watched);
    expect(decision.position, Duration.zero);
  });

  test('handles missing duration as start over', () {
    expect(ResumeManager.calculate(position: const Duration(seconds: 10), duration: Duration.zero).shouldResume, isFalse);
  });

  test('reports start, progress, stop, and watched callbacks', () async {
    final events = <String>[];
    final reporter = PlaybackReporter(
      start: (item, session) async => events.add('start:$item:$session'),
      progress: (item, session, position, duration, paused) async => events.add('progress:${position.inMinutes}:$paused'),
      stop: (item, session, position) async => events.add('stop:${position.inMinutes}'),
    );
    final manager = ResumeManager(
      session: PlaybackSession(itemId: 'item', sessionId: 'session', reporter: reporter),
      onWatched: (item, session) async => events.add('watched:$item:$session'),
    );

    final decision = await manager.begin(position: const Duration(minutes: 20), duration: duration);
    await manager.tick(const Duration(minutes: 30), paused: true);
    await manager.stop(const Duration(minutes: 95));

    expect(decision.shouldResume, isTrue);
    expect(events, ['start:item:session', 'progress:30:true', 'stop:95', 'watched:item:session']);
  });
}
