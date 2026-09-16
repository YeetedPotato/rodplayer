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
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).onChanged?.call('s2');
    await tester.pump();
    s2.complete(<JellyfinLibraryItem>[_episode('e2', 'Fresh')]);
    await tester.pumpAndSettle();
    s1.complete(<JellyfinLibraryItem>[_episode('e1', 'Stale')]);
    await tester.pumpAndSettle();
    expect(find.text('Fresh'), findsOneWidget);
    expect(find.text('Stale'), findsNothing);
  });

  testWidgets('compact long metadata and directional focus are stable', (tester) async {
    final client = _DetailClient(item: _movie('m', 'A Very Long Movie Title That Should Wrap Without Overflow'));
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'm'), size: const Size(390, 760), textScale: 1.25));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(tester.takeException(), isNull);
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
  _DetailClient({required this.item, this.seasons = const <JellyfinLibraryItem>[], this.episodesBySeason = const <String, List<JellyfinLibraryItem>>{}, this.pendingItems = const <String, Completer<JellyfinLibraryItem>>{}, this.pendingEpisodes = const <String, Completer<List<JellyfinLibraryItem>>>{}, this.failItemOnce = false, this.failSeasonsOnce = false, this.failEpisodesOnce = false})
      : super(baseUrl: 'https://server/jellyfin', identity: testIdentity, client: http_testing.MockClient((_) async => http.Response('{}', 200)));
  final JellyfinLibraryItem item;
  final List<JellyfinLibraryItem> seasons;
  final Map<String, List<JellyfinLibraryItem>> episodesBySeason;
  final Map<String, Completer<JellyfinLibraryItem>> pendingItems;
  final Map<String, Completer<List<JellyfinLibraryItem>>> pendingEpisodes;
  bool failItemOnce, failSeasonsOnce, failEpisodesOnce;
  final seasonRequests = <String>[];
  final episodeRequests = <String>[];

  @override
  Future<JellyfinLibraryItem> getItem(String itemId) {
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
}
