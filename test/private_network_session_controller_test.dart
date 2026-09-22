import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/private_network_session_controller.dart';

void main() {
  group('PrivateNetworkSessionController', () {
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
      final controller = PrivateNetworkSessionController(runtime);

      await controller.start();

      expect(runtime.resumeCalls, 1);
      expect(runtime.bootstrapCalls, 0);
      expect(controller.status.value?.state, PrivateNetworkState.starting);
      await controller.close();
    });

    test('does not resume or bootstrap without persisted identity', () async {
      final runtime = _FakeRuntime(
        statusValue: _status(
          state: PrivateNetworkState.stopped,
          hasIdentity: false,
        ),
      );
      final controller = PrivateNetworkSessionController(runtime);

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
        final controller = PrivateNetworkSessionController(runtime);

        await controller.start();

        expect(runtime.bootstrapCalls, 0);
        await controller.close();
      }
    });

    test('retains starting direct status without making it proxyable', () async {
      final direct = _status(
        state: PrivateNetworkState.starting,
        path: PrivateNetworkPath.direct,
        hasIdentity: true,
      );
      final runtime = _FakeRuntime(statusValue: direct);
      final controller = PrivateNetworkSessionController(runtime);

      await controller.start();

      expect(controller.status.value, same(direct));
      expect(controller.status.value?.canProxy, isFalse);
      await controller.close();
    });

    test('event status wins over a stale startup result', () async {
      final status = Completer<PrivateNetworkStatus>();
      final runtime = _FakeRuntime(statusFuture: status.future);
      final controller = PrivateNetworkSessionController(runtime);

      final start = controller.start();
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
      expect(runtime.resumeCalls, 0);
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
      final controller = PrivateNetworkSessionController(runtime);

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
    this.statusError,
    this.resumeValue,
    this.resumeError,
    void Function()? onCancel,
  }) : events = StreamController<PrivateNetworkStatus>.broadcast(
          onCancel: onCancel,
          sync: true,
        );

  final bool hostAvailable;
  final PrivateNetworkStatus? statusValue;
  final Future<PrivateNetworkStatus>? statusFuture;
  final Object? statusError;
  final PrivateNetworkStatus? resumeValue;
  final Object? resumeError;
  final StreamController<PrivateNetworkStatus> events;
  int resumeCalls = 0;
  int bootstrapCalls = 0;

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
  Future<void> reset() async {}

  @override
  Future<PrivateNetworkStatus> resume() async {
    resumeCalls++;
    if (resumeError != null) throw resumeError!;
    return resumeValue ?? statusValue!;
  }

  @override
  Future<PrivateNetworkStatus> status() {
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
