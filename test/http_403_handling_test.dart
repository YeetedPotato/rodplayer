import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';

import 'fakes/test_playback_engine.dart';
import 'test_support.dart';

class _ForbiddenClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = http.Response(jsonEncode(<String, String>{'error': 'forbidden'}), 403, headers: <String, String>{'content-type': 'application/json'});
    return http.StreamedResponse(Stream<List<int>>.value(response.bodyBytes), response.statusCode, headers: response.headers, request: request);
  }
}

void main() {
  test('JellyfinApiClient maps HTTP 403 to a connection exception with status', () async {
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com', identity: testIdentity, client: _ForbiddenClient());
    addTearDown(client.close);
    await expectLater(client.healthCheck(), throwsA(isA<ServerConnectionException>().having((exception) => exception.statusCode, 'statusCode', 403)));
  });

  test('PlaybackEngine exposes a transport failure through its error state', () async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    engine.error.value = 'Server request failed (403)';
    expect(engine.error.value, 'Server request failed (403)');
  });
}
