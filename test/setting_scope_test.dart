import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:rodplayer/core/player_ui_settings.dart';
import 'package:rodplayer/core/settings/setting_scope.dart';

void main() {
  test('existing appearance setting is app-local with explicit fallback', () {
    final definition = CurrentSettingDefinitions.appearanceMode;
    expect(definition.allowedScopes, <SettingScope>{SettingScope.deviceApp});
    expect(definition.precedence, <SettingScope>[SettingScope.deviceApp]);
    expect(definition.resolve(const <SettingScope, String>{}), 'oled');
    expect(
      definition.resolve(const <SettingScope, String>{
        SettingScope.deviceApp: 'light',
      }),
      'light',
    );
  });

  test('navigation, Home, and player settings use device-local scope', () {
    final navigation = CurrentSettingDefinitions.sidebarLibrariesExpanded;
    expect(navigation.allowedScopes, <SettingScope>{SettingScope.deviceApp});
    expect(navigation.precedence, <SettingScope>[SettingScope.deviceApp]);
    expect(navigation.resolve(const <SettingScope, bool>{}), isTrue);

    final home = CurrentSettingDefinitions.homeShelves;
    expect(home.allowedScopes, <SettingScope>{SettingScope.deviceApp});
    expect(home.precedence, <SettingScope>[SettingScope.deviceApp]);
    expect(home.resolve(const <SettingScope, HomeShelfPreferences>{}),
        HomeShelfPreferences.defaults);

    final player = CurrentSettingDefinitions.playerUi;
    expect(player.allowedScopes, <SettingScope>{SettingScope.deviceApp});
    expect(player.precedence, <SettingScope>[SettingScope.deviceApp]);
    expect(player.resolve(const <SettingScope, PlayerUiSettings>{}),
        PlayerUiSettings.defaults);
  });

  test('precedence is declared per setting instead of globally', () {
    final definition = ScopedSettingDefinition<String>(
      key: 'subtitle.language',
      defaultValue: 'auto',
      allowedScopes: const <SettingScope>{
        SettingScope.deviceApp,
        SettingScope.account,
        SettingScope.title,
      },
      precedence: const <SettingScope>[
        SettingScope.title,
        SettingScope.account,
        SettingScope.deviceApp,
      ],
    );
    expect(
      definition.resolve(const <SettingScope, String>{
        SettingScope.deviceApp: 'en',
        SettingScope.account: 'fr',
        SettingScope.title: 'de',
      }),
      'de',
    );
    expect(
      () => definition.resolve(const <SettingScope, String>{
        SettingScope.server: 'es',
      }),
      throwsArgumentError,
    );
  });

  test('credentials cannot be declared as ordinary settings', () {
    expect(
      () => ScopedSettingDefinition<String>(
        key: 'account.accessToken',
        defaultValue: '',
        allowedScopes: const <SettingScope>{SettingScope.account},
        precedence: const <SettingScope>[SettingScope.account],
      ),
      throwsArgumentError,
    );
  });
}
