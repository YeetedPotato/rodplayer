import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/core/theme/appearance_mode.dart';
import 'package:rodplayer/ui/screens/home_screen.dart';
import 'package:rodplayer/ui/screens/discover_screen.dart';
import 'package:rodplayer/ui/screens/item_details_screen.dart';
import 'package:rodplayer/ui/screens/profile_screen.dart';
import 'package:rodplayer/ui/screens/search_screen.dart';
import 'package:rodplayer/ui/shell/rodplayer_app_shell.dart';
import 'package:rodplayer/ui/shell/nautilus_navigation.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  test('RodPlayer theme uses the icy cyan primary accent', () {
    const expected = Color(0xFFA7F9FA);
    final theme = rodPlayerThemeData();

    expect(theme.colorScheme.primary, expected);
    expect(theme.extension<RodPlayerTheme>()!.accent, expected);
  });

  Widget app(Widget child, {NavigationMode navigationMode = NavigationMode.traditional, double textScale = 1, AppearanceMode appearance = AppearanceMode.oled}) => MaterialApp(
        theme: rodPlayerThemeData(mode: appearance),
        home: Builder(builder: (context) {
          final media = MediaQuery.of(context);
          return MediaQuery(data: media.copyWith(navigationMode: navigationMode, textScaler: TextScaler.linear(textScale)), child: child);
        }),
      );
  Widget home(_FakeHomeClient client, {PlayItemCallback? onPlayItem}) => Scaffold(body: HomeScreen(client: client, onPlayItem: onPlayItem));

  void setSurface(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('authenticated shell defaults to Home and renders before futures finish', (tester) async {
    setSurface(tester, const Size(1200, 800));
    final client = _FakeHomeClient(pending: true);
    await tester.pumpWidget(app(RodPlayerAppShell(client: client, onLogout: () async {}, onSwitchProfile: () async {})));

    expect(find.text('Nautilus'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('light appearance renders the Home shell without layout errors', (tester) async {
    setSurface(tester, const Size(390, 760));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(app(
      RodPlayerAppShell(client: _FakeHomeClient(), onLogout: () async {}, onSwitchProfile: () async {}),
      appearance: AppearanceMode.light,
    ));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(HomeScreen))).brightness, Brightness.light);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact shell uses bottom navigation and switches Home/Search', (tester) async {
    setSurface(tester, const Size(390, 760));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(app(RodPlayerAppShell(client: _FakeHomeClient(), onLogout: () async {}, onSwitchProfile: () async {})));
    await tester.pumpAndSettle();

    expect(find.byType(NautilusBottomNavigation), findsOneWidget);
    expect(find.byType(NautilusSideNavigation), findsNothing);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Movies'), findsWidgets);
    expect(find.text('Shows'), findsWidgets);
    expect(find.text('Search'), findsWidgets);
    final bottomNavigation = find.byType(NautilusBottomNavigation);
    for (final label in <String>['Home', 'Movies', 'Shows', 'Search']) {
      expect(
          find.descendant(
              of: bottomNavigation, matching: find.text(label)),
          findsOneWidget);
    }
    expect(
        find.descendant(
            of: bottomNavigation, matching: find.text('Discover')),
        findsNothing);
    expect(find.byTooltip('Discover'), findsOneWidget);
    await tester.tap(find.byTooltip('Discover'));
    await tester.pumpAndSettle();
    expect(find.byType(DiscoverScreen), findsOneWidget);
    expect(find.text('Discover'), findsWidgets);
    expect(
        find.descendant(
            of: bottomNavigation, matching: find.text('Discover')),
        findsNothing);
    expect(find.byIcon(Icons.explore), findsOneWidget);
    await tester.tap(find.byIcon(Icons.search).last);
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.home_outlined).last);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('expanded and directional shells use side navigation and expose logout', (tester) async {
    setSurface(tester, const Size(1200, 800));
    var loggedOut = false;
    await tester.pumpWidget(app(RodPlayerAppShell(client: _FakeHomeClient(), onLogout: () async => loggedOut = true, onSwitchProfile: () async {}), navigationMode: NavigationMode.directional));
    await tester.pumpAndSettle();

    expect(find.byType(NautilusSideNavigation), findsOneWidget);
    expect(find.byType(NautilusBottomNavigation), findsNothing);
    expect(find.text('Movies'), findsWidgets);
    expect(find.text('Shows'), findsWidgets);
    await tester.tap(find.text('Movies').first);
    await tester.pumpAndSettle();
    expect(find.text('No movies found'), findsOneWidget);
    await tester.tap(find.text('Shows').first);
    await tester.pumpAndSettle();
    expect(find.text('No shows found'), findsOneWidget);
    await tester.tap(find.text('Log out'));
    expect(loggedOut, isTrue);
  });

  testWidgets('embedded search has no nested app bar and retains query state', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(app(RodPlayerAppShell(client: _FakeHomeClient(), onLogout: () async {}, onSwitchProfile: () async {})));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'typed');
    await tester.tap(find.byIcon(Icons.home_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(find.widgetWithText(TextField, 'typed'), findsOneWidget);
  });

  testWidgets('Ctrl+K selects and focuses embedded Search', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(app(RodPlayerAppShell(client: _FakeHomeClient(), onLogout: () async {}, onSwitchProfile: () async {})));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus, isTrue);
  });

  testWidgets('Home renders typed sections and isolates failed sections', (tester) async {
    await tester.pumpWidget(app(home(_FakeHomeClient(nextUpError: true))));
    await tester.pumpAndSettle();

    expect(find.text('Resume Movie'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Next Up unavailable'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Next Up unavailable'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Latest Movie'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Latest Movie'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Latest Series'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Latest Series'), findsOneWidget);
  });

  testWidgets('failed shelf retry reloads only that section', (tester) async {
    final client = _FakeHomeClient(nextUpError: true);
    await tester.pumpWidget(app(home(client)));
    await tester.pumpAndSettle();

    expect((client.resumeCalls, client.nextUpCalls, client.movieCalls, client.showCalls), (1, 1, 1, 1));
    await tester.scrollUntilVisible(find.widgetWithText(TextButton, 'Retry'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Retry').first);
    await tester.pumpAndSettle();

    expect((client.resumeCalls, client.nextUpCalls, client.movieCalls, client.showCalls), (1, 2, 1, 1));
    await tester.scrollUntilVisible(find.text('Resume Movie'), -300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Resume Movie'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Latest Movie'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Latest Movie'), findsOneWidget);
  });

  testWidgets('Home empty state appears once when all sections are empty', (tester) async {
    await tester.pumpWidget(app(home(_FakeHomeClient.empty())));
    await tester.pumpAndSettle();

    expect(find.text('No home content yet'), findsOneWidget);
    expect(find.text('RodPlayer'), findsNothing);
  });

  testWidgets('hero priority and playback entry use injected boundary', (tester) async {
    String? played;
    await tester.pumpWidget(app(home(_FakeHomeClient(), onPlayItem: (_, id) => played = id)));
    await tester.pumpAndSettle();

    expect(find.text('Resume Movie'), findsWidgets);
    expect(find.byKey(const ValueKey<String>('home-cinematic-media-bar')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Resume').first);
    expect(played, 'resume');
  });

  testWidgets('desktop cinematic media bar fills the available Home width',
      (tester) async {
    setSurface(tester, const Size(1200, 800));
    await tester.pumpWidget(app(
      RodPlayerAppShell(
        client: _FakeHomeClient(),
        onLogout: () async {},
        onSwitchProfile: () async {},
      ),
      navigationMode: NavigationMode.directional,
    ));
    await tester.pumpAndSettle();

    final homeRect = tester.getRect(find.byType(HomeScreen));
    final mediaBarRect = tester.getRect(
      find.byKey(const ValueKey<String>('home-cinematic-media-bar')),
    );
    expect(mediaBarRect.left, homeRect.left);
    expect(mediaBarRect.width, homeRect.width);
    expect(mediaBarRect.height, inInclusiveRange(480, 600));
  });

  testWidgets('hero skips non-playable resume and falls back to playable items', (tester) async {
    await tester.pumpWidget(app(home(_FakeHomeClient(resume: <ResumableItem>[
      ResumableItem.fromJson(<String, dynamic>{'Id': 'series-resume', 'Name': 'Resume Series', 'Type': 'Series', 'UserData': <String, dynamic>{'PlayedPercentage': 50}}),
    ]))));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Resume'), findsNothing);
    expect(find.text('Next Episode'), findsWidgets);
  });

  testWidgets('hero falls back to next up and latest movie', (tester) async {
    await tester.pumpWidget(app(home(_FakeHomeClient(resume: const <ResumableItem>[]))));
    await tester.pumpAndSettle();
    expect(find.text('Next Episode'), findsWidgets);

    await tester.pumpWidget(app(home(_FakeHomeClient(resume: const <ResumableItem>[], nextUp: const <NextUpItem>[]))));
    await tester.pumpAndSettle();
    expect(find.text('Latest Movie'), findsWidgets);
  });

  testWidgets('Series does not get fabricated direct Play', (tester) async {
    await tester.pumpWidget(app(home(_FakeHomeClient(resume: const <ResumableItem>[], nextUp: const <NextUpItem>[], movies: const <JellyfinLibraryItem>[]))));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Latest Series').first);
    expect(find.text('Latest Series'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Play'), findsNothing);
  });

  testWidgets('Home shelf cards open item details while hero remains direct playback', (tester) async {
    String? played;
    await tester.pumpWidget(app(home(_FakeHomeClient(), onPlayItem: (_, id) => played = id)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Resume').first);
    expect(played, 'resume');
    await tester.tap(find.byKey(const ValueKey<String>('home-cinematic-info-button')));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailsScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(ItemDetailsScreen))).pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(_card('Resume Movie'));
    await tester.tap(_card('Resume Movie'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailsScreen), findsOneWidget);
    expect(find.text('Resume Movie'), findsWidgets);
    Navigator.of(tester.element(find.byType(ItemDetailsScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Resume Movie'), findsWidgets);

    await tester.scrollUntilVisible(_card('Next Episode'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(_card('Next Episode'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailsScreen), findsOneWidget);
    expect(find.textContaining('Show'), findsWidgets);
    Navigator.of(tester.element(find.byType(ItemDetailsScreen))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(_card('Latest Movie'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(_card('Latest Movie'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailsScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(ItemDetailsScreen))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(_card('Latest Series'), 300, scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(_card('Latest Series'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailsScreen), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Play'), findsNothing);
  });

  testWidgets('progress semantics handle unknown zero positive and clamp', (tester) async {
    await tester.pumpWidget(app(home(_FakeHomeClient(resume: <ResumableItem>[ResumableItem.fromJson(<String, dynamic>{'Id': 'resume', 'Name': 'Unknown', 'Type': 'Movie'})]))));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);

    await tester.pumpWidget(app(home(_FakeHomeClient(resume: <ResumableItem>[ResumableItem.fromJson(<String, dynamic>{'Id': 'resume', 'Name': 'Zero', 'Type': 'Movie', 'UserData': <String, dynamic>{'PlayedPercentage': 0}})]))));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);

    await tester.pumpWidget(app(home(_FakeHomeClient(resume: <ResumableItem>[ResumableItem.fromJson(<String, dynamic>{'Id': 'resume', 'Name': 'Positive', 'Type': 'Movie', 'UserData': <String, dynamic>{'PlayedPercentage': 25}})]))));
    await tester.pumpAndSettle();
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first).value, .25);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);

    await tester.pumpWidget(app(home(_FakeHomeClient(resume: <ResumableItem>[ResumableItem.fromJson(<String, dynamic>{'Id': 'resume', 'Name': 'Clamped', 'Type': 'Movie', 'UserData': <String, dynamic>{'PlayedPercentage': 150}})]))));
    await tester.pumpAndSettle();
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first).value, 1);
  });

  testWidgets('compact Home tolerates larger text without overflow', (tester) async {
    setSurface(tester, const Size(390, 620));
    await tester.pumpWidget(app(home(_FakeHomeClient()), textScale: 1.25));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Resume Movie'), findsWidgets);
  });

  testWidgets('wide pointer shell shows expanded Nautilus side navigation',
      (tester) async {
    setSurface(tester, const Size(1200, 800));
    await tester.pumpWidget(app(RodPlayerAppShell(
        client: _FakeHomeClient(),
        onLogout: () async {},
        onSwitchProfile: () async {})));
    await tester.pumpAndSettle();

    expect(find.byType(NautilusSideNavigation), findsOneWidget);
    expect(find.text('Nautilus'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.text('Discover').first);
    await tester.pumpAndSettle();
    expect(find.byType(DiscoverScreen), findsOneWidget);
    expect(find.byIcon(Icons.explore), findsOneWidget);
  });

  testWidgets('medium sidebar collapses and expands without changing selection',
      (tester) async {
    setSurface(tester, const Size(900, 800));
    await tester.pumpWidget(app(RodPlayerAppShell(
        client: _FakeHomeClient(),
        onLogout: () async {},
        onSwitchProfile: () async {})));
    await tester.pumpAndSettle();

    expect(find.text('Nautilus'), findsNothing);
    expect(find.byTooltip('Expand navigation'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand navigation'));
    await tester.pumpAndSettle();
    expect(find.text('Nautilus'), findsOneWidget);

    await tester.tap(find.text('Shows').first);
    await tester.pumpAndSettle();
    expect(find.text('No shows found'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse navigation'));
    await tester.pumpAndSettle();
    expect(find.text('Nautilus'), findsNothing);
    expect(find.byIcon(Icons.tv), findsOneWidget);
    expect(find.byTooltip('Shows'), findsOneWidget);
  });

  testWidgets('collapsed destinations expose tooltips and focusable actions',
      (tester) async {
    setSurface(tester, const Size(900, 800));
    await tester.pumpWidget(app(RodPlayerAppShell(
        client: _FakeHomeClient(),
        onLogout: () async {},
        onSwitchProfile: () async {})));
    await tester.pumpAndSettle();

    for (final label in <String>['Home', 'Movies', 'Shows', 'Discover', 'Search']) {
      expect(find.byTooltip(label), findsOneWidget);
    }
    final navItems = find.descendant(
        of: find.byType(NautilusSideNavigation),
        matching: find.byType(InkWell));
    expect(navItems, findsNWidgets(8));
    expect(
        tester
            .widgetList<InkWell>(navItems)
            .every((item) => item.onTap != null),
        isTrue);
  });

  testWidgets('Cmd+K selects and focuses embedded Search', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(app(RodPlayerAppShell(
        client: _FakeHomeClient(),
        onLogout: () async {},
        onSwitchProfile: () async {})));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isTrue);
  });

  testWidgets('desktop Profile action opens the existing ProfileScreen',
      (tester) async {
    setSurface(tester, const Size(1200, 800));
    await tester.pumpWidget(app(RodPlayerAppShell(
        client: _FakeHomeClient(),
        onLogout: () async {},
        onSwitchProfile: () async {})));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Profile'), findsWidgets);
  });

  testWidgets(
      'mobile glass navigation has four tabs and a Discover app bar action',
      (tester) async {
    setSurface(tester, const Size(390, 760));
    await tester.pumpWidget(app(RodPlayerAppShell(
        client: _FakeHomeClient(),
        onLogout: () async {},
        onSwitchProfile: () async {})));
    await tester.pumpAndSettle();

    final bar = find.byType(NautilusBottomNavigation);
    expect(bar, findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.descendant(of: bar, matching: find.byType(InkWell)),
        findsNWidgets(4));
    for (final label in <String>['Home', 'Movies', 'Shows', 'Search']) {
      expect(find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget);
    }
    expect(find.descendant(of: bar, matching: find.text('Discover')),
        findsNothing);
    expect(find.byTooltip('Discover'), findsOneWidget);
    expect(find.text('Favorites'), findsNothing);
    expect(find.text('Collections'), findsNothing);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets(
      'directional focus can move from navigation into content and back',
      (tester) async {
    setSurface(tester, const Size(1200, 800));
    await tester.pumpWidget(app(
      RodPlayerAppShell(
          client: _FakeHomeClient(),
          onLogout: () async {},
          onSwitchProfile: () async {}),
      navigationMode: NavigationMode.directional,
    ));
    await tester.pumpAndSettle();

    Focus.of(tester.element(find.text('Home').first)).requestFocus();
    await tester.pump();
    final sidebarFocus = FocusManager.instance.primaryFocus;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final contentFocus = FocusManager.instance.primaryFocus;
    expect(contentFocus, isNot(same(sidebarFocus)));
    final contentWidget = find.byWidget(contentFocus!.context!.widget);
    expect(
        find.ancestor(
            of: contentWidget, matching: find.byType(NautilusSideNavigation)),
        findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    final returnedWidget =
        find.byWidget(FocusManager.instance.primaryFocus!.context!.widget);
    expect(
        find.ancestor(
            of: returnedWidget, matching: find.byType(NautilusSideNavigation)),
        findsOneWidget);
  });

  testWidgets('Light Dark and OLED shell layouts render without overflow',
      (tester) async {
    setSurface(tester, const Size(1200, 800));
    for (final mode in <AppearanceMode>[
      AppearanceMode.light,
      AppearanceMode.dark,
      AppearanceMode.oled
    ]) {
      await tester.pumpWidget(app(
        RodPlayerAppShell(
            client: _FakeHomeClient(),
            onLogout: () async {},
            onSwitchProfile: () async {}),
        appearance: mode,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: mode.name);
    }
  });

  testWidgets('expanded navigation tolerates larger text and remains focusable',
      (tester) async {
    setSurface(tester, const Size(1200, 800));
    await tester.pumpWidget(app(
      RodPlayerAppShell(
          client: _FakeHomeClient(),
          onLogout: () async {},
          onSwitchProfile: () async {}),
      textScale: 1.5,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Nautilus'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(NautilusSideNavigation),
            matching: find.byType(InkWell)),
        findsNWidgets(8));
    expect(tester.takeException(), isNull);
  });
}

Finder _card(String title) => find.byWidgetPredicate((widget) => widget is FocusableMediaCard && widget.title == title);

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
        super(baseUrl: 'https://server/jellyfin', identity: testIdentity, client: http_testing.MockClient((_) async => http.Response('{}', 200)));

  _FakeHomeClient.empty()
      : this(resume: const <ResumableItem>[], nextUp: const <NextUpItem>[], movies: const <JellyfinLibraryItem>[], shows: const <JellyfinLibraryItem>[]);

  final bool pending;
  final bool nextUpError;
  final List<ResumableItem> resume;
  final List<NextUpItem> nextUp;
  final List<JellyfinLibraryItem> movies;
  final List<JellyfinLibraryItem> shows;
  int resumeCalls = 0;
  int nextUpCalls = 0;
  int movieCalls = 0;
  int showCalls = 0;

  Future<List<T>> _maybePending<T>(List<T> value) => pending ? Completer<List<T>>().future : Future<List<T>>.value(value);

  @override
  Future<List<ResumableItem>> getResumeItems({int limit = 12}) {
    resumeCalls++;
    return _maybePending(resume);
  }

  @override
  Future<List<NextUpItem>> getNextUp({int limit = 12}) {
    nextUpCalls++;
    return nextUpError ? Future<List<NextUpItem>>.error(StateError('next up failed')) : _maybePending(nextUp);
  }

  @override
  Future<List<JellyfinLibraryItem>> getLatestMovies({int limit = 20}) {
    movieCalls++;
    return _maybePending(movies);
  }

  @override
  Future<List<JellyfinLibraryItem>> getLatestTvShows({int limit = 20}) {
    showCalls++;
    return _maybePending(shows);
  }

  @override
  Future<JellyfinItemsPage<JellyfinLibraryItem>> getLibraryItemsPage({
    required JellyfinLibraryKind kind,
    JellyfinLibrarySort sort = JellyfinLibrarySort.title,
    JellyfinLibraryFilter filter = JellyfinLibraryFilter.all,
    int startIndex = 0,
    int limit = 48,
    String? parentId,
  }) async =>
      JellyfinItemsPage<JellyfinLibraryItem>(items: const <JellyfinLibraryItem>[], totalRecordCount: 0, startIndex: startIndex);

  @override
  Future<JellyfinLibraryItem> getItem(String itemId) async => <JellyfinLibraryItem>[...resume, ...nextUp, ...movies, ...shows].firstWhere((item) => item.id == itemId, orElse: () => JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': itemId, 'Name': 'Item'}));

  @override
  Future<List<JellyfinLibraryItem>> getSeasons({required String seriesId}) async => const <JellyfinLibraryItem>[];

  @override
  Future<List<JellyfinLibraryItem>> getEpisodes({required String seriesId, required String seasonId}) async => const <JellyfinLibraryItem>[];
}
