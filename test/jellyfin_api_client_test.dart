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

  test('content endpoints use authenticated user and typed parsing', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{'Id': 'item', 'Name': 'Film', 'Type': 'Movie'}
          ],
          'TotalRecordCount': 1,
          'StartIndex': 0,
        }), 200));
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: mock)..userId = 'user';

    final page = await client.getItemsPage(limit: 1);

    expect(mock.requests.single.url.path, '/Items');
    expect(mock.requests.single.url.queryParameters, containsPair('UserId', 'user'));
    expect(page.totalRecordCount, 1);
    expect(page.startIndex, 0);
    expect(page.items.single.title, 'Film');
  });

  test('content endpoints preserve configured base path', () async {
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/Items/item')) return http.Response(jsonEncode(<String, dynamic>{'Id': 'item', 'Name': 'Film'}), 200);
      if (request.url.path.endsWith('/Search/Hints')) return http.Response(jsonEncode(<String, dynamic>{'SearchHints': <Map<String, dynamic>>[]}), 200);
      return http.Response(jsonEncode(<String, dynamic>{'Items': <Map<String, dynamic>>[]}), 200);
    });
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com/jellyfin', identity: testIdentity, client: mock)..userId = 'user';

    await client.getItemsPage();
    await client.getNextUp();
    await client.getItem('item');
    await client.search(query: 'star wars');

    expect(mock.requests[0].url.path, '/jellyfin/Items');
    expect(mock.requests[1].url.path, '/jellyfin/Shows/NextUp');
    expect(mock.requests[2].url.path, '/jellyfin/Users/user/Items/item');
    expect(mock.requests[3].url.path, '/jellyfin/Search/Hints');
  });

  test('resume and next up endpoints use authenticated user', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{'Items': <Map<String, dynamic>>[]}), 200));
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: mock)..userId = 'user';

    await client.getResumeItems();
    await client.getNextUp();

    expect(mock.requests[0].url.path, '/Items');
    expect(mock.requests[0].url.queryParameters, containsPair('Filters', 'IsResumable'));
    expect(mock.requests[0].url.queryParameters, containsPair('UserId', 'user'));
    expect(mock.requests[1].url.path, '/Shows/NextUp');
    expect(mock.requests[1].url.queryParameters, containsPair('UserId', 'user'));
  });

  test('latest movies and TV request specific item types', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{'Items': <Map<String, dynamic>>[]}), 200));
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: mock)..userId = 'user';

    await client.getLatestMovies();
    await client.getLatestTvShows();

    expect(mock.requests[0].url.queryParameters, containsPair('IncludeItemTypes', 'Movie'));
    expect(mock.requests[1].url.queryParameters, containsPair('IncludeItemTypes', 'Series'));
  });

  test('library page query maps kind sort filter paging and base path', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{'Id': 'movie', 'Name': 'Film', 'Type': 'Movie'}
          ],
          'TotalRecordCount': 10,
          'StartIndex': 5,
        }), 200));
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com/jellyfin', identity: testIdentity, client: mock)..userId = 'user';

    final page = await client.getLibraryItemsPage(
      kind: JellyfinLibraryKind.movies,
      sort: JellyfinLibrarySort.title,
      filter: JellyfinLibraryFilter.unplayed,
      startIndex: 5,
      limit: 7,
      parentId: 'parent id',
    );

    final uri = mock.requests.single.url;
    expect(uri.path, '/jellyfin/Items');
    expect(uri.queryParameters, containsPair('UserId', 'user'));
    expect(uri.queryParameters, containsPair('IncludeItemTypes', 'Movie'));
    expect(uri.queryParameters, containsPair('Recursive', 'true'));
    expect(uri.queryParameters, containsPair('StartIndex', '5'));
    expect(uri.queryParameters, containsPair('Limit', '7'));
    expect(uri.queryParameters, containsPair('EnableTotalRecordCount', 'true'));
    expect(uri.queryParameters, containsPair('SortBy', 'SortName'));
    expect(uri.queryParameters, containsPair('SortOrder', 'Ascending'));
    expect(uri.queryParameters, containsPair('Filters', 'IsUnplayed'));
    expect(uri.queryParameters, containsPair('ParentId', 'parent id'));
    expect(page.totalRecordCount, 10);
    expect(page.startIndex, 5);
    expect(page.items.single.title, 'Film');
  });

  test('library sorts and filters map to Jellyfin query values', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{'Items': <Map<String, dynamic>>[]}), 200));
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: mock)..userId = 'user';

    await client.getLibraryItemsPage(kind: JellyfinLibraryKind.tvShows, sort: JellyfinLibrarySort.recentlyAdded);
    await client.getLibraryItemsPage(kind: JellyfinLibraryKind.movies, sort: JellyfinLibrarySort.releaseDate);
    await client.getLibraryItemsPage(kind: JellyfinLibraryKind.movies, sort: JellyfinLibrarySort.communityRating, filter: JellyfinLibraryFilter.favorites);

    expect(mock.requests[0].url.queryParameters, containsPair('IncludeItemTypes', 'Series'));
    expect(mock.requests[0].url.queryParameters, containsPair('SortBy', 'DateCreated'));
    expect(mock.requests[0].url.queryParameters, containsPair('SortOrder', 'Descending'));
    expect(mock.requests[1].url.queryParameters, containsPair('SortBy', 'PremiereDate'));
    expect(mock.requests[2].url.queryParameters, containsPair('SortBy', 'CommunityRating'));
    expect(mock.requests[2].url.queryParameters, containsPair('Filters', 'IsFavorite'));
  });

  test('user views and getItem use user-aware endpoints', () async {
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/Views')) return http.Response(jsonEncode(<String, dynamic>{'Items': <Map<String, dynamic>>[]}), 200);
      return http.Response(jsonEncode(<String, dynamic>{'Id': 'item', 'Name': 'Film'}), 200);
    });
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: mock)..userId = 'user';

    await client.getUserViews();
    final item = await client.getItem('item');

    expect(mock.requests[0].url.path, '/Users/user/Views');
    expect(mock.requests[1].url.path, '/Users/user/Items/item');
    expect(item.id, 'item');
  });

  test('search encodes term and returns typed hints', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{
          'SearchHints': <Map<String, dynamic>>[
            <String, dynamic>{'ItemId': 'movie', 'Name': 'A Movie', 'Type': 'Movie'}
          ],
        }), 200));
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: mock)..userId = 'user';

    final results = await client.search(query: 'star wars');

    expect(mock.requests.single.url.path, '/Search/Hints');
    expect(mock.requests.single.url.queryParameters, containsPair('SearchTerm', 'star wars'));
    expect(results.single.id, 'movie');
    expect(results.single.title, 'A Movie');
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
