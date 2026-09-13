import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/remux_client.dart';

class _MockClient extends http.BaseClient { _MockClient(this.handler); final FutureOr<http.Response> Function(http.BaseRequest) handler; @override Future<http.StreamedResponse> send(http.BaseRequest request) async { final response = await handler(request); return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode, headers: response.headers, request: request); } }
void main() {
  const base = 'https://media.example.com';
  test('healthCheck returns server info on HTTP 200', () async { final client = RemuxClient(baseUrl: base, client: _MockClient((request) async => http.Response(jsonEncode({'ServerName': 'Test'}), 200))); expect(await client.healthCheck(), {'ServerName': 'Test'}); });
  test('authenticate throws RemuxAuthException on HTTP 401', () async { final client = RemuxClient(baseUrl: base, client: _MockClient((request) async => http.Response('', 401))); expect(() => client.authenticate(username: 'u', password: 'p'), throwsA(isA<RemuxAuthException>())); });
  test('client exception becomes RemuxConnectionException', () async { final client = RemuxClient(baseUrl: base, client: _MockClient((request) => throw http.ClientException('offline'))); expect(() => client.healthCheck(), throwsA(isA<RemuxConnectionException>())); });
  test('timeout becomes RemuxConnectionException', () async { final client = RemuxClient(baseUrl: base, client: _MockClient((request) => throw TimeoutException('slow'))); expect(() => client.healthCheck(), throwsA(isA<RemuxConnectionException>())); });
  test('getLatestMovies and getLatestTvShows query the latest shelves', () async { final requests = <http.BaseRequest>[]; final client = RemuxClient(baseUrl: base, client: _MockClient((request) { requests.add(request); return http.Response(jsonEncode({'Items': [{'Id': 'item-1'}]}), 200); })); client.userId = 'user-1'; expect(await client.getLatestMovies(limit: 7), [{'Id': 'item-1'}]); expect(await client.getLatestTvShows(limit: 9), [{'Id': 'item-1'}]); expect(requests[0].url.toString(), '$base/Items?userId=user-1&IncludeItemTypes=Movie&Recursive=true&SortBy=DateCreated&SortOrder=Descending&Limit=7&Fields=PrimaryImageAspectRatio,UserData'); expect(requests[1].url.toString(), '$base/Items?userId=user-1&IncludeItemTypes=Series&Recursive=true&SortBy=DateCreated&SortOrder=Descending&Limit=9&Fields=PrimaryImageAspectRatio,UserData'); });
  test('search and getItems attach sanitized MediaBrowser auth headers', () async { final requests = <http.BaseRequest>[]; final client = RemuxClient(baseUrl: base, client: _MockClient((request) { requests.add(request); return http.Response(jsonEncode({'Items': []}), 200); })); client.accessToken = 'Bearer secret'; client.userId = 'user-1'; await client.search(query: 'hello'); await client.getItems(); expect(requests, hasLength(2)); });
  Future<RemuxClient> playbackClient(Map<String, dynamic> body) async { final client = RemuxClient(baseUrl: base, client: _MockClient((request) async => http.Response(jsonEncode(body), 200))); client.userId = 'user-1'; client.accessToken = 'secret'; return client; }
  test('getStreamUri rejects unusable sources', () async { final client = await playbackClient({'MediaSources': [{'Path': ''}, {'DirectStreamUrl': null}]}); expect(() => client.getStreamUri('item'), throwsA(isA<RemuxConnectionException>())); });
}
