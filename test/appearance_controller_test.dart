import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/theme/appearance_controller.dart';
import 'package:rodplayer/core/theme/appearance_mode.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing and corrupt appearance values default to OLED', () async {
    for (final initial in <Map<String, Object>>[
      <String, Object>{},
      <String, Object>{AppearanceController.preferenceKey: 'sepia'},
      <String, Object>{AppearanceController.preferenceKey: 12},
    ]) {
      SharedPreferences.setMockInitialValues(initial);
      final preferences = await SharedPreferences.getInstance();
      final controller = AppearanceController(preferences);
      expect(controller.mode, AppearanceMode.oled);
      expect(controller.effectiveMode, AppearanceMode.oled);
      expect(controller.themeData.scaffoldBackgroundColor,
          const Color(0xFF000000));
      controller.dispose();
    }
  });

  test('appearance selections persist and resolve to their palettes', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppearanceController(preferences);
    addTearDown(controller.dispose);

    for (final mode in <AppearanceMode>[
      AppearanceMode.light,
      AppearanceMode.dark,
      AppearanceMode.oled,
    ]) {
      await controller.setMode(mode);
      expect(
          preferences.getString(AppearanceController.preferenceKey), mode.name);
      expect(controller.effectiveMode, mode);
      expect(controller.themeData.brightness,
          mode == AppearanceMode.light ? Brightness.light : Brightness.dark);
      expect(controller.themeData.extension<RodPlayerTheme>()!.accent,
          const Color(0xFFA7F9FA));
    }
    expect(
        controller.themeData.scaffoldBackgroundColor, const Color(0xFF000000));
  });

  test('transient feedback is theme-aware in Light, Dark, and OLED', () {
    for (final mode in <AppearanceMode>[
      AppearanceMode.light,
      AppearanceMode.dark,
      AppearanceMode.oled,
    ]) {
      final theme = rodPlayerThemeData(mode: mode);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.snackBarTheme.backgroundColor, isNotNull);
      expect(theme.snackBarTheme.contentTextStyle?.color, isNotNull);
      expect(theme.snackBarTheme.actionTextColor,
          theme.extension<RodPlayerTheme>()!.accentBright);
      expect(theme.snackBarTheme.shape, isA<RoundedRectangleBorder>());
    }
  });

  test('System follows platform light and dark without selecting OLED',
      () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(binding.platformDispatcher.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppearanceController(preferences);
    addTearDown(controller.dispose);

    await controller.setMode(AppearanceMode.system);
    expect(controller.effectiveMode, AppearanceMode.light);
    expect(controller.themeData.brightness, Brightness.light);

    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    expect(controller.mode, AppearanceMode.system);
    expect(controller.effectiveMode, AppearanceMode.dark);
    expect(controller.themeData.scaffoldBackgroundColor,
        isNot(const Color(0xFF000000)));
  });
}
