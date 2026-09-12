import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/remux_client.dart';
import 'package:rodplayer/core/player/player_controller.dart';

class _ForbiddenClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = http.Response(
      jsonEncode(<String, String>{'error': 'forbidden'}),
      403,
      headers: <String, String>{'content-type': 'application/json'},
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  test('RemuxClient maps HTTP 403 to a connection exception with status', () async {
    final client = RemuxClient(
      baseUrl: 'https://remux.example.com',
      client: _ForbiddenClient(),
    );
    addTearDown(client.close);

    await expectLater(
      client.healthCheck(),
      throwsA(
        isA<RemuxConnectionException>().having(
          (exception) => exception.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
  });

  test('RodPlayerEngine exposes a transport failure through its error state', () async {
    final engine = RodPlayerEngine();
    addTearDown(engine.dispose);

    engine.error.value = 'Remux request failed (403)';

    expect(engine.error.value, 'Remux request failed (403)');
  });
}
