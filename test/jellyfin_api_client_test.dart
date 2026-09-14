import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/playback_info_request.dart';

import 'test_support.dart';

class MockClient extends http.BaseClient {
  MockClient(this.handler);
  final FutureOr<http.Response> Function(http.BaseRequest) handler;
  final requests = <http.BaseRequest>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = await handler(request);
    return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode, headers: response.headers, request: request);
  }
}

void main() {
  const base = 'https://media.example.com';

  test('healthCheck returns server info on HTTP 200', () async {
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{'ServerName': 'Test'}), 200)));
    expect(await client.healthCheck(), <String, dynamic>{'ServerName': 'Test'});
  });

  test('authenticate throws JellyfinAuthException on HTTP 401', () async {
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: MockClient((request) async => http.Response('', 401)));
    expect(() => client.authenticate(username: 'u', password: 'p'), throwsA(isA<JellyfinAuthException>()));
  });

  test('Authorization header uses RodPlayer identity and stable device/version', () async {
    late http.BaseRequest seen;
    final mock = MockClient((request) {
      seen = request;
      return http.Response(jsonEncode(<String, dynamic>{'Items': <dynamic>[]}), 200);
    });
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: mock)
      ..accessToken = 'Bearer secret'
      ..userId = 'user-1';
    await client.getItems();
    final auth = seen.headers['Authorization']!;
    expect(auth, contains('Client="RodPlayer"'));
    expect(auth, contains('Device="Test device"'));
    expect(auth, isNot(contains('FireTV')));
    expect(auth, contains('DeviceId="device-stable"'));
    expect(auth, contains('Version="9.8.7"'));
  });

  test('getPlaybackInfo returns DTO and does not choose best stream', () async {
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{'PlaySessionId': 'play', 'MediaSources': <Map<String, dynamic>>[<String, dynamic>{'Id': 'source', 'MediaStreams': <dynamic>[] }]}), 200)))..userId = 'user';
    final response = await client.getPlaybackInfo(const PlaybackInfoRequest(itemId: 'item', deviceProfile: <String, dynamic>{'Name': 'RodPlayer'}));
    expect(response.playSessionId, 'play');
    expect(response.mediaSources.single.id, 'source');
  });

  test('buildDirectPlayUri uses Jellyfin stream endpoint with auth and session query', () {
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: MockClient((_) async => http.Response('', 200)))..accessToken = 'Bearer token';
    final uri = client.buildDirectPlayUri(itemId: 'item', mediaSourceId: 'source', playSessionId: 'play', audioStreamIndex: 4, subtitleStreamIndex: 6);
    expect(uri.path, '/Videos/item/stream');
    expect(uri.queryParameters, containsPair('static', 'true'));
    expect(uri.queryParameters, containsPair('mediaSourceId', 'source'));
    expect(uri.queryParameters, containsPair('playSessionId', 'play'));
    expect(uri.queryParameters, containsPair('audioStreamIndex', '4'));
    expect(uri.queryParameters, containsPair('subtitleStreamIndex', '6'));
    expect(uri.queryParameters, containsPair('api_key', 'token'));
  });
}
