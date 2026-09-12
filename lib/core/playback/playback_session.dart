typedef PlaybackStart = Future<void> Function(String itemId, String sessionId);
typedef PlaybackProgress = Future<void> Function(String itemId, String sessionId, Duration position, Duration duration, bool paused);
typedef PlaybackStop = Future<void> Function(String itemId, String sessionId, Duration position);

class PlaybackReporter {
  const PlaybackReporter({required this.start, required this.progress, required this.stop});
  final PlaybackStart start;
  final PlaybackProgress progress;
  final PlaybackStop stop;
}

class PlaybackSession {
  PlaybackSession({required this.itemId, required this.sessionId, required this.reporter});
  final String itemId;
  final String sessionId;
  final PlaybackReporter reporter;
  Future<void> begin() => reporter.start(itemId, sessionId);
  Future<void> reportProgress(Duration position, Duration duration, {bool paused = false}) => reporter.progress(itemId, sessionId, position, duration, paused);
  Future<void> end(Duration position) => reporter.stop(itemId, sessionId, position);
}