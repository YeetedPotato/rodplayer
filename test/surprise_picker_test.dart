import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/discovery/surprise_picker.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';

import 'test_support.dart';

void main() {
  test('unwatched movies select an indexed row from the reported population',
      () async {
    final client = _PickerClient(
      movies: List<JellyfinLibraryItem>.generate(
        20,
        (index) => _item('movie-$index'),
      ),
    );
    final result = await SurprisePicker(
      client: client,
      random: _FixedRandom(19),
    ).pick(mode: SurpriseMode.unwatchedMovies);

    expect(result?.id, 'movie-19');
    expect(client.calls.first.kind, JellyfinLibraryKind.movies);
    expect(client.calls.first.filter, JellyfinLibraryFilter.unplayed);
    expect(client.calls.first.limit, 1);
    expect(client.calls.last.startIndex, 19);
    expect(client.calls.last.startIndex, inInclusiveRange(0, 19));
  });

  test('unwatched shows query only unplayed Series', () async {
    final client = _PickerClient(
      shows: <JellyfinLibraryItem>[_item('series-0', type: 'Series')],
    );
    final result = await SurprisePicker(
      client: client,
      random: _FixedRandom(0),
    ).pick(mode: SurpriseMode.unwatchedShows);

    expect(result?.id, 'series-0');
    expect(result?.kind, JellyfinItemKind.series);
    expect(client.calls, hasLength(1));
    expect(client.calls.single.kind, JellyfinLibraryKind.tvShows);
    expect(client.calls.single.filter, JellyfinLibraryFilter.unplayed);
  });

  test('favorites weight Movie and Series rows by their actual counts',
      () async {
    final client = _PickerClient(
      movies: <JellyfinLibraryItem>[
        _item('movie-0'),
        _item('movie-1'),
      ],
      shows: <JellyfinLibraryItem>[
        _item('series-0', type: 'Series'),
        _item('series-1', type: 'Series'),
        _item('series-2', type: 'Series'),
      ],
    );

    final firstMovie = await SurprisePicker(
      client: client,
      random: _FixedRandom(0),
    ).pick(mode: SurpriseMode.favorites);
    final firstShow = await SurprisePicker(
      client: client,
      random: _FixedRandom(2),
    ).pick(mode: SurpriseMode.favorites);

    expect(firstMovie?.id, 'movie-0');
    expect(firstShow?.id, 'series-0');
    expect(firstShow?.kind, JellyfinItemKind.series);
    expect(
        client.calls
            .every((call) => call.filter == JellyfinLibraryFilter.favorites),
        isTrue);
    expect(
      client.calls
          .where((call) => call.startIndex == 0)
          .map((call) => call.kind),
      containsAll(<JellyfinLibraryKind>[
        JellyfinLibraryKind.movies,
        JellyfinLibraryKind.tvShows,
      ]),
    );
  });

  test('zero population is known exhaustion', () async {
    final result = await SurprisePicker(
      client: _PickerClient(),
      random: _FixedRandom(0),
    ).pick(mode: SurpriseMode.unwatchedMovies);
    expect(result, isNull);
  });

  test('supported modes are limited to the three truthful populations', () {
    expect(
      SurpriseMode.values.map((mode) => mode.label),
      <String>[
        'Unwatched movies',
        'Unwatched shows',
        'Favorite movies and shows',
      ],
    );
  });

  test('single-item population exhausts only after the known item is shown',
      () async {
    final client = _PickerClient(movies: <JellyfinLibraryItem>[_item('only')]);
    final picker = SurprisePicker(client: client, random: _FixedRandom(0));
    final first = await picker.pick(mode: SurpriseMode.unwatchedMovies);
    final second = await picker.pick(
      mode: SurpriseMode.unwatchedMovies,
      excludedItemIds: <String>{first!.id},
    );

    expect(first.id, 'only');
    expect(second, isNull);
  });

  test('Another skips already-seen rows and continues with a new index',
      () async {
    final client = _PickerClient(
      movies: List<JellyfinLibraryItem>.generate(
        3,
        (index) => _item('movie-$index'),
      ),
    );
    final result = await SurprisePicker(
      client: client,
      random: _SequenceRandom(<int>[0, 1]),
    ).pick(
      mode: SurpriseMode.unwatchedMovies,
      excludedItemIds: const <String>{'movie-0'},
    );

    expect(result?.id, 'movie-1');
    expect(client.calls.last.startIndex, 1);
  });

  test('known all-excluded population returns exhaustion', () async {
    final client = _PickerClient(
      movies: <JellyfinLibraryItem>[_item('movie-0'), _item('movie-1')],
    );
    final result = await SurprisePicker(
      client: client,
      random: _FixedRandom(0),
    ).pick(
      mode: SurpriseMode.unwatchedMovies,
      excludedItemIds: const <String>{'movie-0', 'movie-1'},
    );

    expect(result, isNull);
    expect(client.calls.any((call) => call.limit == 2), isTrue);
  });

  test('unrelated excluded IDs cannot falsely claim exhaustion', () async {
    final client = _PickerClient(
      movies: <JellyfinLibraryItem>[_item('movie-0'), _item('movie-1')],
    );
    final result = await SurprisePicker(
      client: client,
      random: _FixedRandom(1),
    ).pick(
      mode: SurpriseMode.unwatchedMovies,
      excludedItemIds: const <String>{'other-0', 'other-1'},
    );

    expect(result?.id, 'movie-1');
  });

  test('random collisions fail unavailable instead of false exhaustion',
      () async {
    final client = _PickerClient(
      movies: <JellyfinLibraryItem>[_item('movie-0'), _item('movie-1')],
    );

    await expectLater(
      SurprisePicker(client: client, random: _FixedRandom(0)).pick(
        mode: SurpriseMode.unwatchedMovies,
        excludedItemIds: const <String>{'movie-0'},
      ),
      throwsA(isA<SurpriseSelectionUnavailableException>()),
    );
  });

  test('missing total count fails safely instead of using a biased page',
      () async {
    final client = _PickerClient(
      movies: <JellyfinLibraryItem>[_item('movie-0')],
      omitTotalCount: true,
    );

    await expectLater(
      SurprisePicker(client: client, random: _FixedRandom(0))
          .pick(mode: SurpriseMode.unwatchedMovies),
      throwsA(isA<SurpriseSelectionUnavailableException>()),
    );
    expect(client.calls, hasLength(1));
  });
}

class _FixedRandom implements Random {
  const _FixedRandom(this.offset);

  final int offset;

  @override
  int nextInt(int max) {
    if (offset < 0 || offset >= max) {
      throw RangeError.range(offset, 0, max - 1);
    }
    return offset;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

class _SequenceRandom implements Random {
  _SequenceRandom(this.offsets);

  final List<int> offsets;
  int _index = 0;

  @override
  int nextInt(int max) {
    final value = offsets[_index++];
    if (value < 0 || value >= max) {
      throw RangeError.range(value, 0, max - 1);
    }
    return value;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

JellyfinLibraryItem _item(String id, {String type = 'Movie'}) =>
    JellyfinLibraryItem.fromJson(
      <String, dynamic>{'Id': id, 'Name': id, 'Type': type},
    );

class _LibraryCall {
  const _LibraryCall(this.kind, this.filter, this.startIndex, this.limit);

  final JellyfinLibraryKind kind;
  final JellyfinLibraryFilter filter;
  final int startIndex;
  final int limit;
}

class _PickerClient extends JellyfinApiClient {
  _PickerClient({
    this.movies = const <JellyfinLibraryItem>[],
    this.shows = const <JellyfinLibraryItem>[],
    this.omitTotalCount = false,
  }) : super(
          baseUrl: 'https://server/jellyfin',
          identity: testIdentity,
          client:
              http_testing.MockClient((_) async => http.Response('{}', 200)),
        );

  final List<JellyfinLibraryItem> movies;
  final List<JellyfinLibraryItem> shows;
  final bool omitTotalCount;
  final calls = <_LibraryCall>[];

  @override
  Future<JellyfinItemsPage<JellyfinLibraryItem>> getLibraryItemsPage({
    required JellyfinLibraryKind kind,
    JellyfinLibrarySort sort = JellyfinLibrarySort.title,
    JellyfinLibraryFilter filter = JellyfinLibraryFilter.all,
    int startIndex = 0,
    int limit = 48,
    String? parentId,
  }) async {
    calls.add(_LibraryCall(kind, filter, startIndex, limit));
    final items = kind == JellyfinLibraryKind.movies ? movies : shows;
    final page = startIndex < items.length
        ? items.skip(startIndex).take(limit).toList(growable: false)
        : const <JellyfinLibraryItem>[];
    return JellyfinItemsPage<JellyfinLibraryItem>(
      items: page,
      totalRecordCount: omitTotalCount ? null : items.length,
      startIndex: startIndex,
    );
  }
}
