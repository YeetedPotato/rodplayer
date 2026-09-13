import 'package:rodplayer/core/api/remux_client.dart';

typedef PlaybackStart = Future<void> Function(String itemId, String sessionId);
typedef PlaybackProgress = Future<void> Function(String itemId, String sessionId, Duration position, Duration duration, bool paused);
typedef PlaybackStop = Future<void> Function(String itemId, String sessionId, Duration position);

class PlaybackReporter {
  const PlaybackReporter({required this.start, required this.progress, required this.stop});
  final PlaybackStart start;
  final PlaybackProgress progress;
  final PlaybackStop stop;

  factory PlaybackReporter.fromRemuxClient(RemuxClient client) => PlaybackReporter(
        start: (itemId, sessionId) => client.reportPlaybackStarted(itemId: itemId, sessionId: sessionId),
        progress: (itemId, _, position, duration, paused) => client.reportPlaybackProgress(itemId: itemId, position: position, duration: duration, isPaused: paused),
        stop: (itemId, _, position) => client.reportPlaybackStopped(itemId: itemId, position: position),
      );
}

class PlaybackSession {
  PlaybackSession({required this.itemId, required this.sessionId, required this.reporter, this.streamInfo});

  factory PlaybackSession.fromRemuxClient({required String itemId, required String sessionId, required RemuxClient client, PlaybackStreamInfo? streamInfo}) => PlaybackSession(itemId: itemId, sessionId: sessionId, reporter: PlaybackReporter.fromRemuxClient(client), streamInfo: streamInfo);

  final String itemId;
  final String sessionId;
  final PlaybackReporter reporter;
  final PlaybackStreamInfo? streamInfo;
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
