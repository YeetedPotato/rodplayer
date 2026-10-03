import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:rodplayer/core/nautilus_settings_backup.dart';
import 'package:rodplayer/core/player_ui_settings.dart';

void main() {
  test('backup round-trips app-local player and Home settings only', () {
    final source = NautilusSettingsBackup(
      player: PlayerUiSettings.defaults.copyWith(seekIntervalSeconds: 30),
      home: HomeShelfPreferences.defaults.copyWith(
        order: <HomeShelfId>[
          HomeShelfId.latestShows,
          HomeShelfId.latestMovies,
          HomeShelfId.continueWatching,
          HomeShelfId.nextUp,
          HomeShelfId.popularMovies,
          HomeShelfId.popularShows,
        ],
        visible: <HomeShelfId>{HomeShelfId.latestShows},
      ),
    );
    final exported = source.exportJson();
    final restored = NautilusSettingsBackup.parseImport(exported);

    expect(restored.player.seekIntervalSeconds, 30);
    expect(restored.home.order, source.home.order);
    expect(restored.home.visible, source.home.visible);
    expect(exported, isNot(contains('token')));
    expect(exported, isNot(contains('password')));
  });

  test('backup rejects credentials, extra keys, and invalid shelf ids', () {
    final exported = NautilusSettingsBackup(
      player: PlayerUiSettings.defaults,
      home: HomeShelfPreferences.defaults,
    ).toJson();
    final injectedCredential = Map<String, dynamic>.from(exported)
      ..['accessToken'] = 'must not be accepted';
    expect(
      () => NautilusSettingsBackup.parseImport(jsonEncode(injectedCredential)),
      throwsFormatException,
    );

    final invalidHome = Map<String, dynamic>.from(exported)
      ..['homeShelves'] = <String, Object>{
        'order': <String>['continueWatching', 'bad'],
        'visible': <String>[],
      };
    expect(
      () => NautilusSettingsBackup.parseImport(jsonEncode(invalidHome)),
      throwsFormatException,
    );
  });
}
