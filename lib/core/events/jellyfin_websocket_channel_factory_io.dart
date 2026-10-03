import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

bool isJellyfinWebSocketAuthenticationFailure(Object error) {
  final inner = error is WebSocketChannelException ? error.inner : error;
  return inner is WebSocketException &&
      (inner.httpStatusCode == HttpStatus.unauthorized ||
          inner.httpStatusCode == HttpStatus.forbidden);
}

WebSocketChannel connectJellyfinWebSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
  Duration? connectTimeout,
}) =>
    IOWebSocketChannel.connect(
      uri,
      headers: headers,
      connectTimeout: connectTimeout,
    );
