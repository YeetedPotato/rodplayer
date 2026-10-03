import 'dart:async';
import 'dart:convert';

import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/events/jellyfin_server_events.dart';
import 'package:rodplayer/core/events/jellyfin_websocket_channel_factory.dart';
import 'package:rodplayer/core/network/service_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Jellyfin's authenticated `/socket` connector, bound to one server session.
///
/// Authentication follows the MediaBrowser protocol: the account access token
/// is sent as the `ApiKey` query parameter, with the installation device ID.
/// The token-bearing URI and socket exceptions are never logged or surfaced.
final class JellyfinWebSocketEventConnector implements ServerEventConnector {
  JellyfinWebSocketEventConnector({
    required String baseUrl,
    required String accessToken,
    required this.userId,
    required this.deviceId,
    required this.transport,
    this.channelFactory = connectJellyfinWebSocket,
    this.connectTimeout = const Duration(seconds: 10),
  })  : _base = Uri.parse(baseUrl),
        _accessToken = JellyfinApiClient.cleanToken(accessToken) ?? '';

  final Uri _base;
  final String _accessToken;
  final String userId;
  final String deviceId;
  final ServiceTransport transport;
  final JellyfinWebSocketChannelFactory channelFactory;
  final Duration connectTimeout;

  Uri buildCanonicalUri() {
    if ((_base.scheme != 'http' && _base.scheme != 'https') ||
        _base.host.isEmpty ||
        _base.userInfo.isNotEmpty ||
        _base.query.isNotEmpty ||
        _base.fragment.isNotEmpty ||
        _accessToken.isEmpty ||
        userId.trim().isEmpty ||
        deviceId.trim().isEmpty) {
      throw const ServerEventTransportUnsupported();
    }
    final basePath = _base.path.endsWith('/')
        ? _base.path.substring(0, _base.path.length - 1)
        : _base.path;
    return _base.replace(
      scheme: _base.scheme == 'https' ? 'wss' : 'ws',
      path: '$basePath/socket',
      queryParameters: <String, String>{
        'ApiKey': _accessToken,
        'deviceId': deviceId,
      },
    );
  }

  @override
  Future<ServerEventWireConnection> connect({
    ServerEventConnectionCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw const ServerEventConnectionCancelled();
    }
    final canonical = buildCanonicalUri();
    final Uri resolved;
    try {
      if (cancellation == null) {
        await transport.waitUntilReadyForWebSocket();
      } else {
        final cancelled = await Future.any<bool>(<Future<bool>>[
          transport.waitUntilReadyForWebSocket().then((_) => false),
          cancellation.whenCancelled.then((_) => true),
        ]);
        if (cancelled) throw const ServerEventConnectionCancelled();
      }
      resolved = transport.resolveWebSocketUri(canonical);
    } on ServerEventConnectionCancelled {
      rethrow;
    } on ServerEventTransportUnsupported {
      rethrow;
    } on Object {
      // Resolver failures can include private endpoint details. Keep them local.
      throw const ServerEventTransportUnsupported();
    }

    if ((resolved.scheme != 'ws' && resolved.scheme != 'wss') ||
        resolved.userInfo.isNotEmpty ||
        resolved.host.isEmpty) {
      throw const ServerEventTransportUnsupported();
    }
    // The Apple loopback gateway is a plain TCP tunnel. Never downgrade a
    // secure canonical socket to ws; that would fail TLS and expose credentials.
    if (canonical.scheme == 'wss' && resolved.scheme != 'wss') {
      throw const ServerEventTransportUnsupported();
    }

    final WebSocketChannel channel;
    try {
      channel = channelFactory(
        resolved,
        headers: <String, dynamic>{'Host': canonical.authority},
        connectTimeout: connectTimeout,
      );
    } on UnsupportedError {
      throw const ServerEventTransportUnsupported();
    } on Object {
      throw const ServerEventConnectionFailure();
    }
    try {
      if (cancellation == null) {
        await channel.ready.timeout(connectTimeout);
      } else {
        final cancelled = await Future.any<bool>(<Future<bool>>[
          channel.ready.timeout(connectTimeout).then((_) => false),
          cancellation.whenCancelled.then((_) => true),
        ]);
        if (cancelled) {
          unawaited(channel.sink.close().catchError((Object _) {}));
          throw const ServerEventConnectionCancelled();
        }
      }
    } on ServerEventConnectionCancelled {
      rethrow;
    } on Object catch (error) {
      // The channel closes itself after a failed handshake. Awaiting sink.close
      // here can hang because no WebSocket session was established.
      if (isJellyfinWebSocketAuthenticationFailure(error)) {
        throw const ServerEventAuthenticationFailure();
      }
      throw const ServerEventConnectionFailure();
    }
    return _JellyfinWebSocketWireConnection(
      channel: channel,
      authenticatedUserId: userId,
    );
  }
}

final class ServerEventConnectionFailure implements Exception {
  const ServerEventConnectionFailure();
}

final class _JellyfinWebSocketWireConnection
    implements ServerEventWireConnection {
  _JellyfinWebSocketWireConnection({
    required this.channel,
    required this.authenticatedUserId,
  }) {
    _subscription = channel.stream.listen(
      _onFrame,
      onError: (Object _) => _closeEventsWithError(),
      onDone: _closeEvents,
      cancelOnError: true,
    );
  }

  final WebSocketChannel channel;
  final String authenticatedUserId;
  final StreamController<JellyfinServerEvent> _events =
      StreamController<JellyfinServerEvent>();
  StreamSubscription<dynamic>? _subscription;
  Timer? _keepAlive;
  bool _closed = false;
  bool _eventsClosed = false;

  @override
  Stream<JellyfinServerEvent> get events => _events.stream;

  void _onFrame(dynamic frame) {
    final message = _decode(frame);
    if (message?['MessageType'] == 'ForceKeepAlive') {
      _scheduleKeepAlive(message?['Data']);
      return;
    }
    final event = normalizeJellyfinEventFrame(
      frame,
      authenticatedUserId: authenticatedUserId,
    );
    if (event != null && !_events.isClosed) _events.add(event);
  }

  Map<String, dynamic>? _decode(dynamic frame) {
    try {
      final Object? decoded = switch (frame) {
        String value => jsonDecode(value),
        List<int> value => jsonDecode(utf8.decode(value)),
        _ => null,
      };
      return decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : null;
    } on Object {
      return null;
    }
  }

  void _scheduleKeepAlive(Object? timeoutValue) {
    final timeoutSeconds = timeoutValue is num ? timeoutValue.toInt() : 60;
    final interval = Duration(seconds: (timeoutSeconds ~/ 2).clamp(10, 300));
    _keepAlive?.cancel();
    _sendKeepAlive();
    _keepAlive = Timer.periodic(interval, (_) => _sendKeepAlive());
  }

  void _sendKeepAlive() {
    if (_closed) return;
    try {
      channel.sink.add(jsonEncode(const <String, String>{
        'MessageType': 'KeepAlive',
      }));
    } on Object {
      _closeEventsWithError();
    }
  }

  void _closeEventsWithError() {
    if (_eventsClosed) return;
    _eventsClosed = true;
    _keepAlive?.cancel();
    _keepAlive = null;
    if (!_events.isClosed) {
      _events.addError(const ServerEventConnectionFailure());
      unawaited(_events.close());
    }
  }

  void _closeEvents() {
    if (_eventsClosed) return;
    _eventsClosed = true;
    _keepAlive?.cancel();
    _keepAlive = null;
    if (!_events.isClosed) unawaited(_events.close());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _keepAlive?.cancel();
    _keepAlive = null;
    await _subscription?.cancel();
    try {
      await channel.sink.close();
    } on Object {
      // The transport is best-effort during session teardown.
    }
    _closeEvents();
  }
}
