import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/discover_screen.dart';
import 'package:rodplayer/ui/screens/item_details_screen.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/user_data_badge.dart';
import 'package:rodplayer/ui/widgets/smart_shelf.dart';

import 'test_support.dart';

void main() {
  Widget app(Widget child,
          {Size size = const Size(1000, 800), double textScale = 1}) =>
      MaterialApp(
        theme: rodPlayerThemeData(),
        home: MediaQuery(
          data: MediaQueryData(
              size: size, textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      );

  testWidgets(
      'Discover uses real movie and show sorts and opens existing details',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const emptyShowShelf = _DiscoveryCall(
      JellyfinDiscoveryKind.tvShows,
      JellyfinDiscoverySort.topRated,
      limit: 12,
    );
    final client =
        _DiscoverClient(emptyCalls: <_DiscoveryCall>{emptyShowShelf});
    await tester.pumpWidget(
        app(DiscoverScreen(client: client), size: const Size(1000, 1800)));
    await tester.pumpAndSettle();

    expect(find.text('Top rated movies'), findsOneWidget);
    expect(find.text('Recently added movies'), findsOneWidget);
    expect(find.text('Top rated shows'), findsOneWidget);
    expect(find.text('Recently added shows'), findsOneWidget);
    expect(find.text('Glass House'), findsOneWidget);
    expect(find.text('Signal Lost'), findsNothing);
    expect(find.text('New Show'), findsOneWidget);
    expect(find.text('No titles available in this shelf.'), findsOneWidget);
    expect(find.byType(UserDataBadge), findsOneWidget);
    expect(find.byType(SmartShelf), findsNWidgets(3));
    expect(
        client.calls,
        containsAll(<_DiscoveryCall>[
          const _DiscoveryCall(
              JellyfinDiscoveryKind.movies, JellyfinDiscoverySort.topRated,
              limit: 12),
          const _DiscoveryCall(
              JellyfinDiscoveryKind.movies, JellyfinDiscoverySort.recentlyAdded,
              limit: 12),
          const _DiscoveryCall(
              JellyfinDiscoveryKind.tvShows, JellyfinDiscoverySort.topRated,
              limit: 12),
          const _DiscoveryCall(JellyfinDiscoveryKind.tvShows,
              JellyfinDiscoverySort.recentlyAdded,
              limit: 12),
        ]));
    expect(JellyfinDiscoveryKind.movies.includeItemType, 'Movie');
    expect(JellyfinDiscoveryKind.tvShows.includeItemType, 'Series');
    expect(JellyfinDiscoverySort.topRated.sortBy, 'CommunityRating');
    expect(JellyfinDiscoverySort.recentlyAdded.sortBy, 'DateCreated');
    expect(JellyfinDiscoverySort.topRated.sortOrder, 'Descending');
    expect(JellyfinDiscoverySort.recentlyAdded.sortOrder, 'Descending');
    expect(find.text('Kids'), findsNothing);
    expect(find.text('Streaming services'), findsNothing);

    await tester.tap(find.text('Glass House'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailsScreen), findsOneWidget);
    expect(client.itemRequests, <String>['movie']);
  });

  testWidgets('empty and failed Discover groups remain scoped and retry',
      (tester) async {
    final client = _DiscoverClient(failures: {
      const _DiscoveryCall(
          JellyfinDiscoveryKind.movies, JellyfinDiscoverySort.topRated,
          limit: 12),
    });
    await tester.pumpWidget(app(DiscoverScreen(client: client),
        size: const Size(390, 760), textScale: 1.2));
    await tester.pumpAndSettle();

    expect(find.text('Could not load top rated movies.'), findsOneWidget);
    expect(find.text('Recently added movies'), findsOneWidget);
    expect(find.text('New Movie'), findsOneWidget);
    expect(find.text('No movies or shows to discover yet.'), findsNothing);
    expect(tester.takeException(), isNull);

    client.failures.clear();
    await tester.tap(find.text('Retry').first);
    await tester.pumpAndSettle();
    expect(find.text('Could not load top rated movies.'), findsNothing);
    expect(
        client.calls
            .where((call) =>
                call ==
                const _DiscoveryCall(JellyfinDiscoveryKind.movies,
                    JellyfinDiscoverySort.topRated,
                    limit: 12))
            .length,
        2);
    expect(
        client.calls
            .where((call) =>
                call ==
                const _DiscoveryCall(JellyfinDiscoveryKind.movies,
                    JellyfinDiscoverySort.recentlyAdded,
                    limit: 12))
            .length,
        1);
  });

  testWidgets('empty supported discovery queries show a clear empty state',
      (tester) async {
    final client = _DiscoverClient(empty: true);
    await tester.pumpWidget(app(DiscoverScreen(client: client)));
    await tester.pumpAndSettle();

    expect(find.text('No movies or shows to discover yet.'), findsOneWidget);
    expect(find.byType(FocusableMediaCard), findsNothing);
  });

  testWidgets('pending shelf shows progress while other shelves resolve',
      (tester) async {
    const delayedCall = _DiscoveryCall(
      JellyfinDiscoveryKind.movies,
      JellyfinDiscoverySort.topRated,
      limit: 12,
    );
    final response = Completer<JellyfinItemsPage<JellyfinLibraryItem>>();
    final client = _DiscoverClient(
      delayed: <_DiscoveryCall,
          Completer<JellyfinItemsPage<JellyfinLibraryItem>>>{
        delayedCall: response,
      },
    );
    await tester.pumpWidget(app(
      DiscoverScreen(client: client),
      size: const Size(1000, 1200),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('New Movie'), findsOneWidget);

    response.complete(JellyfinItemsPage<JellyfinLibraryItem>(
      items: <JellyfinLibraryItem>[],
      totalRecordCount: 0,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No movies or shows to discover yet.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive Discover defers queries until selected',
      (tester) async {
    final client = _DiscoverClient();
    await tester.pumpWidget(app(DiscoverScreen(client: client, active: false)));
    await tester.pump();
    expect(client.calls, isEmpty);

    await tester.pumpWidget(app(DiscoverScreen(client: client, active: true)));
    await tester.pumpAndSettle();
    expect(client.calls, hasLength(4));

    await tester.pumpWidget(app(DiscoverScreen(client: client, active: false)));
    await tester.pumpWidget(app(DiscoverScreen(client: client, active: true)));
    await tester.pumpAndSettle();
    expect(client.calls, hasLength(4));
  });

  testWidgets('client replacement ignores stale discovery responses',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const delayedCall = _DiscoveryCall(
        JellyfinDiscoveryKind.movies, JellyfinDiscoverySort.topRated,
        limit: 12);
    final oldResponse = Completer<JellyfinItemsPage<JellyfinLibraryItem>>();
    final oldClient = _DiscoverClient(
      namePrefix: 'Old client',
      delayed: <_DiscoveryCall,
          Completer<JellyfinItemsPage<JellyfinLibraryItem>>>{
        delayedCall: oldResponse,
      },
    );
    await tester.pumpWidget(app(DiscoverScreen(client: oldClient)));
    await tester.pump();

    final newClient = _DiscoverClient(namePrefix: 'New client');
    await tester.pumpWidget(app(DiscoverScreen(client: newClient)));
    await tester.pumpAndSettle();
    expect(find.text('New client movies topRated'), findsOneWidget);

    oldResponse.complete(JellyfinItemsPage<JellyfinLibraryItem>(
      items: <JellyfinLibraryItem>[
        JellyfinLibraryItem.fromJson(<String, dynamic>{
          'Id': 'stale',
          'Name': 'Stale result',
          'Type': 'Movie',
        }),
      ],
      totalRecordCount: 1,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Stale result'), findsNothing);
    expect(find.text('New client movies topRated'), findsOneWidget);
  });
}

class _DiscoveryCall {
  const _DiscoveryCall(this.kind, this.sort, {this.limit = 48});

  final JellyfinDiscoveryKind kind;
  final JellyfinDiscoverySort sort;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is _DiscoveryCall &&
      other.kind == kind &&
      other.sort == sort &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(kind, sort, limit);
}

class _DiscoverClient extends JellyfinApiClient {
  _DiscoverClient({
    this.empty = false,
    this.failures = const <_DiscoveryCall>{},
    this.emptyCalls = const <_DiscoveryCall>{},
    this.namePrefix = '',
    this.delayed = const <_DiscoveryCall,
        Completer<JellyfinItemsPage<JellyfinLibraryItem>>>{},
  }) : super(
            baseUrl: 'https://server/jellyfin',
            identity: testIdentity,
            client:
                http_testing.MockClient((_) async => http.Response('{}', 200)));

  final bool empty;
  final Set<_DiscoveryCall> failures;
  final Set<_DiscoveryCall> emptyCalls;
  final String namePrefix;
  final Map<_DiscoveryCall, Completer<JellyfinItemsPage<JellyfinLibraryItem>>>
      delayed;
  final calls = <_DiscoveryCall>[];
  final itemRequests = <String>[];

  @override
  Future<JellyfinItemsPage<JellyfinLibraryItem>> getDiscoveryItemsPage({
    required JellyfinDiscoveryKind kind,
    JellyfinDiscoverySort sort = JellyfinDiscoverySort.topRated,
    String? genre,
    int startIndex = 0,
    int limit = 48,
  }) async {
    final call = _DiscoveryCall(kind, sort, limit: limit);
    calls.add(call);
    if (failures.contains(call)) throw StateError('synthetic query failure');
    final pending = delayed[call];
    if (pending != null) return pending.future;
    if (empty || emptyCalls.contains(call)) {
      return JellyfinItemsPage<JellyfinLibraryItem>(
          items: <JellyfinLibraryItem>[], totalRecordCount: 0);
    }
    final isMovie = kind == JellyfinDiscoveryKind.movies;
    final itemId = isMovie
        ? (sort == JellyfinDiscoverySort.topRated ? 'movie' : 'new-movie')
        : (sort == JellyfinDiscoverySort.topRated ? 'show' : 'new-show');
    final name = isMovie
        ? (sort == JellyfinDiscoverySort.topRated ? 'Glass House' : 'New Movie')
        : (sort == JellyfinDiscoverySort.topRated ? 'Signal Lost' : 'New Show');
    final displayName =
        namePrefix.isEmpty ? name : '$namePrefix ${kind.name} ${sort.name}';
    final item = JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': itemId,
      'Name': displayName,
      'Type': isMovie ? 'Movie' : 'Series',
      'ImageTags': <String, dynamic>{'Primary': itemId},
      if (itemId == 'movie') 'UserData': <String, dynamic>{'IsFavorite': true},
    });
    final items = <JellyfinLibraryItem>[item];
    return JellyfinItemsPage<JellyfinLibraryItem>(
        items: items, totalRecordCount: items.length);
  }

  @override
  Future<JellyfinLibraryItem> getItem(String itemId) async {
    itemRequests.add(itemId);
    return JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': itemId,
      'Name': itemId == 'movie' ? 'Glass House' : 'Signal Lost',
      'Type': itemId == 'movie' ? 'Movie' : 'Series'
    });
  }
}
