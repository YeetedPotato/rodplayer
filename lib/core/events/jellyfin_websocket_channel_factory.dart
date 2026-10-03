import 'package:web_socket_channel/web_socket_channel.dart';

import 'jellyfin_websocket_channel_factory_stub.dart'
    if (dart.library.io) 'jellyfin_websocket_channel_factory_io.dart' as impl;

typedef JellyfinWebSocketChannelFactory = WebSocketChannel Function(
  Uri uri, {
  Map<String, dynamic>? headers,
  Duration? connectTimeout,
});

bool isJellyfinWebSocketAuthenticationFailure(Object error) =>
    impl.isJellyfinWebSocketAuthenticationFailure(error);

WebSocketChannel connectJellyfinWebSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
  Duration? connectTimeout,
}) =>
    impl.connectJellyfinWebSocket(
      uri,
      headers: headers,
      connectTimeout: connectTimeout,
    );
