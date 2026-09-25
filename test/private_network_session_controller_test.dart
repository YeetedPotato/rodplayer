import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/private_network_session_controller.dart';
import 'package:rodplayer/core/network/private_service_endpoint_resolver.dart';

import 'test_support.dart';

final _claim = PrivateNetworkIdentityClaim(
  profileId: 'profile-one',
  controlUrl: Uri.parse('https://control.example.test'),
  homeIpv4: '100.64.0.1',
  homePort: 3000,
);

void main() {
  group('PrivateNetworkSessionController', () {
    test('multiple waiters share resume and wait for verified ready', () async {
      final pending = Completer<PrivateNetworkStatus>();
      final resumed = Completer<void>();
      final runtime = _FakeRuntime(
        statusValue:
            _status(state: PrivateNetworkState.stopped, hasIdentity: true),
        resumeFuture: pending.future,
        resumeStarted: resumed,
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);
      final first = controller.waitUntilReady();
      final second = controller.waitUntilReady();
      await resumed.future;
      expect(runtime.resumeCalls, 1);
      pending.complete(
          _status(state: PrivateNetworkState.starting, hasIdentity: true));
      await controller.start();
      var completed = false;
      first.then((_) => completed = true);
      await Future<void>.value();
      expect(completed, isFalse);
      runtime.events.add(PrivateNetworkStatus.fromPayload({
        'state': 'ready',
        'path': 'direct',
        'hasPersistedIdentity': true,
        'reason': 'none',
        'gatewayUrl': 'http://127.0.0.1:45000',
      }));
      await Future.wait([first, second]);
      expect(completed, isTrue);
      await controller.close();
    });

    test('terminal unavailable and native failures settle readiness', () async {
      final cases = <_FakeRuntime>[
        _FakeRuntime(hostAvailable: false),
        _FakeRuntime(statusError: StateError('status')),
        _FakeRuntime(
            statusValue:
                _status(state: PrivateNetworkState.stopped, hasIdentity: true),
            resumeError: StateError('resume')),
        _FakeRuntime(
            statusValue: _status(
                state: PrivateNetworkState.stopped, hasIdentity: false)),
        _FakeRuntime(
            statusValue:
                _status(state: PrivateNetworkState.stopped, hasIdentity: true),
            resumeValue: _status(
                state: PrivateNetworkState.unavailable,
                hasIdentity: true,
                reason: PrivateNetworkUnavailableReason.unknown)),
        _FakeRuntime(
            statusValue:
                _status(state: PrivateNetworkState.stopped, hasIdentity: true),
            resumeValue:
                _status(state: PrivateNetworkState.stopped, hasIdentity: true)),
      ];
      for (final runtime in cases) {
        final controller = PrivateNetworkSessionController(runtime, _claim);
        await expectLater(controller.waitUntilReady(),
            throwsA(isA<PrivateNetworkException>()));
        await controller.close();
      }
    });

    test('terminal resume status cannot be resurrected by a late ready event',
        () async {
      final terminalStatuses = <PrivateNetworkStatus>[
        _status(
          state: PrivateNetworkState.unavailable,
          reason: PrivateNetworkUnavailableReason.unknown,
          hasIdentity: true,
        ),
        _status(state: PrivateNetworkState.stopped, hasIdentity: true),
      ];

      for (final terminal in terminalStatuses) {
        final runtime = _FakeRuntime(
          statusValue:
              _status(state: PrivateNetworkState.stopped, hasIdentity: true),
          resumeValue: terminal,
        );
        final controller = PrivateNetworkSessionController(runtime, _claim);
        final resolver = PrivateServiceEndpointResolver(
          canonicalBaseUrl: 'https://private.example',
          status: controller.status,
        );
        var sends = 0;
        final transport = PrivateServiceHttpClient(
          MockClient((_) async {
            sends++;
            return http.Response('ok', 200);
          }),
          resolver,
          waitUntilReady: controller.waitUntilReady,
        );
        final serviceUrl = Uri.parse('https://private.example/Items');

        await expectLater(
          controller.waitUntilReady(),
          throwsA(isA<PrivateNetworkException>()),
        );
        expect(runtime.resumeCalls, 1);
        expect(runtime.bootstrapCalls, 0);
        expect(controller.status.value?.canProxy, isFalse);
        expect(controller.status.value?.gatewayBaseUrl, isNull);
        expect(
          () => resolver.resolve(serviceUrl),
          throwsA(isA<PrivateNetworkException>()),
        );
        await expectLater(
          transport.get(serviceUrl),
          throwsA(isA<PrivateNetworkException>()),
        );
        expect(sends, 0);

        runtime.events.add(_ready(45000));

        await expectLater(
          controller.waitUntilReady(),
          throwsA(isA<PrivateNetworkException>()),
        );
        expect(controller.status.value?.canProxy, isFalse);
        expect(controller.status.value?.gatewayBaseUrl, isNull);
        expect(controller.status.value?.state, terminal.state);
        expect(
          () => resolver.resolve(serviceUrl),
          throwsA(isA<PrivateNetworkException>()),
        );
        await expectLater(
          transport.get(serviceUrl),
          throwsA(isA<PrivateNetworkException>()),
        );
        expect(sends, 0);

        transport.close();
        await controller.close();
      }
    });

    test('close settles a waiter while native resume is still pending',
        () async {
      final pending = Completer<PrivateNetworkStatus>();
      final resumed = Completer<void>();
      final runtime = _FakeRuntime(
        statusValue:
            _status(state: PrivateNetworkState.stopped, hasIdentity: true),
        resumeFuture: pending.future,
        resumeStarted: resumed,
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);
      final waiting = expectLater(
          controller.waitUntilReady(),
          throwsA(isA<PrivateNetworkException>().having(
              (e) => e.failure, 'failure', PrivateNetworkFailure.closed)));
      await resumed.future;
      await controller.close();
      await waiting;
      pending.complete(
          _status(state: PrivateNetworkState.starting, hasIdentity: true));
    });

    test('closing during a routed HTTP wait emits no request', () async {
      final pending = Completer<PrivateNetworkStatus>();
      final resumed = Completer<void>();
      final runtime = _FakeRuntime(
        statusValue:
            _status(state: PrivateNetworkState.stopped, hasIdentity: true),
        resumeFuture: pending.future,
        resumeStarted: resumed,
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);
      var sends = 0;
      final transport = PrivateServiceHttpClient(
        MockClient((_) async {
          sends++;
          return http.Response('{}', 200);
        }),
        PrivateServiceEndpointResolver(
            canonicalBaseUrl: 'https://private.example',
            status: controller.status),
        waitUntilReady: controller.waitUntilReady,
      );
      final request = expectLater(
          transport.get(Uri.parse('https://private.example/Items')),
          throwsA(isA<PrivateNetworkException>().having(
              (e) => e.failure, 'failure', PrivateNetworkFailure.closed)));
      await resumed.future;
      await controller.close();
      await request;
      pending.complete(PrivateNetworkStatus.fromPayload({
        'state': 'ready',
        'path': 'direct',
        'hasPersistedIdentity': true,
        'reason': 'none',
        'gatewayUrl': 'http://127.0.0.1:45000',
      }));
      expect(sends, 0);
      transport.close();
    });

    test('status stream loss invalidates a previously ready gateway', () async {
      final ready = PrivateNetworkStatus.fromPayload({
        'state': 'ready',
        'path': 'direct',
        'hasPersistedIdentity': true,
        'reason': 'none',
        'gatewayUrl': 'http://127.0.0.1:45000',
      });
      final runtime = _FakeRuntime(statusValue: ready, resumeValue: ready);
      final controller = PrivateNetworkSessionController(runtime, _claim);
      await controller.waitUntilReady();
      expect(controller.status.value?.canProxy, isTrue);
      await runtime.events.close();
      expect(controller.status.value?.canProxy, isFalse);
      expect(controller.status.value?.unavailableReason,
          PrivateNetworkUnavailableReason.transportFailure);
      await controller.close();
    });

    for (final reason in <PrivateNetworkUnavailableReason>[
      PrivateNetworkUnavailableReason.directPathUnavailable,
      PrivateNetworkUnavailableReason.transportFailure,
    ]) {
      test('$reason remains pending until monitored ready', () async {
        final transient = _unavailable(reason);
        final runtime = _FakeRuntime(
          statusValue: reason ==
                  PrivateNetworkUnavailableReason.directPathUnavailable
              ? transient
              : _status(state: PrivateNetworkState.stopped, hasIdentity: true),
          resumeValue: transient,
        );
        final controller = PrivateNetworkSessionController(runtime, _claim);
        final requests = <http.BaseRequest>[];
        final transport = PrivateServiceHttpClient(
          MockClient((request) async {
            requests.add(request);
            return http.Response('ok', 200);
          }),
          PrivateServiceEndpointResolver(
              canonicalBaseUrl: 'https://private.example:3000',
              status: controller.status),
          waitUntilReady: controller.waitUntilReady,
        );
        await controller.start();
        final response =
            transport.get(Uri.parse('https://private.example:3000/Items'));
        expect(runtime.resumeCalls, 1);
        expect(controller.status.value, same(transient));
        var completed = false;
        response.then((_) => completed = true);
        await Future<void>.value();
        expect(completed, isFalse);
        expect(requests, isEmpty);

        runtime.events.add(_ready(45000));
        expect((await response).body, 'ok');
        expect(requests.single.url.host, '127.0.0.1');
        expect(requests.single.url.port, 45000);
        expect(requests.single.headers['host'], 'private.example:3000');
        transport.close();
        await controller.close();
      });
    }

    test('two Jellyfin clients share recoverable readiness and one resume',
        () async {
      final runtime = _FakeRuntime(
        statusValue:
            _status(state: PrivateNetworkState.stopped, hasIdentity: true),
        resumeValue:
            _unavailable(PrivateNetworkUnavailableReason.directPathUnavailable),
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);
      var sends = 0;
      JellyfinApiClient client() {
        final result = JellyfinApiClient(
          baseUrl: 'https://private.example',
          identity: testIdentity,
          client: MockClient((request) async {
            sends++;
            expect(request.url.host, '127.0.0.1');
            return http.Response('[{"Id":"user","Name":"User"}]', 200);
          }),
        );
        result.usePrivateTransport(controller.status,
            waitUntilReady: controller.waitUntilReady);
        return result;
      }

      await controller.start();
      final first = client();
      final second = client();
      final firstUsers = first.getPublicUsers();
      final secondUsers = second.getPublicUsers();
      expect(runtime.resumeCalls, 1);
      expect(sends, 0);
      runtime.events.add(_ready(45000));
      expect((await firstUsers).single.id, 'user');
      expect((await secondUsers).single.id, 'user');
      expect(sends, 2);
      first.close();
      second.close();
      await controller.close();
    });

    test('no identity and unavailable host settle without an HTTP send',
        () async {
      for (final runtime in <_FakeRuntime>[
        _FakeRuntime(
            statusValue: _status(
          state: PrivateNetworkState.unavailable,
          reason: PrivateNetworkUnavailableReason.noIdentity,
          hasIdentity: false,
        )),
        _FakeRuntime(
            statusValue:
                _unavailable(PrivateNetworkUnavailableReason.hostUnavailable)),
        _FakeRuntime(hostAvailable: false),
      ]) {
        final controller = PrivateNetworkSessionController(runtime, _claim);
        var sends = 0;
        final transport = PrivateServiceHttpClient(
          MockClient((_) async {
            sends++;
            return http.Response('ok', 200);
          }),
          PrivateServiceEndpointResolver(
              canonicalBaseUrl: 'https://private.example',
              status: controller.status),
          waitUntilReady: controller.waitUntilReady,
        );
        await expectLater(
            transport.get(Uri.parse('https://private.example/Items')),
            throwsA(isA<PrivateNetworkException>()));
        expect(runtime.resumeCalls, 0);
        expect(sends, 0);
        transport.close();
        await controller.close();
      }
    });

    test('ready, unavailable, then rotated ready uses live gateway', () async {
      final runtime =
          _FakeRuntime(statusValue: _ready(45000), resumeValue: _ready(45000));
      final controller = PrivateNetworkSessionController(runtime, _claim);
      final ports = <int>[];
      final transport = PrivateServiceHttpClient(
        MockClient((request) async {
          ports.add(request.url.port);
          return http.Response('ok', 200);
        }),
        PrivateServiceEndpointResolver(
            canonicalBaseUrl: 'https://private.example',
            status: controller.status),
        waitUntilReady: controller.waitUntilReady,
      );
      final url = Uri.parse('https://private.example/Items');
      await controller.waitUntilReady();
      await transport.get(url);
      runtime.events.add(
          _unavailable(PrivateNetworkUnavailableReason.directPathUnavailable));
      await expectLater(
          transport.get(url), throwsA(isA<PrivateNetworkException>()));
      runtime.events.add(_ready(46000));
      await transport.get(url);
      expect(ports, [45000, 46000]);
      transport.close();
      await controller.close();
    });

    test('close during recoverable unavailability cancels the HTTP waiter',
        () async {
      final runtime = _FakeRuntime(
        statusValue:
            _status(state: PrivateNetworkState.stopped, hasIdentity: true),
        resumeValue:
            _unavailable(PrivateNetworkUnavailableReason.directPathUnavailable),
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);
      var sends = 0;
      final transport = PrivateServiceHttpClient(
        MockClient((_) async {
          sends++;
          return http.Response('ok', 200);
        }),
        PrivateServiceEndpointResolver(
            canonicalBaseUrl: 'https://private.example',
            status: controller.status),
        waitUntilReady: controller.waitUntilReady,
      );
      await controller.start();
      final waiting = expectLater(
          transport.get(Uri.parse('https://private.example/Items')),
          throwsA(isA<PrivateNetworkException>().having(
              (e) => e.failure, 'failure', PrivateNetworkFailure.closed)));
      expect(controller.status.value?.unavailableReason,
          PrivateNetworkUnavailableReason.directPathUnavailable);
      expect(sends, 0);
      await controller.close();
      await waiting;
      runtime.events.add(_ready(45000));
      expect(sends, 0);
      transport.close();
    });

    test('status channel error cannot reauthorize a later event', () async {
      final ready = PrivateNetworkStatus.fromPayload({
        'state': 'ready',
        'path': 'direct',
        'hasPersistedIdentity': true,
        'reason': 'none',
        'gatewayUrl': 'http://127.0.0.1:45000',
      });
      final runtime = _FakeRuntime(statusValue: ready, resumeValue: ready);
      final controller = PrivateNetworkSessionController(runtime, _claim);
      await controller.waitUntilReady();
      runtime.events.addError(StateError('channel'));
      runtime.events.add(ready);
      expect(controller.status.value?.canProxy, isFalse);
      await controller.close();
    });

    test('status channel failure during resume cannot publish late ready',
        () async {
      final pending = Completer<PrivateNetworkStatus>();
      final resumed = Completer<void>();
      final runtime = _FakeRuntime(
        statusValue:
            _status(state: PrivateNetworkState.stopped, hasIdentity: true),
        resumeFuture: pending.future,
        resumeStarted: resumed,
      );
      final controller = PrivateNetworkSessionController(runtime, _claim);
      final start = controller.start();
      await resumed.future;
      runtime.events.addError(StateError('channel'));
      pending.complete(_ready(45000));
      await start;
      runtime.events.add(_ready(45000));
      expect(controller.status.value?.canProxy, isFalse);
      await expectLater(
          controller.waitUntilReady(), throwsA(isA<PrivateNetworkException>()));
      await controller.close();
    });

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

PrivateNetworkStatus _ready(int port) => PrivateNetworkStatus.fromPayload({
      'state': 'ready',
      'path': 'direct',
      'hasPersistedIdentity': true,
      'reason': 'none',
      'gatewayUrl': 'http://127.0.0.1:$port',
    });

PrivateNetworkStatus _unavailable(PrivateNetworkUnavailableReason reason) =>
    _status(
        state: PrivateNetworkState.unavailable,
        reason: reason,
        hasIdentity: true);

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
