import 'dart:async';

import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_metadata.dart';
import 'package:rodplayer/core/playback/playback_reporting.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';

typedef PlaybackSourceNegotiation = Future<PlaybackPlanDecision> Function({
  required String itemId,
  required String mediaSourceId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
});

typedef PlaybackSourceSelectionCommitted = Future<void> Function(
  PlaybackSourceHandoff previous,
  PlaybackRuntimeSession replacement,
);

/// Immutable handoff data captured from the committed source before negotiation.
class PlaybackSourceHandoff {
  const PlaybackSourceHandoff({
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    required this.position,
    required this.wasPlaying,
    required this.audioStreamIndex,
    required this.subtitleStreamIndex,
    required this.metadata,
  });

  final String itemId;
  final String mediaSourceId;
  final String? playSessionId;
  final Duration position;
  final bool wasPlaying;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final PlaybackMetadata metadata;
}

enum PlaybackSourceSwitchStatus { committed, unchanged, superseded }

class PlaybackSourceSwitchCoordinator {
  PlaybackSourceSwitchCoordinator({
    required this.session,
    required this.runtimeCoordinator,
    required this.negotiate,
    required this.reporter,
    required this.invalidateRecovery,
    required this.onCommitted,
  });

  final LogicalPlaybackSession session;
  final PlaybackRuntimeCoordinator runtimeCoordinator;
  final PlaybackSourceNegotiation negotiate;
  final PlaybackSessionReporter reporter;
  final void Function() invalidateRecovery;
  final PlaybackSourceSelectionCommitted onCommitted;

  int _generation = 0;
  bool _disposed = false;
  bool? _pendingPlayIntent;
  PlaybackTransitionOperation? _operation;

  Future<PlaybackSourceSwitchStatus> select(MediaSourceInfo source) async {
    final generation = ++_generation;
    final previous = runtimeCoordinator.active;
    if (_disposed || previous == null || source.id.isEmpty) {
      return PlaybackSourceSwitchStatus.unchanged;
    }
    if (source.id == session.activePlan.mediaSourceId) {
      return PlaybackSourceSwitchStatus.unchanged;
    }

    final wasPlaying = _pendingPlayIntent ?? previous.engine.playing.value;
    final endTransition = runtimeCoordinator.beginTransition();
    _operation = endTransition;
    _pendingPlayIntent = wasPlaying;
    final handoff = PlaybackSourceHandoff(
      itemId: session.itemId,
      mediaSourceId: session.activePlan.mediaSourceId,
      playSessionId: session.activePlan.playSessionId,
      position: previous.engine.position,
      wasPlaying: wasPlaying,
      audioStreamIndex: session.selectedAudio,
      subtitleStreamIndex: session.selectedSubtitle,
      metadata: session.metadata,
    );

    invalidateRecovery();
    try {
      if (previous.engine.playing.value) await previous.engine.pause();
      if (!_isCurrent(generation, previous)) {
        return PlaybackSourceSwitchStatus.superseded;
      }

      final decision = await negotiate(
        itemId: handoff.itemId,
        mediaSourceId: source.id,
        audioStreamIndex: handoff.audioStreamIndex,
        subtitleStreamIndex: handoff.subtitleStreamIndex,
      );
      if (!_isCurrent(generation, previous)) {
        return PlaybackSourceSwitchStatus.superseded;
      }

      final plan = decision.plan;
      if (plan.itemId != handoff.itemId || plan.mediaSourceId != source.id) {
        throw StateError(
          'The server did not return the selected video version.',
        );
      }
      if (handoff.playSessionId != null &&
          plan.playSessionId == handoff.playSessionId) {
        throw StateError(
          'The selected video version did not start a new session.',
        );
      }

      await runtimeCoordinator.activateCandidates(
        decision.orderedUsableCandidates,
        transition: endTransition,
        canCommit: () =>
            endTransition.isCurrent && _isCurrent(generation, previous),
        prepare: (candidate) async {
          if (!_isCurrent(generation, previous)) {
            throw PlaybackActivationSupersededException();
          }
          if (candidate.engine.playing.value) {
            await candidate.engine.pause();
          }
          await candidate.engine.seek(handoff.position);
          if (!_isCurrent(generation, previous)) {
            throw PlaybackActivationSupersededException();
          }
          if (wasPlaying) {
            await candidate.engine.play();
          } else {
            await candidate.engine.pause();
          }
        },
        onCommit: (oldRuntime, newRuntime) async {
          session.position = handoff.position;
          // Runtime binding observers and this coordinator share the reporter.
          // Its serialized target transition makes this idempotent.
          unawaited(reporter.synchronize(handoff.position));
          await onCommitted(handoff, newRuntime);
        },
      );

      if (!_isCurrent(generation, runtimeCoordinator.active)) {
        return PlaybackSourceSwitchStatus.superseded;
      }
      return PlaybackSourceSwitchStatus.committed;
    } on PlaybackActivationSupersededException {
      return PlaybackSourceSwitchStatus.superseded;
    } on Object {
      if (!_isCurrentGeneration(generation)) {
        return PlaybackSourceSwitchStatus.superseded;
      }
      if (_isCurrent(generation, previous) &&
          identical(runtimeCoordinator.active, previous)) {
        session.position = handoff.position;
        if (wasPlaying) {
          await previous.engine.play();
        } else {
          await previous.engine.pause();
        }
      }
      rethrow;
    } finally {
      if (!_disposed && generation == _generation) _pendingPlayIntent = null;
      endTransition();
    }
  }

  void dispose() {
    _disposed = true;
    _generation += 1;
    _pendingPlayIntent = null;
  }

  bool _isCurrentGeneration(int generation) =>
      !_disposed && generation == _generation && _operation?.isCurrent == true;

  bool _isCurrent(int generation, PlaybackRuntimeSession? previous) =>
      _isCurrentGeneration(generation) &&
      identical(runtimeCoordinator.active, previous);
}
