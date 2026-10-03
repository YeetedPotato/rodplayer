import 'package:rodplayer/core/player/playback_command_controller.dart';
import 'companion_remote_protocol.dart';

enum CompanionCommandAdmission {
  accepted,
  unknownDevice,
  unauthorizedDevice,
  expiredDevice,
  replayed,
  rateLimited,
  malformed
}

final class CompanionCommandDecision {
  const CompanionCommandDecision(this.admission, {this.playbackResult});
  final CompanionCommandAdmission admission;
  final PlaybackCommandResult? playbackResult;

  CompanionAcknowledgmentStatus get acknowledgmentStatus {
    return switch (playbackResult?.status) {
      PlaybackCommandStatus.executed ||
      PlaybackCommandStatus.appliedReplacement =>
        CompanionAcknowledgmentStatus.executed,
      PlaybackCommandStatus.unsupportedCapability ||
      PlaybackCommandStatus.needsServerRenegotiation ||
      PlaybackCommandStatus.externalAttachRequired =>
        CompanionAcknowledgmentStatus.unsupported,
      PlaybackCommandStatus.staleSession ||
      PlaybackCommandStatus.ignoredNoActiveSession =>
        CompanionAcknowledgmentStatus.staleSession,
      PlaybackCommandStatus.unauthorizedOrigin =>
        CompanionAcknowledgmentStatus.unauthorized,
      PlaybackCommandStatus.invalidArgument =>
        CompanionAcknowledgmentStatus.invalid,
      PlaybackCommandStatus.commandQueueFull ||
      PlaybackCommandStatus.transitionInProgress =>
        CompanionAcknowledgmentStatus.rateLimited,
      PlaybackCommandStatus.failedRuntimeOperation =>
        CompanionAcknowledgmentStatus.failed,
      null => switch (admission) {
          CompanionCommandAdmission.accepted =>
            CompanionAcknowledgmentStatus.failed,
          CompanionCommandAdmission.unknownDevice ||
          CompanionCommandAdmission.unauthorizedDevice ||
          CompanionCommandAdmission.expiredDevice =>
            CompanionAcknowledgmentStatus.unauthorized,
          CompanionCommandAdmission.replayed ||
          CompanionCommandAdmission.malformed =>
            CompanionAcknowledgmentStatus.invalid,
          CompanionCommandAdmission.rateLimited =>
            CompanionAcknowledgmentStatus.rateLimited,
        },
    };
  }

  CompanionAcknowledgment toAcknowledgment({required String messageId}) =>
      CompanionAcknowledgment(
        protocolVersion: 1,
        messageId: messageId,
        status: acknowledgmentStatus,
      );
}

/// The only path from an authenticated remote command into local playback.
/// The central PlaybackCommandController still denies this future origin by
/// default until an explicit authority policy is enabled.
final class CompanionCommandBridge {
  CompanionCommandBridge({
    required this.playback,
    required this.target,
    required this.replayWindow,
    required this.rateLimiter,
    required this.monotonicNow,
  });

  final PlaybackCommandController playback;
  final PlaybackCommandTargetId target;
  final RemoteReplayWindow replayWindow;
  final RemoteControlRateLimiter rateLimiter;
  final Duration Function() monotonicNow;

  Future<CompanionCommandDecision> handle({
    required PairedRemoteDevice? device,
    required CompanionCommandMessage message,
    required DateTime wallNow,
  }) async {
    if (device == null)
      return const CompanionCommandDecision(
          CompanionCommandAdmission.unknownDevice);
    if (device.status == RemoteDeviceStatus.revoked ||
        device.status == RemoteDeviceStatus.pairing) {
      return const CompanionCommandDecision(
          CompanionCommandAdmission.unauthorizedDevice);
    }
    if (!device.isAuthorizedAt(wallNow)) {
      return const CompanionCommandDecision(
          CompanionCommandAdmission.expiredDevice);
    }
    if (message.protocolVersion != 1 || message.command == null) {
      return const CompanionCommandDecision(
          CompanionCommandAdmission.malformed);
    }
    final now = monotonicNow();
    final replayScope =
        '${device.id.value}|${target.logicalSessionId}|${target.runtimeGeneration}';
    if (!replayWindow.accept(
      message.messageId,
      now,
      sessionId: replayScope,
    )) {
      return const CompanionCommandDecision(CompanionCommandAdmission.replayed);
    }
    if (!rateLimiter.allow(device.id.value, now)) {
      return const CompanionCommandDecision(
          CompanionCommandAdmission.rateLimited);
    }
    final result = await playback.dispatch(PlaybackCommandRequest(
      command: message.command!,
      origin: PlaybackCommandOrigin.companionRemote,
      target: target,
    ));
    return CompanionCommandDecision(CompanionCommandAdmission.accepted,
        playbackResult: result);
  }
}
