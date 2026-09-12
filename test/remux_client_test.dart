import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/remux_client.dart';

class _MockClient extends http.BaseClient {
  _MockClient(this.handler);
  final FutureOr<http.Response> Function(http.BaseRequest) handler;
  @override Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode, headers: response.headers, request: request);
  }
}

void main() {
  const base = 'https://media.example.com';
  test('healthCheck returns server info on HTTP 200', () async {
    final client = RemuxClient(baseUrl: base, client: _MockClient((request) async => http.Response(jsonEncode({'ServerName': 'Test'}), 200)));
    expect(await client.healthCheck(), {'ServerName': 'Test'});
  });
  test('authenticate throws RemuxAuthException on HTTP 401', () async {
    final client = RemuxClient(baseUrl: base, client: _MockClient((request) async => http.Response('', 401)));
    expect(() => client.authenticate(username: 'u', password: 'p'), throwsA(isA<RemuxAuthException>()));
  });
  test('client exception becomes RemuxConnectionException', () async {
    final client = RemuxClient(baseUrl: base, client: _MockClient((request) => throw http.ClientException('offline')));
    expect(() => client.healthCheck(), throwsA(isA<RemuxConnectionException>()));
  });
  test('timeout becomes RemuxConnectionException', () async {
    final client = RemuxClient(baseUrl: base, client: _MockClient((request) => throw TimeoutException('slow')));
    expect(() => client.healthCheck(), throwsA(isA<RemuxConnectionException>()));
  });
  test('search and getItems attach sanitized MediaBrowser auth headers', () async {
    final requests = <http.BaseRequest>[];
    final client = RemuxClient(baseUrl: base, client: _MockClient((request) { requests.add(request); return http.Response(jsonEncode({'Items': []}), 200); }));
    client.accessToken = 'Bearer secret'; client.userId = 'user-1';
    await client.search('hello'); await client.getItems();
    expect(requests, hasLength(2));
    for (final request in requests) {
      expect(request.headers['authorization'], contains('Token="secret"'));
      expect(request.headers['authorization'], isNot(contains('Bearer')));
      expect(request.url.toString(), startsWith(base));
    }
  });
}
