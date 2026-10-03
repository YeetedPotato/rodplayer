import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';
import 'package:rodplayer/core/player/track_controller.dart';

typedef SubtitleNegotiation = Future<PlaybackPlanDecision> Function({
  required String itemId,
  required String selectedMediaSourceId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
});

/// Uses the same replacement authority as source selection, never local URLs.
class PlaybackSubtitleSwitchCoordinator {
  PlaybackSubtitleSwitchCoordinator(
      {required this.coordinator,
      required this.negotiate,
      required this.invalidateRecovery});
  final PlaybackRuntimeCoordinator coordinator;
  final SubtitleNegotiation negotiate;
  final void Function() invalidateRecovery;

  Future<PlaybackRuntimeSession?> select(RodPlayerTrack track) async {
    final index = track.serverStreamIndex;
    final previous = coordinator.active;
    if (index == null || previous == null) {
      throw StateError('Subtitle replacement is unavailable');
    }
    final operation = coordinator.beginTransition();
    bool current() =>
        operation.isCurrent && identical(coordinator.active, previous);
    void check() {
      if (!current()) throw PlaybackActivationSupersededException();
    }

    final session = coordinator.session;
    final position = previous.engine.position;
    final playing = previous.engine.playing.value;
    final audio = session.selectedAudio;
    final source = session.activePlan.mediaSourceId;
    invalidateRecovery();
    try {
      final decision = await negotiate(
          itemId: session.itemId,
          selectedMediaSourceId: source,
          audioStreamIndex: audio,
          subtitleStreamIndex: index);
      check();
      final next = await coordinator.activateCandidates(
        decision.orderedUsableCandidates,
        transition: operation,
        canCommit: current,
        prepare: (candidate) async {
          check();
          await candidate.engine.seek(position);
          check();
          if (playing) {
            await candidate.engine.play();
          } else {
            await candidate.engine.pause();
          }
          check();
        },
        onCommit: (_, next) async {
          if (operation.isCurrent && identical(coordinator.active, next)) {
            session.position = position;
          }
        },
      );
      return operation.isCurrent && identical(coordinator.active, next)
          ? next
          : null;
    } on PlaybackActivationSupersededException {
      return null;
    } finally {
      operation();
    }
  }
}
