import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:rodplayer/core/player_ui_settings.dart';
import 'package:rodplayer/core/theme/appearance_controller.dart';
import 'package:rodplayer/core/theme/appearance_mode.dart';
import 'package:rodplayer/ui/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('settings expose real appearance and player preferences',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final appearance = AppearanceController(prefs);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(appearanceController: appearance),
    ));
    await tester.pumpAndSettle();

    expect(find.text('App settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Player'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('10 seconds'), findsOneWidget);
    expect(find.text('Click video to play or pause'), findsOneWidget);
    expect(find.text('Single-click always toggles playback.'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.text('Click video to play or pause'),
            matching: find.byType(SwitchListTile)),
        findsNothing,
        reason:
            'surface click behavior is no longer a user-disableable toggle');
    Future<void> scrollTo(String label) async {
      for (var attempt = 0;
          attempt < 12 && find.text(label).evaluate().isEmpty;
          attempt++) {
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();
      }
      expect(find.text(label), findsOneWidget);
    }

    await scrollTo('Double-click video for fullscreen');

    for (final label in <String>[
      'Keyboard & mouse',
      'Audio & subtitles',
      'Data & backup',
      'About & diagnostics',
    ]) {
      await scrollTo(label);
    }
  });

  testWidgets('confirmed reset restores only UI settings', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PlayerUiSettings.seekKey: 30,
      PlayerUiSettings.hideKey: 8,
      PlayerUiSettings.endTimeKey: false,
      'rodplayer_appearance_mode': 'dark',
      'jellyfin_access_token': 'kept',
      'server_connection': 'kept',
    });
    final prefs = await SharedPreferences.getInstance();
    final appearance = AppearanceController(prefs);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(appearanceController: appearance),
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset UI settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset UI settings'));
    await tester.pumpAndSettle();

    expect(appearance.mode, AppearanceMode.oled);
    expect(prefs.getInt(PlayerUiSettings.seekKey), isNull);
    expect(prefs.getString('jellyfin_access_token'), 'kept');
    expect(prefs.getString('server_connection'), 'kept');
  });

  testWidgets('Home shelf controls persist visibility and order',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    HomeShelfPreferences? changed;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(onHomeShelfPreferencesChanged: (value) {
        changed = value;
      }),
    ));
    await tester.pumpAndSettle();
    final moviesSwitch =
        find.widgetWithText(SwitchListTile, 'New Movie Releases');
    await tester.scrollUntilVisible(
      moviesSwitch,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(moviesSwitch);
    await tester.pumpAndSettle();
    expect(
      (await HomeShelfPreferences.load(preferences: prefs)).visible,
      isNot(contains(HomeShelfId.latestMovies)),
    );

    final moveDown = find.byTooltip('Move Continue Watching down');
    await tester.ensureVisible(moveDown);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Continue Watching down'));
    await tester.pumpAndSettle();
    final saved = await HomeShelfPreferences.load(preferences: prefs);
    expect(saved.order.first, HomeShelfId.nextUp);
    expect(changed?.order, saved.order);
  });

  testWidgets('settings remain overflow-free across target layout widths',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final appearance = AppearanceController(prefs);
    addTearDown(appearance.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in <Size>[
      const Size(390, 844),
      const Size(430, 932),
      const Size(600, 900),
      const Size(768, 1024),
      const Size(900, 900),
      const Size(1024, 768),
      const Size(1280, 720),
      const Size(1440, 1000),
      const Size(1920, 1080),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(appearanceController: appearance),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'size: $size');
    }
  });
}
