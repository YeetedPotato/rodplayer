import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/p5e_live_proof.dart';

void main() {
  test('P5E_ACTION resumes after cached event replay and records safe fields', () async {
    final home = await Directory.systemTemp.createTemp('p5e-proof-');
    addTearDown(() => home.delete(recursive: true));
    final runtime = _ProofRuntime(_directStatus);

    final result = await runP5ELiveProof(
      environment: <String, String>{
        'HOME': 'ignored-by-proof-home',
        'P5E_ACTION': 'resume',
        'P5E_PROOF_HOME': home.path,
      },
      runtime: runtime,
    );

    expect(result, 0);
    expect(runtime.operationCalledAfterCachedReplay, isTrue);
    final proof = File(
      '${home.path}${Platform.pathSeparator}Library${Platform.pathSeparator}'
      'Application Support${Platform.pathSeparator}RodPlayer'
      '${Platform.pathSeparator}P5EProof${Platform.pathSeparator}proof.jsonl',
    );
    final records = (await proof.readAsLines())
        .map((line) => jsonDecode(line) as Map<String, Object?>)
        .toList();

    expect(records, isNotEmpty);
    for (final record in records) {
      expect(
        record.keys.toSet(),
        <String>{
          'timestamp',
          'action',
          'source',
          'state',
          'path',
          'hasPersistedIdentity',
          'reason',
          'hasGateway',
          'canProxy',
        },
      );
      expect(record['hasGateway'], isFalse);
      expect(record['canProxy'], isFalse);
    }
  });

  test('bootstrap deletes setup code before enrollment and redacts proof log', () async {
    final home = await Directory.systemTemp.createTemp('p5e-proof-');
    addTearDown(() => home.delete(recursive: true));
    final directory = Directory(
      '${home.path}${Platform.pathSeparator}Library${Platform.pathSeparator}'
      'Application Support${Platform.pathSeparator}RodPlayer'
      '${Platform.pathSeparator}P5EProof',
    );
    await directory.create(recursive: true);
    const setupCode = 'setup-code-sentinel';
    const authKey = 'auth-key-sentinel';
    final codeFile = File('${directory.path}/setup-code.txt');
    await codeFile.writeAsString(setupCode);
    final runtime = _ProofRuntime(_directStatus);

    final result = await runP5ELiveProof(
      arguments: const <String>['--p5e-action=bootstrap'],
      environment: <String, String>{'P5E_PROOF_HOME': home.path},
      runtime: runtime,
      enroll: (code) async {
        expect(code, setupCode);
        expect(await codeFile.exists(), isFalse);
        return FamilyEnrollmentResult(
          version: 1,
          controlUrl: Uri(scheme: 'https', host: 'mesh.example.test'),
          authKey: authKey,
          authKeyLifetime: Duration(minutes: 5),
          homeIpv4: '100.64.0.1',
          homePort: 3000,
        );
      },
    );

    expect(result, 0);
    expect(runtime.operationCalledAfterCachedReplay, isTrue);
    expect(await codeFile.exists(), isFalse);
    final proof = await File('${directory.path}/proof.jsonl').readAsString();
    expect(proof, isNot(contains(setupCode)));
    expect(proof, isNot(contains(authKey)));
  });

  test('diagnose records only the allowlisted diagnostic payload', () async {
    final home = await Directory.systemTemp.createTemp('p5e-proof-');
    addTearDown(() => home.delete(recursive: true));
    final runtime = _ProofRuntime(_directStatus);

    final result = await runP5ELiveProof(
      environment: <String, String>{
        'P5E_ACTION': 'diagnose',
        'P5E_PROOF_HOME': home.path,
      },
      runtime: runtime,
      diagnose: () async => <String, Object?>{
        'backendState': 'Running',
        'totalPeerCount': 2,
        'homePeerMatchCount': 1,
        'homePeerOnline': true,
        'homePeerHasCurAddr': true,
        'homePeerHasPeerRelay': false,
        'persistedIdentity': true,
      },
    );

    expect(result, 0);
    final proof = await File(
      '${home.path}${Platform.pathSeparator}Library${Platform.pathSeparator}'
      'Application Support${Platform.pathSeparator}RodPlayer'
      '${Platform.pathSeparator}P5EProof${Platform.pathSeparator}proof.jsonl',
    ).readAsString();
    final record = jsonDecode(proof) as Map<String, Object?>;
    expect(record.keys.toSet(), <String>{
      'timestamp',
      'action',
      'backendState',
      'totalPeerCount',
      'homePeerMatchCount',
      'homePeerOnline',
      'homePeerHasCurAddr',
      'homePeerHasPeerRelay',
      'persistedIdentity',
    });
    expect(proof, isNot(contains('auth-key-sentinel')));
  });

  test('diagnose rejects unallowlisted endpoint and key data', () async {
    final home = await Directory.systemTemp.createTemp('p5e-proof-');
    addTearDown(() => home.delete(recursive: true));
    final runtime = _ProofRuntime(_directStatus);

    final result = await runP5ELiveProof(
      environment: <String, String>{
        'P5E_ACTION': 'diagnose',
        'P5E_PROOF_HOME': home.path,
      },
      runtime: runtime,
      diagnose: () async => <String, Object?>{
        'backendState': 'Running',
        'totalPeerCount': 1,
        'homePeerMatchCount': 1,
        'homePeerOnline': true,
        'homePeerHasCurAddr': true,
        'homePeerHasPeerRelay': false,
        'persistedIdentity': true,
        'curAddr': 'endpoint-sentinel',
        'authKey': 'auth-key-sentinel',
      },
    );

    expect(result, 1);
  });

  test('bounded cancellation returns when an event subscription never closes', () async {
    final home = await Directory.systemTemp.createTemp('p5e-proof-');
    addTearDown(() => home.delete(recursive: true));
    final runtime = _ProofRuntime(_directStatus, hangOnCancel: true);
    final watch = Stopwatch()..start();

    final result = await runP5ELiveProof(
      arguments: const <String>['--p5e-action=resume'],
      environment: <String, String>{'HOME': home.path},
      runtime: runtime,
    );

    expect(result, 0);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('reset requires the authoritative stopped identity-free status', () async {
    final home = await Directory.systemTemp.createTemp('p5e-proof-');
    addTearDown(() => home.delete(recursive: true));
    final runtime = _ProofRuntime(_stoppedWithoutIdentity);

    final result = await runP5ELiveProof(
      arguments: const <String>['--p5e-action=reset'],
      environment: <String, String>{'HOME': home.path},
      runtime: runtime,
    );

    expect(result, 0);
    expect(runtime.resetCalls, 1);
  });
}

const _directStatus = PrivateNetworkStatus(
  state: PrivateNetworkState.starting,
  path: PrivateNetworkPath.direct,
  hasPersistedIdentity: true,
  unavailableReason: PrivateNetworkUnavailableReason.none,
);

const _stoppedWithoutIdentity = PrivateNetworkStatus(
  state: PrivateNetworkState.stopped,
  path: PrivateNetworkPath.none,
  hasPersistedIdentity: false,
  unavailableReason: PrivateNetworkUnavailableReason.none,
);

class _ProofRuntime implements PrivateNetworkRuntime {
  _ProofRuntime(this._status, {bool hangOnCancel = false})
    : _hangOnCancel = hangOnCancel,
      _events = StreamController<PrivateNetworkStatus>.broadcast(sync: true) {
    _events.onListen = () {
      cachedReplayDelivered = true;
      _events.add(_status);
    };
    if (_hangOnCancel) {
      _events.onCancel = () => _neverCancel.future;
    }
  }

  PrivateNetworkStatus _status;
  final StreamController<PrivateNetworkStatus> _events;
  final bool _hangOnCancel;
  final Completer<void> _neverCancel = Completer<void>();
  bool cachedReplayDelivered = false;
  bool operationCalledAfterCachedReplay = false;
  int resetCalls = 0;

  @override
  Stream<PrivateNetworkStatus> get statuses => _events.stream;

  @override
  Future<PrivateNetworkStatus> bootstrap(PrivateNetworkBootstrap bootstrap) {
    operationCalledAfterCachedReplay = cachedReplayDelivered;
    return Future<PrivateNetworkStatus>.value(_status);
  }

  @override
  Future<bool> confirmHostAvailable() => Future<bool>.value(true);

  @override
  Future<void> reset() async {
    resetCalls += 1;
    _status = _stoppedWithoutIdentity;
  }

  @override
  Future<PrivateNetworkStatus> resume() async {
    operationCalledAfterCachedReplay = cachedReplayDelivered;
    _events.add(_status);
    return _status;
  }

  @override
  Future<PrivateNetworkStatus> status() => Future<PrivateNetworkStatus>.value(_status);

  @override
  Future<void> stop() async {}
}
