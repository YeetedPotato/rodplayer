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
import 'package:rodplayer/ui/screens/search_screen.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  Widget app(Widget child, {Size size = const Size(900, 700), double textScale = 1}) => MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(theme: rodPlayerThemeData(), home: Scaffold(body: child)),
      );

  void setSurface(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('empty query shows paged Discover by default', (tester) async {
    final client = _SearchClient(discoveryPages: {0: _page([_movie('m1', 'Top Movie')], total: 1)});
    await tester.pumpWidget(app(SearchScreen(client: client)));
    await tester.pumpAndSettle();

    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Top Movie'), findsOneWidget);
    expect(client.discoveryCalls.single.kind, JellyfinDiscoveryKind.movies);
    expect(client.discoveryCalls.single.sort, JellyfinDiscoverySort.topRated);
  });

  testWidgets('search debounce sends current query and opens details', (tester) async {
    final client = _SearchClient(searchPages: {0: _page([_movie('s1', 'Star Film')], total: 1)});
    await tester.pumpWidget(app(SearchScreen(client: client)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'star');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(client.searchCalls.single.query, 'star');
    await tester.tap(_card('Star Film'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailsScreen), findsOneWidget);
    expect(client.itemRequests, <String>['s1']);
  });

  testWidgets('stale old query result is ignored and recent searches dedupe', (tester) async {
    final old = Completer<JellyfinItemsPage<JellyfinLibraryItem>>();
    final client = _SearchClient(delayedSearch: {'star': old}, searchPages: {0: _page([_movie('new', 'Star Wars')], total: 1)});
    await tester.pumpWidget(app(SearchScreen(client: client)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'star');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'star wars');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    old.complete(_page([_movie('old', 'Old Star')], total: 1));
    await tester.pumpAndSettle();

    expect(find.text('Star Wars'), findsOneWidget);
    expect(find.text('Old Star'), findsNothing);
    await tester.enterText(find.byType(TextField), 'STAR WARS');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('rodplayer_recent_searches'), <String>['STAR WARS']);
  });

  testWidgets('type change resets search paging and maps type through API', (tester) async {
    final client = _SearchClient(searchPages: {0: _page([_series('show', 'Show')], total: 1)});
    await tester.pumpWidget(app(SearchScreen(client: client)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'show');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'TV Shows'));
    await tester.pumpAndSettle();

    expect(client.searchCalls.last.type, JellyfinSearchType.tvShows);
    expect(client.searchCalls.last.startIndex, 0);
  });

  testWidgets('search load-more failure preserves first page and retries failed offset', (tester) async {
    final first = List<JellyfinLibraryItem>.generate(48, (index) => _movie('m$index', 'Movie $index'));
    final client = _SearchClient(searchPages: {0: _page(first, total: 50)}, failSearchStarts: {48});
    await tester.pumpWidget(app(SearchScreen(client: client)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'movie');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.widgetWithText(TextButton, 'Retry loading more'), 900, scrollable: find.byType(Scrollable).first);
    expect(find.text('Movie 0'), findsNothing);
    await tester.scrollUntilVisible(find.text('Movie 0'), -900, scrollable: find.byType(Scrollable).first);
    expect(find.text('Movie 0'), findsOneWidget);
    client.failSearchStarts.clear();
    client.searchPages[48] = _page([_movie('m48', 'Movie 48')], total: 49, start: 48);
    await tester.scrollUntilVisible(find.widgetWithText(TextButton, 'Retry loading more'), 900, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(TextButton, 'Retry loading more'));
    await tester.pumpAndSettle();

    expect(client.searchCalls.map((call) => call.startIndex), <int>[0, 48, 48]);
    await tester.scrollUntilVisible(find.text('Movie 48'), 600, scrollable: find.byType(Scrollable).first);
    expect(find.text('Movie 48'), findsOneWidget);
  });

  testWidgets('discovery controls genre paging stale result and client replacement', (tester) async {
    final old = Completer<JellyfinItemsPage<JellyfinLibraryItem>>();
    final first = _SearchClient(genres: ['Drama'], delayedDiscovery: {JellyfinDiscoverySort.topRated: old}, discoveryPages: {0: _page([_movie('new', 'Recent Movie')], total: 1)});
    final second = _SearchClient(discoveryPages: {0: _page([_movie('second', 'Second Client')], total: 1)});
    await tester.pumpWidget(app(SearchScreen(client: first)));
    await tester.pump();
    await tester.tap(find.text('Sort: Top Rated'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Sort: Recently Added').last);
    await tester.pumpAndSettle();
    old.complete(_page([_movie('old', 'Old Top')], total: 1));
    await tester.pumpAndSettle();

    expect(find.text('Recent Movie'), findsOneWidget);
    expect(find.text('Old Top'), findsNothing);
    await tester.tap(find.text('Genre: All Genres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genre: Drama').last);
    await tester.pumpAndSettle();
    expect(first.discoveryCalls.last.genre, 'Drama');

    await tester.pumpWidget(app(SearchScreen(client: second)));
    await tester.pumpAndSettle();
    expect(find.text('Second Client'), findsOneWidget);
  });

  testWidgets('genre failure does not block discovery and compact directional layout is stable', (tester) async {
    setSurface(tester, const Size(390, 760));
    final client = _SearchClient(failGenres: true, discoveryPages: {0: _page([_movie('m', 'A Long Discovery Movie Title')], total: 1)});
    await tester.pumpWidget(app(SearchScreen(client: client), size: const Size(390, 760), textScale: 1.25));
    await tester.pumpAndSettle();

    expect(find.text('A Long Discovery Movie Title'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ID-less result does not open details and recent chip executes query', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'rodplayer_recent_searches': <String>['recent']});
    final client = _SearchClient(searchPages: {0: _page([_movie('', 'No Id')], total: 1)});
    await tester.pumpWidget(app(SearchScreen(client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'recent'));
    await tester.pumpAndSettle();
    expect(client.searchCalls.single.query, 'recent');
    await tester.tap(_card('No Id'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailsScreen), findsNothing);
  });
}

Finder _card(String title) => find.byWidgetPredicate((widget) => widget is FocusableMediaCard && widget.title == title);
JellyfinItemsPage<JellyfinLibraryItem> _page(List<JellyfinLibraryItem> items, {int? total, int start = 0}) => JellyfinItemsPage<JellyfinLibraryItem>(items: items, totalRecordCount: total ?? items.length, startIndex: start);
JellyfinLibraryItem _movie(String id, String name) => JellyfinLibraryItem.fromJson({'Id': id, 'Name': name, 'Type': 'Movie', 'ProductionYear': 2024});
JellyfinLibraryItem _series(String id, String name) => JellyfinLibraryItem.fromJson({'Id': id, 'Name': name, 'Type': 'Series'});

class _SearchCall {
  const _SearchCall(this.query, this.type, this.genre, this.startIndex);
  final String query;
  final JellyfinSearchType type;
  final String? genre;
  final int startIndex;
}

class _DiscoveryCall {
  const _DiscoveryCall(this.kind, this.sort, this.genre, this.startIndex);
  final JellyfinDiscoveryKind kind;
  final JellyfinDiscoverySort sort;
  final String? genre;
  final int startIndex;
}

class _SearchClient extends JellyfinApiClient {
  _SearchClient({this.searchPages = const {}, this.discoveryPages = const {}, this.delayedSearch = const {}, this.delayedDiscovery = const {}, this.failSearchStarts = const {}, this.genres = const [], this.failGenres = false})
      : super(baseUrl: 'https://server/jellyfin', identity: testIdentity, client: http_testing.MockClient((_) async => http.Response('{}', 200)));
  final Map<int, JellyfinItemsPage<JellyfinLibraryItem>> searchPages;
  final Map<int, JellyfinItemsPage<JellyfinLibraryItem>> discoveryPages;
  final Map<String, Completer<JellyfinItemsPage<JellyfinLibraryItem>>> delayedSearch;
  final Map<JellyfinDiscoverySort, Completer<JellyfinItemsPage<JellyfinLibraryItem>>> delayedDiscovery;
  final Set<int> failSearchStarts;
  final List<String> genres;
  final bool failGenres;
  final searchCalls = <_SearchCall>[];
  final discoveryCalls = <_DiscoveryCall>[];
  final itemRequests = <String>[];

  @override
  Future<JellyfinItemsPage<JellyfinLibraryItem>> getSearchItemsPage({required String query, JellyfinSearchType type = JellyfinSearchType.all, String? genre, int startIndex = 0, int limit = 48}) {
    searchCalls.add(_SearchCall(query, type, genre, startIndex));
    if (failSearchStarts.contains(startIndex)) return Future<JellyfinItemsPage<JellyfinLibraryItem>>.error(StateError('failed'));
    final delayed = delayedSearch[query];
    if (delayed != null && startIndex == 0) return delayed.future;
    return Future<JellyfinItemsPage<JellyfinLibraryItem>>.value(searchPages[startIndex] ?? _page(const <JellyfinLibraryItem>[], start: startIndex));
  }

  @override
  Future<JellyfinItemsPage<JellyfinLibraryItem>> getDiscoveryItemsPage({required JellyfinDiscoveryKind kind, JellyfinDiscoverySort sort = JellyfinDiscoverySort.topRated, String? genre, int startIndex = 0, int limit = 48}) {
    discoveryCalls.add(_DiscoveryCall(kind, sort, genre, startIndex));
    final delayed = delayedDiscovery[sort];
    if (delayed != null && startIndex == 0) return delayed.future;
    return Future<JellyfinItemsPage<JellyfinLibraryItem>>.value(discoveryPages[startIndex] ?? _page(const <JellyfinLibraryItem>[], start: startIndex));
  }

  @override
  Future<List<String>> getGenres() => failGenres ? Future<List<String>>.error(StateError('genres')) : Future<List<String>>.value(genres);

  @override
  Future<JellyfinLibraryItem> getItem(String itemId) async {
    itemRequests.add(itemId);
    for (final page in [...searchPages.values, ...discoveryPages.values]) {
      for (final item in page.items) {
        if (item.id == itemId) return item;
      }
    }
    return _movie(itemId, itemId);
  }
}
