import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/network/private_network_runtime.dart';

/// Resolves one explicitly associated service, never arbitrary URLs.
class PrivateServiceEndpointResolver {
  PrivateServiceEndpointResolver({
    required String canonicalBaseUrl,
    required this.status,
  }) : _canonical = Uri.parse(canonicalBaseUrl);

  final Uri _canonical;
  final ValueListenable<PrivateNetworkStatus?> status;

  Uri resolve(Uri canonicalUrl) => _resolve(canonicalUrl, socket: false);

  Uri resolveWebSocket(Uri canonicalUrl) =>
      _resolve(canonicalUrl, socket: true);

  Uri _resolve(Uri canonicalUrl, {required bool socket}) {
    final expectedScheme = socket
        ? (_canonical.scheme == 'https' ? 'wss' : 'ws')
        : _canonical.scheme;
    if (canonicalUrl.scheme != expectedScheme ||
        canonicalUrl.host.toLowerCase() != _canonical.host.toLowerCase() ||
        (socket
            ? canonicalUrl.hasPort != _canonical.hasPort ||
                (canonicalUrl.hasPort && canonicalUrl.port != _canonical.port)
            : canonicalUrl.port != _canonical.port) ||
        canonicalUrl.userInfo.isNotEmpty) {
      throw const PrivateNetworkException(
          PrivateNetworkFailure.operationFailed);
    }
    final current = status.value;
    if (current?.canProxy != true) {
      throw const PrivateNetworkException(
          PrivateNetworkFailure.operationFailed);
    }
    final gateway = current!.gatewayBaseUrl!;
    return canonicalUrl.replace(
      scheme: socket ? 'ws' : gateway.scheme,
      host: gateway.host,
      port: gateway.port,
      userInfo: '',
    );
  }
}

/// Routes at send time and handles redirects without an automatic escape.
class PrivateServiceHttpClient extends http.BaseClient {
  PrivateServiceHttpClient(this._inner, this._resolver);

  final http.Client _inner;
  final PrivateServiceEndpointResolver _resolver;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var canonicalUrl = request.url;
    var currentRequest = request;
    var redirects = 0;
    while (true) {
      final destination = _resolver.resolve(canonicalUrl);
      final response = await _inner.send(
        _TransportRequest(currentRequest, destination),
      );
      final location = _location(response);
      if (!request.followRedirects ||
          !_isRedirect(response.statusCode) ||
          location == null ||
          !_canFollow(currentRequest.method, response.statusCode)) {
        return response;
      }
      final nextUrl = canonicalUrl.resolve(location);
      // Validate before any second request; no absolute external redirect escapes.
      try {
        _resolver.resolve(nextUrl);
      } on PrivateNetworkException {
        await response.stream.listen((_) {}, onError: (Object _) {}).cancel();
        rethrow;
      }
      if (redirects++ >= request.maxRedirects ||
          currentRequest is! http.Request) {
        await response.stream.drain<void>();
        throw const PrivateNetworkException(
            PrivateNetworkFailure.operationFailed);
      }
      await response.stream.drain<void>();
      currentRequest =
          _redirectRequest(currentRequest, nextUrl, response.statusCode);
      canonicalUrl = nextUrl;
    }
  }

  @override
  void close() => _inner.close();
}

class _TransportRequest extends http.BaseRequest with http.Abortable {
  _TransportRequest(this.source, Uri destination)
      : super(source.method, destination) {
    headers.addAll(source.headers);
    headers['Host'] = _logicalHost(source.url);
    contentLength = source.contentLength;
    persistentConnection = source.persistentConnection;
    followRedirects = false;
    maxRedirects = source.maxRedirects;
  }

  final http.BaseRequest source;

  @override
  Future<void>? get abortTrigger =>
      source is http.Abortable ? (source as http.Abortable).abortTrigger : null;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return source.finalize();
  }
}

String _logicalHost(Uri canonicalUrl) {
  final host = canonicalUrl.host;
  final authorityHost =
      host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
  return canonicalUrl.hasPort
      ? '$authorityHost:${canonicalUrl.port}'
      : authorityHost;
}

String? _location(http.StreamedResponse response) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == 'location') return entry.value;
  }
  return null;
}

bool _isRedirect(int status) =>
    status == 301 ||
    status == 302 ||
    status == 303 ||
    status == 307 ||
    status == 308;

bool _canFollow(String method, int status) =>
    method == 'GET' ||
    method == 'HEAD' ||
    status == 303 ||
    status == 307 ||
    status == 308;

http.Request _redirectRequest(http.Request prior, Uri url, int status) {
  final method = status == 303 && prior.method != 'HEAD' ? 'GET' : prior.method;
  final next = http.Request(method, url)
    ..headers.addAll(prior.headers)
    ..persistentConnection = prior.persistentConnection
    ..followRedirects = prior.followRedirects
    ..maxRedirects = prior.maxRedirects;
  if (method == prior.method) {
    next.bodyBytes = prior.bodyBytes;
  } else {
    next.headers.remove('content-length');
    next.headers.remove('content-type');
  }
  return next;
}
