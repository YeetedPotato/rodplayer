import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:rodplayer/core/nautilus_settings_backup.dart';
import 'package:rodplayer/core/player_ui_settings.dart';
import 'package:rodplayer/core/settings/ui_settings_persistence.dart';
import 'package:rodplayer/ui/screens/settings_screen.dart';
import 'package:rodplayer/core/theme/appearance_controller.dart';
import 'package:rodplayer/core/theme/appearance_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late _Storage storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {HomeShelfPreferences.schemaVersionKey: 1});
    prefs = await SharedPreferences.getInstance();
    storage = _Storage({'flutter.${HomeShelfPreferences.schemaVersionKey}': 1});
    SharedPreferencesStorePlatform.instance = storage;
  });

  NautilusSettingsBackup backup(int seek, {bool showEndTime = true}) =>
      NautilusSettingsBackup(
          player: PlayerUiSettings.defaults
              .copyWith(seekIntervalSeconds: seek, showEndTime: showEndTime),
          home: HomeShelfPreferences.defaults);

  testWidgets('settings load failure is scoped and retryable', (tester) async {
    await prefs.setString(PlayerUiSettings.hideKey, 'malformed');
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Settings unavailable. Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await prefs.remove(PlayerUiSettings.hideKey);
    await tester.tap(find.text('Settings unavailable. Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Seek interval'), findsOneWidget);
  });

  testWidgets('Home mutation preserves a newer shared player intent',
      (tester) async {
    // Settings opens on the baseline before the other surface changes player.
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    final owner = await UiSettingsPersistence.acquire(prefs);
    storage.gate = Completer<void>();
    storage.entered = Completer<void>();
    final pending = owner.updatePlayer(
        (value) => value.copyWith(seekIntervalSeconds: 30));
    await storage.entered!.future;
    await tester.pump();
    final shelf = HomeShelfPreferences.defaults.order.first;
    final toggle = find.widgetWithText(SwitchListTile, shelf.label);
    await tester.scrollUntilVisible(toggle, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(owner.intent.player.seekIntervalSeconds, 30);
    expect(owner.intent.home.visible, isNot(contains(shelf)));
    storage.gate!.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(prefs.getInt(PlayerUiSettings.seekKey), 30);
    final durable = await HomeShelfPreferences.load(preferences: prefs);
    expect(durable.visible, isNot(contains(shelf)));
    expect(owner.baseline.player.seekIntervalSeconds, 30);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settled unverified Settings state blocks export on acquisition',
      (tester) async {
    final owner = await UiSettingsPersistence.acquire(prefs);
    storage.failKey = 'flutter.${PlayerUiSettings.hideKey}';
    storage.failRead = true;
    expect(await owner.updatePlayer(
        (value) => value.copyWith(seekIntervalSeconds: 30)), isFalse);
    expect(owner.baselineVerified, isFalse);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Stored settings could not be verified.'), findsOneWidget);
    var exported = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') exported = true;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final exportButton = find.text('Export UI settings');
    await tester.scrollUntilVisible(exportButton, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(exportButton);
    await tester.pumpAndSettle();
    await tester.tap(exportButton);
    await tester.pumpAndSettle();
    expect(exported, isFalse);
    expect(find.text('Stored settings could not be verified. Export is unavailable.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    storage.failRead = false;
    expect(await owner.updatePlayer(
        (value) => value.copyWith(seekIntervalSeconds: 15)), isTrue);
    expect(tester.takeException(), isNull,
        reason: 'disposed Settings listener has been removed');
  });

  testWidgets('appearance save failure retains durable mode and remains scoped',
      (tester) async {
    final appearance = AppearanceController(prefs);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(appearanceController: appearance)));
    await tester.pumpAndSettle();
    storage.failKey = 'flutter.${AppearanceController.preferenceKey}';
    await tester.tap(find.widgetWithText(ChoiceChip, 'Light'));
    await tester.pumpAndSettle();
    expect(appearance.mode, AppearanceMode.oled);
    expect(find.text('Unable to save appearance. Previous mode retained.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('failed save restores exact raw keys and export uses durable baseline',
      () async {
    await prefs.setString('unrelated', 'retained');
    final before = await storage.getAll();
    final store = UiSettingsPersistence(prefs, backup(10));
    storage.failKey = 'flutter.${PlayerUiSettings.hideKey}';
    expect(await store.save(backup(30)), isFalse);
    expect(await storage.getAll(), before);
    expect(store.baseline.player.seekIntervalSeconds, 10);
    expect(
        NautilusSettingsBackup.parseImport(store.baseline.exportJson())
            .player
            .seekIntervalSeconds,
        10);
  });

  test('import failure midway restores both groups and returns failure',
      () async {
    await backup(15).player.save(prefs);
    await backup(15).home.save(prefs);
    final before = await storage.getAll();
    final store = UiSettingsPersistence(prefs, backup(15));
    storage.failKey = 'flutter.${HomeShelfPreferences.visibleKey}';
    expect(await store.save(backup(30, showEndTime: false)), isFalse);
    expect(await storage.getAll(), before);
    expect(store.baseline.player.seekIntervalSeconds, 15);
  });

  test('failed reload marks baseline unverified until a complete save succeeds',
      () async {
    final store = UiSettingsPersistence(prefs, backup(10));
    storage.failKey = 'flutter.${PlayerUiSettings.hideKey}';
    storage.failRead = true;
    expect(await store.save(backup(30)), isFalse);
    expect(store.baselineVerified, isFalse);
    expect(store.isSaving, isFalse);
    storage.failRead = false;
    expect(await store.save(backup(15)), isTrue);
    expect(store.baselineVerified, isTrue);
    expect(store.baseline.player.seekIntervalSeconds, 15);
  });

  test('rapid intents coalesce behind older in-flight write without reordering',
      () async {
    final store = UiSettingsPersistence(prefs, backup(10));
    storage.gate = Completer<void>();
    storage.entered = Completer<void>();
    final first = store.save(backup(15));
    await storage.entered!.future;
    final middle = store.save(backup(10));
    final last = store.save(backup(30, showEndTime: false));
    expect(identical(middle, last), isTrue);
    expect(storage.seekValues, [15]);
    storage.gate!.complete();
    expect(await Future.wait([first, middle, last]), everyElement(true));
    expect(storage.seekValues, [15, 30]);
    expect(store.baseline.player.seekIntervalSeconds, 30);
    expect(prefs.getInt(PlayerUiSettings.seekKey), 30);
    expect(store.isSaving, isFalse);
  });

  for (final failReload in [false, true]) {
    testWidgets(
        'failed imported settings remain scoped; reload failure=$failReload',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();
      storage.failKey = 'flutter.${HomeShelfPreferences.visibleKey}';
      storage.failRead = failReload;
      final importButton = find.text('Import UI settings');
      await tester.scrollUntilVisible(importButton, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(importButton);
      await tester.pumpAndSettle();
      await tester.tap(importButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), backup(30).exportJson());
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();
      expect(find.text('UI settings imported.'), findsNothing);
      expect(
          find.text(failReload
              ? 'Unable to save UI settings. Stored state could not be verified.'
              : 'Unable to save UI settings. Stored settings have been reloaded.'),
          findsOneWidget);
      expect(prefs.getInt(PlayerUiSettings.seekKey), isNull);
      String? exported;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData')
          exported = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final exportButton = find.text('Export UI settings');
      await tester.ensureVisible(exportButton);
      await tester.pumpAndSettle();
      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      if (failReload) {
        expect(exported, isNull);
        expect(
            find.text(
                'Stored settings could not be verified. Export is unavailable.'),
            findsOneWidget);
      } else {
        expect(
            NautilusSettingsBackup.parseImport(exported!)
                .player
                .seekIntervalSeconds,
            10);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

final class _Storage extends InMemorySharedPreferencesStore {
  _Storage(super.data) : super.withData();
  String? failKey;
  bool failRead = false;
  Completer<void>? gate;
  Completer<void>? entered;
  final seekValues = <int>[];

  @override
  Future<Map<String, Object>> getAll() async {
    if (failRead) throw StateError('Read unavailable');
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.${PlayerUiSettings.seekKey}') {
      seekValues.add(value as int);
      if (entered != null && !entered!.isCompleted) {
        entered!.complete();
        await gate?.future;
      }
    }
    if (key == failKey) {
      failKey = null;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}
