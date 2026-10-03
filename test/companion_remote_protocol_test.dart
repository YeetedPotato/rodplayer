import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/companion/companion_command_bridge.dart';
import 'package:rodplayer/core/companion/companion_remote_protocol.dart';
import 'package:rodplayer/core/player/playback_command_controller.dart';
import 'package:rodplayer/core/companion/remote_device_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('applied runtime replacement retains the executed acknowledgment', () {
    const decision = CompanionCommandDecision(
      CompanionCommandAdmission.accepted,
      playbackResult: PlaybackCommandResult(
        PlaybackCommandStatus.appliedReplacement,
        PlaybackCommandOrigin.localUi,
      ),
    );
    expect(decision.acknowledgmentStatus, CompanionAcknowledgmentStatus.executed);
  });

  test('pair approval and revocation persist metadata without a pairing secret',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = PreferencesRemoteDeviceStore(prefs);
    final pairing = CompanionPairingCoordinator(store: store);
    final at = DateTime.utc(2026);
    final pending = await pairing.request(
      id: RemoteDeviceId('remote-1'),
      label: 'living-room remote',
      at: at,
    );
    final approved = await pairing.approve(pending.id, at: at);
    expect(approved.status, RemoteDeviceStatus.paired);
    expect((await store.load()).single.status, RemoteDeviceStatus.paired);
    final revoked = await pairing.revoke(pending.id, at: at);
    expect(revoked.status, RemoteDeviceStatus.revoked);
    expect((await store.load()).single.status, RemoteDeviceStatus.revoked);
    final stored = prefs.getString(PreferencesRemoteDeviceStore.preferenceKey)!;
    expect(stored, isNot(contains('token')));
    expect(stored, isNot(contains('secret')));
  });

  test('remote-device snapshots over the storage bound fail closed', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PreferencesRemoteDeviceStore.preferenceKey,
      jsonEncode(<String, Object?>{
        'version': 1,
        'devices': List<Map<String, Object?>>.generate(
          33,
          (index) => <String, Object?>{
            'id': 'remote-$index',
            'label': 'Remote $index',
            'status': 'paired',
            'pairedAt': DateTime.utc(2026).toIso8601String(),
          },
        ),
      }),
    );
    await expectLater(
      PreferencesRemoteDeviceStore(prefs).load(),
      throwsA(isA<RemoteDeviceStoreCorruptException>()),
    );
  });

  test('typed protocol allowlist contains no server token or media URL field',
      () {
    final message = decodeCompanionMessage(<String, Object?>{
      'version': 1,
      'id': 'msg-1',
      'type': 'command',
      'command': 'seekRelative',
      'seekMs': 15000,
    }) as CompanionCommandMessage;
    expect(message.command, isA<SeekRelativeCommand>());
    expect((message.command as SeekRelativeCommand).offset,
        const Duration(seconds: 15));
    expect(message.toJson().keys,
        containsAll(<String>['version', 'id', 'type', 'command', 'seekMs']));
    expect(message.toJson().keys, isNot(contains('url')));
    expect(message.toJson().keys, isNot(contains('accessToken')));
    expect(
        () => decodeCompanionMessage(<String, Object?>{
              'version': 2,
              'id': 'x',
              'type': 'ping',
              'monotonicMs': 1
            }),
        throwsFormatException);
    expect(
        () => decodeCompanionMessage(<String, Object?>{
              'version': 1,
              'id': 'x',
              'type': 'invoke',
              'method': 'play'
            }),
        throwsFormatException);
    expect(
      () => decodeCompanionMessage(<String, Object?>{
        'version': 1,
        'id': 'x',
        'type': 'command',
        'command': 'play',
        'accessToken': 'must-not-be-accepted',
      }),
      throwsFormatException,
    );
    expect(
      () => decodeCompanionMessage(<String, Object?>{
        'version': 1,
        'id': 'x',
        'type': 'playbackState',
        'playing': true,
        'positionMs': -1,
      }),
      throwsFormatException,
    );
    expect(
      () => decodeCompanionMessage(<String, Object?>{
        'version': 1,
        'id': 'x',
        'type': 'command',
        'command': 'seekRelative',
        'seekMs': 999999999,
      }),
      throwsFormatException,
    );
  });

  test('replay window is bounded, expires old IDs, and rejects duplicates', () {
    final replay =
        RemoteReplayWindow(capacity: 2, maxAge: const Duration(seconds: 5));
    expect(replay.accept('a', Duration.zero), isTrue);
    expect(replay.accept('a', const Duration(seconds: 1)), isFalse);
    expect(replay.accept('b', const Duration(seconds: 1)), isTrue);
    expect(replay.accept('c', const Duration(seconds: 2)), isTrue);
    expect(replay.accept('a', const Duration(seconds: 3)), isTrue);
    expect(replay.accept('a', const Duration(seconds: 10)), isTrue);
  });

  test('replay IDs are scoped to device/runtime session', () {
    final replay = RemoteReplayWindow();
    expect(replay.accept('same-id', Duration.zero, sessionId: 'device-a:s1'),
        isTrue);
    expect(
        replay.accept('same-id', const Duration(milliseconds: 1),
            sessionId: 'device-a:s1'),
        isFalse);
    expect(
        replay.accept('same-id', const Duration(milliseconds: 2),
            sessionId: 'device-b:s1'),
        isTrue);
    expect(
        replay.accept('same-id', const Duration(milliseconds: 3),
            sessionId: 'device-a:s2'),
        isTrue);
    replay.clearSession('device-a:s1');
    expect(
        replay.accept('same-id', const Duration(milliseconds: 4),
            sessionId: 'device-a:s1'),
        isTrue);
  });

  test('one thousand replay attempts never exceed the configured window', () {
    final replay = RemoteReplayWindow(capacity: 64);
    for (var index = 0; index < 1000; index++) {
      expect(
        replay.accept('message-$index', Duration(milliseconds: index)),
        isTrue,
      );
    }
    expect(replay.length, 64);
  });

  test('replay expiry is inclusive and a regressing clock fails closed', () {
    final replay = RemoteReplayWindow(maxAge: const Duration(seconds: 5));
    expect(replay.accept('same', Duration.zero), isTrue);
    expect(replay.accept('same', const Duration(seconds: 5)), isTrue);
    expect(replay.accept('new', const Duration(seconds: 4)), isFalse);
    expect(replay.accept('new', const Duration(seconds: 6)), isTrue);
  });

  test('per-peer limiter caps command floods and forgets disconnected peers',
      () {
    final limiter = RemoteControlRateLimiter(limit: 2, maxPeers: 1);
    expect(limiter.allow('a', Duration.zero), isTrue);
    expect(limiter.allow('a', const Duration(milliseconds: 1)), isTrue);
    expect(limiter.allow('a', const Duration(milliseconds: 2)), isFalse);
    expect(limiter.allow('b', const Duration(milliseconds: 3)), isTrue);
    limiter.removePeer('b');
    expect(limiter.allow('b', const Duration(milliseconds: 4)), isTrue);
  });

  test('per-peer limiter does not reopen a burst on clock regression', () {
    final limiter = RemoteControlRateLimiter(limit: 1);
    expect(limiter.allow('a', const Duration(seconds: 10)), isTrue);
    expect(limiter.allow('a', const Duration(seconds: 9)), isFalse);
    expect(limiter.allow('a', const Duration(seconds: 10)), isFalse);
    expect(limiter.allow('a', const Duration(seconds: 11)), isTrue);
  });

  test('revoked, expired, and unknown peers are rejected before playback',
      () async {
    final bridge = _bridge();
    final message = const CompanionCommandMessage(
        protocolVersion: 1, messageId: 'one', kind: CompanionCommandKind.play);
    expect(
        (await bridge.handle(
                device: null, message: message, wallNow: DateTime.utc(2026)))
            .admission,
        CompanionCommandAdmission.unknownDevice);
    expect(
        (await bridge.handle(
                device: _device(RemoteDeviceStatus.revoked),
                message: message,
                wallNow: DateTime.utc(2026)))
            .admission,
        CompanionCommandAdmission.unauthorizedDevice);
    expect(
        (await bridge.handle(
                device: _device(RemoteDeviceStatus.paired,
                    expiresAt: DateTime.utc(2025)),
                message: message,
                wallNow: DateTime.utc(2026)))
            .admission,
        CompanionCommandAdmission.expiredDevice);
  });

  test('paired remote acknowledgment reflects central authority gate',
      () async {
    final bridge = _bridge();
    final device = _device(RemoteDeviceStatus.paired);
    final message = const CompanionCommandMessage(
        protocolVersion: 1, messageId: 'one', kind: CompanionCommandKind.play);
    final decision = await bridge.handle(
        device: device, message: message, wallNow: DateTime.utc(2026));
    expect(decision.admission, CompanionCommandAdmission.accepted);
    expect(decision.playbackResult?.status,
        PlaybackCommandStatus.unauthorizedOrigin);
    expect(decision.acknowledgmentStatus,
        CompanionAcknowledgmentStatus.unauthorized);
    expect(
      decodeCompanionMessage(
              decision.toAcknowledgment(messageId: 'one').toJson())
          .toJson()['status'],
      'unauthorized',
    );
  });

  test('pairing lifecycle supports request, approval, expiry, and revoke',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final coordinator = CompanionPairingCoordinator(
      store: PreferencesRemoteDeviceStore(prefs),
    );
    final now = DateTime.utc(2026);
    final pending = await coordinator.request(
      id: RemoteDeviceId('new-device'),
      label: 'Living room',
      at: now,
      expiresAt: now.add(const Duration(days: 1)),
    );
    expect(pending.status, RemoteDeviceStatus.pairing);
    final approved = await coordinator.approve(
      pending.id,
      at: now.add(const Duration(minutes: 1)),
    );
    expect(approved.status, RemoteDeviceStatus.paired);
    final revoked = await coordinator.revoke(
      pending.id,
      at: now.add(const Duration(minutes: 2)),
    );
    expect(revoked.status, RemoteDeviceStatus.revoked);
    await expectLater(
      coordinator.approve(
        pending.id,
        at: now.add(const Duration(minutes: 3)),
      ),
      throwsStateError,
    );

    await coordinator.request(
      id: RemoteDeviceId('expiring-device'),
      label: 'Temporary',
      at: now,
      expiresAt: now.add(const Duration(seconds: 1)),
    );
    expect(await coordinator.expire(now.add(const Duration(seconds: 2))), 1);
    final saved = await PreferencesRemoteDeviceStore(prefs).load();
    expect(
        saved.singleWhere((item) => item.id.value == 'expiring-device').status,
        RemoteDeviceStatus.expired);
  });
}

CompanionCommandBridge _bridge() => CompanionCommandBridge(
      playback: PlaybackCommandController(currentTarget: () => null),
      target: const PlaybackCommandTargetId(
          logicalSessionId: 'session', runtimeGeneration: 1),
      replayWindow: RemoteReplayWindow(),
      rateLimiter: RemoteControlRateLimiter(limit: 4),
      monotonicNow: () => Duration.zero,
    );

PairedRemoteDevice _device(RemoteDeviceStatus status, {DateTime? expiresAt}) =>
    PairedRemoteDevice(
      id: RemoteDeviceId('remote-1'),
      label: 'living-room remote',
      status: status,
      pairedAt: DateTime.utc(2025),
      expiresAt: expiresAt,
    );
