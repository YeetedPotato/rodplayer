final class RoomId {
  RoomId(String value) : value = _required(value, 'room ID');
  final String value;
  @override
  bool operator ==(Object other) => other is RoomId && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

final class ParticipantId {
  ParticipantId(String value) : value = _required(value, 'participant ID');
  final String value;
  @override
  bool operator ==(Object other) =>
      other is ParticipantId && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

String _required(String value, String label) {
  if (value.trim().isEmpty || value.trim() != value)
    throw FormatException('Invalid $label');
  return value;
}

void _opaqueIdentity(String value, String label, int maxLength) {
  if (value.trim().isEmpty ||
      value.trim() != value ||
      value.length > maxLength ||
      value.contains('://') ||
      value.contains(RegExp(r'\s'))) {
    throw FormatException('Invalid $label');
  }
}

enum RoomRole { host, guest }

enum RoomPlaybackState { playing, paused }

enum RoomPlaybackCommandKind { play, pause, seek }

/// Safe identity used for local library resolution. No URL, token, or source
/// path can be represented in a room media reference.
final class RoomMediaReference {
  RoomMediaReference({
    required this.serverId,
    required this.itemId,
    this.serverSystemId,
  }) {
    _opaqueIdentity(serverId, 'server ID', 128);
    _opaqueIdentity(itemId, 'item ID', 256);
    if (serverSystemId != null) {
      _opaqueIdentity(serverSystemId!, 'server system ID', 256);
    }
  }
  final String serverId;
  final String itemId;
  final String? serverSystemId;
}

final class RoomParticipant {
  const RoomParticipant({
    required this.id,
    required this.role,
    this.mayControl = false,
  });
  final ParticipantId id;
  final RoomRole role;
  final bool mayControl;
}

final class RoomPlaybackIntent {
  const RoomPlaybackIntent({
    required this.media,
    required this.state,
    required this.position,
    required this.hostMonotonicTime,
    required this.sequence,
  });
  final RoomMediaReference media;
  final RoomPlaybackState state;
  final Duration position;
  final Duration hostMonotonicTime;
  final int sequence;
}

final class RoomState {
  RoomState({
    required this.protocolVersion,
    required this.id,
    required this.hostId,
    required this.intent,
    required Iterable<RoomParticipant> participants,
  }) : participants = List<RoomParticipant>.unmodifiable(participants) {
    if (protocolVersion < 1 ||
        intent.sequence < 0 ||
        intent.position.isNegative ||
        intent.hostMonotonicTime.isNegative ||
        this.participants.length > 256)
      throw ArgumentError('Invalid room version, sequence, or playback time');
    if (this.participants.map((participant) => participant.id).toSet().length !=
        this.participants.length) {
      throw ArgumentError('Duplicate room participant identity');
    }
    if (!this.participants.any(
      (participant) =>
          participant.id == hostId && participant.role == RoomRole.host,
    )) {
      throw ArgumentError('Room host must be a host participant');
    }
  }

  final int protocolVersion;
  final RoomId id;
  final ParticipantId hostId;
  final RoomPlaybackIntent intent;
  final List<RoomParticipant> participants;

  bool permits(ParticipantId participant, RoomPlaybackCommandKind command) {
    RoomParticipant? member;
    for (final value in participants) {
      if (value.id == participant) {
        member = value;
        break;
      }
    }
    if (member == null) return false;
    if (member.role == RoomRole.host) return true;
    // Guests follow authoritative state by default. The opt-in permission is
    // intentionally explicit and can be narrowed by command type later.
    return member.mayControl && command != RoomPlaybackCommandKind.seek;
  }

  /// Sender-local IDs are provenance only, never cross-device resolution keys.
  /// A participant must first map this verified system ID to its own ServerId.
  bool canResolveOnVerifiedServer(String? verifiedSystemId) =>
      intent.media.serverSystemId != null &&
      intent.media.serverSystemId == verifiedSystemId;

  RoomState accept(RoomState incoming, {required ParticipantId sender}) {
    if (sender != hostId) {
      throw StateError('Only the room host may publish authoritative state');
    }
    if (incoming.id.value != id.value ||
        incoming.protocolVersion != protocolVersion) {
      throw StateError('Room identity or protocol version mismatch');
    }
    if (incoming.intent.sequence <= intent.sequence) return this;
    if (incoming.hostId != hostId)
      throw StateError('Room host authority cannot change in a state update');
    return incoming;
  }
}

final class ClockSyncSample {
  const ClockSyncSample({
    required this.localSent,
    required this.remoteReceived,
    required this.remoteSent,
    required this.localReceived,
  });
  final Duration localSent;
  final Duration remoteReceived;
  final Duration remoteSent;
  final Duration localReceived;

  Duration? get roundTrip {
    final elapsed = localReceived - localSent - (remoteSent - remoteReceived);
    return elapsed.isNegative ? null : elapsed;
  }

  /// Remote monotonic clock minus local monotonic clock.
  Duration get offset => Duration(
    microseconds:
        ((remoteReceived - localSent).inMicroseconds +
            (remoteSent - localReceived).inMicroseconds) ~/
        2,
  );
}

final class ClockOffsetEstimator {
  ClockOffsetEstimator({
    this.maxSamples = nineSamples,
    this.maxRoundTrip = const Duration(seconds: 2),
  }) {
    if (maxSamples < 1 || maxSamples > 64 || maxRoundTrip.isNegative) {
      throw ArgumentError('Invalid clock estimator bounds');
    }
  }

  static const nineSamples = 9;
  final int maxSamples;
  final Duration maxRoundTrip;
  final List<({Duration offset, Duration roundTrip})> _samples = [];

  int get sampleCount => _samples.length;
  Duration? get offset {
    if (_samples.isEmpty) return null;
    final sorted =
        _samples.map((sample) => sample.offset.inMicroseconds).toList()..sort();
    return Duration(microseconds: sorted[sorted.length ~/ 2]);
  }

  bool add(ClockSyncSample sample) {
    final roundTrip = sample.roundTrip;
    if (roundTrip == null || roundTrip > maxRoundTrip) return false;
    final candidate = (offset: sample.offset, roundTrip: roundTrip);
    final existing = offset;
    if (existing != null &&
        (candidate.offset - existing).abs() > const Duration(seconds: 30))
      return false;
    _samples.add(candidate);
    if (_samples.length > maxSamples) _samples.removeAt(0);
    return true;
  }
}

enum DriftAction { ignore, adjustRate, seek }

final class DriftPolicy {
  const DriftPolicy({
    this.ignoreUnder = const Duration(milliseconds: 250),
    this.maxRateAdjustUnder = const Duration(seconds: 5),
    this.maxRateCorrection = 0.03,
  });
  final Duration ignoreUnder;
  final Duration maxRateAdjustUnder;
  final double maxRateCorrection;

  DriftAction action(
    Duration drift, {
    required bool playing,
    required bool rateAdjustmentSupported,
  }) {
    if (!playing || drift.abs() <= ignoreUnder) return DriftAction.ignore;
    if (rateAdjustmentSupported && drift.abs() <= maxRateAdjustUnder)
      return DriftAction.adjustRate;
    return DriftAction.seek;
  }

  double rateCorrection(Duration drift) =>
      (drift.inMicroseconds / const Duration(seconds: 30).inMicroseconds)
          .clamp(-maxRateCorrection, maxRateCorrection)
          .toDouble();
}

Duration estimateReconnectPosition({
  required RoomPlaybackIntent intent,
  required Duration localNow,
  required Duration remoteMinusLocalClockOffset,
}) {
  if (intent.state == RoomPlaybackState.paused) return intent.position;
  final remoteNow = localNow + remoteMinusLocalClockOffset;
  final elapsed = remoteNow - intent.hostMonotonicTime;
  return intent.position + (elapsed.isNegative ? Duration.zero : elapsed);
}

Duration absoluteDrift(Duration expected, Duration actual) =>
    Duration(microseconds: (expected - actual).inMicroseconds.abs());
