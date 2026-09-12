import 'package:rodplayer/core/playback/playback_session.dart';

enum ResumeAction { resume, startOver, watched }

class ResumeDecision {
  const ResumeDecision({required this.action, required this.position});

  final ResumeAction action;
  final Duration position;

  bool get shouldResume => action == ResumeAction.resume;
  bool get isWatched => action == ResumeAction.watched;
}

typedef PlaybackWatched = Future<void> Function(String itemId, String sessionId);

class ResumeManager {
  ResumeManager({required this.session, this.onWatched});

  static const double startOverThreshold = 0.05;
  static const double watchedThreshold = 0.90;

  final PlaybackSession session;
  final PlaybackWatched? onWatched;
  Duration _duration = Duration.zero;
  bool _started = false;

  static ResumeDecision calculate({required Duration position, required Duration duration}) {
    if (duration <= Duration.zero || position <= Duration.zero) {
      return const ResumeDecision(action: ResumeAction.startOver, position: Duration.zero);
    }
    final ratio = position.inMicroseconds / duration.inMicroseconds;
    if (ratio < startOverThreshold) {
      return const ResumeDecision(action: ResumeAction.startOver, position: Duration.zero);
    }
    if (ratio > watchedThreshold) {
      return const ResumeDecision(action: ResumeAction.watched, position: Duration.zero);
    }
    return ResumeDecision(action: ResumeAction.resume, position: position);
  }

  Future<ResumeDecision> begin({required Duration position, required Duration duration}) async {
    _duration = duration;
    final decision = calculate(position: position, duration: duration);
    await session.begin();
    _started = true;
    if (decision.isWatched) await _markWatched();
    return decision;
  }

  Future<void> tick(Duration position, {bool paused = false}) async {
    if (!_started) return;
    await session.reportProgress(position, _duration, paused: paused);
  }

  Future<void> stop(Duration position) async {
    if (!_started) return;
    final decision = calculate(position: position, duration: _duration);
    await session.end(position);
    if (decision.isWatched) await _markWatched();
    _started = false;
  }

  Future<void> _markWatched() async {
    final callback = onWatched;
    if (callback != null) await callback(session.itemId, session.sessionId);
  }
}
