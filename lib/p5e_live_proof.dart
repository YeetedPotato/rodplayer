import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/platform/network/method_channel_private_network_runtime.dart';

const _proofDirectoryParts = <String>[
  'Library',
  'Application Support',
  'RodPlayer',
  'P5EProof',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  exit(await runP5ELiveProof());
}

Future<int> runP5ELiveProof({
  List<String>? arguments,
  Map<String, String>? environment,
  PrivateNetworkRuntime? runtime,
  Future<FamilyEnrollmentResult> Function(String setupCode)? enroll,
  Future<Object?> Function()? diagnose,
}) async {
  final values = environment ?? Platform.environment;
  final action = _parseAction(arguments ?? const <String>[]) ??
      _parseEnvironmentAction(values['P5E_ACTION']);
  if (action == null) {
    return 64;
  }

  final proofHome = values['P5E_PROOF_HOME'];
  final home = proofHome != null && proofHome.isNotEmpty
      ? proofHome
      : values['HOME'];
  if (home == null || home.isEmpty) {
    return 1;
  }

  final directory = _proofDirectory(home);
  await directory.create(recursive: true);
  final recorder = _ProofRecorder(File('${directory.path}/proof.jsonl'));
  final network = runtime ?? MethodChannelPrivateNetworkRuntime();

  try {
    if (!await network.confirmHostAvailable()) {
      return 1;
    }

    return switch (action) {
      _ProofAction.bootstrap => await _runBootstrap(
          network,
          directory,
          recorder,
          enroll,
        ),
      _ProofAction.resume => await _runDirectAction(
          network,
          recorder,
          action,
          network.resume,
        ),
      _ProofAction.status => await _runStatus(network, recorder, action),
      _ProofAction.stop => await _runStop(network, recorder),
      _ProofAction.reset => await _runReset(network, recorder),
      _ProofAction.diagnose => await _runDiagnose(
          network,
          recorder,
          diagnose ?? _nativeDiagnose,
        ),
    };
  } on FamilyEnrollmentException catch (error) {
    _printFailure(error.failure.name);
  } on PrivateNetworkException catch (error) {
    _printFailure(error.failure.name);
  } catch (error) {
    _printFailure(error.runtimeType.toString());
  }

  return 1;
}

Directory _proofDirectory(String home) => Directory.fromUri(
  Directory(home).absolute.uri.resolve(
    '${_proofDirectoryParts.join('/')}/',
  ),
);

_ProofAction? _parseAction(List<String> arguments) {
  const prefix = '--p5e-action=';
  final value = arguments
      .where((argument) => argument.startsWith(prefix))
      .map((argument) => argument.substring(prefix.length))
      .firstOrNull;

  return switch (value) {
    'bootstrap' => _ProofAction.bootstrap,
    'resume' => _ProofAction.resume,
    'status' => _ProofAction.status,
    'stop' => _ProofAction.stop,
    'reset' => _ProofAction.reset,
    'diagnose' => _ProofAction.diagnose,
    _ => null,
  };
}

_ProofAction? _parseEnvironmentAction(String? value) => switch (value) {
  'bootstrap' => _ProofAction.bootstrap,
  'resume' => _ProofAction.resume,
  'status' => _ProofAction.status,
  'stop' => _ProofAction.stop,
  'reset' => _ProofAction.reset,
  'diagnose' => _ProofAction.diagnose,
  _ => null,
};

Future<int> _runBootstrap(
  PrivateNetworkRuntime runtime,
  Directory directory,
  _ProofRecorder recorder,
  Future<FamilyEnrollmentResult> Function(String setupCode)? enroll,
) async {
  final codeFile = File('${directory.path}/setup-code.txt');
  if (!await codeFile.exists()) {
    return 1;
  }

  final contents = await codeFile.readAsString();
  await codeFile.delete();
  final setupCode = contents.trim();
  if (setupCode.isEmpty) {
    return 1;
  }

  if (enroll != null) {
    final enrollment = await enroll(setupCode);
    return await _runDirectAction(
      runtime,
      recorder,
      _ProofAction.bootstrap,
      () => runtime.bootstrap(PrivateNetworkBootstrap.fromEnrollment(enrollment)),
    );
  }

  final enrollmentClient = FamilyEnrollmentClient();
  try {
    final enrollment = await enrollmentClient.enroll(setupCode);
    return await _runDirectAction(
      runtime,
      recorder,
      _ProofAction.bootstrap,
      () => runtime.bootstrap(PrivateNetworkBootstrap.fromEnrollment(enrollment)),
    );
  } finally {
    enrollmentClient.close();
  }
}

Future<int> _runDirectAction(
  PrivateNetworkRuntime runtime,
  _ProofRecorder recorder,
  _ProofAction action,
  Future<PrivateNetworkStatus> Function() operation,
) async {
  final firstEvent = Completer<void>();
  final directEvent = Completer<PrivateNetworkStatus>();
  Object? streamError;
  late final StreamSubscription<PrivateNetworkStatus> subscription;
  subscription = runtime.statuses.listen(
    (status) {
      unawaited(recorder.record(action, 'event', status));
      if (!firstEvent.isCompleted) {
        firstEvent.complete();
      }
      if (_isExpectedDirect(status) && !directEvent.isCompleted) {
        directEvent.complete(status);
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      streamError ??= error;
      if (!firstEvent.isCompleted) {
        firstEvent.completeError(error, stackTrace);
      }
      if (!directEvent.isCompleted) {
        directEvent.completeError(error, stackTrace);
      }
    },
  );

  try {
    await firstEvent.future.timeout(const Duration(seconds: 20));
    final operationStatus = await operation();
    await recorder.record(action, 'method', operationStatus);
    await directEvent.future.timeout(const Duration(seconds: 20));
    if (streamError != null) {
      return 1;
    }

    final current = await runtime.status();
    await recorder.record(action, 'method', current);
    return _isExpectedDirect(current) ? 0 : 1;
  } finally {
    await subscription.cancel().timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
    await recorder.drain();
  }
}

Future<int> _runDiagnose(
  PrivateNetworkRuntime runtime,
  _ProofRecorder recorder,
  Future<Object?> Function() diagnose,
) async {
  await runtime.resume();
  final diagnostic = _ProofDiagnostic.fromPayload(await diagnose());
  await recorder.recordDiagnostic(diagnostic);
  return 0;
}

Future<Object?> _nativeDiagnose() =>
    const MethodChannel('rodplayer/private_network').invokeMethod<Object?>(
      'p5eDebugStatus',
    );

Future<int> _runStatus(
  PrivateNetworkRuntime runtime,
  _ProofRecorder recorder,
  _ProofAction action,
) async {
  final status = await runtime.status();
  await recorder.record(action, 'method', status);
  return 0;
}

Future<int> _runStop(
  PrivateNetworkRuntime runtime,
  _ProofRecorder recorder,
) async {
  await runtime.stop();
  final status = await runtime.status();
  await recorder.record(_ProofAction.stop, 'method', status);
  return status.state == PrivateNetworkState.stopped &&
          status.path == PrivateNetworkPath.none &&
          status.gatewayBaseUrl == null
      ? 0
      : 1;
}

Future<int> _runReset(
  PrivateNetworkRuntime runtime,
  _ProofRecorder recorder,
) async {
  await runtime.reset();
  final status = await runtime.status();
  await recorder.record(_ProofAction.reset, 'method', status);
  return status.state == PrivateNetworkState.stopped &&
          status.path == PrivateNetworkPath.none &&
          !status.hasPersistedIdentity &&
          status.gatewayBaseUrl == null
      ? 0
      : 1;
}

bool _isExpectedDirect(PrivateNetworkStatus status) =>
    status.state == PrivateNetworkState.starting &&
    status.path == PrivateNetworkPath.direct &&
    status.hasPersistedIdentity &&
    status.unavailableReason == PrivateNetworkUnavailableReason.none &&
    status.gatewayBaseUrl == null &&
    !status.canProxy;

void _printFailure(String value) => stderr.writeln('P5E proof failed: $value');

class _ProofRecorder {
  _ProofRecorder(this._file);

  final File _file;
  Future<void> _pending = Future<void>.value();
  Object? _writeError;

  Future<void> record(
    _ProofAction action,
    String source,
    PrivateNetworkStatus status,
  ) {
    final write = _pending.then<void>(
      (_) async {
        await _file.writeAsString(
          '${jsonEncode(<String, Object?>{
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'action': action.name,
            'source': source,
            'state': status.state.name,
            'path': status.path.name,
            'hasPersistedIdentity': status.hasPersistedIdentity,
            'reason': status.unavailableReason.name,
            'hasGateway': status.gatewayBaseUrl != null,
            'canProxy': status.canProxy,
          })}\n',
          mode: FileMode.append,
          flush: true,
        );
      },
    );
    _pending = write.catchError((Object error) {
      _writeError ??= error;
    });
    return write;
  }

  Future<void> drain() async {
    await _pending;
    if (_writeError != null) {
      throw _ProofWriteException();
    }
  }

  Future<void> recordDiagnostic(_ProofDiagnostic diagnostic) => _file.writeAsString(
    '${jsonEncode(diagnostic.payload)}\n',
    mode: FileMode.append,
    flush: true,
  );
}

class _ProofDiagnostic {
  const _ProofDiagnostic({
    required this.backendState,
    required this.totalPeerCount,
    required this.homePeerMatchCount,
    required this.homePeerOnline,
    required this.homePeerHasCurAddr,
    required this.homePeerHasPeerRelay,
    required this.persistedIdentity,
  });

  final String backendState;
  final int totalPeerCount;
  final int homePeerMatchCount;
  final bool? homePeerOnline;
  final bool? homePeerHasCurAddr;
  final bool? homePeerHasPeerRelay;
  final bool persistedIdentity;

  static const fields = <String>{
    'backendState',
    'totalPeerCount',
    'homePeerMatchCount',
    'homePeerOnline',
    'homePeerHasCurAddr',
    'homePeerHasPeerRelay',
    'persistedIdentity',
  };

  factory _ProofDiagnostic.fromPayload(Object? payload) {
    if (payload is! Map) {
      throw const FormatException();
    }
    final values = Map<String, Object?>.from(payload);
    if (values.length != fields.length || !values.keys.every(fields.contains)) {
      throw const FormatException();
    }
    final backendState = values['backendState'];
    final totalPeerCount = values['totalPeerCount'];
    final homePeerMatchCount = values['homePeerMatchCount'];
    final persistedIdentity = values['persistedIdentity'];
    if (backendState is! String ||
        totalPeerCount is! int ||
        totalPeerCount < 0 ||
        homePeerMatchCount is! int ||
        homePeerMatchCount < 0 ||
        persistedIdentity is! bool) {
      throw const FormatException();
    }
    return _ProofDiagnostic(
      backendState: backendState,
      totalPeerCount: totalPeerCount,
      homePeerMatchCount: homePeerMatchCount,
      homePeerOnline: _nullableBool(values['homePeerOnline']),
      homePeerHasCurAddr: _nullableBool(values['homePeerHasCurAddr']),
      homePeerHasPeerRelay: _nullableBool(values['homePeerHasPeerRelay']),
      persistedIdentity: persistedIdentity,
    );
  }

  Map<String, Object?> get payload => <String, Object?>{
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'action': _ProofAction.diagnose.name,
    'backendState': backendState,
    'totalPeerCount': totalPeerCount,
    'homePeerMatchCount': homePeerMatchCount,
    'homePeerOnline': homePeerOnline,
    'homePeerHasCurAddr': homePeerHasCurAddr,
    'homePeerHasPeerRelay': homePeerHasPeerRelay,
    'persistedIdentity': persistedIdentity,
  };
}

bool? _nullableBool(Object? value) {
  if (value == null || value is bool) {
    return value as bool?;
  }
  throw const FormatException();
}

enum _ProofAction { bootstrap, resume, status, stop, reset, diagnose }

class _ProofWriteException implements Exception {}
