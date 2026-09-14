// Legacy fixed-session helper retained for ResumeManager compatibility.
// New playback uses LogicalPlaybackSession + PlaybackReporter.
typedef PlaybackStart = Future<void> Function(String itemId, String sessionId);
typedef PlaybackProgress = Future<void> Function(String itemId, String sessionId, Duration position, Duration duration, bool paused);
typedef PlaybackStop = Future<void> Function(String itemId, String sessionId, Duration position);

class PlaybackSessionReporter {
  const PlaybackSessionReporter({required this.start, required this.progress, required this.stop});
  final PlaybackStart start;
  final PlaybackProgress progress;
  final PlaybackStop stop;
}

class PlaybackSession {
  PlaybackSession({required this.itemId, required this.sessionId, required this.reporter});

  final String itemId;
  final String sessionId;
  final PlaybackSessionReporter reporter;
  bool _started = false;
  bool _ended = false;

  Future<void> begin() async {
    if (_started || _ended) return;
    _started = true;
    await reporter.start(itemId, sessionId);
  }

  Future<void> reportProgress(Duration position, Duration duration, {bool paused = false}) {
    if (_ended) return Future<void>.value();
    return reporter.progress(itemId, sessionId, position, duration, paused);
  }

  Future<void> end(Duration position) async {
    if (_ended) return;
    _ended = true;
    await reporter.stop(itemId, sessionId, position);
  }
}
