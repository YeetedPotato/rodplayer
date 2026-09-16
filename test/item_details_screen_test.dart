import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

  testWidgets('movie details expose authoritative playback boundary', (tester) async {
    String? played;
    await tester.pumpWidget(app(ItemDetailsScreen(client: _DetailClient(item: _movie('movie', 'A Movie', progress: 25)), itemId: 'movie', onPlayItem: (_, id) => played = id)));
    await tester.pumpAndSettle();

    expect(find.text('A Movie'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    expect(played, 'movie');
  });

  testWidgets('series details load seasons and episodes without fabricated series playback', (tester) async {
    String? played;
    final client = _DetailClient(
      item: _series('series', 'A Series'),
      seasons: <JellyfinLibraryItem>[_season('s1', 'Season 1'), _season('s2', 'Season 2')],
      episodesBySeason: <String, List<JellyfinLibraryItem>>{
        's1': <JellyfinLibraryItem>[_episode('e1', 'Episode One', season: 1, episode: 1)],
        's2': <JellyfinLibraryItem>[_episode('e2', 'Episode Two', season: 2, episode: 1, progress: 50)],
      },
    );
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'series', onPlayItem: (_, id) => played = id)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Play'), findsNothing);
    expect(find.text('Episode One'), findsOneWidget);
    await tester.tap(find.text('Season 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Season 2').last);
    await tester.pumpAndSettle();
    expect(find.text('Episode Two'), findsOneWidget);

    await tester.tap(find.text('Episode Two'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    expect(played, 'e2');
  });

  testWidgets('details errors retry and compact layout remains stable', (tester) async {
    final client = _DetailClient(item: _movie('movie', 'Recovered'), failItemOnce: true);
    await tester.pumpWidget(app(ItemDetailsScreen(client: client, itemId: 'movie'), size: const Size(390, 760), textScale: 1.25));
    await tester.pumpAndSettle();

    expect(find.text('Details unavailable'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Recovered'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

JellyfinLibraryItem _movie(String id, String name, {double? progress}) => JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': id,
      'Name': name,
      'Type': 'Movie',
      'ProductionYear': 2024,
      'Overview': 'Movie overview',
      if (progress != null) 'UserData': <String, dynamic>{'PlayedPercentage': progress},
    });

JellyfinLibraryItem _series(String id, String name) => JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': id,
      'Name': name,
      'Type': 'Series',
      'Overview': 'Series overview',
    });

JellyfinLibraryItem _season(String id, String name) => JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': id,
      'Name': name,
      'Type': 'Season',
      'SeasonName': name,
    });

JellyfinLibraryItem _episode(String id, String name, {int? season, int? episode, double? progress}) => JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': id,
      'Name': name,
      'Type': 'Episode',
      'SeriesName': 'A Series',
      'ParentIndexNumber': season,
      'IndexNumber': episode,
      if (progress != null) 'UserData': <String, dynamic>{'PlayedPercentage': progress},
    });

class _DetailClient extends JellyfinApiClient {
  _DetailClient({
    required this.item,
    this.seasons = const <JellyfinLibraryItem>[],
    this.episodesBySeason = const <String, List<JellyfinLibraryItem>>{},
    this.failItemOnce = false,
  }) : super(baseUrl: 'https://server/jellyfin', identity: testIdentity, client: http.Client());

  final JellyfinLibraryItem item;
  final List<JellyfinLibraryItem> seasons;
  final Map<String, List<JellyfinLibraryItem>> episodesBySeason;
  bool failItemOnce;

  @override
  Future<JellyfinLibraryItem> getItem(String itemId) {
    if (failItemOnce) {
      failItemOnce = false;
      return Future<JellyfinLibraryItem>.error(StateError('failed'));
    }
    for (final episodes in episodesBySeason.values) {
      for (final episode in episodes) {
        if (episode.id == itemId) return Future<JellyfinLibraryItem>.value(episode);
      }
    }
    return Future<JellyfinLibraryItem>.value(item);
  }

  @override
  Future<List<JellyfinLibraryItem>> getSeasons({required String seriesId}) async => seasons;

  @override
  Future<List<JellyfinLibraryItem>> getEpisodes({required String seriesId, required String seasonId}) async => episodesBySeason[seasonId] ?? const <JellyfinLibraryItem>[];
}
