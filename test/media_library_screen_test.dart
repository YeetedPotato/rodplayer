import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/media_library_screen.dart';

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

  testWidgets('Movies and TV libraries render typed cards and activation behavior', (tester) async {
    String? played;
    await tester.pumpWidget(app(MediaLibraryScreen(client: _LibraryClient(items: [_movie('m1', 'Movie One', progress: 25)]), kind: JellyfinLibraryKind.movies, onPlayItem: (_, id) => played = id)));
    await tester.pumpAndSettle();

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('1 titles'), findsOneWidget);
    expect(find.text('Movie One'), findsOneWidget);
    await tester.tap(find.text('Movie One'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    expect(played, 'm1');

    await tester.pumpWidget(app(MediaLibraryScreen(client: _LibraryClient(items: [_series('s1', 'Series One')]), kind: JellyfinLibraryKind.tvShows)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Series One'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Play')).onPressed, isNull);
  });

  testWidgets('initial error, empty, and compact large text states are stable', (tester) async {
    await tester.pumpWidget(app(MediaLibraryScreen(client: _LibraryClient(failInitial: true), kind: JellyfinLibraryKind.movies)));
    await tester.pumpAndSettle();
    expect(find.text('Movies unavailable'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

    await tester.pumpWidget(app(MediaLibraryScreen(client: _LibraryClient(items: const []), kind: JellyfinLibraryKind.movies)));
    await tester.pumpAndSettle();
    expect(find.text('No movies found'), findsOneWidget);

    setSurface(tester, const Size(390, 760));
    await tester.pumpWidget(app(MediaLibraryScreen(client: _LibraryClient(items: [_movie('m1', 'A Long Movie Title That Should Not Overflow')]), kind: JellyfinLibraryKind.movies), size: const Size(390, 760), textScale: 1.25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort: Title'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort: Community Rating').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter: All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter: Favorites').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pagination appends, deduplicates, and stops at total', (tester) async {
    final first = List<JellyfinLibraryItem>.generate(48, (index) => _movie('m$index', 'Movie $index'));
    final client = _LibraryClient(pages: {
      0: JellyfinItemsPage<JellyfinLibraryItem>(items: first, totalRecordCount: 51, startIndex: 0),
      48: JellyfinItemsPage<JellyfinLibraryItem>(items: [_movie('m47', 'Movie 47 duplicate'), _movie('m48', 'Movie 48'), _movie('m49', 'Movie 49')], totalRecordCount: 51, startIndex: 48),
    });
    await tester.pumpWidget(app(MediaLibraryScreen(client: client, kind: JellyfinLibraryKind.movies)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Movie 49'), 900, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(client.starts, <int>[0, 48]);
    expect(find.text('Movie 47'), findsOneWidget);
    expect(find.text('Movie 49'), findsOneWidget);
  });

  testWidgets('load-more error preserves first page and retry requests failed page only', (tester) async {
    final client = _LibraryClient(
      pages: {0: JellyfinItemsPage<JellyfinLibraryItem>(items: List<JellyfinLibraryItem>.generate(48, (index) => _movie('m$index', 'Movie $index')), totalRecordCount: 50, startIndex: 0)},
      failStarts: <int>{48},
    );
    await tester.pumpWidget(app(MediaLibraryScreen(client: client, kind: JellyfinLibraryKind.movies)));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Retry loading more'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Movie 0'), -900, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Movie 0'), findsWidgets);
    final scrollableState =
        tester.state<ScrollableState>(find.byType(Scrollable).first);

    scrollableState.position.jumpTo(
      scrollableState.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextButton, 'Retry loading more'),
      findsOneWidget,
    );
    client.failStarts.clear();
    client.pages[48] = JellyfinItemsPage<JellyfinLibraryItem>(items: [_movie('m48', 'Movie 48')], totalRecordCount: 49, startIndex: 48);
    await tester.tap(find.widgetWithText(TextButton, 'Retry loading more'));
    await tester.pumpAndSettle();

    expect(client.starts, <int>[0, 48, 48]);
    await tester.scrollUntilVisible(find.text('Movie 48'), 600, scrollable: find.byType(Scrollable).first);
    expect(find.text('Movie 48'), findsOneWidget);
  });

  testWidgets('sort/filter changes reset paging and stale results are ignored', (tester) async {
    final titleCompleter = Completer<JellyfinItemsPage<JellyfinLibraryItem>>();
    final recentCompleter = Completer<JellyfinItemsPage<JellyfinLibraryItem>>();
    final client = _LibraryClient(delayed: {
      JellyfinLibrarySort.title: titleCompleter,
      JellyfinLibrarySort.recentlyAdded: recentCompleter,
    });
    await tester.pumpWidget(app(MediaLibraryScreen(client: client, kind: JellyfinLibraryKind.movies)));
    await tester.pump();

    await tester.tap(find.text('Sort: Title'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Sort: Recently Added').last);
    await tester.pump();
    recentCompleter.complete(JellyfinItemsPage<JellyfinLibraryItem>(items: [_movie('new', 'Newest')], totalRecordCount: 1, startIndex: 0));
    await tester.pumpAndSettle();
    titleCompleter.complete(JellyfinItemsPage<JellyfinLibraryItem>(items: [_movie('old', 'Old Title')], totalRecordCount: 1, startIndex: 0));
    await tester.pumpAndSettle();

    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Old Title'), findsNothing);

    await tester.tap(find.text('Filter: All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter: Favorites').last);
    await tester.pumpAndSettle();
    expect(client.filters, contains(JellyfinLibraryFilter.favorites));
  });

  testWidgets('client replacement restarts library query', (tester) async {
    final first = _LibraryClient(items: [_movie('old', 'Old Library')]);
    final second = _LibraryClient(items: [_movie('new', 'New Library')]);
    await tester.pumpWidget(app(MediaLibraryScreen(client: first, kind: JellyfinLibraryKind.movies)));
    await tester.pumpAndSettle();
    expect(find.text('Old Library'), findsOneWidget);

    await tester.pumpWidget(app(MediaLibraryScreen(client: second, kind: JellyfinLibraryKind.movies)));
    await tester.pumpAndSettle();
    expect(find.text('Old Library'), findsNothing);
    expect(find.text('New Library'), findsOneWidget);
  });
}

JellyfinLibraryItem _movie(String id, String name, {double? progress}) => JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': id,
      'Name': name,
      'Type': 'Movie',
      'ProductionYear': 2024,
      if (progress != null) 'UserData': <String, dynamic>{'PlayedPercentage': progress},
    });

JellyfinLibraryItem _series(String id, String name) => JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': id, 'Name': name, 'Type': 'Series'});

class _LibraryClient extends JellyfinApiClient {
  _LibraryClient({
    List<JellyfinLibraryItem>? items,
    Map<int, JellyfinItemsPage<JellyfinLibraryItem>>? pages,
    this.failInitial = false,
    Set<int>? failStarts,
    Map<JellyfinLibrarySort, Completer<JellyfinItemsPage<JellyfinLibraryItem>>>? delayed,
  })  : pages = pages ?? {0: JellyfinItemsPage<JellyfinLibraryItem>(items: items ?? <JellyfinLibraryItem>[], totalRecordCount: items?.length ?? 0, startIndex: 0)},
        failStarts = failStarts ?? <int>{},
        delayed = delayed ?? <JellyfinLibrarySort, Completer<JellyfinItemsPage<JellyfinLibraryItem>>>{},
        super(baseUrl: 'https://server/jellyfin', identity: testIdentity, client: http.Client());

  final Map<int, JellyfinItemsPage<JellyfinLibraryItem>> pages;
  final bool failInitial;
  final Set<int> failStarts;
  final Map<JellyfinLibrarySort, Completer<JellyfinItemsPage<JellyfinLibraryItem>>> delayed;
  final starts = <int>[];
  final filters = <JellyfinLibraryFilter>[];

  @override
  Future<JellyfinItemsPage<JellyfinLibraryItem>> getLibraryItemsPage({
    required JellyfinLibraryKind kind,
    JellyfinLibrarySort sort = JellyfinLibrarySort.title,
    JellyfinLibraryFilter filter = JellyfinLibraryFilter.all,
    int startIndex = 0,
    int limit = 48,
    String? parentId,
  }) {
    starts.add(startIndex);
    filters.add(filter);
    if (failInitial && startIndex == 0) return Future<JellyfinItemsPage<JellyfinLibraryItem>>.error(StateError('failed'));
    if (failStarts.contains(startIndex)) return Future<JellyfinItemsPage<JellyfinLibraryItem>>.error(StateError('failed page'));
    final completer = delayed[sort];
    if (completer != null && startIndex == 0) return completer.future;
    return Future<JellyfinItemsPage<JellyfinLibraryItem>>.value(pages[startIndex] ?? JellyfinItemsPage<JellyfinLibraryItem>(items: const <JellyfinLibraryItem>[], totalRecordCount: startIndex, startIndex: startIndex));
  }
}
