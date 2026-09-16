import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/item_details_screen.dart';

import 'test_support.dart';

void main() {
  Widget app(Widget child, {Size size = const Size(900, 720), double textScale = 1}) => MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(theme: rodPlayerThemeData(), home: child),
      );

  testWidgets('loading item error and retry are scoped', (tester) async {
    final client = _DetailClient(item: _movie('m', 'Recovered'), failItemOnce: true);
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'm')));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Details unavailable'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered'), findsWidgets);
  });

  testWidgets('movie details show metadata and use injected playback seam', (tester) async {
    String? played;
    await tester.pumpWidget(app(ItemDetailsScreen(client: _DetailClient(item: _movie('movie', 'A Movie', progress: 42)), itemId: 'movie', onPlayItem: (_, id) => played = id)));
    await tester.pumpAndSettle();

    expect(find.text('A Movie'), findsWidgets);
    expect(find.textContaining('Tagline'), findsOneWidget);
    expect(find.textContaining('Studios: Studio'), findsOneWidget);
    expect(find.textContaining('Cast: Actor'), findsOneWidget);
    expect(find.textContaining('2024-01-02'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    expect(played, 'movie');

    await tester.pumpWidget(app(ItemDetailsScreen(client: _DetailClient(item: _movie('zero', 'Zero', progress: 0)), itemId: 'zero')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);
  });

  testWidgets('favorite and watched actions update state and emit changes', (tester) async {
    final changes = <JellyfinUserDataChange>[];
    final client = _DetailClient(item: JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': 'movie', 'Name': 'A Movie', 'Type': 'Movie'}));
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'movie', onUserDataChanged: changes.add)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add to favorites'));
    await tester.pumpAndSettle();
    expect(client.favoriteCalls, <String>['movie:true']);
    expect(find.widgetWithText(OutlinedButton, 'Remove from favorites'), findsOneWidget);
    expect(changes.last.isFavorite, isTrue);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark watched'));
    await tester.pumpAndSettle();
    expect(client.playedCalls, <String>['movie:true']);
    expect(find.widgetWithText(OutlinedButton, 'Mark unwatched'), findsOneWidget);
    expect(changes.last.played, isTrue);
  });

  testWidgets('mutation failure preserves old state and unsupported items expose no actions', (tester) async {
    final client = _DetailClient(item: _movie('movie', 'A Movie'), failFavoriteOnce: true);
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'movie')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add to favorites'));
    await tester.pumpAndSettle();
    expect(find.text('Could not update favorite'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Add to favorites'), findsOneWidget);

    await tester.pumpWidget(app(ItemDetailsScreen(client: _DetailClient(item: JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': '', 'Name': 'Folder', 'Type': 'Folder'})), itemId: 'folder')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Add to favorites'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Mark watched'), findsNothing);
  });

  testWidgets('item replacement clears stale favorite and watched busy states', (tester) async {
    final favorite = Completer<void>();
    final first = _DetailClient(
      item: _movie('first', 'First'),
      pendingFavorite: favorite,
    );
    final second = _DetailClient(item: _movie('second', 'Second'));

    await tester.pumpWidget(
      app(ItemDetailsScreen(client: first, itemId: 'first')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Add to favorites'),
    );
    await tester.pump();

    await tester.pumpWidget(
      app(ItemDetailsScreen(client: second, itemId: 'second')),
    );
    await tester.pumpAndSettle();

    var favoriteButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Add to favorites'),
    );
    expect(favoriteButton.onPressed, isNotNull);

    favorite.complete();
    await tester.pumpAndSettle();

    final watched = Completer<void>();
    final third = _DetailClient(
      item: _movie('third', 'Third'),
      pendingPlayed: watched,
    );
    final fourth = _DetailClient(item: _movie('fourth', 'Fourth'));

    await tester.pumpWidget(
      app(ItemDetailsScreen(client: third, itemId: 'third')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Mark watched'),
    );
    await tester.pump();

    await tester.pumpWidget(
      app(ItemDetailsScreen(client: fourth, itemId: 'fourth')),
    );
    await tester.pumpAndSettle();

    final watchedButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Mark watched'),
    );
    expect(watchedButton.onPressed, isNotNull);

    watched.complete();
    await tester.pumpAndSettle();
  });
  testWidgets('movie similar items load independently retry and open details', (tester) async {
    final client = _DetailClient(item: _movie('movie', 'A Movie'), similar: <JellyfinLibraryItem>[_movie('similar', 'Similar Movie')], failSimilarOnce: true);
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'movie')));
    await tester.pumpAndSettle();

    expect(client.similarRequests, <String>['movie']);
    expect(find.text('A Movie'), findsWidgets);
    expect(find.text('Similar items unavailable'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Retry').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Similar Movie'), 260, scrollable: find.byType(Scrollable).first);
    expect(find.text('Similar Movie'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Similar Movie'));
    await tester.pumpAndSettle();
    expect(client.itemRequests.last, 'similar');
    expect(find.byType(ItemDetailsScreen), findsOneWidget);
  });

  testWidgets('series seasons and episodes stay scoped and playable only at episode level', (tester) async {
    String? played;
    final client = _DetailClient(
      item: _series('series', 'A Series'),
      seasons: <JellyfinLibraryItem>[_season('', 'Broken'), _season('s1', ''), _season('s2', 'Second Season'), _season('s2', 'Duplicate')],
      episodesBySeason: <String, List<JellyfinLibraryItem>>{
        's1': <JellyfinLibraryItem>[_episode('e1', 'Episode One', season: 1, episode: 1)],
        's2': <JellyfinLibraryItem>[_episode('e2', 'Episode Two', season: 2, episode: 1, progress: 50)],
      },
    );
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'series', onPlayItem: (_, id) => played = id)));
    await tester.pumpAndSettle();

    expect(client.seasonRequests, <String>['series']);
    expect(client.episodeRequests, <String>['s1']);
    expect(find.widgetWithText(FilledButton, 'Play'), findsNothing);
    expect(find.text('Specials'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Episode One'), 260, scrollable: find.byType(Scrollable).first);
    expect(find.text('Episode One'), findsOneWidget);
    tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).onChanged?.call('s2');
    await tester.pumpAndSettle();
    expect(client.episodeRequests.last, 's2');
    await tester.scrollUntilVisible(find.text('Episode Two'), 260, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Episode Two'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A Series'), findsWidgets);
    expect(find.textContaining('S02E01'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    expect(played, 'e2');
  });

  testWidgets('similar requests are scoped by item type id and stale generation', (tester) async {
    final oldItem = Completer<JellyfinLibraryItem>();
    final oldSimilar = Completer<List<JellyfinLibraryItem>>();
    final client = _DetailClient(item: _movie('new', 'New'), pendingItems: <String, Completer<JellyfinLibraryItem>>{'old': oldItem}, pendingSimilar: <String, Completer<List<JellyfinLibraryItem>>>{'old': oldSimilar});
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'old')));
    await tester.pump();
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'new')));
    await tester.pumpAndSettle();
    oldItem.complete(_movie('old', 'Old'));
    oldSimilar.complete(<JellyfinLibraryItem>[_movie('stale', 'Stale Similar')]);
    await tester.pumpAndSettle();

    expect(find.text('New'), findsWidgets);
    expect(find.text('Stale Similar'), findsNothing);

    final seasonClient = _DetailClient(item: _season('season', 'Season'));
    await tester.pumpWidget(app(ItemDetailsScreen(client: seasonClient, itemId: 'season')));
    await tester.pumpAndSettle();
    expect(seasonClient.similarRequests, isEmpty);

    final emptyClient = _DetailClient(item: _movie('', 'No Id'));
    await tester.pumpWidget(app(ItemDetailsScreen(client: emptyClient, itemId: 'lookup')));
    await tester.pumpAndSettle();
    expect(emptyClient.similarRequests, isEmpty);
  });

  testWidgets('series with empty id and id-less seasons do not request invalid episodes', (tester) async {
    final emptySeriesClient = _DetailClient(item: _series('', 'Missing Id'));
    await tester.pumpWidget(app(ItemDetailsScreen(client: emptySeriesClient, itemId: 'lookup')));
    await tester.pumpAndSettle();
    expect(emptySeriesClient.seasonRequests, isEmpty);
    expect(find.text('No seasons found'), findsOneWidget);

    final idlessSeasonClient = _DetailClient(item: _series('series', 'Series'), seasons: <JellyfinLibraryItem>[_season('', 'Broken')]);
    await tester.pumpWidget(app(ItemDetailsScreen(client: idlessSeasonClient, itemId: 'series')));
    await tester.pumpAndSettle();
    expect(idlessSeasonClient.episodeRequests, isEmpty);
    expect(find.text('No selectable seasons found'), findsOneWidget);
  });

  testWidgets('season and episode failures retry without dropping series header', (tester) async {
    final client = _DetailClient(item: _series('series', 'Series'), seasons: <JellyfinLibraryItem>[_season('s1', 'Season 1')], episodesBySeason: <String, List<JellyfinLibraryItem>>{'s1': <JellyfinLibraryItem>[_episode('e1', 'Episode One')]}, failSeasonsOnce: true, failEpisodesOnce: true);
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'series')));
    await tester.pumpAndSettle();
    expect(find.text('Series'), findsWidgets);
    expect(find.text('Seasons unavailable'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Episodes unavailable'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Episode One'), 260, scrollable: find.byType(Scrollable).first);
    expect(find.text('Episode One'), findsOneWidget);
  });

  testWidgets('stale item and stale episode results are ignored', (tester) async {
    final oldItem = Completer<JellyfinLibraryItem>();
    final client = _DetailClient(item: _movie('new', 'New'), pendingItems: <String, Completer<JellyfinLibraryItem>>{'old': oldItem});
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'old')));
    await tester.pump();
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'new')));
    await tester.pumpAndSettle();
    oldItem.complete(_movie('old', 'Old'));
    await tester.pumpAndSettle();
    expect(find.text('New'), findsWidgets);
    expect(find.text('Old'), findsNothing);

    final s1 = Completer<List<JellyfinLibraryItem>>();
    final s2 = Completer<List<JellyfinLibraryItem>>();
    final seriesClient = _DetailClient(item: _series('series', 'Series'), seasons: <JellyfinLibraryItem>[_season('s1', 'Season 1'), _season('s2', 'Season 2')], pendingEpisodes: <String, Completer<List<JellyfinLibraryItem>>>{'s1': s1, 's2': s2});
    await tester.pumpWidget(app(ItemDetailsScreen(client: seriesClient, itemId: 'series')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).onChanged?.call('s2');
    await tester.pump();
    s2.complete(<JellyfinLibraryItem>[_episode('e2', 'Fresh')]);
    await tester.pumpAndSettle();
    s1.complete(<JellyfinLibraryItem>[_episode('e1', 'Stale')]);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Fresh'), 260, scrollable: find.byType(Scrollable).first);
    expect(find.text('Fresh'), findsOneWidget);
    expect(find.text('Stale'), findsNothing);
  });

  testWidgets('compact long metadata and directional focus are stable', (tester) async {
    final client = _DetailClient(item: _movie('m', 'A Very Long Movie Title That Should Wrap Without Overflow'));
    String? played;
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'm', onPlayItem: (_, id) => played = id), size: const Size(390, 760), textScale: 1.25));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(tester.takeException(), isNull);
    if (played != null) expect(played, 'm');
  });
}

JellyfinLibraryItem _movie(String id, String name, {double? progress}) => JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': id,
      'Name': name,
      'Type': 'Movie',
      'Taglines': <String>['Tagline'],
      'ProductionYear': 2024,
      'PremiereDate': '2024-01-02T00:00:00Z',
      'Overview': 'Movie overview',
      'RunTimeTicks': 54000000000,
      'Studios': <Map<String, dynamic>>[<String, dynamic>{'Name': 'Studio'}],
      'People': <Map<String, dynamic>>[<String, dynamic>{'Id': 'p1', 'Name': 'Actor', 'Role': 'Lead', 'Type': 'Actor'}],
      'Genres': <String>['Drama'],
      if (progress != null) 'UserData': <String, dynamic>{'PlayedPercentage': progress},
    });
JellyfinLibraryItem _series(String id, String name) => JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': id, 'Name': name, 'Type': 'Series', 'Status': 'Continuing', 'Overview': 'Series overview'});
JellyfinLibraryItem _season(String id, String name, {int? seasonNumber = 0}) => JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': id, 'Name': name, 'Type': 'Season', 'ParentIndexNumber': seasonNumber});
JellyfinLibraryItem _episode(String id, String name, {int? season, int? episode, double? progress}) => JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': id, 'Name': name, 'Type': 'Episode', 'SeriesName': 'A Series', 'SeasonName': 'Season Two', 'ParentIndexNumber': season, 'IndexNumber': episode, if (progress != null) 'UserData': <String, dynamic>{'PlayedPercentage': progress}});

class _DetailClient extends JellyfinApiClient {
  _DetailClient({
    required this.item,
    this.seasons = const <JellyfinLibraryItem>[],
    this.episodesBySeason = const <String, List<JellyfinLibraryItem>>{},
    this.similar = const <JellyfinLibraryItem>[],
    this.pendingItems = const <String, Completer<JellyfinLibraryItem>>{},
    this.pendingEpisodes = const <String, Completer<List<JellyfinLibraryItem>>>{},
    this.pendingSimilar = const <String, Completer<List<JellyfinLibraryItem>>>{},
    this.failItemOnce = false,
    this.failSeasonsOnce = false,
    this.failEpisodesOnce = false,
    this.failSimilarOnce = false,
    this.failFavoriteOnce = false,
    this.pendingFavorite,
    this.pendingPlayed,
  })
      : super(baseUrl: 'https://server/jellyfin', identity: testIdentity, client: http_testing.MockClient((_) async => http.Response('{}', 200)));
  final JellyfinLibraryItem item;
  final List<JellyfinLibraryItem> seasons;
  final Map<String, List<JellyfinLibraryItem>> episodesBySeason;
  final List<JellyfinLibraryItem> similar;
  final Map<String, Completer<JellyfinLibraryItem>> pendingItems;
  final Map<String, Completer<List<JellyfinLibraryItem>>> pendingEpisodes;
  final Map<String, Completer<List<JellyfinLibraryItem>>> pendingSimilar;
  bool failItemOnce, failSeasonsOnce, failEpisodesOnce, failSimilarOnce, failFavoriteOnce;
  final Completer<void>? pendingFavorite;
  final Completer<void>? pendingPlayed;
  final seasonRequests = <String>[];
  final episodeRequests = <String>[];
  final similarRequests = <String>[];
  final itemRequests = <String>[];
  final favoriteCalls = <String>[];
  final playedCalls = <String>[];

  @override
  Future<JellyfinLibraryItem> getItem(String itemId) {
    itemRequests.add(itemId);
    if (failItemOnce) {
      failItemOnce = false;
      return Future<JellyfinLibraryItem>.error(StateError('item failed'));
    }
    final pending = pendingItems[itemId];
    if (pending != null) return pending.future;
    for (final episodes in episodesBySeason.values) {
      for (final episode in episodes) {
        if (episode.id == itemId) return Future<JellyfinLibraryItem>.value(episode);
      }
    }
    return Future<JellyfinLibraryItem>.value(item);
  }

  @override
  Future<List<JellyfinLibraryItem>> getSeasons({required String seriesId}) {
    seasonRequests.add(seriesId);
    if (failSeasonsOnce) {
      failSeasonsOnce = false;
      return Future<List<JellyfinLibraryItem>>.error(StateError('seasons failed'));
    }
    return Future<List<JellyfinLibraryItem>>.value(seasons);
  }

  @override
  Future<List<JellyfinLibraryItem>> getEpisodes({required String seriesId, required String seasonId}) {
    episodeRequests.add(seasonId);
    if (failEpisodesOnce) {
      failEpisodesOnce = false;
      return Future<List<JellyfinLibraryItem>>.error(StateError('episodes failed'));
    }
    final pending = pendingEpisodes[seasonId];
    if (pending != null) return pending.future;
    return Future<List<JellyfinLibraryItem>>.value(episodesBySeason[seasonId] ?? const <JellyfinLibraryItem>[]);
  }

  @override
  Future<List<JellyfinLibraryItem>> getSimilarItems({required String itemId, int limit = 12}) {
    similarRequests.add(itemId);
    if (failSimilarOnce) {
      failSimilarOnce = false;
      return Future<List<JellyfinLibraryItem>>.error(StateError('similar failed'));
    }
    final pending = pendingSimilar[itemId];
    if (pending != null) return pending.future;
    return Future<List<JellyfinLibraryItem>>.value(similar);
  }

  @override
  Future<void> setFavorite({required String itemId, required bool isFavorite}) async {
    favoriteCalls.add('$itemId:$isFavorite');
    if (failFavoriteOnce) {
      failFavoriteOnce = false;
      throw StateError('favorite');
    }
    final pending = pendingFavorite;
    if (pending != null) await pending.future;
  }

  @override
  Future<void> setPlayed({required String itemId, required bool played}) async {
    playedCalls.add('$itemId:$played');
    final pending = pendingPlayed;
    if (pending != null) await pending.future;
  }
}
