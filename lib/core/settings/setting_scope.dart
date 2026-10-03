import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:rodplayer/core/player_ui_settings.dart';

enum SettingScope {
  deviceApp,
  server,
  account,
  playerBackend,
  session,
  title,
}

/// Declares both where a value may be stored and the precedence used when
/// more than one allowed scope supplies a value. Credentials are deliberately
/// excluded from this ordinary-settings model.
final class ScopedSettingDefinition<T> {
  ScopedSettingDefinition({
    required this.key,
    required this.defaultValue,
    required Iterable<SettingScope> allowedScopes,
    required Iterable<SettingScope> precedence,
  })  : allowedScopes = Set<SettingScope>.unmodifiable(allowedScopes),
        precedence = List<SettingScope>.unmodifiable(precedence) {
    if (!RegExp(r'^[a-z][A-Za-z0-9.]{0,63}$').hasMatch(key) ||
        _isCredentialLike(key)) {
      throw ArgumentError.value(key, 'key');
    }
    if (this.allowedScopes.isEmpty ||
        this.precedence.isEmpty ||
        this.precedence.toSet().length != this.precedence.length ||
        this.precedence.any((scope) => !this.allowedScopes.contains(scope))) {
      throw ArgumentError(
          'Setting scope precedence must be explicit and valid');
    }
  }

  final String key;
  final T defaultValue;
  final Set<SettingScope> allowedScopes;
  final List<SettingScope> precedence;

  T resolve(Map<SettingScope, T> values) {
    if (values.keys.any((scope) => !allowedScopes.contains(scope))) {
      throw ArgumentError('A setting value was supplied at a forbidden scope');
    }
    for (final scope in precedence) {
      if (values.containsKey(scope)) return values[scope] as T;
    }
    return defaultValue;
  }
}

bool _isCredentialLike(String value) => RegExp(
      r'(?:password|token|credential|secret|api.?key|authorization)',
      caseSensitive: false,
    ).hasMatch(value);

/// Scope inventory for the current app-local settings. Future server/account,
/// backend, session, or title preferences need their own definition and
/// explicit precedence before they are persisted or shown in UI.
abstract final class CurrentSettingDefinitions {
  static final appearanceMode = ScopedSettingDefinition<String>(
    key: 'appearance.mode',
    defaultValue: 'oled',
    allowedScopes: const <SettingScope>{SettingScope.deviceApp},
    precedence: const <SettingScope>[SettingScope.deviceApp],
  );

  static final sidebarLibrariesExpanded = ScopedSettingDefinition<bool>(
    key: 'navigation.librariesExpanded',
    defaultValue: true,
    allowedScopes: const <SettingScope>{SettingScope.deviceApp},
    precedence: const <SettingScope>[SettingScope.deviceApp],
  );

  static final homeShelves = ScopedSettingDefinition<HomeShelfPreferences>(
    key: 'home.shelves',
    defaultValue: HomeShelfPreferences.defaults,
    allowedScopes: const <SettingScope>{SettingScope.deviceApp},
    precedence: const <SettingScope>[SettingScope.deviceApp],
  );

  static final playerUi = ScopedSettingDefinition<PlayerUiSettings>(
    key: 'player.ui',
    defaultValue: PlayerUiSettings.defaults,
    allowedScopes: const <SettingScope>{SettingScope.deviceApp},
    precedence: const <SettingScope>[SettingScope.deviceApp],
  );
}
