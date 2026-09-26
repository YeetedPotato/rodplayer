import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appearance_mode.dart';
import 'rodplayer_theme.dart';

class AppearanceController extends ChangeNotifier with WidgetsBindingObserver {
  AppearanceController(this._preferences) {
    String? savedMode;
    try {
      savedMode = _preferences.getString(preferenceKey);
    } on TypeError {
      // A value stored with the wrong preference type is treated as corrupt.
    }
    _mode = AppearanceMode.values.firstWhere(
      (mode) => mode.name == savedMode,
      orElse: () => AppearanceMode.oled,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  static const preferenceKey = 'rodplayer_appearance_mode';

  final SharedPreferences _preferences;
  late AppearanceMode _mode;

  AppearanceMode get mode => _mode;
  Brightness get platformBrightness =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  AppearanceMode get effectiveMode => _mode == AppearanceMode.system
      ? (platformBrightness == Brightness.light
          ? AppearanceMode.light
          : AppearanceMode.dark)
      : _mode;

  ThemeData get themeData => rodPlayerThemeData(mode: effectiveMode);

  Future<void> setMode(AppearanceMode mode) async {
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
    await _preferences.setString(preferenceKey, mode.name);
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == AppearanceMode.system) notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
