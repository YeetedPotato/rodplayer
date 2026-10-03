import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/discovery/surprise_picker.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/appearance_mode.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/discover_screen.dart';
import 'package:rodplayer/ui/screens/item_details_screen.dart';
import 'package:rodplayer/ui/screens/surprise_me_dialog.dart';

import 'test_support.dart';

void main() {
  void setSurface(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Discover offers Surprise Me without adding a shelf or tab',
      (tester) async {
    setSurface(tester, const Size(1000, 800));
    await tester.pumpWidget(MaterialApp(
      theme: rodPlayerThemeData(),
      home: Scaffold(body: DiscoverScreen(client: _SurpriseClient(count: 0))),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(DiscoverScreen), findsOneWidget);
    for (final shelf in <String>[
      'Top rated movies',
      'Recently added movies',
      'Top rated shows',
      'Recently added shows',
    ]) {
      expect(find.text(shelf), findsOneWidget);
    }
    expect(find.text('Surprise Me'), findsOneWidget);
    await tester.tap(find.text('Surprise Me'));
    await tester.pumpAndSettle();
    expect(find.byType(SurpriseMeDialog), findsOneWidget);
    expect(find.text('No more items are available in this group.'),
        findsOneWidget);
  });

  testWidgets(
      'Surprise Me supports Another, Details, and existing Play callback',
      (tester) async {
    setSurface(tester, const Size(1000, 800));
    final client = _SurpriseClient(count: 10);
    final played = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: rodPlayerThemeData(),
      home: Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                  onPressed: () => showSurpriseMePicker(
                    context: context,
                    client: client,
                    random: Random(3),
                    onPlayItem: (_, id) => played.add(id),
                  ),
                  child: const Text('Open'),
                )),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Surprise Me'), findsOneWidget);
    expect(find.byType(DropdownButton<SurpriseMode>), findsOneWidget);
    final oledTheme = Theme.of(tester.element(find.text('Surprise Me')))
        .extension<RodPlayerTheme>()!;
    for (final button
        in tester.widgetList<OutlinedButton>(find.byType(OutlinedButton))) {
      expect(
        button.style!.foregroundColor!.resolve(<WidgetState>{}),
        oledTheme.accentBright,
      );
    }
    final initial = client.lastPickedId;
    expect(initial, isNotNull);

    await tester.tap(find.text('Another'));
    await tester.pumpAndSettle();
    expect(client.lastPickedId, isNot(initial));

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailsScreen), findsOneWidget);

    final anotherId = client.lastPickedId;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(client.lastPickedId, anotherId);
    expect(find.textContaining('Movie pick '), findsOneWidget);
    await tester.tap(find.text('Play'));
    expect(played, <String>[client.lastPickedId!]);
  });

  testWidgets(
      'compact Surprise Me opens as a bottom sheet and handles no candidates',
      (tester) async {
    setSurface(tester, const Size(390, 760));
    final client = _SurpriseClient(count: 0);
    await tester.pumpWidget(MaterialApp(
      theme: rodPlayerThemeData(mode: AppearanceMode.light),
      home: Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                  onPressed: () =>
                      showSurpriseMePicker(context: context, client: client),
                  child: const Text('Open'),
                )),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Surprise Me'), findsOneWidget);
    expect(find.text('No more items are available in this group.'),
        findsOneWidget);
    final theme = Theme.of(tester.element(find.text('Surprise Me')))
        .extension<RodPlayerTheme>()!;
    final outline =
        tester.widget<OutlinedButton>(find.byType(OutlinedButton).first);
    expect(outline.style!.foregroundColor!.resolve(<WidgetState>{}),
        theme.accentDeep);
    expect(
      outline.style!.side!.resolve(<WidgetState>{})!.color,
      theme.accentDeep.withValues(alpha: .65),
    );

    await tester.tap(find.byType(DropdownButton<SurpriseMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorite movies and shows').last);
    await tester.pumpAndSettle();
    expect(find.text('Favorite movies and shows'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Surprise Me never offers direct Play for a Series', (tester) async {
    setSurface(tester, const Size(1000, 800));
    final played = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () => showSurpriseMePicker(
            context: context,
            client: _SurpriseClient(count: 10),
            onPlayItem: (_, id) => played.add(id),
          ),
          child: const Text('Open'),
        )),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<SurpriseMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unwatched shows').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Show pick '), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Details'), findsOneWidget);
    expect(played, isEmpty);
  });

  testWidgets('Dark and OLED outlined actions use bright semantic contrast',
      (tester) async {
    setSurface(tester, const Size(900, 760));
    for (final mode in <AppearanceMode>[
      AppearanceMode.dark,
      AppearanceMode.oled,
    ]) {
      await tester.pumpWidget(MaterialApp(
        theme: rodPlayerThemeData(mode: mode),
        home: Scaffold(
          body: SurpriseMeDialog(client: _SurpriseClient(count: 0)),
        ),
      ));
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(find.text('Surprise Me')))
          .extension<RodPlayerTheme>()!;
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Another'),
      );
      final focused = <WidgetState>{WidgetState.focused};
      expect(
        button.style!.foregroundColor!.resolve(focused),
        theme.accentBright,
      );
      expect(
        button.style!.side!.resolve(focused)!.color,
        theme.accentBright.withValues(alpha: .65),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('changing Surprise mode ignores an older pending result',
      (tester) async {
    setSurface(tester, const Size(900, 760));
    final oldMovies = Completer<JellyfinItemsPage<JellyfinLibraryItem>>();
    final client = _SurpriseClient(count: 10, delayedMovie: oldMovies);
    await tester.pumpWidget(MaterialApp(
      theme: rodPlayerThemeData(),
      home: Scaffold(body: SurpriseMeDialog(client: client, random: Random(5))),
    ));
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<SurpriseMode>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Unwatched shows').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Show pick '), findsOneWidget);
    final currentId = client.lastPickedId;

    oldMovies.complete(JellyfinItemsPage<JellyfinLibraryItem>(
      items: <JellyfinLibraryItem>[
        JellyfinLibraryItem.fromJson(<String, dynamic>{
          'Id': 'stale-movie',
          'Name': 'Stale movie',
          'Type': 'Movie',
        }),
      ],
      totalRecordCount: 1,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Stale movie'), findsNothing);
    expect(find.textContaining('Show pick '), findsOneWidget);
    expect(client.lastPickedId, currentId);
  });
}

class _SurpriseClient extends JellyfinApiClient {
  _SurpriseClient({required this.count, this.delayedMovie})
      : super(
          baseUrl: 'https://server/jellyfin',
          identity: testIdentity, serverId: testServerId,
          client:
              http_testing.MockClient((_) async => http.Response('{}', 200)),
        );

  final int count;
  final Completer<JellyfinItemsPage<JellyfinLibraryItem>>? delayedMovie;
  final calls = <int>[];
  String? lastPickedId;
  bool _movieDelayUsed = false;

  @override
  Future<JellyfinItemsPage<JellyfinLibraryItem>> getLibraryItemsPage({
    required JellyfinLibraryKind kind,
    JellyfinLibrarySort sort = JellyfinLibrarySort.title,
    JellyfinLibraryFilter filter = JellyfinLibraryFilter.all,
    int startIndex = 0,
    int limit = 48,
    String? parentId,
  }) async {
    calls.add(startIndex);
    if (kind == JellyfinLibraryKind.movies &&
        delayedMovie != null &&
        !_movieDelayUsed) {
      _movieDelayUsed = true;
      return delayedMovie!.future;
    }
    if (count == 0) {
      return JellyfinItemsPage<JellyfinLibraryItem>(
          items: const <JellyfinLibraryItem>[], totalRecordCount: 0);
    }
    final item = JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': 'surprise-$startIndex',
      'Name': kind == JellyfinLibraryKind.movies
          ? 'Movie pick $startIndex'
          : 'Show pick $startIndex',
      'Type': kind == JellyfinLibraryKind.movies ? 'Movie' : 'Series'
    });
    lastPickedId = item.id;
    return JellyfinItemsPage<JellyfinLibraryItem>(
        items: <JellyfinLibraryItem>[item],
        totalRecordCount: count,
        startIndex: startIndex);
  }

  @override
  Future<JellyfinLibraryItem> getItem(String itemId) async =>
      JellyfinLibraryItem.fromJson(<String, dynamic>{
        'Id': itemId,
        'Name': 'Surprise detail',
        'Type': 'Movie'
      });
}
