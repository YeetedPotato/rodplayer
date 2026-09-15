import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/home_screen.dart';
import 'package:rodplayer/ui/screens/search_screen.dart';
import 'package:rodplayer/ui/shell/rodplayer_app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  Widget app(Widget child, {Size size = const Size(1200, 800), NavigationMode navigationMode = NavigationMode.traditional, double textScale = 1}) => MediaQuery(
        data: MediaQueryData(size: size, navigationMode: navigationMode, textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(theme: rodPlayerThemeData(), home: child),
      );

  testWidgets('authenticated shell defaults to Home and renders before futures finish', (tester) async {
    final client = _FakeHomeClient(pending: true);
    await tester.pumpWidget(app(RodPlayerAppShell(client: client, onLogout: () async {})));

    expect(find.text('RodPlayer'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('compact shell uses bottom navigation and can switch destinations', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final client = _FakeHomeClient();
    await tester.pumpWidget(app(RodPlayerAppShell(client: client, onLogout: () async {}), size: const Size(390, 760)));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.byIcon(Icons.search).last);
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.home_outlined).last);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('expanded and directional shells use side navigation and expose logout', (tester) async {
    var loggedOut = false;
    await tester.pumpWidget(app(RodPlayerAppShell(client: _FakeHomeClient(), onLogout: () async => loggedOut = true), navigationMode: NavigationMode.directional));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Log out'));
    expect(loggedOut, isTrue);
  });

  testWidgets('embedded search has no nested app bar chrome', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(app(RodPlayerAppShell(client: _FakeHomeClient(), onLogout: () async {})));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(SearchScreen), findsOneWidget);
  });

  testWidgets('Home renders typed sections and isolates failed sections', (tester) async {
    await tester.pumpWidget(app(HomeScreen(client: _FakeHomeClient(nextUpError: true))));
    await tester.pumpAndSettle();

    expect(find.text('Resume Movie'), findsWidgets);
    expect(find.text('Latest Movie'), findsOneWidget);
    expect(find.text('Latest Series'), findsOneWidget);
    expect(find.text('Next Up unavailable'), findsOneWidget);
  });

  testWidgets('Home empty state appears when all sections are empty', (tester) async {
    await tester.pumpWidget(app(HomeScreen(client: _FakeHomeClient.empty())));
    await tester.pumpAndSettle();

    expect(find.text('No home content yet'), findsOneWidget);
  });

  testWidgets('hero priority and playback entry use injected boundary', (tester) async {
    String? played;
    await tester.pumpWidget(app(HomeScreen(client: _FakeHomeClient(), onPlayItem: (_, id) => played = id)));
    await tester.pumpAndSettle();

    expect(find.text('Resume Movie'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Resume').first);
    expect(played, 'resume');
  });

  testWidgets('hero falls back to next up and latest movie', (tester) async {
    await tester.pumpWidget(app(HomeScreen(client: _FakeHomeClient(resume: const <ResumableItem>[]))));
    await tester.pumpAndSettle();
    expect(find.text('Next Episode'), findsWidgets);

    await tester.pumpWidget(app(HomeScreen(client: _FakeHomeClient(resume: const <ResumableItem>[], nextUp: const <NextUpItem>[]))));
    await tester.pumpAndSettle();
    expect(find.text('Latest Movie'), findsWidgets);
  });

  testWidgets('Series does not get fabricated direct Play', (tester) async {
    await tester.pumpWidget(app(HomeScreen(client: _FakeHomeClient(resume: const <ResumableItem>[], nextUp: const <NextUpItem>[], movies: const <JellyfinLibraryItem>[]))));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Latest Series').first);
    await tester.tap(find.text('Latest Series').first);
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Play'));
    expect(button.onPressed, isNull);
  });

  testWidgets('progress is clamped and unknown progress omits bar', (tester) async {
    await tester.pumpWidget(app(HomeScreen(client: _FakeHomeClient(resume: <ResumableItem>[
      ResumableItem.fromJson(<String, dynamic>{'Id': 'resume', 'Name': 'Resume Movie', 'Type': 'Movie', 'UserData': <String, dynamic>{'PlayedPercentage': 150}}),
    ]))));
    await tester.pumpAndSettle();
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first).value, 1);

    await tester.pumpWidget(app(HomeScreen(client: _FakeHomeClient(resume: <ResumableItem>[ResumableItem.fromJson(<String, dynamic>{'Id': 'resume', 'Name': 'Resume Movie', 'Type': 'Movie'})]))));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('compact Home tolerates larger text without overflow', (tester) async {
    await tester.pumpWidget(app(HomeScreen(client: _FakeHomeClient()), size: const Size(390, 760), textScale: 1.25));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Resume Movie'), findsWidgets);
  });
}

class _FakeHomeClient extends JellyfinApiClient {
  _FakeHomeClient({
    this.pending = false,
    this.nextUpError = false,
    List<ResumableItem>? resume,
    List<NextUpItem>? nextUp,
    List<JellyfinLibraryItem>? movies,
    List<JellyfinLibraryItem>? shows,
  })  : resume = resume ?? <ResumableItem>[ResumableItem.fromJson(<String, dynamic>{'Id': 'resume', 'Name': 'Resume Movie', 'Type': 'Movie', 'Overview': 'Resume overview', 'UserData': <String, dynamic>{'PlayedPercentage': 42}})],
        nextUp = nextUp ?? <NextUpItem>[NextUpItem.fromJson(<String, dynamic>{'Id': 'episode', 'Name': 'Next Episode', 'Type': 'Episode', 'SeriesName': 'Show', 'ParentIndexNumber': 1, 'IndexNumber': 2})],
        movies = movies ?? <JellyfinLibraryItem>[JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': 'movie', 'Name': 'Latest Movie', 'Type': 'Movie', 'ProductionYear': 2024})],
        shows = shows ?? <JellyfinLibraryItem>[JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': 'series', 'Name': 'Latest Series', 'Type': 'Series'})],
        super(baseUrl: 'https://server/jellyfin', identity: testIdentity, client: http.Client());

  _FakeHomeClient.empty()
      : this(resume: const <ResumableItem>[], nextUp: const <NextUpItem>[], movies: const <JellyfinLibraryItem>[], shows: const <JellyfinLibraryItem>[]);

  final bool pending;
  final bool nextUpError;
  final List<ResumableItem> resume;
  final List<NextUpItem> nextUp;
  final List<JellyfinLibraryItem> movies;
  final List<JellyfinLibraryItem> shows;

  Future<List<T>> _maybePending<T>(List<T> value) => pending ? Completer<List<T>>().future : Future<List<T>>.value(value);

  @override
  Future<List<ResumableItem>> getResumeItems({int limit = 12}) => _maybePending(resume);
  @override
  Future<List<NextUpItem>> getNextUp({int limit = 12}) => nextUpError ? Future<List<NextUpItem>>.error(StateError('next up failed')) : _maybePending(nextUp);
  @override
  Future<List<JellyfinLibraryItem>> getLatestMovies({int limit = 20}) => _maybePending(movies);
  @override
  Future<List<JellyfinLibraryItem>> getLatestTvShows({int limit = 20}) => _maybePending(shows);
}
