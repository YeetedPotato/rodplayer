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
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;

  AppearanceMode get mode => _mode;
  Brightness get platformBrightness =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  AppearanceMode get effectiveMode => _mode == AppearanceMode.system
      ? (platformBrightness == Brightness.light
          ? AppearanceMode.light
          : AppearanceMode.dark)
      : _mode;

  ThemeData get themeData => rodPlayerThemeData(mode: effectiveMode);

  Future<void> setMode(AppearanceMode mode) {
    final result = _writes.then((_) async {
      if (_disposed) return;
      try {
        if (!await _preferences.setString(preferenceKey, mode.name)) {
          throw StateError('Appearance could not be saved');
        }
      } on Object {
        await _preferences.reload();
        rethrow;
      }
      if (_disposed) return;
      _mode = mode;
      notifyListeners();
    });
    _writes = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == AppearanceMode.system) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
