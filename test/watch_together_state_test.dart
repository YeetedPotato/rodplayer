import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/watch_together/watch_together_state.dart';

void main() {
  late RoomState state;
  late ParticipantId host;
  late ParticipantId guest;

  setUp(() {
    host = ParticipantId('host');
    guest = ParticipantId('guest');
    state = _room(sequence: 5);
  });

  test(
    'host controls; guests follow unless explicitly granted narrow permission',
    () {
      expect(state.permits(host, RoomPlaybackCommandKind.seek), isTrue);
      expect(state.permits(guest, RoomPlaybackCommandKind.play), isFalse);
      expect(
        state.permits(ParticipantId('unknown'), RoomPlaybackCommandKind.pause),
        isFalse,
      );
      final granted = _room(sequence: 5, guestControl: true);
      expect(granted.permits(guest, RoomPlaybackCommandKind.play), isTrue);
      expect(granted.permits(guest, RoomPlaybackCommandKind.seek), isFalse);
    },
  );

  test('older or duplicate room packets cannot rewind state', () {
    expect(state.accept(_room(sequence: 4), sender: host), same(state));
    expect(state.accept(_room(sequence: 5), sender: host), same(state));
    expect(state.accept(_room(sequence: 6), sender: host).intent.sequence, 6);
  });

  test(
    'one thousand ordered and reordered packets keep bounded monotonic state',
    () {
      var current = state;
      for (var sequence = 6; sequence <= 1000; sequence++) {
        current = current.accept(_room(sequence: sequence), sender: host);
      }
      expect(current.intent.sequence, 1000);
      expect(current.accept(_room(sequence: 999), sender: host), same(current));
    },
  );

  test('guest cannot publish authoritative playback state', () {
    expect(
      () => state.accept(_room(sequence: 6), sender: guest),
      throwsStateError,
    );
  });

  test('protocol version and room identity mismatches are rejected', () {
    expect(
      () => state.accept(_room(sequence: 6, version: 2), sender: host),
      throwsStateError,
    );
    expect(
      () => state.accept(_room(sequence: 6, roomId: 'other'), sender: host),
      throwsStateError,
    );
  });

  test(
    'room state rejects duplicate participants and negative playback data',
    () {
      final duplicateHost = RoomParticipant(id: host, role: RoomRole.host);
      expect(
        () => RoomState(
          protocolVersion: 1,
          id: RoomId('room'),
          hostId: host,
          intent: _intent(sequence: 1),
          participants: <RoomParticipant>[duplicateHost, duplicateHost],
        ),
        throwsArgumentError,
      );
      expect(
        () => RoomState(
          protocolVersion: 1,
          id: RoomId('room'),
          hostId: host,
          intent: RoomPlaybackIntent(
            media: RoomMediaReference(serverId: 'server-a', itemId: 'item-a'),
            state: RoomPlaybackState.playing,
            position: const Duration(seconds: -1),
            hostMonotonicTime: Duration.zero,
            sequence: 1,
          ),
          participants: <RoomParticipant>[duplicateHost],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'room media identity cannot carry endpoints or oversized membership',
    () {
      expect(
        () => RoomMediaReference(
          serverId: 'https://private.example.test',
          itemId: 'item-a',
        ),
        throwsFormatException,
      );
      final members = <RoomParticipant>[
        RoomParticipant(id: host, role: RoomRole.host),
        for (var i = 0; i < 256; i++)
          RoomParticipant(id: ParticipantId('guest-$i'), role: RoomRole.guest),
      ];
      expect(
        () => RoomState(
          protocolVersion: 1,
          id: RoomId('room'),
          hostId: host,
          intent: _intent(sequence: 1),
          participants: members,
        ),
        throwsArgumentError,
      );
      expect(() => ClockOffsetEstimator(maxSamples: 65), throwsArgumentError);
    },
  );

  test('media resolves only on the provenance server', () {
    expect(
      state.canResolveOnVerifiedServer('server-a'),
      isFalse,
      reason: 'sender-local ID is not a verified cross-device identity',
    );
    expect(state.canResolveOnVerifiedServer(null), isFalse);
  });

  test(
    'cross-device resolution requires verified identity, not sender local ID',
    () {
      final verified = RoomState(
        protocolVersion: 1,
        id: state.id,
        hostId: host,
        participants: state.participants,
        intent: RoomPlaybackIntent(
          media: RoomMediaReference(
            serverId: 'sender-local-a',
            itemId: 'item-a',
            serverSystemId: 'system-one',
          ),
          state: RoomPlaybackState.paused,
          position: Duration.zero,
          hostMonotonicTime: Duration.zero,
          sequence: 1,
        ),
      );
      expect(verified.canResolveOnVerifiedServer('system-one'), isTrue);
      expect(verified.canResolveOnVerifiedServer('sender-local-a'), isFalse);
      expect(verified.canResolveOnVerifiedServer('system-two'), isFalse);
    },
  );

  test(
    'clock offset estimator uses monotonic samples and rejects outliers',
    () {
      final estimator = ClockOffsetEstimator();
      expect(
        estimator.add(
          const ClockSyncSample(
            localSent: Duration(seconds: 10),
            remoteReceived: Duration(seconds: 15, milliseconds: 20),
            remoteSent: Duration(seconds: 15, milliseconds: 30),
            localReceived: Duration(seconds: 10, milliseconds: 40),
          ),
        ),
        isTrue,
      );
      expect(estimator.offset, const Duration(seconds: 5, milliseconds: 5));
      expect(
        estimator.add(
          const ClockSyncSample(
            localSent: Duration(seconds: 11),
            remoteReceived: Duration(seconds: 80),
            remoteSent: Duration(seconds: 80),
            localReceived: Duration(seconds: 11, milliseconds: 10),
          ),
        ),
        isFalse,
      );
      expect(estimator.sampleCount, 1);
    },
  );

  test(
      'drift policy ignores tiny and paused drift, rate-corrects moderate, seeks large',
      () {
    const policy = DriftPolicy();
    expect(
      policy.action(
        const Duration(milliseconds: 100),
        playing: true,
        rateAdjustmentSupported: true,
      ),
      DriftAction.ignore,
    );
    expect(
      policy.action(
        const Duration(seconds: 2),
        playing: true,
        rateAdjustmentSupported: true,
      ),
      DriftAction.adjustRate,
    );
    expect(
      policy.action(
        const Duration(seconds: 8),
        playing: true,
        rateAdjustmentSupported: true,
      ),
      DriftAction.seek,
    );
    expect(
      policy.action(
        const Duration(seconds: 8),
        playing: false,
        rateAdjustmentSupported: true,
      ),
      DriftAction.ignore,
    );
    expect(policy.rateCorrection(const Duration(seconds: 20)), 0.03);
  });

  test('reconnect target advances only while host is playing', () {
    final playing = _intent(
      sequence: 1,
      state: RoomPlaybackState.playing,
      hostTime: const Duration(seconds: 100),
    );
    expect(
      estimateReconnectPosition(
        intent: playing,
        localNow: const Duration(seconds: 105),
        remoteMinusLocalClockOffset: Duration.zero,
      ),
      const Duration(seconds: 5),
    );
    final paused = _intent(
      sequence: 2,
      state: RoomPlaybackState.paused,
      hostTime: const Duration(seconds: 100),
    );
    expect(
      estimateReconnectPosition(
        intent: paused,
        localNow: const Duration(seconds: 105),
        remoteMinusLocalClockOffset: Duration.zero,
      ),
      Duration.zero,
    );
  });
}

RoomState _room({
  required int sequence,
  int version = 1,
  String roomId = 'room',
  bool guestControl = false,
}) =>
    RoomState(
      protocolVersion: version,
      id: RoomId(roomId),
      hostId: ParticipantId('host'),
      participants: <RoomParticipant>[
        RoomParticipant(id: ParticipantId('host'), role: RoomRole.host),
        RoomParticipant(
          id: ParticipantId('guest'),
          role: RoomRole.guest,
          mayControl: guestControl,
        ),
      ],
      intent: _intent(sequence: sequence),
    );

RoomPlaybackIntent _intent({
  required int sequence,
  RoomPlaybackState state = RoomPlaybackState.playing,
  Duration hostTime = Duration.zero,
}) =>
    RoomPlaybackIntent(
      media: RoomMediaReference(serverId: 'server-a', itemId: 'item-a'),
      state: state,
      position: Duration.zero,
      hostMonotonicTime: hostTime,
      sequence: sequence,
    );
