import 'package:web_socket_channel/web_socket_channel.dart';

bool isJellyfinWebSocketAuthenticationFailure(Object error) => false;

WebSocketChannel connectJellyfinWebSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
  Duration? connectTimeout,
}) =>
    throw UnsupportedError(
        'WebSocket transport is unavailable on this platform');
