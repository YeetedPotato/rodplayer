import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/playback_info_request.dart';
import 'package:rodplayer/core/models/jellyfin_user_profile.dart';

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
      return http.Response(jsonEncode(<String, dynamic>{'Items': <Map<String, dynamic>>[]}), 200);
    });
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com/jellyfin', identity: testIdentity, client: mock)..userId = 'user';

    await client.getItemsPage();
    await client.getNextUp();
    await client.getItem('item');
    await client.getSearchItemsPage(query: 'star wars');

    expect(mock.requests[0].url.path, '/jellyfin/Items');
    expect(mock.requests[1].url.path, '/jellyfin/Shows/NextUp');
    expect(mock.requests[2].url.path, '/jellyfin/Users/user/Items/item');
    expect(mock.requests[3].url.path, '/jellyfin/Items');
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
    expect(mock.requests[1].url.queryParameters['Fields'], contains('Chapters'));
    expect(item.id, 'item');
  });

  test('getSeasons requests user-aware typed seasons', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{'Id': 'season 1', 'Name': 'Season 1', 'Type': 'Season'},
            <String, dynamic>{'Name': 'Missing ID', 'Type': 'Season'},
          ],
          'TotalRecordCount': 1,
          'StartIndex': 0,
        }), 200));
    final client = JellyfinApiClient(baseUrl: '$base/jellyfin', identity: testIdentity, client: mock)..userId = 'user';

    final seasons = await client.getSeasons(seriesId: 'series/id');

    final uri = mock.requests.single.url;
    expect(uri.path, '/jellyfin/Shows/series%2Fid/Seasons');
    expect(uri.queryParameters, containsPair('UserId', 'user'));
    expect(uri.queryParameters, containsPair('EnableImages', 'true'));
    expect(uri.queryParameters, containsPair('EnableUserData', 'true'));
    expect(uri.queryParameters['Fields'], contains('People'));
    expect(seasons.map((item) => item.title), <String>['Season 1', 'Missing ID']);
    expect(seasons.last.id, '');
  });

  test('getEpisodes requests exact season without arbitrary limit', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{'Id': 'e1', 'Name': 'Episode 1', 'Type': 'Episode', 'SeriesName': 'Show', 'ParentIndexNumber': 1, 'IndexNumber': 1},
            <String, dynamic>{'Id': 'e2', 'Name': 'Episode 2', 'Type': 'Episode', 'SeriesName': 'Show', 'ParentIndexNumber': 1, 'IndexNumber': 2},
          ],
        }), 200));
    final client = JellyfinApiClient(baseUrl: '$base/jellyfin', identity: testIdentity, client: mock)..userId = 'user';

    final episodes = await client.getEpisodes(seriesId: 'series/id', seasonId: 'season id');

    final uri = mock.requests.single.url;
    expect(uri.path, '/jellyfin/Shows/series%2Fid/Episodes');
    expect(uri.queryParameters, containsPair('UserId', 'user'));
    expect(uri.queryParameters, containsPair('SeasonId', 'season id'));
    expect(uri.queryParameters, containsPair('EnableImages', 'true'));
    expect(uri.queryParameters, containsPair('EnableUserData', 'true'));
    expect(uri.queryParameters.containsKey('Limit'), isFalse);
    expect(episodes.map((item) => item.episodeNumber), <int?>[1, 2]);
  });

  test('paged search maps types genre paging and keeps relevance ordering', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{'Id': 'movie', 'Name': 'A Movie', 'Type': 'Movie'}
          ],
          'TotalRecordCount': 9,
          'StartIndex': 4,
        }), 200));
    final client = JellyfinApiClient(baseUrl: '$base/jellyfin', identity: testIdentity, client: mock)..userId = 'user';

    final page = await client.getSearchItemsPage(query: 'star wars', type: JellyfinSearchType.tvShows, genre: 'Sci Fi', startIndex: 4, limit: 8);

    final uri = mock.requests.single.url;
    expect(uri.path, '/jellyfin/Items');
    expect(uri.queryParameters, containsPair('UserId', 'user'));
    expect(uri.queryParameters, containsPair('SearchTerm', 'star wars'));
    expect(uri.queryParameters, containsPair('IncludeItemTypes', 'Series'));
    expect(uri.queryParameters, containsPair('Recursive', 'true'));
    expect(uri.queryParameters, containsPair('StartIndex', '4'));
    expect(uri.queryParameters, containsPair('Limit', '8'));
    expect(uri.queryParameters, containsPair('EnableTotalRecordCount', 'true'));
    expect(uri.queryParameters, containsPair('EnableImages', 'true'));
    expect(uri.queryParameters, containsPair('EnableUserData', 'true'));
    expect(uri.queryParameters, containsPair('Genres', 'Sci Fi'));
    expect(uri.queryParameters.containsKey('SortBy'), isFalse);
    expect(page.totalRecordCount, 9);
    expect(page.startIndex, 4);
    expect(page.items.single.title, 'A Movie');
  });

  test('search type mappings are typed', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{'Items': <Map<String, dynamic>>[]}), 200));
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: mock)..userId = 'user';

    for (final type in JellyfinSearchType.values) {
      await client.getSearchItemsPage(query: 'x', type: type);
    }

    expect(mock.requests.map((request) => request.url.queryParameters['IncludeItemTypes']), <String>['Movie,Series,Episode,Audio', 'Movie', 'Series', 'Episode', 'Audio']);
  });

  test('discovery page maps kind sort genre and base path', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{'Id': 'series', 'Name': 'Show', 'Type': 'Series'}
          ],
          'TotalRecordCount': 3,
          'StartIndex': 2,
        }), 200));
    final client = JellyfinApiClient(baseUrl: '$base/jellyfin', identity: testIdentity, client: mock)..userId = 'user';

    final page = await client.getDiscoveryItemsPage(kind: JellyfinDiscoveryKind.tvShows, sort: JellyfinDiscoverySort.releaseDate, genre: 'Drama', startIndex: 2, limit: 6);

    final uri = mock.requests.single.url;
    expect(uri.path, '/jellyfin/Items');
    expect(uri.queryParameters, containsPair('IncludeItemTypes', 'Series'));
    expect(uri.queryParameters, containsPair('SortBy', 'PremiereDate'));
    expect(uri.queryParameters, containsPair('SortOrder', 'Descending'));
    expect(uri.queryParameters, containsPair('Genres', 'Drama'));
    expect(uri.queryParameters, containsPair('StartIndex', '2'));
    expect(uri.queryParameters, containsPair('Limit', '6'));
    expect(page.totalRecordCount, 3);
    expect(page.startIndex, 2);
    expect(page.items.single.title, 'Show');
  });

  test('discovery sort mappings are typed', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{'Items': <Map<String, dynamic>>[]}), 200));
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: mock)..userId = 'user';

    for (final sort in JellyfinDiscoverySort.values) {
      await client.getDiscoveryItemsPage(kind: JellyfinDiscoveryKind.movies, sort: sort);
    }

    expect(mock.requests.map((request) => request.url.queryParameters['SortBy']), <String>['CommunityRating', 'DateCreated', 'PremiereDate']);
  });

  test('genres request video scope and parses non-empty names', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{'Name': 'Drama'},
            <String, dynamic>{'Name': ''},
            <String, dynamic>{},
          ],
        }), 200));
    final client = JellyfinApiClient(baseUrl: '$base/jellyfin', identity: testIdentity, client: mock)..userId = 'user';

    final genres = await client.getGenres();

    final uri = mock.requests.single.url;
    expect(uri.path, '/jellyfin/Genres');
    expect(uri.queryParameters, containsPair('UserId', 'user'));
    expect(uri.queryParameters, containsPair('IncludeItemTypes', 'Movie,Series'));
    expect(uri.queryParameters, containsPair('SortBy', 'SortName'));
    expect(genres, <String>['Drama']);
    expect(() => genres.add('x'), throwsUnsupportedError);
  });

  test('similar items use encoded item path and preserve returned order', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{
          'Items': <Map<String, dynamic>>[
            <String, dynamic>{'Id': 'a', 'Name': 'A', 'Type': 'Movie'},
            <String, dynamic>{'Id': 'b', 'Name': 'B', 'Type': 'Movie'},
          ],
        }), 200));
    final client = JellyfinApiClient(baseUrl: '$base/jellyfin', identity: testIdentity, client: mock)..userId = 'user';

    final items = await client.getSimilarItems(itemId: 'item/id', limit: 7);

    final uri = mock.requests.single.url;
    expect(uri.path, '/jellyfin/Items/item%2Fid/Similar');
    expect(uri.queryParameters, containsPair('UserId', 'user'));
    expect(uri.queryParameters, containsPair('Limit', '7'));
    expect(uri.queryParameters['Fields'], contains('People'));
    expect(items.map((item) => item.id), <String>['a', 'b']);
  });

  test('getPlaybackInfo returns DTO and does not choose best stream', () async {
    final client = JellyfinApiClient(baseUrl: base, identity: testIdentity, client: MockClient((request) async => http.Response(jsonEncode(<String, dynamic>{'PlaySessionId': 'play', 'MediaSources': <Map<String, dynamic>>[<String, dynamic>{'Id': 'source', 'MediaStreams': <dynamic>[] }]}), 200)))..userId = 'user';
    final response = await client.getPlaybackInfo(const PlaybackInfoRequest(itemId: 'item', deviceProfile: <String, dynamic>{'Name': 'RodPlayer'}));
    expect(response.playSessionId, 'play');
    expect(response.mediaSources.single.id, 'source');
  });

  test('user profile endpoints map routes bodies and session logout', () async {
    final seen = <http.BaseRequest>[];
    final client = JellyfinApiClient(
      baseUrl: '$base/jellyfin',
      identity: testIdentity,
      client: MockClient((request) async {
        seen.add(request);
        if (request.url.path == '/jellyfin/Users/user%20id') return http.Response(jsonEncode(<String, dynamic>{'Id': 'user id', 'Name': 'Current', 'Configuration': <String, dynamic>{'GroupedFolders': <String>['keep']}}), 200);
        if (request.url.path == '/jellyfin/Users/Public') return http.Response(jsonEncode(<Map<String, dynamic>>[<String, dynamic>{'Id': 'a', 'Name': 'A'}, <String, dynamic>{'Id': 'b', 'Name': 'B'}]), 200);
        if (request.url.path == '/jellyfin/Users/Configuration') {
          final body = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
          expect(request.url.queryParameters['userId'], 'user id');
          expect(body['GroupedFolders'], <String>['keep']);
          expect(body['AudioLanguagePreference'], 'eng');
          return http.Response('', 204);
        }
        if (request.url.path == '/jellyfin/Sessions/Logout') return http.Response('', 204);
        return http.Response('missing', 404);
      }),
    )..userId = 'user id';

    expect((await client.getCurrentUser()).name, 'Current');
    client.userId = null;
    expect((await client.getPublicUsers()).map((user) => user.name), <String>['A', 'B']);
    client.userId = 'user id';
    await client.updateCurrentUserConfiguration(const JellyfinUserConfiguration(raw: <String, dynamic>{'GroupedFolders': <String>['keep']}, audioLanguagePreference: 'eng'));
    await client.reportSessionEnded();
    final image = client.userPrimaryImageUri(const JellyfinUserProfile(id: 'user id', name: 'A', primaryImageTag: 'tag'))!;
    expect(image.path, '/jellyfin/Users/user%20id/Images/Primary');
    expect(image.queryParameters['tag'], 'tag');
    expect(seen.map((request) => request.url.path), containsAll(<String>['/jellyfin/Users/user%20id', '/jellyfin/Users/Public', '/jellyfin/Users/Configuration', '/jellyfin/Sessions/Logout']));
  });

  test('configuration update falls back only for missing modern route', () async {
    var calls = 0;
    final client = JellyfinApiClient(
      baseUrl: base,
      identity: testIdentity,
      client: MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response('', 404);
        expect(request.url.path, '/Users/user/Configuration');
        return http.Response('', 204);
      }),
    )..userId = 'user';
    await client.updateCurrentUserConfiguration(const JellyfinUserConfiguration());
    expect(calls, 2);
  });

  test('setFavorite uses modern route and only falls back on missing method', () async {
    final paths = <String>[];
    final methods = <String>[];
    final client = JellyfinApiClient(
      baseUrl: '$base/jellyfin',
      identity: testIdentity,
      client: MockClient((request) async {
        paths.add('${request.method} ${request.url.path}?${request.url.query}');
        methods.add(request.method);
        if (paths.length == 1) return http.Response('', 204);
        if (paths.length == 2) return http.Response('', 404);
        return http.Response('', 204);
      }),
    )..userId = 'user id';

    await client.setFavorite(itemId: 'item/id', isFavorite: true);
    await client.setFavorite(itemId: 'item/id', isFavorite: false);

    expect(paths[0], 'POST /jellyfin/UserFavoriteItems/item%2Fid?userId=user+id');
    expect(paths[1], 'DELETE /jellyfin/UserFavoriteItems/item%2Fid?userId=user+id');
    expect(paths[2], 'DELETE /jellyfin/Users/user%20id/FavoriteItems/item%2Fid?');
    expect(methods, <String>['POST', 'DELETE', 'DELETE']);
  });

  test('setPlayed maps watched routes and does not fallback on validation errors', () async {
    var calls = 0;
    final client = JellyfinApiClient(
      baseUrl: base,
      identity: testIdentity,
      client: MockClient((request) async {
        calls++;
        expect(request.url.path, '/UserPlayedItems/item%20id');
        expect(request.url.queryParameters['userId'], 'user');
        return http.Response('', 400);
      }),
    )..userId = 'user';

    await expectLater(client.setPlayed(itemId: 'item id', played: true), throwsA(isA<ServerConnectionException>()));
    expect(calls, 1);
  });

  test('user-data mutations use modern methods and fallback matrix', () async {
    for (final operation in <String>['favorite', 'played']) {
      for (final enabled in <bool>[true, false]) {
        final seen = <String>[];
        final client = JellyfinApiClient(
          baseUrl: '$base/jellyfin',
          identity: testIdentity,
          client: MockClient((request) async {
            seen.add('${request.method} ${request.url.path}?${request.url.query}');
            return http.Response('', 204);
          }),
        )..userId = 'user id';
        if (operation == 'favorite') {
          await client.setFavorite(itemId: 'item/id', isFavorite: enabled);
        } else {
          await client.setPlayed(itemId: 'item/id', played: enabled);
        }
        final route = operation == 'favorite' ? 'UserFavoriteItems' : 'UserPlayedItems';
        expect(seen.single, '${enabled ? 'POST' : 'DELETE'} /jellyfin/$route/item%2Fid?userId=user+id');
      }

      for (final status in <int>[404, 405]) {
        final seen = <String>[];
        final client = JellyfinApiClient(
          baseUrl: '$base/jellyfin',
          identity: testIdentity,
          client: MockClient((request) async {
            seen.add('${request.method} ${request.url.path}?${request.url.query}');
            return http.Response('', seen.length == 1 ? status : 204);
          }),
        )..userId = 'user id';
        if (operation == 'favorite') {
          await client.setFavorite(itemId: 'item/id', isFavorite: true);
        } else {
          await client.setPlayed(itemId: 'item/id', played: true);
        }
        final modernRoute = operation == 'favorite' ? 'UserFavoriteItems' : 'UserPlayedItems';
        final legacyRoute = operation == 'favorite' ? 'FavoriteItems' : 'PlayedItems';
        expect(seen, <String>[
          'POST /jellyfin/$modernRoute/item%2Fid?userId=user+id',
          'POST /jellyfin/Users/user%20id/$legacyRoute/item%2Fid?',
        ]);
      }

      for (final status in <int>[400, 401, 403, 409, 500]) {
        var calls = 0;
        final client = JellyfinApiClient(
          baseUrl: base,
          identity: testIdentity,
          client: MockClient((request) async {
            calls++;
            return http.Response('', status);
          }),
        )..userId = 'user';
        final future = operation == 'favorite' ? client.setFavorite(itemId: 'item', isFavorite: true) : client.setPlayed(itemId: 'item', played: true);
        await expectLater(future, throwsA(isA<ServerConnectionException>()));
        expect(calls, 1);
      }
    }
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


  test('getMediaSegments preserves base path, item identity, auth, and QueryResult parsing', () async {
    final mock = MockClient((request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'Items': <Map<String, dynamic>>[
              <String, dynamic>{
                'Id': 'segment-id',
                'ItemId': 'item/id',
                'Type': 'Intro',
                'StartTicks': 10000000,
                'EndTicks': 30000000,
              },
            ],
            'TotalRecordCount': 1,
            'StartIndex': 0,
          }),
          200,
        ));
    final client = JellyfinApiClient(
      baseUrl: '$base/jellyfin',
      identity: testIdentity,
      client: mock,
    )
      ..accessToken = 'Bearer secret'
      ..userId = 'must-not-be-sent';

    final segments = await client.getMediaSegments(itemId: 'item/id');

    final request = mock.requests.single;
    expect(request.url.path, '/jellyfin/MediaSegments/item%2Fid');
    expect(request.url.queryParameters, isEmpty);
    expect(request.url.queryParameters.containsKey('UserId'), isFalse);
    expect(request.headers['Authorization'], contains('Token="secret"'));
    expect(segments, isNotNull);
    expect(segments, hasLength(1));
    final segment = segments!.single;
    expect(segment.id, 'segment-id');
    expect(segment.itemId, 'item/id');
    expect(segment.type, 'Intro');
    expect(segment.start, const Duration(seconds: 1));
    expect(segment.end, const Duration(seconds: 3));
  });

  test('getMediaSegments treats successful empty Items as authoritative empty', () async {
    final client = JellyfinApiClient(
      baseUrl: base,
      identity: testIdentity,
      client: MockClient((_) async => http.Response(
            jsonEncode(<String, dynamic>{
              'Items': <dynamic>[],
              'TotalRecordCount': 0,
              'StartIndex': 0,
            }),
            200,
          )),
    );

    final segments = await client.getMediaSegments(itemId: 'item');
    expect(segments, isNotNull);
    expect(segments, isEmpty);
  });

  test('getMediaSegments treats 404 and 405 as endpoint unavailable', () async {
    for (final status in <int>[404, 405]) {
      final client = JellyfinApiClient(
        baseUrl: base,
        identity: testIdentity,
        client: MockClient((_) async => http.Response('', status)),
      );
      expect(await client.getMediaSegments(itemId: 'item'), isNull);
    }
  });

  test('getMediaSegments surfaces non-availability HTTP failures', () async {
    final client = JellyfinApiClient(
      baseUrl: base,
      identity: testIdentity,
      client: MockClient((_) async => http.Response('failure', 500)),
    );

    await expectLater(
      client.getMediaSegments(itemId: 'item'),
      throwsA(isA<ServerConnectionException>()),
    );
  });

  test('getMediaSegments rejects malformed QueryResult without Items', () async {
    final client = JellyfinApiClient(
      baseUrl: base,
      identity: testIdentity,
      client: MockClient((_) async => http.Response(
            jsonEncode(<String, dynamic>{
              'TotalRecordCount': 0,
              'StartIndex': 0,
            }),
            200,
          )),
    );

    await expectLater(
      client.getMediaSegments(itemId: 'item'),
      throwsA(isA<ServerConnectionException>()),
    );
  });
}
