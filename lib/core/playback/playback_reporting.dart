import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';

class PlaybackReportState {
  const PlaybackReportState({
    required this.itemId,
    required this.playSessionId,
    required this.mediaSourceId,
    required this.positionTicks,
    required this.playMethod,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.isPaused = false,
    this.isMuted = false,
    this.volumeLevel = 100,
    this.canSeek = true,
  });

  final String itemId;
  final String? playSessionId;
  final String mediaSourceId;
  final int positionTicks;
  final PlayMethod playMethod;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final bool isPaused;
  final bool isMuted;
  final int volumeLevel;
  final bool canSeek;

  Map<String, dynamic> toJson({String? eventName, int? runtimeTicks}) => <String, dynamic>{
        'ItemId': itemId,
        if (playSessionId != null) 'PlaySessionId': playSessionId,
        'MediaSourceId': mediaSourceId,
        'PositionTicks': positionTicks,
        'PlayMethod': playMethod.jellyfinName,
        if (audioStreamIndex != null) 'AudioStreamIndex': audioStreamIndex,
        if (subtitleStreamIndex != null) 'SubtitleStreamIndex': subtitleStreamIndex,
        'IsPaused': isPaused,
        'IsMuted': isMuted,
        'VolumeLevel': volumeLevel,
        'CanSeek': canSeek,
        if (eventName != null) 'EventName': eventName,
        if (runtimeTicks != null) 'RunTimeTicks': runtimeTicks,
      };
}

class PlaybackReporter {
  PlaybackReporter({required this.client, required this.session});

  final JellyfinApiClient client;
  final LogicalPlaybackSession session;
  PlaybackReportSnapshot? _reportedSnapshot;
  Future<void> _tail = Future<void>.value();

  Future<void> started([Duration position = Duration.zero]) {
    final snapshot = _snapshot(position);
    return _enqueue(() async {
      if (_reportedSnapshot == null) {
        await client.reportPlaybackStarted(snapshot.state.toJson());
        _reportedSnapshot = snapshot;
      }
    });
  }

  Future<void> progress(Duration position, Duration duration, {bool paused = false}) {
    final snapshot = _snapshot(position, duration: duration, paused: paused);
    return _enqueue(() async {
      await _transition(snapshot);
      await client.reportPlaybackProgress(snapshot.state.toJson(eventName: 'timeupdate', runtimeTicks: snapshot.runtimeTicks));
      _reportedSnapshot = snapshot;
    });
  }

  Future<void> stopped(Duration position) {
    final snapshot = _snapshot(position);
    return _enqueue(() async {
      final previous = _reportedSnapshot;
      if (previous != null) await client.reportPlaybackStopped(snapshot.stateFor(previous).toJson());
      _reportedSnapshot = null;
    });
  }

  Future<void> synchronize(Duration position) {
    final snapshot = _snapshot(position);
    return _enqueue(() => _transition(snapshot));
  }

  Future<void> _transition(PlaybackReportSnapshot snapshot) async {
    final previous = _reportedSnapshot;
    if (previous?.target == snapshot.target) {
      _reportedSnapshot = snapshot;
      return;
    }
    if (previous != null) await client.reportPlaybackStopped(snapshot.stateFor(previous).toJson());
    await client.reportPlaybackStarted(snapshot.state.toJson());
    _reportedSnapshot = snapshot;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    _tail = _tail.then((_) => operation()).catchError((_) {});
    return _tail;
  }

  PlaybackReportSnapshot _snapshot(Duration position, {Duration duration = Duration.zero, bool paused = false}) {
    final target = PlaybackReportTarget.fromSession(session);
    return PlaybackReportSnapshot(
      target: target,
      state: _state(target, position, paused: paused, audioStreamIndex: session.selectedAudio, subtitleStreamIndex: session.selectedSubtitle),
      runtimeTicks: _ticks(duration),
    );
  }

  PlaybackReportState _state(PlaybackReportTarget target, Duration position, {bool paused = false, int? audioStreamIndex, int? subtitleStreamIndex}) {
    return PlaybackReportState(
      itemId: session.itemId,
      playSessionId: target.playSessionId,
      mediaSourceId: target.mediaSourceId,
      positionTicks: _ticks(position),
      playMethod: target.playMethod,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      isPaused: paused,
    );
  }

  static int _ticks(Duration duration) => duration.inMicroseconds * 10;
}

class PlaybackReportSnapshot {
  const PlaybackReportSnapshot({required this.target, required this.state, required this.runtimeTicks});
  final PlaybackReportTarget target;
  final PlaybackReportState state;
  final int runtimeTicks;
  PlaybackReportState stateFor(PlaybackReportSnapshot previous) => PlaybackReportState(itemId: state.itemId, playSessionId: previous.target.playSessionId, mediaSourceId: previous.target.mediaSourceId, positionTicks: state.positionTicks, playMethod: previous.target.playMethod, audioStreamIndex: previous.state.audioStreamIndex, subtitleStreamIndex: previous.state.subtitleStreamIndex, isPaused: state.isPaused, isMuted: state.isMuted, volumeLevel: state.volumeLevel, canSeek: state.canSeek);
}

class PlaybackReportTarget {
  const PlaybackReportTarget({required this.playSessionId, required this.mediaSourceId, required this.playMethod});

  factory PlaybackReportTarget.fromSession(LogicalPlaybackSession session) => PlaybackReportTarget(
    playSessionId: session.activePlan.playSessionId,
    mediaSourceId: session.activePlan.mediaSourceId,
    playMethod: session.activePlan.playMethod,
  );

  final String? playSessionId;
  final String mediaSourceId;
  final PlayMethod playMethod;

  @override
  bool operator ==(Object other) => other is PlaybackReportTarget && other.playSessionId == playSessionId && other.mediaSourceId == mediaSourceId && other.playMethod == playMethod;

  @override
  int get hashCode => Object.hash(playSessionId, mediaSourceId, playMethod);
}
