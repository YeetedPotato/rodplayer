import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/events/jellyfin_server_events.dart';

void main() {
  group('JellyfinServerEventSessionController', () {
    test(
      'normalizes known events and rejects malformed, foreign, or unknown',
      () {
        expect(
          normalizeJellyfinEventFrame(
            '{"MessageType":"LibraryChanged","Data":{"ItemsUpdated":["x"]}}',
            authenticatedUserId: 'user-a',
          )?.kind,
          JellyfinServerEventKind.libraryInvalidated,
        );
        expect(
          normalizeJellyfinEventFrame(
            utf8.encode(
              '{"MessageType":"UserDataChanged","Data":{"UserId":"user-a"}}',
            ),
            authenticatedUserId: 'user-a',
          )?.kind,
          JellyfinServerEventKind.userDataInvalidated,
        );
        expect(
          normalizeJellyfinEventFrame(
            '{"MessageType":"UserDataChanged","Data":{"UserId":"user-b"}}',
            authenticatedUserId: 'user-a',
          ),
          isNull,
        );
        expect(
          normalizeJellyfinEventFrame(
            '{"MessageType":"ForceKeepAlive","Data":20}',
            authenticatedUserId: 'user-a',
          ),
          isNull,
        );
        expect(
          normalizeJellyfinEventFrame('{broken', authenticatedUserId: 'user-a'),
          isNull,
        );
        expect(
          normalizeJellyfinEventFrame(
            '{"MessageType":"LibraryChanged","Data":null}',
            authenticatedUserId: 'user-a',
          ),
          isNull,
        );
        expect(
          normalizeJellyfinEventFrame(
            '{"MessageType":"UserDataChanged","Data":{"UserId":3}}',
            authenticatedUserId: 'user-a',
          ),
          isNull,
        );
        expect(
          normalizeJellyfinEventFrame(
            '{"MessageType":"UserDataChanged","Data":{}}',
            authenticatedUserId: ' ',
          ),
          isNull,
        );
      },
    );

    test(
      'reconnects after disconnect and cancels late reconnect on close',
      () async {
        final first = _WireConnection();
        final second = _WireConnection();
        final connector = _Connector(<Object>[
          Future<ServerEventWireConnection>.value(first),
          Future<ServerEventWireConnection>.value(second),
        ]);
        final source = ReconnectingJellyfinServerEventSource(
          connector: connector,
          retryDelay: Duration.zero,
          wait: (_) async {},
        );
        await Future<void>.delayed(Duration.zero);
        expect(source.state, ServerEventConnectionState.connected);
        first.end();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(connector.calls, 2);
        expect(source.state, ServerEventConnectionState.connected);
        await source.close();
        expect(source.state, ServerEventConnectionState.closed);
        expect(second.closed, 1);
      },
    );

    test(
      'unsupported transport is truthfully represented without fallback',
      () async {
        final source = ReconnectingJellyfinServerEventSource(
          connector: _Connector(<Future<ServerEventWireConnection>>[
            Future<ServerEventWireConnection>.error(
              const ServerEventTransportUnsupported(),
            ),
          ]),
          wait: (_) async {},
        );
        await Future<void>.delayed(Duration.zero);
        expect(source.support, ServerEventsSupport.unsupported);
        expect(source.state, ServerEventConnectionState.unsupported);
        await source.close();
      },
    );

    test('close invalidates a pending connection result', () async {
      final pending = Completer<ServerEventWireConnection>();
      final source = ReconnectingJellyfinServerEventSource(
        connector: _Connector(<Future<ServerEventWireConnection>>[
          pending.future,
        ]),
        wait: (_) async {},
      );
      await source.close();
      final late = _WireConnection();
      pending.complete(late);
      await Future<void>.delayed(Duration.zero);
      expect(late.closed, 1);
      expect(source.state, ServerEventConnectionState.closed);
    });

    test('close cancels an in-flight authenticated socket handshake', () async {
      final pending = Completer<ServerEventWireConnection>();
      final connector = _Connector(<Object>[pending.future]);
      final source = ReconnectingJellyfinServerEventSource(
        connector: connector,
      );
      await Future<void>.delayed(Duration.zero);
      expect(connector.cancellations, hasLength(1));
      final cancellation = connector.cancellations.single!;

      await source.close();
      expect(cancellation.isCancelled, isTrue);

      final lateConnection = _WireConnection();
      pending.complete(lateConnection);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(lateConnection.closed, 1);
    });

    test(
      'superseded connection failure cannot overwrite a newer start',
      () async {
        final first = Completer<ServerEventWireConnection>();
        final second = Completer<ServerEventWireConnection>();
        final connector = _Connector(<Object>[first.future, second.future]);
        final source = ReconnectingJellyfinServerEventSource(
          connector: connector,
          wait: (_) async {},
        );
        source.start();
        expect(connector.calls, 2);
        first.completeError(const ServerEventTransportUnsupported());
        await _flushAsync();
        expect(source.state, ServerEventConnectionState.connecting);
        final connection = _WireConnection();
        second.complete(connection);
        await _flushAsync();
        expect(source.state, ServerEventConnectionState.connected);
        await source.close();
      },
    );

    test(
      'simultaneous socket error and completion schedules one reconnect',
      () async {
        final first = _WireConnection();
        final delays = <Duration>[];
        final connector = _Connector(<Object>[first, _WireConnection()]);
        final source = ReconnectingJellyfinServerEventSource(
          connector: connector,
          wait: (delay) async => delays.add(delay),
          jitter: () => 0.5,
        );
        await _flushAsync();
        first.fail();
        await _flushAsync();

        expect(connector.calls, 2);
        expect(delays, <Duration>[const Duration(seconds: 2)]);
        await source.close();
      },
    );

    test('short-lived connections use bounded exponential retries', () async {
      final first = _WireConnection();
      final delays = <Duration>[];
      final connector = _Connector(<Object>[
        Future<ServerEventWireConnection>.value(first),
        StateError('offline'),
        StateError('offline'),
      ]);
      final source = ReconnectingJellyfinServerEventSource(
        connector: connector,
        maxAttempts: 3,
        retryDelay: const Duration(seconds: 2),
        wait: (duration) async => delays.add(duration),
        jitter: () => 0.5,
      );
      await _flushAsync();
      first.end();
      await _flushAsync();

      expect(connector.calls, 3);
      expect(source.state, ServerEventConnectionState.failed);
      expect(delays, <Duration>[
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ]);
      await source.close();
    });

    test('authentication failure is terminal and is not retried', () async {
      final connector = _Connector(<Object>[
        const ServerEventAuthenticationFailure(),
      ]);
      final source = ReconnectingJellyfinServerEventSource(
        connector: connector,
        wait: (_) async {},
      );
      await _flushAsync();
      expect(connector.calls, 1);
      expect(source.state, ServerEventConnectionState.failed);
      expect(source.support, ServerEventsSupport.unknown);
      await source.close();
    });

    test('a stable connection resets the reconnect attempt budget', () async {
      final first = _WireConnection();
      final second = _WireConnection();
      var now = Duration.zero;
      final connector = _Connector(<Object>[
        Future<ServerEventWireConnection>.value(first),
        StateError('brief drop'),
        Future<ServerEventWireConnection>.value(second),
      ]);
      final source = ReconnectingJellyfinServerEventSource(
        connector: connector,
        maxAttempts: 2,
        retryDelay: const Duration(seconds: 1),
        stableConnectionDuration: const Duration(seconds: 5),
        wait: (_) async {},
        monotonicNow: () => now,
        jitter: () => 0.5,
      );
      await _flushAsync();
      now = const Duration(seconds: 5);
      first.end();
      await _flushAsync();

      expect(connector.calls, 3);
      expect(source.state, ServerEventConnectionState.connected);
      await source.close();
    });

    test('one hundred disconnect cycles remain bounded and close each socket',
        () async {
      final connections = List<_WireConnection>.generate(
        101,
        (_) => _WireConnection(),
      );
      final connector = _Connector(connections);
      final source = ReconnectingJellyfinServerEventSource(
        connector: connector,
        maxAttempts: 1,
        retryDelay: Duration.zero,
        stableConnectionDuration: Duration.zero,
        wait: (_) async {},
        jitter: () => 0.5,
      );
      await _flushAsync();
      expect(source.state, ServerEventConnectionState.connected);

      for (var index = 0; index < 100; index++) {
        connections[index].end();
        await _flushAsync();
        expect(connector.calls, index + 2);
        expect(connections[index].closed, 1);
        expect(source.state, ServerEventConnectionState.connected);
      }
      await source.close();
      expect(connections.last.closed, 1);
    });

    test('coalesces invalidations and filters blank item IDs', () {
      fakeAsync((async) {
        final source = _EventSource();
        var libraries = 0;
        var userData = 0;
        final invalidated = <Set<String>>[];
        final controller = JellyfinServerEventSessionController(
          source: source,
          isCurrent: () => true,
          onLibraryInvalidated: () => libraries++,
          onUserDataInvalidated: () => userData++,
          onItemsInvalidated: invalidated.add,
        );
        source.emit(
          const JellyfinServerEvent(
            kind: JellyfinServerEventKind.libraryInvalidated,
          ),
        );
        source.emit(
          const JellyfinServerEvent(
            kind: JellyfinServerEventKind.userDataInvalidated,
          ),
        );
        source.emit(
          const JellyfinServerEvent(
            kind: JellyfinServerEventKind.itemInvalidated,
            itemIds: <String>{'one', ' ', 'two'},
          ),
        );
        async.elapse(const Duration(milliseconds: 150));
        expect(libraries, 1);
        expect(userData, 1);
        expect(invalidated, <Set<String>>[
          {'one', 'two'},
        ]);
        unawaited(controller.close());
        async.flushMicrotasks();
      });
    });

    test('large item invalidation burst falls back to bounded broad refresh',
        () {
      fakeAsync((async) {
        final source = _EventSource();
        var libraries = 0;
        final invalidated = <Set<String>>[];
        final controller = JellyfinServerEventSessionController(
          source: source,
          isCurrent: () => true,
          onLibraryInvalidated: () => libraries++,
          onUserDataInvalidated: () {},
          onItemsInvalidated: invalidated.add,
          maxCoalescedItemIds: 32,
        );
        source.emit(JellyfinServerEvent(
          kind: JellyfinServerEventKind.itemInvalidated,
          itemIds: <String>{for (var i = 0; i < 2000; i++) 'item-$i'},
        ));
        async.elapse(const Duration(milliseconds: 150));
        expect(libraries, 1);
        expect(invalidated, isEmpty);

        source.emit(const JellyfinServerEvent(
          kind: JellyfinServerEventKind.itemInvalidated,
          itemIds: <String>{'next-window-item'},
        ));
        async.elapse(const Duration(milliseconds: 150));
        expect(invalidated, <Set<String>>[
          <String>{'next-window-item'},
        ]);
        unawaited(controller.close());
        async.flushMicrotasks();
      });
    });

    test('drops queued work after session becomes stale', () {
      fakeAsync((async) {
        final source = _EventSource();
        var current = true;
        var invalidations = 0;
        final controller = JellyfinServerEventSessionController(
          source: source,
          isCurrent: () => current,
          onLibraryInvalidated: () => invalidations++,
          onUserDataInvalidated: () {},
          onItemsInvalidated: (_) {},
        );
        source.emit(
          const JellyfinServerEvent(
            kind: JellyfinServerEventKind.libraryInvalidated,
          ),
        );
        current = false;
        async.elapse(const Duration(milliseconds: 200));
        expect(invalidations, 0);
        unawaited(controller.close());
        async.flushMicrotasks();
      });
    });

    test(
      'unsupported default does not create a public endpoint fallback',
      () async {
        const source = UnsupportedServerEventSource();
        expect(source.support, ServerEventsSupport.unsupported);
        expect(await source.events.isEmpty, isTrue);
        await source.close();
      },
    );

    test('close cancels stream and closes its source exactly once', () async {
      final source = _EventSource();
      final controller = JellyfinServerEventSessionController(
        source: source,
        isCurrent: () => true,
        onLibraryInvalidated: () {},
        onUserDataInvalidated: () {},
        onItemsInvalidated: (_) {},
      );
      await controller.close();
      await controller.close();
      expect(source.closed, 1);
    });
  });
}

Future<void> _flushAsync() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _EventSource implements ServerEventSource {
  final StreamController<JellyfinServerEvent> _controller =
      StreamController<JellyfinServerEvent>.broadcast(sync: true);
  int closed = 0;

  void emit(JellyfinServerEvent event) => _controller.add(event);

  @override
  ServerEventsSupport get support => ServerEventsSupport.supported;
  @override
  Stream<JellyfinServerEvent> get events => _controller.stream;
  @override
  Future<void> close() async {
    closed++;
    await _controller.close();
  }
}

final class _Connector implements ServerEventConnector {
  _Connector(this.responses);
  final List<Object> responses;
  final List<ServerEventConnectionCancellation?> cancellations = [];
  int calls = 0;
  @override
  Future<ServerEventWireConnection> connect({
    ServerEventConnectionCancellation? cancellation,
  }) {
    cancellations.add(cancellation);
    final response = responses[calls++];
    if (response is Future<ServerEventWireConnection>) return response;
    if (response is ServerEventWireConnection) {
      return Future<ServerEventWireConnection>.value(response);
    }
    return Future<ServerEventWireConnection>.error(response);
  }
}

final class _WireConnection implements ServerEventWireConnection {
  final StreamController<JellyfinServerEvent> _events =
      StreamController<JellyfinServerEvent>();
  int closed = 0;
  @override
  Stream<JellyfinServerEvent> get events => _events.stream;
  void end() => unawaited(_events.close());
  void fail() {
    _events.addError(StateError('transport closed'));
    unawaited(_events.close());
  }

  @override
  Future<void> close() async {
    closed++;
    if (!_events.isClosed) await _events.close();
  }
}
