import 'dart:async';
import 'dart:typed_data';

import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/track_controller.dart';

enum PlaybackCommandOrigin {
  localUi,
  keyboard,
  dpad,
  systemMedia,
  companionRemote,
  watchTogether,
}

abstract interface class PlaybackCommandAuthorityPolicy {
  bool allows(PlaybackCommandOrigin origin, PlaybackCommand command);
}

/// Safe default: local inputs and operating-system media controls work, while
/// networked origins require an explicitly composed authority policy.
final class AllowedPlaybackOriginsPolicy
    implements PlaybackCommandAuthorityPolicy {
  AllowedPlaybackOriginsPolicy({
    required Iterable<PlaybackCommandOrigin> allowedOrigins,
  }) : allowedOrigins = Set<PlaybackCommandOrigin>.unmodifiable(allowedOrigins);

  static final localOnly = AllowedPlaybackOriginsPolicy(
    allowedOrigins: const <PlaybackCommandOrigin>{
      PlaybackCommandOrigin.localUi,
      PlaybackCommandOrigin.keyboard,
      PlaybackCommandOrigin.dpad,
      PlaybackCommandOrigin.systemMedia,
    },
  );

  final Set<PlaybackCommandOrigin> allowedOrigins;

  @override
  bool allows(PlaybackCommandOrigin origin, PlaybackCommand command) =>
      allowedOrigins.contains(origin);
}

/// A target identifies one concrete runtime incarnation, not merely a title.
/// Runtime generations make commands captured before source replacement stale.
final class PlaybackCommandTargetId {
  const PlaybackCommandTargetId({
    required this.logicalSessionId,
    required this.runtimeGeneration,
  });

  final String logicalSessionId;
  final int runtimeGeneration;

  @override
  bool operator ==(Object other) =>
      other is PlaybackCommandTargetId &&
      other.logicalSessionId == logicalSessionId &&
      other.runtimeGeneration == runtimeGeneration;

  @override
  int get hashCode => Object.hash(logicalSessionId, runtimeGeneration);
}

sealed class PlaybackCommand {
  const PlaybackCommand();
}

final class PlayCommand extends PlaybackCommand {
  const PlayCommand();
}

final class PauseCommand extends PlaybackCommand {
  const PauseCommand();
}

final class TogglePlayPauseCommand extends PlaybackCommand {
  const TogglePlayPauseCommand();
}

final class StopCommand extends PlaybackCommand {
  const StopCommand();
}

final class SeekAbsoluteCommand extends PlaybackCommand {
  const SeekAbsoluteCommand(this.position);
  final Duration position;
}

final class SeekRelativeCommand extends PlaybackCommand {
  const SeekRelativeCommand(this.offset);
  final Duration offset;
}

final class SetVolumeCommand extends PlaybackCommand {
  const SetVolumeCommand(this.value);
  final double value;
}

final class SetPlaybackRateCommand extends PlaybackCommand {
  const SetPlaybackRateCommand(this.value);
  final double value;
}

final class AdjustSubtitleDelayCommand extends PlaybackCommand {
  const AdjustSubtitleDelayCommand(this.value);
  final Duration value;
}

final class SelectAudioCommand extends PlaybackCommand {
  const SelectAudioCommand(this.track);
  final RodPlayerTrack track;
}

final class SelectSubtitleCommand extends PlaybackCommand {
  const SelectSubtitleCommand(this.track);
  final RodPlayerTrack? track;
}

final class PlaybackCommandRequest {
  const PlaybackCommandRequest({
    required this.command,
    required this.origin,
    required this.target,
  });

  final PlaybackCommand command;
  final PlaybackCommandOrigin origin;
  final PlaybackCommandTargetId target;
}

enum PlaybackCommandStatus {
  transitionInProgress,
  needsServerRenegotiation,
  externalAttachRequired,
  executed,
  appliedReplacement,
  ignoredNoActiveSession,
  staleSession,
  unauthorizedOrigin,
  unsupportedCapability,
  invalidArgument,
  commandQueueFull,
  failedRuntimeOperation,
}

final class PlaybackCommandResult {
  const PlaybackCommandResult(this.status, this.origin);
  final PlaybackCommandStatus status;
  final PlaybackCommandOrigin origin;
  bool get wasApplied =>
      status == PlaybackCommandStatus.executed ||
      status == PlaybackCommandStatus.appliedReplacement;
}

/// Small command-facing view of the current runtime. It deliberately exposes
/// no server credentials, protocol client, or player UI/chrome state.
abstract interface class PlaybackCommandTarget {
  PlaybackCommandTargetId get id;
  PlaybackEngine get engine;
  TrackSelectionController? get tracks;
  AdvancedPlaybackControls? get advanced;
}

final class RuntimePlaybackCommandTarget implements PlaybackCommandTarget {
  const RuntimePlaybackCommandTarget({required this.id, required this.runtime});

  final PlaybackRuntimeSession runtime;

  @override
  final PlaybackCommandTargetId id;

  @override
  PlaybackEngine get engine => runtime.engine;
  @override
  TrackSelectionController? get tracks => runtime.tracks;
  @override
  AdvancedPlaybackControls? get advanced => runtime.advanced;
}

enum TrackSubtitleIntent { ordinary, forced, sdh, closedCaptions }

enum PlaybackTrackKind { audio, subtitle }

/// User intent survives engine/source IDs changing across runtime activation.
final class PlaybackTrackIntent {
  const PlaybackTrackIntent({
    this.language,
    this.kind = PlaybackTrackKind.audio,
    this.subtitle = TrackSubtitleIntent.ordinary,
    this.commentary,
    this.isDefault,
    this.audioChannels,
  });

  final String? language;
  final PlaybackTrackKind kind;
  final TrackSubtitleIntent subtitle;
  final bool? commentary;
  final bool? isDefault;
  final int? audioChannels;

  String? get normalizedLanguage {
    final value = language?.trim().toLowerCase();
    return value == null || value.isEmpty ? null : value;
  }

  bool matches(RodPlayerTrack track) {
    if (normalizedLanguage != null &&
        normalizedLanguage != track.language?.trim().toLowerCase()) {
      return false;
    }
    if (isDefault != null && track.isDefault != isDefault) return false;
    if (kind == PlaybackTrackKind.audio &&
        audioChannels != null &&
        track.channels != audioChannels) {
      return false;
    }
    final description = '${track.title ?? ''} ${track.label}'.toLowerCase();
    final subtitleMatches = switch (subtitle) {
      TrackSubtitleIntent.ordinary => track.isForced != true,
      TrackSubtitleIntent.forced => track.isForced == true,
      TrackSubtitleIntent.sdh =>
        description.contains('sdh') || description.contains('hearing impaired'),
      TrackSubtitleIntent.closedCaptions =>
        description.contains('closed caption') ||
            RegExp(r'\bcc\b').hasMatch(description),
    };
    if (!subtitleMatches) return false;
    if (commentary != null &&
        description.contains('commentary') != commentary) {
      return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackTrackIntent &&
      other.normalizedLanguage == normalizedLanguage &&
      other.kind == kind &&
      other.subtitle == subtitle &&
      other.commentary == commentary &&
      other.isDefault == isDefault &&
      other.audioChannels == audioChannels;

  @override
  int get hashCode => Object.hash(
        normalizedLanguage,
        kind,
        subtitle,
        commentary,
        isDefault,
        audioChannels,
      );
}

enum ScrubPreviewProvenance { serverTrickplay, backendFrame, unknown }

enum ScrubPreviewUnavailableReason {
  unsupported,
  noPreviewAtPosition,
  cancelled,
}

enum ScrubPreviewFailureCategory { transport, invalidResponse, unknown }

final class ScrubPreviewSourceIdentity {
  const ScrubPreviewSourceIdentity({
    required this.serverId,
    required this.itemId,
    required this.mediaSourceId,
  });

  final String serverId;
  final String itemId;
  final String mediaSourceId;
}

abstract interface class ScrubPreviewCancellation {
  bool get isCancelled;
}

final class ScrubPreviewCancellationToken implements ScrubPreviewCancellation {
  bool _cancelled = false;
  @override
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

final class ScrubPreviewRequest {
  const ScrubPreviewRequest({
    required this.position,
    required this.source,
    required this.cancellation,
  });

  final Duration position;
  final ScrubPreviewSourceIdentity source;
  final ScrubPreviewCancellation cancellation;
}

sealed class ScrubPreviewResult {
  const ScrubPreviewResult();
}

final class ScrubPreviewAvailable extends ScrubPreviewResult {
  const ScrubPreviewAvailable({required this.bytes, required this.provenance});

  final Uint8List bytes;
  final ScrubPreviewProvenance provenance;
}

final class ScrubPreviewUnavailable extends ScrubPreviewResult {
  const ScrubPreviewUnavailable(this.reason);
  final ScrubPreviewUnavailableReason reason;
}

final class ScrubPreviewFailed extends ScrubPreviewResult {
  const ScrubPreviewFailed(this.category);
  final ScrubPreviewFailureCategory category;
}

/// Preview lookup stays behind a source contract; timelines must not build
/// Jellyfin trickplay URLs themselves. Implementations must honor cancellation
/// and return provenance so callers can label/debug the source truthfully.
abstract interface class ScrubPreviewSource {
  Future<ScrubPreviewResult> request(ScrubPreviewRequest request);
}

final class PlaybackCommandController {
  static const int _maxQueuedTrackCommandsPerRuntime = 32;

  PlaybackCommandController({
    required this.currentTarget,
    this.isTransitioning,
    this.renegotiateSubtitle,
    PlaybackCommandAuthorityPolicy? authority,
  }) : authority = authority ?? AllowedPlaybackOriginsPolicy.localOnly;

  final PlaybackCommandTarget? Function() currentTarget;
  final bool Function()? isTransitioning;
  final Future<PlaybackRuntimeSession?> Function(RodPlayerTrack track)?
      renegotiateSubtitle;
  final PlaybackCommandAuthorityPolicy authority;
  final Map<PlaybackCommandTargetId, Future<void>> _trackCommandTails =
      <PlaybackCommandTargetId, Future<void>>{};
  final Map<PlaybackCommandTargetId, int> _pendingTrackCommands =
      <PlaybackCommandTargetId, int>{};

  factory PlaybackCommandController.forCoordinator(
    PlaybackRuntimeCoordinator coordinator, {
    Future<PlaybackRuntimeSession?> Function(RodPlayerTrack track)?
        renegotiateSubtitle,
    PlaybackCommandAuthorityPolicy? authority,
  }) =>
      PlaybackCommandController(
        isTransitioning: () => coordinator.isTransitioning,
        renegotiateSubtitle: renegotiateSubtitle,
        authority: authority,
        currentTarget: () {
          final runtime = coordinator.active;
          if (runtime == null || coordinator.activeGeneration == 0) return null;
          return RuntimePlaybackCommandTarget(
            id: PlaybackCommandTargetId(
              logicalSessionId: coordinator.session.id,
              runtimeGeneration: coordinator.activeGeneration,
            ),
            runtime: runtime,
          );
        },
      );

  Future<PlaybackCommandResult> dispatchCurrent({
    required PlaybackCommand command,
    required PlaybackCommandOrigin origin,
  }) {
    final target = currentTarget();
    if (target == null) {
      return Future<PlaybackCommandResult>.value(
        PlaybackCommandResult(
          PlaybackCommandStatus.ignoredNoActiveSession,
          origin,
        ),
      );
    }
    return dispatch(
      PlaybackCommandRequest(
        command: command,
        origin: origin,
        target: target.id,
      ),
    );
  }

  Future<PlaybackCommandResult> dispatch(PlaybackCommandRequest request) async {
    if (!authority.allows(request.origin, request.command)) {
      return PlaybackCommandResult(
        PlaybackCommandStatus.unauthorizedOrigin,
        request.origin,
      );
    }
    final target = currentTarget();
    if (target == null) {
      return PlaybackCommandResult(
        PlaybackCommandStatus.ignoredNoActiveSession,
        request.origin,
      );
    }
    if (target.id != request.target) {
      return PlaybackCommandResult(
        PlaybackCommandStatus.staleSession,
        request.origin,
      );
    }
    if (request.command is SelectAudioCommand ||
        request.command is SelectSubtitleCommand) {
      return _dispatchTrackCommand(request);
    }
    return _execute(request, target);
  }

  Future<PlaybackCommandResult> _dispatchTrackCommand(
    PlaybackCommandRequest request,
  ) async {
    final targetId = request.target;
    final pending = _pendingTrackCommands[targetId] ?? 0;
    if (pending >= _maxQueuedTrackCommandsPerRuntime) {
      return PlaybackCommandResult(
        PlaybackCommandStatus.commandQueueFull,
        request.origin,
      );
    }
    _pendingTrackCommands[targetId] = pending + 1;
    final previous = _trackCommandTails[targetId] ?? Future<void>.value();
    final result = Completer<PlaybackCommandResult>();
    late final Future<void> operation;
    operation = () async {
      try {
        await previous;
      } on Object {
        // A previous operation must not strand later commands in the queue.
      }
      try {
        final current = currentTarget();
        if (current == null) {
          result.complete(
            PlaybackCommandResult(
              PlaybackCommandStatus.ignoredNoActiveSession,
              request.origin,
            ),
          );
        } else if (current.id != targetId) {
          result.complete(
            PlaybackCommandResult(
              PlaybackCommandStatus.staleSession,
              request.origin,
            ),
          );
        } else {
          result.complete(await _execute(request, current));
        }
      } on Object {
        if (!result.isCompleted) {
          result.complete(
            PlaybackCommandResult(
              PlaybackCommandStatus.failedRuntimeOperation,
              request.origin,
            ),
          );
        }
      }
    }();
    _trackCommandTails[targetId] = operation;
    try {
      return await result.future;
    } finally {
      final remaining = (_pendingTrackCommands[targetId] ?? 1) - 1;
      if (remaining == 0) {
        _pendingTrackCommands.remove(targetId);
      } else {
        _pendingTrackCommands[targetId] = remaining;
      }
      if (identical(_trackCommandTails[targetId], operation)) {
        _trackCommandTails.remove(targetId);
      }
    }
  }

  Future<PlaybackCommandResult> _execute(
    PlaybackCommandRequest request,
    PlaybackCommandTarget target,
  ) async {
    if (isTransitioning?.call() == true) {
      return PlaybackCommandResult(
        PlaybackCommandStatus.transitionInProgress,
        request.origin,
      );
    }
    final engine = target.engine;
    final command = request.command;
    try {
      if (command is PlayCommand) {
        await engine.play();
      } else if (command is PauseCommand) {
        await engine.pause();
      } else if (command is TogglePlayPauseCommand) {
        await engine.playOrPause();
      } else if (command is StopCommand) {
        await engine.stop();
      } else if (command is SeekAbsoluteCommand) {
        if (command.position.isNegative) return _invalid(request);
        await engine.seek(command.position);
      } else if (command is SeekRelativeCommand) {
        final position = engine.position + command.offset;
        final lowerBounded =
            position < Duration.zero ? Duration.zero : position;
        final duration = engine.duration;
        await engine.seek(
          duration > Duration.zero && lowerBounded > duration
              ? duration
              : lowerBounded,
        );
      } else if (command is SetVolumeCommand) {
        if (!command.value.isFinite || command.value < 0 || command.value > 100)
          return _invalid(request);
        await engine.setVolume(command.value);
      } else if (command is SetPlaybackRateCommand) {
        final controls = target.advanced;
        if (controls == null ||
            controls.capabilities.playbackRate != CapabilitySupport.supported) {
          return _unsupported(request);
        }
        if (!command.value.isFinite || command.value <= 0)
          return _invalid(request);
        await controls.setRate(command.value);
      } else if (command is AdjustSubtitleDelayCommand) {
        final controls = target.advanced;
        if (controls == null ||
            controls.capabilities.subtitleDelay !=
                CapabilitySupport.supported) {
          return _unsupported(request);
        }
        await controls.adjustSubtitleDelay(command.value);
      } else if (command is SelectAudioCommand) {
        final tracks = target.tracks;
        if (tracks == null ||
            tracks.capabilities.audioSelection != CapabilitySupport.supported ||
            !tracks.audioTracks.contains(command.track))
          return _unsupported(request);
        final result = await tracks.selectAudio(command.track);
        if (currentTarget()?.id != request.target) {
          return PlaybackCommandResult(
            PlaybackCommandStatus.staleSession,
            request.origin,
          );
        }
        switch (result.mode) {
          case TrackSwitchMode.local:
            break;
          case TrackSwitchMode.serverRenegotiation:
            return PlaybackCommandResult(
              PlaybackCommandStatus.needsServerRenegotiation,
              request.origin,
            );
          case TrackSwitchMode.externalAttach:
            return PlaybackCommandResult(
              PlaybackCommandStatus.externalAttachRequired,
              request.origin,
            );
        }
      } else if (command is SelectSubtitleCommand) {
        final tracks = target.tracks;
        if (tracks == null ||
            tracks.capabilities.subtitleSelection !=
                CapabilitySupport.supported ||
            (command.track != null &&
                !tracks.subtitleTracks.contains(command.track)))
          return _unsupported(request);
        final result = await tracks.selectSubtitle(command.track);
        if (currentTarget()?.id != request.target) {
          return PlaybackCommandResult(
              PlaybackCommandStatus.staleSession, request.origin);
        }
        if (result.mode == TrackSwitchMode.externalAttach) {
          return PlaybackCommandResult(
            PlaybackCommandStatus.externalAttachRequired,
            request.origin,
          );
        }
        if (result.mode == TrackSwitchMode.serverRenegotiation) {
          final selected = command.track;
          final callback = renegotiateSubtitle;
          if (selected == null ||
              selected.serverStreamIndex == null ||
              callback == null) {
            return _unsupported(request);
          }
          final replacement = await callback(selected);
          final current = currentTarget();
          return PlaybackCommandResult(
            replacement != null &&
                    current is RuntimePlaybackCommandTarget &&
                    identical(current.runtime, replacement)
                ? PlaybackCommandStatus.appliedReplacement
                : PlaybackCommandStatus.staleSession,
            request.origin,
          );
        }
      } else {
        return _unsupported(request);
      }
      // Runtime replacement can race a command's await. Do not report an old
      // target as successful if ownership changed while it was in flight.
      if (currentTarget()?.id != request.target)
        return PlaybackCommandResult(
          PlaybackCommandStatus.staleSession,
          request.origin,
        );
      return PlaybackCommandResult(
        PlaybackCommandStatus.executed,
        request.origin,
      );
    } on Object {
      if (currentTarget()?.id != request.target) {
        return PlaybackCommandResult(
          PlaybackCommandStatus.staleSession,
          request.origin,
        );
      }
      return PlaybackCommandResult(
        PlaybackCommandStatus.failedRuntimeOperation,
        request.origin,
      );
    }
  }

  PlaybackCommandResult _invalid(PlaybackCommandRequest request) =>
      PlaybackCommandResult(
        PlaybackCommandStatus.invalidArgument,
        request.origin,
      );
  PlaybackCommandResult _unsupported(PlaybackCommandRequest request) =>
      PlaybackCommandResult(
        PlaybackCommandStatus.unsupportedCapability,
        request.origin,
      );
}
