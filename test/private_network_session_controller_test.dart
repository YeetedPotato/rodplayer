import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/private_network_session_controller.dart';

final _claim = PrivateNetworkIdentityClaim(
  profileId: 'profile-one',
  controlUrl: Uri.parse('https://control.example.test'),
  homeIpv4: '100.64.0.1',
  homePort: 3000,
);

void main() {
  group('PrivateNetworkSessionController', () {
    test('cached ready gateway is withheld until profile ownership verifies',
        () async {
      final pending = Completer<PrivateNetworkStatus>();
      final resumeStarted = Completer<void>();
      final ready = PrivateNetworkStatus.fromPayload({
        'state': 'ready',
        'path': 'direct',
        'hasPersistedIdentity': true,
        'reason': 'none',
        'gatewayUrl': 'http://127.0.0.1:45000',
      });
      final runtime = _FakeRuntime(
          statusValue: ready,
          resumeFuture: pending.future,
          resumeStarted: resumeStarted);
      final controller = PrivateNetworkSessionController(runtime, _claim);
      final start = controller.start();
      await resumeStarted.future;
      expect(controller.status.value, isNull);
      expect(runtime.resumeCalls, 1);
      pending.complete(ready);
      await start;
      expect(controller.status.value?.canProxy, isTrue);
      await controller.close();
    });

    test('no-identity response cannot authorize a later unrelated gateway',
        () async {
      final stopped =
          _status(state: PrivateNetworkState.stopped, hasIdentity: true);
      final noIdentity = _status(
          state: PrivateNetworkState.unavailable,
          reason: PrivateNetworkUnavailableReason.noIdentity,
          hasIdentity: false);
      final runtime =
          _FakeRuntime(statusValue: stopped, resumeValue: noIdentity);
      final controller = PrivateNetworkSessionController(runtime, _claim);
      await controller.start();
      expect(controller.status.value, same(noIdentity));
      runtime.events.add(PrivateNetworkStatus.fromPayload({
        'state': 'ready',
        'path': 'direct',
        'hasPersistedIdentity': true,
        'reason': 'none',
        'gatewayUrl': 'http://127.0.0.1:45000',
      }));
      expect(controller.status.value?.canProxy, isFalse);
      await controller.close();
    });

    test('resumes one persisted stopped identity once', () async {
      final runtime = _FakeRuntime(
        statusValue: _status(
          state: PrivateNetworkState.stopped,
          hasIdentity: true,
        ),
        resumeValue: _status(
          state: PrivateNetworkState.starting,
          hasIdentity: true,
        ),
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);

      await controller.start();
      expect(controller.status.value?.state, PrivateNetworkState.starting);
      runtime.events.add(_status(
        state: PrivateNetworkState.stopped,
        hasIdentity: true,
      ));
      await controller.start();

      expect(runtime.resumeCalls, 1);
      expect(runtime.bootstrapCalls, 0);
      await controller.close();
    });

    test('does not resume or bootstrap without persisted identity', () async {
      final runtime = _FakeRuntime(
        statusValue: _status(
          state: PrivateNetworkState.stopped,
          hasIdentity: false,
        ),
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);

      await controller.start();

      expect(runtime.resumeCalls, 0);
      expect(runtime.bootstrapCalls, 0);
      expect(controller.status.value?.hasPersistedIdentity, isFalse);
      await controller.close();
    });

    test('host, status, and resume failures remain locally scoped', () async {
      for (final runtime in <_FakeRuntime>[
        _FakeRuntime(hostAvailable: false),
        _FakeRuntime(statusError: StateError('status')),
        _FakeRuntime(
          statusValue: _status(
            state: PrivateNetworkState.stopped,
            hasIdentity: true,
          ),
          resumeError: StateError('resume'),
        ),
      ]) {
        final controller = PrivateNetworkSessionController(runtime, _claim);

        await controller.start();

        expect(runtime.bootstrapCalls, 0);
        await controller.close();
      }
    });

    test('retains starting direct status without making it proxyable',
        () async {
      final direct = _status(
        state: PrivateNetworkState.starting,
        path: PrivateNetworkPath.direct,
        hasIdentity: true,
      );
      final runtime = _FakeRuntime(statusValue: direct);
      final controller = PrivateNetworkSessionController(runtime, _claim);

      await controller.start();

      expect(controller.status.value, same(direct));
      expect(controller.status.value?.canProxy, isFalse);
      await controller.close();
    });

    test('event status wins over a stale startup result', () async {
      final status = Completer<PrivateNetworkStatus>();
      final statusStarted = Completer<void>();
      final runtime = _FakeRuntime(
        statusFuture: status.future,
        statusStarted: statusStarted,
        resumeValue: _status(
          state: PrivateNetworkState.unavailable,
          reason: PrivateNetworkUnavailableReason.directPathUnavailable,
          hasIdentity: true,
        ),
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);

      final start = controller.start();
      await statusStarted.future;
      runtime.events.add(
        _status(
          state: PrivateNetworkState.unavailable,
          reason: PrivateNetworkUnavailableReason.directPathUnavailable,
          hasIdentity: true,
        ),
      );
      status.complete(
        _status(
          state: PrivateNetworkState.stopped,
          hasIdentity: true,
        ),
      );
      await start;

      expect(
        controller.status.value?.unavailableReason,
        PrivateNetworkUnavailableReason.directPathUnavailable,
      );
      expect(runtime.resumeCalls, 1);
      await controller.close();
    });

    test('cached stopped event resumes despite a stale status result',
        () async {
      final status = Completer<PrivateNetworkStatus>();
      final statusStarted = Completer<void>();
      final runtime = _FakeRuntime(
        statusFuture: status.future,
        statusStarted: statusStarted,
        resumeValue: _status(
          state: PrivateNetworkState.starting,
          hasIdentity: true,
        ),
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);

      final start = controller.start();
      await statusStarted.future;
      runtime.events.add(_status(
        state: PrivateNetworkState.stopped,
        hasIdentity: true,
      ));
      status.complete(_status(
        state: PrivateNetworkState.stopped,
        hasIdentity: false,
      ));
      await start;

      expect(runtime.resumeCalls, 1);
      expect(runtime.bootstrapCalls, 0);
      expect(runtime.resetCalls, 0);
      expect(controller.status.value?.hasPersistedIdentity, isTrue);
      expect(controller.status.value?.state, PrivateNetworkState.starting);
      await controller.close();
    });

    test('cached starting event still requires ownership verification',
        () async {
      final status = Completer<PrivateNetworkStatus>();
      final statusStarted = Completer<void>();
      final runtime = _FakeRuntime(
        statusFuture: status.future,
        statusStarted: statusStarted,
        resumeValue: _status(
          state: PrivateNetworkState.starting,
          hasIdentity: true,
        ),
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);

      final start = controller.start();
      await statusStarted.future;
      runtime.events.add(_status(
        state: PrivateNetworkState.starting,
        hasIdentity: true,
      ));
      status.complete(_status(
        state: PrivateNetworkState.stopped,
        hasIdentity: true,
      ));
      await start;

      expect(runtime.resumeCalls, 1);
      expect(controller.status.value?.state, PrivateNetworkState.starting);
      await controller.close();
    });

    test('latest of multiple events survives ownership verification', () async {
      for (final latest in <PrivateNetworkState>[
        PrivateNetworkState.stopped,
        PrivateNetworkState.starting,
      ]) {
        final status = Completer<PrivateNetworkStatus>();
        final statusStarted = Completer<void>();
        final runtime = _FakeRuntime(
          statusFuture: status.future,
          statusStarted: statusStarted,
          resumeValue: _status(
            state: PrivateNetworkState.starting,
            hasIdentity: true,
          ),
        );
        final controller = PrivateNetworkSessionController(runtime, _claim);

        final start = controller.start();
        await statusStarted.future;
        runtime.events.add(_status(
          state: PrivateNetworkState.stopped,
          hasIdentity: true,
        ));
        runtime.events.add(_status(
          state: latest,
          hasIdentity: true,
        ));
        status.complete(_status(
          state: PrivateNetworkState.stopped,
          hasIdentity: false,
        ));
        await start;

        expect(runtime.resumeCalls, 1);
        expect(controller.status.value?.hasPersistedIdentity, isTrue);
        expect(controller.status.value?.state, PrivateNetworkState.starting);
        await controller.close();
      }
    });

    test('close during status or resume discards pending results', () async {
      final pendingStatus = Completer<PrivateNetworkStatus>();
      final statusStarted = Completer<void>();
      final statusRuntime = _FakeRuntime(
        statusFuture: pendingStatus.future,
        statusStarted: statusStarted,
      );
      final statusController =
          PrivateNetworkSessionController(statusRuntime, _claim);
      final statusStart = statusController.start();
      await statusStarted.future;
      await statusController.close();
      pendingStatus.complete(_status(
        state: PrivateNetworkState.stopped,
        hasIdentity: true,
      ));
      await statusStart;
      expect(statusRuntime.resumeCalls, 0);

      final pendingResume = Completer<PrivateNetworkStatus>();
      final resumeStarted = Completer<void>();
      final resumeRuntime = _FakeRuntime(
        statusValue: _status(
          state: PrivateNetworkState.stopped,
          hasIdentity: true,
        ),
        resumeFuture: pendingResume.future,
        resumeStarted: resumeStarted,
      );
      final resumeController =
          PrivateNetworkSessionController(resumeRuntime, _claim);
      final resumeStart = resumeController.start();
      await resumeStarted.future;
      await resumeController.close();
      pendingResume.complete(_status(
        state: PrivateNetworkState.starting,
        hasIdentity: true,
      ));
      await resumeStart;
      expect(resumeRuntime.resumeCalls, 1);
    });

    test('event status wins over a stale resume result', () async {
      final resume = Completer<PrivateNetworkStatus>();
      final resumeStarted = Completer<void>();
      final runtime = _FakeRuntime(
        statusValue: _status(
          state: PrivateNetworkState.stopped,
          hasIdentity: true,
        ),
        resumeFuture: resume.future,
        resumeStarted: resumeStarted,
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);

      final start = controller.start();
      await resumeStarted.future;
      runtime.events.add(
        _status(
          state: PrivateNetworkState.unavailable,
          reason: PrivateNetworkUnavailableReason.directPathUnavailable,
          hasIdentity: true,
        ),
      );
      resume.complete(
        _status(
          state: PrivateNetworkState.starting,
          hasIdentity: true,
        ),
      );
      await start;

      expect(runtime.resumeCalls, 1);
      expect(runtime.bootstrapCalls, 0);
      expect(
        controller.status.value?.unavailableReason,
        PrivateNetworkUnavailableReason.directPathUnavailable,
      );
      await controller.close();
    });

    test('close cancels the runtime status subscription', () async {
      var cancelled = false;
      final runtime = _FakeRuntime(
        statusValue: _status(
          state: PrivateNetworkState.stopped,
          hasIdentity: false,
        ),
        onCancel: () => cancelled = true,
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);

      await controller.start();
      await controller.close();

      expect(cancelled, isTrue);
    });
  });
}

PrivateNetworkStatus _status({
  required PrivateNetworkState state,
  PrivateNetworkPath path = PrivateNetworkPath.none,
  PrivateNetworkUnavailableReason reason = PrivateNetworkUnavailableReason.none,
  required bool hasIdentity,
}) =>
    PrivateNetworkStatus(
      state: state,
      path: path,
      hasPersistedIdentity: hasIdentity,
      unavailableReason: reason,
    );

class _FakeRuntime implements PrivateNetworkRuntime {
  _FakeRuntime({
    this.hostAvailable = true,
    this.statusValue,
    this.statusFuture,
    this.statusStarted,
    this.statusError,
    this.resumeValue,
    this.resumeFuture,
    this.resumeStarted,
    this.resumeError,
    void Function()? onCancel,
  }) : events = StreamController<PrivateNetworkStatus>.broadcast(
          onCancel: onCancel,
          sync: true,
        );

  final bool hostAvailable;
  final PrivateNetworkStatus? statusValue;
  final Future<PrivateNetworkStatus>? statusFuture;
  final Completer<void>? statusStarted;
  final Object? statusError;
  final PrivateNetworkStatus? resumeValue;
  final Future<PrivateNetworkStatus>? resumeFuture;
  final Completer<void>? resumeStarted;
  final Object? resumeError;
  final StreamController<PrivateNetworkStatus> events;
  int resumeCalls = 0;
  int bootstrapCalls = 0;
  int resetCalls = 0;

  @override
  Future<PrivateNetworkStatus> bootstrap(
    PrivateNetworkBootstrap bootstrap,
  ) async {
    bootstrapCalls++;
    throw UnsupportedError('bootstrap is not used at startup');
  }

  @override
  Future<bool> confirmHostAvailable() async => hostAvailable;

  @override
  Future<void> reset() async => resetCalls++;

  @override
  Future<PrivateNetworkStatus> resume(PrivateNetworkIdentityClaim claim) async {
    expect(claim.profileId, _claim.profileId);
    resumeCalls++;
    resumeStarted?.complete();
    if (resumeError != null) throw resumeError!;
    return resumeFuture != null
        ? await resumeFuture!
        : resumeValue ?? statusValue!;
  }

  @override
  Future<PrivateNetworkStatus> status() {
    statusStarted?.complete();
    if (statusError != null) {
      return Future<PrivateNetworkStatus>.error(statusError!);
    }
    return statusFuture ?? Future<PrivateNetworkStatus>.value(statusValue!);
  }

  @override
  Stream<PrivateNetworkStatus> get statuses => events.stream;

  @override
  Future<void> stop() async {}
}
