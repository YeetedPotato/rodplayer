import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/player_ui_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('player preferences have deterministic defaults and persist values',
      () async {
    var settings = await PlayerUiSettings.load();
    expect(settings.seekIntervalSeconds, 10);
    expect(settings.autoHideSeconds, 3);
    expect(settings.showEndTime, isTrue);
    expect(settings.singleClickPlayPause, isTrue);
    expect(settings.doubleClickFullscreen, isTrue);
    expect(settings.mouseWheelVolume, isTrue);

    final prefs = await SharedPreferences.getInstance();
    settings = settings.copyWith(
      seekIntervalSeconds: 15,
      autoHideSeconds: 5,
      showEndTime: false,
      doubleClickFullscreen: false,
      mouseWheelVolume: false,
    );
    await settings.save(prefs);
    final loaded = await PlayerUiSettings.load(preferences: prefs);
    expect(loaded.seekIntervalSeconds, 15);
    expect(loaded.autoHideSeconds, 5);
    expect(loaded.showEndTime, isFalse);
    expect(loaded.doubleClickFullscreen, isFalse);
    expect(loaded.mouseWheelVolume, isFalse);
  });

  test('versioned export contains only safe UI values and validates import',
      () {
    const settings = PlayerUiSettings(
      seekIntervalSeconds: 30,
      autoHideSeconds: 8,
      showEndTime: false,
      singleClickPlayPause: false,
      doubleClickFullscreen: false,
      mouseWheelVolume: true,
    );
    final exported = settings.exportJson();
    expect(jsonDecode(exported), settings.toJson());
    expect(exported, isNot(contains('token')));
    expect(PlayerUiSettings.parseImport(exported).seekIntervalSeconds, 30);

    expect(
      () => PlayerUiSettings.parseImport(
        exported.replaceFirst('"schemaVersion": 1', '"schemaVersion": 2'),
      ),
      throwsFormatException,
    );
    expect(
      () => PlayerUiSettings.parseImport(
        exported.replaceFirst('"showEndTime": false',
            '"accessToken": "secret", "showEndTime": false'),
      ),
      throwsFormatException,
    );
    expect(
      () => PlayerUiSettings.parseImport(
        exported.replaceFirst(
            '"seekIntervalSeconds": 30', '"seekIntervalSeconds": 180'),
      ),
      throwsFormatException,
    );
  });

  test('reset clears only app-local player preference keys', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PlayerUiSettings.seekKey: 30,
      PlayerUiSettings.hideKey: 8,
      'rodplayer_appearance_mode': 'dark',
      'jellyfin_access_token': 'kept',
      'server_connection': 'kept',
    });
    final prefs = await SharedPreferences.getInstance();
    await PlayerUiSettings.reset(prefs);

    expect(prefs.getInt(PlayerUiSettings.seekKey), isNull);
    expect(prefs.getInt(PlayerUiSettings.hideKey), isNull);
    expect(prefs.getString('rodplayer_appearance_mode'), 'dark');
    expect(prefs.getString('jellyfin_access_token'), 'kept');
    expect(prefs.getString('server_connection'), 'kept');
  });
}
