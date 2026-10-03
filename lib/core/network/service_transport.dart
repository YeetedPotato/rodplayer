import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/network/private_service_endpoint_resolver.dart';

/// HTTP and endpoint-resolution boundary for one configured service.
///
/// Protocol clients own routes and payload mapping; transports own how a
/// canonical service endpoint is reached. This interface intentionally has no
/// mesh, enrollment, Headscale, or relay policy API.
abstract interface class ServiceTransport {
  http.Client get httpClient;

  Uri resolveServiceUri(Uri canonicalUri);

  Uri resolveWebSocketUri(Uri canonicalUri);

  /// Validates socket availability before a handshake. Private upgrades are
  /// explicitly unsupported, independently of private HTTP readiness.
  Future<void> waitUntilReadyForWebSocket();

  /// Optional signal that endpoint availability/routing has changed.
  Listenable? get endpointChanges;

  Future<Uint8List> readBytes(
    Uri canonicalUri, {
    Map<String, String>? headers,
  });

  void close();
}

/// HTTP transport implementation. Private mode delegates request enforcement
/// and redirects to the existing [PrivateServiceHttpClient] and resolver.
class HttpServiceTransport implements ServiceTransport {
  HttpServiceTransport({http.Client? client})
      : _inner = client ?? http.Client();

  final http.Client _inner;
  PrivateServiceEndpointResolver? _resolver;
  PrivateServiceHttpClient? _privateClient;
  Future<void> Function()? _waitUntilReady;
  bool _closed = false;

  @override
  http.Client get httpClient => _privateClient ?? _inner;

  @override
  Listenable? get endpointChanges => _resolver?.status;

  /// Binds the already validated private resolver once during composition.
  /// It cannot be replaced with another server or policy after requests begin.
  void bindPrivateResolver(
    PrivateServiceEndpointResolver resolver, {
    Future<void> Function()? waitUntilReady,
  }) {
    if (_closed || _resolver != null) {
      throw StateError('Service transport is already configured');
    }
    _resolver = resolver;
    _waitUntilReady = waitUntilReady;
    _privateClient = PrivateServiceHttpClient(
      _inner,
      resolver,
      waitUntilReady: waitUntilReady,
    );
  }

  @override
  Uri resolveServiceUri(Uri canonicalUri) =>
      _resolver?.resolve(canonicalUri) ?? canonicalUri;

  @override
  Uri resolveWebSocketUri(Uri canonicalUri) =>
      _resolver?.resolveWebSocket(canonicalUri) ?? canonicalUri;

  @override
  Future<void> waitUntilReadyForWebSocket() async {
    if (_resolver != null) throw const PrivateServiceWebSocketUnsupported();
    await _waitUntilReady?.call();
  }

  @override
  Future<Uint8List> readBytes(
    Uri canonicalUri, {
    Map<String, String>? headers,
  }) async {
    final response = await httpClient.get(canonicalUri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Service image request failed (${response.statusCode})',
        canonicalUri,
      );
    }
    return response.bodyBytes;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _privateClient?.close();
    if (_privateClient == null) _inner.close();
  }
}
