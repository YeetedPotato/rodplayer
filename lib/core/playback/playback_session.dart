import 'package:rodplayer/core/api/remux_client.dart';

class PlaybackReporter {
  const PlaybackReporter(this.client);
  final RemuxClient client;
  Future<void> start({required String itemId, required String sessionId}) => client.reportPlaybackStart(itemId: itemId, sessionId: sessionId);
  Future<void> progress({required String itemId, required String sessionId, required Duration position, required Duration duration, bool paused = false}) => client.reportPlaybackProgress(itemId: itemId, sessionId: sessionId, position: position, duration: duration, isPaused: paused);
  Future<void> stop({required String itemId, required String sessionId, required Duration position}) => client.reportPlaybackStop(itemId: itemId, sessionId: sessionId, position: position);
}

class PlaybackSession {
  PlaybackSession({required this.itemId, required this.sessionId, required this.reporter});
  final String itemId;
  final String sessionId;
  final PlaybackReporter reporter;
  Future<void> start() => reporter.start(itemId: itemId, sessionId: sessionId);
  Future<void> reportProgress(Duration position, Duration duration, {bool paused = false}) => reporter.progress(itemId: itemId, sessionId: sessionId, position: position, duration: duration, paused: paused);
  Future<void> stop(Duration position) => reporter.stop(itemId: itemId, sessionId: sessionId, position: position);
}