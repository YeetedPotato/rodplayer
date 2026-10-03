import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/live_tv.dart';
import 'package:rodplayer/core/live_tv/jellyfin_live_tv_repository.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_negotiator.dart';

import 'test_support.dart';

void main() {
  const base = 'https://media.example.com';

  test(
      'channels page uses user-scoped Jellyfin LiveTv endpoint and typed fields',
      () async {
    late http.BaseRequest seen;
    final client = JellyfinApiClient(
      baseUrl: base,
      identity: testIdentity,
      serverId: testServerId,
      userId: 'user',
      accessToken: 'test-token',
      client: _Client((request) async {
        seen = request;
        return http.Response(
            jsonEncode(<String, Object?>{
              'Items': <Object?>[
                <String, Object?>{
                  'Id': 'channel-1',
                  'Name': 'Channel',
                  'Number': '7',
                  'ImageTags': <String, Object?>{'Primary': 'tag'}
                },
              ],
              'TotalRecordCount': 1,
              'StartIndex': 0,
            }),
            200);
      }),
    );
    final page = await client.getLiveTvChannelsPage(limit: 12);
    expect(seen.url.path, '/LiveTv/Channels');
    expect(seen.url.queryParameters['UserId'], 'user');
    expect(seen.url.queryParameters['Limit'], '12');
    expect(seen.headers['Authorization'], contains('test-token'));
    expect(page.totalRecordCount, 1);
    expect(page.items.single, isA<JellyfinLiveTvChannel>());
    expect(page.items.single.channelNumber, '7');
    expect(page.items.single.primaryImageTag, 'tag');
  });

  test('guide query uses normalized channel IDs and UTC window', () async {
    late http.BaseRequest seen;
    final client = JellyfinApiClient(
      baseUrl: base,
      identity: testIdentity,
      serverId: testServerId,
      userId: 'user',
      accessToken: 'test-token',
      client: _Client((request) async {
        seen = request;
        return http.Response(
            jsonEncode(<String, Object?>{
              'Items': <Object?>[
                <String, Object?>{
                  'Id': 'program-1',
                  'Name': 'News',
                  'ChannelId': 'channel-1',
                  'StartDate': '2026-10-01T10:00:00Z',
                  'EndDate': '2026-10-01T11:00:00Z',
                  'IsAiring': true
                },
              ],
              'TotalRecordCount': 1,
            }),
            200);
      }),
    );
    final start = DateTime.parse('2026-10-01T05:00:00-05:00');
    final page = await client.getLiveTvProgramsPage(
      channelIds: <String>[' channel-1 ', 'channel-1'],
      start: start,
      end: start.add(const Duration(hours: 4)),
      limit: 20,
    );
    expect(seen.url.path, '/LiveTv/Programs');
    expect(seen.url.queryParameters['ChannelIds'], 'channel-1');
    expect(seen.url.queryParameters['MinEndDate'], '2026-10-01T10:00:00.000Z');
    expect(
        seen.url.queryParameters['MaxStartDate'], '2026-10-01T14:00:00.000Z');
    expect(page.items.single.start.isUtc, isTrue);
    expect(page.items.single.isAiring, isTrue);
  });

  test('guide rejects invalid range and server empty guide remains empty',
      () async {
    final client = JellyfinApiClient(
      baseUrl: base,
      identity: testIdentity,
      serverId: testServerId,
      userId: 'user',
      accessToken: 'test-token',
      client: _Client(
          (_) async => http.Response('{"Items":[],"TotalRecordCount":0}', 200)),
    );
    await expectLater(
      client.getLiveTvProgramsPage(
          start: DateTime.utc(2026), end: DateTime.utc(2026)),
      throwsArgumentError,
    );
    final page = await client.getLiveTvProgramsPage(
      start: DateTime.utc(2026),
      end: DateTime.utc(2026).add(const Duration(hours: 1)),
    );
    expect(page.items, isEmpty);
    expect(page.totalRecordCount, 0);
  });

  test('late unsupported probe cannot downgrade observed Live TV support',
      () async {
    final unsupported = Completer<http.Response>();
    var requests = 0;
    final client = JellyfinApiClient(
      baseUrl: base,
      identity: testIdentity,
      serverId: testServerId,
      userId: 'user',
      accessToken: 'test-token',
      client: _Client((_) {
        requests++;
        return requests == 1
            ? unsupported.future
            : http.Response('{"Items":[]}', 200);
      }),
    );
    final repository = JellyfinLiveTvRepository(
      client: client,
      negotiator: PlaybackNegotiator(client: client),
    );
    final first = repository.channels(startIndex: 0);
    await Future<void>.delayed(Duration.zero);
    await repository.channels(startIndex: 1);
    expect(repository.serverCapability.value, CapabilitySupport.supported);
    unsupported.complete(http.Response('', 404));
    await expectLater(first, throwsA(isA<ServerConnectionException>()));
    expect(repository.serverCapability.value, CapabilitySupport.supported);
    repository.dispose();
  });

  test('disposed Live TV repository ignores late capability results', () async {
    final response = Completer<http.Response>();
    final client = JellyfinApiClient(
      baseUrl: base,
      identity: testIdentity,
      serverId: testServerId,
      userId: 'user',
      accessToken: 'test-token',
      client: _Client((_) => response.future),
    );
    final repository = JellyfinLiveTvRepository(
      client: client,
      negotiator: PlaybackNegotiator(client: client),
    );
    final pending = repository.channels();
    await Future<void>.delayed(Duration.zero);
    repository.dispose();
    response.complete(http.Response('{"Items":[]}', 200));
    await pending;
    repository.dispose();
  });
}

final class _Client extends http.BaseClient {
  _Client(this.handler);
  final FutureOr<http.Response> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
        Stream.value(response.bodyBytes), response.statusCode,
        headers: response.headers, request: request);
  }
}
