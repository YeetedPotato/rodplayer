import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/events/jellyfin_server_event_session_factory.dart';
import 'package:rodplayer/core/events/jellyfin_server_events.dart';
import 'package:rodplayer/core/events/jellyfin_websocket_event_connector.dart';
import 'package:rodplayer/core/models/server_identity.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/core/network/private_service_endpoint_resolver.dart';
import 'package:rodplayer/core/network/service_transport.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  test('production session factory binds the active client and invalidates',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handshake = Completer<HttpRequest>();
    final socketClosed = Completer<void>();
    server.listen((request) async {
      handshake.complete(request);
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {}, onDone: () {
        if (!socketClosed.isCompleted) socketClosed.complete();
      });
      socket.add(jsonEncode({'MessageType': 'LibraryChanged', 'Data': {}}));
      socket.add(jsonEncode({
        'MessageType': 'UserDataChanged',
        'Data': {'UserId': 'user-1'},
      }));
    });
    final client = JellyfinApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}/jellyfin',
      identity: const InstallationIdentity(
        deviceId: 'device-1',
        clientName: 'Nautilus',
        deviceName: 'Test device',
        appVersion: '1.0',
      ),
      serverId: ServerId('server-1'),
      userId: 'user-1',
      accessToken: 'fixture-token',
    );
    final invalidated = Completer<void>();
    var libraryInvalidations = 0;
    var userDataInvalidations = 0;
    final controller = createJellyfinServerEventSession(
      client: client,
      isCurrent: () => true,
      onLibraryInvalidated: () => libraryInvalidations++,
      onUserDataInvalidated: () {
        userDataInvalidations++;
        if (libraryInvalidations > 0 && !invalidated.isCompleted) {
          invalidated.complete();
        }
      },
      onItemsInvalidated: (_) {},
    );

    final request = await handshake.future.timeout(const Duration(seconds: 2));
    expect(request.uri.path, '/jellyfin/socket');
    expect(request.uri.queryParameters, {
      'ApiKey': 'fixture-token',
      'deviceId': 'device-1',
    });
    await invalidated.future.timeout(const Duration(seconds: 2));
    expect(libraryInvalidations, 1);
    expect(userDataInvalidations, 1);

    await controller.close();
    await socketClosed.future.timeout(const Duration(seconds: 2));
    client.close();
    await server.close(force: true);
  });

  test('builds authenticated Jellyfin socket through service transport',
      () async {
    final transport = HttpServiceTransport();
    Uri? connectedUri;
    Map<String, dynamic>? connectedHeaders;
    final connector = JellyfinWebSocketEventConnector(
      baseUrl: 'http://media.example:8096/jellyfin',
      accessToken: 'Bearer fixture-token',
      userId: 'user-1',
      deviceId: 'device-1',
      transport: transport,
      channelFactory: (uri, {headers, connectTimeout}) {
        connectedUri = uri;
        connectedHeaders = headers;
        throw const ServerEventConnectionFailure();
      },
    );

    await expectLater(
      connector.connect(),
      throwsA(isA<ServerEventConnectionFailure>()),
    );
    expect(connectedUri!.scheme, 'ws');
    expect(connectedUri!.path, '/jellyfin/socket');
    expect(connectedUri!.queryParameters, {
      'ApiKey': 'fixture-token',
      'deviceId': 'device-1',
    });
    expect(connectedHeaders, {'Host': 'media.example:8096'});
    transport.close();
  });

  test('private HTTP socket is unsupported before readiness or channel creation',
      () async {
    final status = ValueNotifier<PrivateNetworkStatus>(
      _readyStatus('http://127.0.0.1:43127'),
    );
    var readinessWaited = false;
    final transport = HttpServiceTransport()
      ..bindPrivateResolver(
        PrivateServiceEndpointResolver(
          canonicalBaseUrl: 'http://media.tailnet:8096',
          status: status,
        ),
        waitUntilReady: () async {
          readinessWaited = true;
          expect(status.value.canProxy, isTrue);
        },
      );
    Uri? connectedUri;
    Map<String, dynamic>? connectedHeaders;
    final connector = JellyfinWebSocketEventConnector(
      baseUrl: 'http://media.tailnet:8096',
      accessToken: 'fixture-token',
      userId: 'user-1',
      deviceId: 'device-1',
      transport: transport,
      channelFactory: (uri, {headers, connectTimeout}) {
        connectedUri = uri;
        connectedHeaders = headers;
        throw const ServerEventConnectionFailure();
      },
    );

    await expectLater(
      connector.connect(),
      throwsA(isA<ServerEventTransportUnsupported>()),
    );
    expect(readinessWaited, isFalse);
    expect(connectedUri, isNull, reason: 'no gateway or public socket attempt');
    expect(connectedHeaders, isNull);
    expect(() => transport.resolveWebSocketUri(connector.buildCanonicalUri()),
        throwsA(isA<PrivateServiceWebSocketUnsupported>()));
    transport.close();
    status.dispose();
  });

  test('private HTTPS socket is explicitly unsupported before channel creation',
      () async {
    final status = ValueNotifier<PrivateNetworkStatus>(
      _readyStatus('http://127.0.0.1:43127'),
    );
    final transport = HttpServiceTransport()
      ..bindPrivateResolver(
        PrivateServiceEndpointResolver(
          canonicalBaseUrl: 'https://media.tailnet:8920',
          status: status,
        ),
      );
    var channelOpened = false;
    final connector = JellyfinWebSocketEventConnector(
      baseUrl: 'https://media.tailnet:8920',
      accessToken: 'fixture-token',
      userId: 'user-1',
      deviceId: 'device-1',
      transport: transport,
      channelFactory: (uri, {headers, connectTimeout}) {
        channelOpened = true;
        throw const ServerEventConnectionFailure();
      },
    );

    await expectLater(
      connector.connect(),
      throwsA(isA<ServerEventTransportUnsupported>()),
    );
    expect(channelOpened, isFalse);
    expect(() => transport.resolveWebSocketUri(connector.buildCanonicalUri()),
        throwsA(isA<PrivateServiceWebSocketUnsupported>()));
    transport.close();
    status.dispose();
  });

  test('ordinary HTTPS retains authenticated wss behavior', () async {
    final transport = HttpServiceTransport();
    Uri? connected;
    Map<String, dynamic>? headersSeen;
    final connector = JellyfinWebSocketEventConnector(
      baseUrl: 'https://media.example:8920/jellyfin',
      accessToken: 'fixture-token', userId: 'user-1', deviceId: 'device-1',
      transport: transport,
      channelFactory: (uri, {headers, connectTimeout}) {
        connected = uri;
        headersSeen = headers;
        throw const ServerEventConnectionFailure();
      },
    );
    await expectLater(connector.connect(),
        throwsA(isA<ServerEventConnectionFailure>()));
    expect(connected!.scheme, 'wss');
    expect(connected!.host, 'media.example');
    expect(connected!.port, 8920);
    expect(connected!.path, '/jellyfin/socket');
    expect(connected!.queryParameters['ApiKey'], 'fixture-token');
    expect(headersSeen, {'Host': 'media.example:8920'});
    transport.close();
  });

  test('unready private association is unsupported without waiting or fallback',
      () async {
    final status = ValueNotifier<PrivateNetworkStatus?>(null);
    final transport = HttpServiceTransport()..bindPrivateResolver(
      PrivateServiceEndpointResolver(
          canonicalBaseUrl: 'http://media.example:8096', status: status),
      waitUntilReady: () => Completer<void>().future,
    );
    var opened = false;
    final connector = JellyfinWebSocketEventConnector(
      baseUrl: 'http://media.example:8096', accessToken: 'fixture-token',
      userId: 'user-1', deviceId: 'device-1', transport: transport,
      channelFactory: (uri, {headers, connectTimeout}) {
        opened = true;
        throw const ServerEventConnectionFailure();
      },
    );
    await expectLater(connector.connect(),
        throwsA(isA<ServerEventTransportUnsupported>()));
    expect(opened, isFalse);
    transport.close();
    status.dispose();
  });

  test('answers ForceKeepAlive and emits only matching-user invalidations',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final socketReady = Completer<WebSocket>();
    final socketClosed = Completer<void>();
    final serverFrames = StreamController<Object?>();
    server.transform(WebSocketTransformer()).listen((socket) {
      socketReady.complete(socket);
      socket.listen(
        serverFrames.add,
        onError: serverFrames.addError,
        onDone: () {
          if (!socketClosed.isCompleted) socketClosed.complete();
        },
      );
      socket.add(jsonEncode({'MessageType': 'ForceKeepAlive', 'Data': 30}));
      socket.add(jsonEncode({
        'MessageType': 'UserDataChanged',
        'Data': {'UserId': 'other-user'},
      }));
      socket.add(jsonEncode({
        'MessageType': 'UserDataChanged',
        'Data': {'UserId': 'user-1'},
      }));
      socket.add(jsonEncode({'MessageType': 'LibraryChanged', 'Data': {}}));
    });
    final transport = HttpServiceTransport();
    final connector = JellyfinWebSocketEventConnector(
      baseUrl: 'http://127.0.0.1:${server.port}',
      accessToken: 'fixture-token',
      userId: 'user-1',
      deviceId: 'device-1',
      transport: transport,
    );
    final connection = await connector.connect();
    final received = <JellyfinServerEvent>[];
    final gotEvents = Completer<void>();
    final subscription = connection.events.listen((event) {
      received.add(event);
      if (received.length == 2 && !gotEvents.isCompleted) gotEvents.complete();
    });
    await socketReady.future;

    await expectLater(
      serverFrames.stream,
      emits(contains('"MessageType":"KeepAlive"')),
    );
    await gotEvents.future.timeout(const Duration(seconds: 2));
    expect(received.map((event) => event.kind), [
      JellyfinServerEventKind.userDataInvalidated,
      JellyfinServerEventKind.libraryInvalidated,
    ]);

    await subscription.cancel();
    await connection.close();
    await socketClosed.future.timeout(const Duration(seconds: 2));
    await serverFrames.close();
    await server.close(force: true);
    transport.close();
  });

  test('treats HTTP authentication rejection as terminal and redacts it',
      () async {
    final transport = HttpServiceTransport();
    final connector = JellyfinWebSocketEventConnector(
      baseUrl: 'http://media.example:8096',
      accessToken: 'fixture-token-must-not-appear',
      userId: 'user-1',
      deviceId: 'device-1',
      transport: transport,
      channelFactory: (_, {headers, connectTimeout}) => IOWebSocketChannel(
        Future<WebSocket>.error(
          const WebSocketException('unauthorized', HttpStatus.unauthorized),
        ),
      ),
    );

    Object? failure;
    try {
      await connector.connect();
    } on Object catch (error) {
      failure = error;
    }
    expect(failure, isA<ServerEventAuthenticationFailure>());
    expect(failure.toString(), isNot(contains('fixture-token')));
    transport.close();
  });

  test('logout cancellation interrupts a pending WebSocket handshake',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<void>();
    server.listen((_) => accepted.complete());
    final transport = HttpServiceTransport();
    final connector = JellyfinWebSocketEventConnector(
      baseUrl: 'http://127.0.0.1:${server.port}',
      accessToken: 'fixture-token',
      userId: 'user-1',
      deviceId: 'device-1',
      transport: transport,
      connectTimeout: const Duration(seconds: 30),
    );
    final cancellation = ServerEventConnectionCancellation();
    final connecting = connector.connect(cancellation: cancellation);

    await accepted.future.timeout(const Duration(seconds: 2));
    cancellation.cancel();
    await expectLater(
      connecting,
      throwsA(isA<ServerEventConnectionCancelled>()),
    ).timeout(const Duration(seconds: 2));

    transport.close();
    await server.close(force: true);
  });

  test('session cancellation interrupts a supported transport readiness wait',
      () async {
    final readiness = Completer<void>();
    var channelOpened = false;
    final transport = _WaitingTransport(readiness);
    final connector = JellyfinWebSocketEventConnector(
      baseUrl: 'http://media.tailnet:8096',
      accessToken: 'fixture-token',
      userId: 'user-1',
      deviceId: 'device-1',
      transport: transport,
      channelFactory: (uri, {headers, connectTimeout}) {
        channelOpened = true;
        throw const ServerEventConnectionFailure();
      },
    );
    final cancellation = ServerEventConnectionCancellation();
    final connecting = connector.connect(cancellation: cancellation);
    await transport.entered.future;
    cancellation.cancel();
    await expectLater(
      connecting,
      throwsA(isA<ServerEventConnectionCancelled>()),
    );
    expect(channelOpened, isFalse);

    readiness.complete();
    transport.close();
  });

  test('rejects malformed endpoint or missing credential before connection',
      () async {
    final transport = HttpServiceTransport();
    var channelOpened = false;
    final connector = JellyfinWebSocketEventConnector(
      baseUrl: 'https://user@media.example:8920',
      accessToken: 'fixture-token',
      userId: 'user-1',
      deviceId: 'device-1',
      transport: transport,
      channelFactory: (uri, {headers, connectTimeout}) {
        channelOpened = true;
        throw const ServerEventConnectionFailure();
      },
    );
    await expectLater(
      connector.connect(),
      throwsA(isA<ServerEventTransportUnsupported>()),
    );
    expect(channelOpened, isFalse);
    transport.close();
  });
}

final class _WaitingTransport extends HttpServiceTransport {
  _WaitingTransport(this.readiness);
  final Completer<void> readiness;
  final entered = Completer<void>();
  @override
  Future<void> waitUntilReadyForWebSocket() {
    entered.complete();
    return readiness.future;
  }
}

PrivateNetworkStatus _readyStatus(String gateway) =>
    PrivateNetworkStatus.fromPayload({
      'state': 'ready',
      'path': 'direct',
      'hasPersistedIdentity': true,
      'reason': 'none',
      'gatewayUrl': gateway,
    });
