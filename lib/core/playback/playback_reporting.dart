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

  Future<void> started() => client.reportPlaybackStarted(_state(Duration.zero).toJson());
  Future<void> progress(Duration position, Duration duration, {bool paused = false}) => client.reportPlaybackProgress(_state(position, paused: paused).toJson(eventName: 'timeupdate', runtimeTicks: _ticks(duration)));
  Future<void> stopped(Duration position) => client.reportPlaybackStopped(_state(position).toJson());

  PlaybackReportState _state(Duration position, {bool paused = false}) {
    final plan = session.activePlan;
    return PlaybackReportState(
      itemId: session.itemId,
      playSessionId: plan.playSessionId,
      mediaSourceId: plan.mediaSourceId,
      positionTicks: _ticks(position),
      playMethod: plan.playMethod,
      audioStreamIndex: session.selectedAudio,
      subtitleStreamIndex: session.selectedSubtitle,
      isPaused: paused,
    );
  }

  static int _ticks(Duration duration) => duration.inMicroseconds * 10;
}
