import 'dart:ui';

import 'package:flutter/material.dart';

import 'appearance_mode.dart';

@immutable
class RodPlayerTheme extends ThemeExtension<RodPlayerTheme> {
  const RodPlayerTheme({
    this.obsidian = const Color(0xFF000000),
    this.surface1 = const Color(0xFF08090B),
    this.surface2 = const Color(0xFF0D0F12),
    this.surface3 = const Color(0xFF14171B),
    this.obsidianRaised = const Color(0xFF08090B),
    this.obsidianGlass = const Color(0xCC0D0F12),
    this.obsidianGlassStrong = const Color(0xF014171B),
    this.accent = const Color(0xFFA7F9FA),
    this.accentBright = const Color(0xFFD9FFFF),
    this.accentDeep = const Color(0xFF174B50),
    this.textPrimary = const Color(0xFFF4F6F8),
    this.textSecondary = const Color(0xFFA2A9B3),
    this.textMuted = const Color(0xFF707780),
    this.success = const Color(0xFF83C98A),
    this.error = const Color(0xFFE27D72),
    this.radiusPill = 999,
    this.radiusSmall = 8,
    this.radiusMedium = 14,
    this.radiusLarge = 20,
    this.radiusXLarge = 22,
    this.glassBlur = 18,
    this.shadowColor = const Color(0x66000000),
    this.border = const Color(0xFFFFFFFF),
    this.artworkScrim = const Color(0xFF000000),
    this.artworkTextPrimary = const Color(0xFFF4F6F8),
    this.artworkTextSecondary = const Color(0xFFA2A9B3),
  });

  final Color obsidian, surface1, surface2, surface3, obsidianRaised;
  final Color obsidianGlass,
      obsidianGlassStrong,
      accent,
      accentBright,
      accentDeep;
  final Color textPrimary,
      textSecondary,
      textMuted,
      success,
      error,
      shadowColor,
      border,
      artworkScrim,
      artworkTextPrimary,
      artworkTextSecondary;
  final double radiusPill, radiusSmall, radiusMedium, radiusLarge, radiusXLarge;
  final double glassBlur;

  List<BoxShadow> get glassShadow => [
        BoxShadow(
            color: shadowColor, blurRadius: 24, offset: const Offset(0, 10)),
      ];

  List<BoxShadow> get accentGlow => [
        BoxShadow(
          color: accent.withValues(alpha: 0.22),
          blurRadius: 18,
          spreadRadius: 1,
        ),
      ];

  Color borderColor([double alpha = 0.1]) => border.withValues(alpha: alpha);

  BorderRadius radius(double value) => BorderRadius.circular(value);

  @override
  RodPlayerTheme copyWith({
    Color? obsidian,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? obsidianRaised,
    Color? obsidianGlass,
    Color? obsidianGlassStrong,
    Color? accent,
    Color? accentBright,
    Color? accentDeep,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? error,
    double? radiusPill,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? radiusXLarge,
    double? glassBlur,
    Color? shadowColor,
    Color? border,
    Color? artworkScrim,
    Color? artworkTextPrimary,
    Color? artworkTextSecondary,
  }) =>
      RodPlayerTheme(
        obsidian: obsidian ?? this.obsidian,
        surface1: surface1 ?? this.surface1,
        surface2: surface2 ?? this.surface2,
        surface3: surface3 ?? this.surface3,
        obsidianRaised: obsidianRaised ?? this.obsidianRaised,
        obsidianGlass: obsidianGlass ?? this.obsidianGlass,
        obsidianGlassStrong: obsidianGlassStrong ?? this.obsidianGlassStrong,
        accent: accent ?? this.accent,
        accentBright: accentBright ?? this.accentBright,
        accentDeep: accentDeep ?? this.accentDeep,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        success: success ?? this.success,
        error: error ?? this.error,
        radiusPill: radiusPill ?? this.radiusPill,
        radiusSmall: radiusSmall ?? this.radiusSmall,
        radiusMedium: radiusMedium ?? this.radiusMedium,
        radiusLarge: radiusLarge ?? this.radiusLarge,
        radiusXLarge: radiusXLarge ?? this.radiusXLarge,
        glassBlur: glassBlur ?? this.glassBlur,
        shadowColor: shadowColor ?? this.shadowColor,
        border: border ?? this.border,
        artworkScrim: artworkScrim ?? this.artworkScrim,
        artworkTextPrimary: artworkTextPrimary ?? this.artworkTextPrimary,
        artworkTextSecondary: artworkTextSecondary ?? this.artworkTextSecondary,
      );

  @override
  RodPlayerTheme lerp(covariant RodPlayerTheme? other, double t) {
    if (other == null) return this;
    return copyWith(
      obsidian: Color.lerp(obsidian, other.obsidian, t),
      surface1: Color.lerp(surface1, other.surface1, t),
      surface2: Color.lerp(surface2, other.surface2, t),
      surface3: Color.lerp(surface3, other.surface3, t),
      obsidianRaised: Color.lerp(obsidianRaised, other.obsidianRaised, t),
      obsidianGlass: Color.lerp(obsidianGlass, other.obsidianGlass, t),
      obsidianGlassStrong:
          Color.lerp(obsidianGlassStrong, other.obsidianGlassStrong, t),
      accent: Color.lerp(accent, other.accent, t),
      accentBright: Color.lerp(accentBright, other.accentBright, t),
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t),
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t),
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t),
      textMuted: Color.lerp(textMuted, other.textMuted, t),
      success: Color.lerp(success, other.success, t),
      error: Color.lerp(error, other.error, t),
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t),
      border: Color.lerp(border, other.border, t),
      artworkScrim: Color.lerp(artworkScrim, other.artworkScrim, t),
      artworkTextPrimary:
          Color.lerp(artworkTextPrimary, other.artworkTextPrimary, t),
      artworkTextSecondary:
          Color.lerp(artworkTextSecondary, other.artworkTextSecondary, t),
      radiusPill: lerpDouble(radiusPill, other.radiusPill, t),
      radiusSmall: lerpDouble(radiusSmall, other.radiusSmall, t),
      radiusMedium: lerpDouble(radiusMedium, other.radiusMedium, t),
      radiusLarge: lerpDouble(radiusLarge, other.radiusLarge, t),
      radiusXLarge: lerpDouble(radiusXLarge, other.radiusXLarge, t),
      glassBlur: lerpDouble(glassBlur, other.glassBlur, t),
    );
  }
}

RodPlayerTheme rodPlayerPalette(AppearanceMode mode) {
  switch (mode) {
    case AppearanceMode.light:
      return const RodPlayerTheme(
        obsidian: Color(0xFFF4F7F8),
        surface1: Color(0xFFFFFFFF),
        surface2: Color(0xFFEDF2F3),
        surface3: Color(0xFFE4EBED),
        obsidianRaised: Color(0xFFFFFFFF),
        obsidianGlass: Color(0xF7FFFFFF),
        obsidianGlassStrong: Color(0xFFFFFFFF),
        accentBright: Color(0xFF17666B),
        textPrimary: Color(0xFF172126),
        textSecondary: Color(0xFF46565D),
        textMuted: Color(0xFF627178),
        shadowColor: Color(0x18000000),
        border: Color(0xFF172126),
        artworkTextPrimary: Color(0xFFFFFFFF),
        artworkTextSecondary: Color(0xFFD3DADF),
        success: Color(0xFF287A36),
        error: Color(0xFFB24237),
      );
    case AppearanceMode.dark:
      return const RodPlayerTheme(
        obsidian: Color(0xFF101316),
        surface1: Color(0xFF171B1F),
        surface2: Color(0xFF1D2227),
        surface3: Color(0xFF272E34),
        obsidianRaised: Color(0xFF1B2024),
        obsidianGlass: Color(0xE61D2227),
        obsidianGlassStrong: Color(0xF5272E34),
        border: Color(0xFFFFFFFF),
      );
    case AppearanceMode.system:
    case AppearanceMode.oled:
      return const RodPlayerTheme();
  }
}

ThemeData rodPlayerThemeData({AppearanceMode mode = AppearanceMode.oled}) {
  final t = rodPlayerPalette(mode);
  final brightness =
      mode == AppearanceMode.light ? Brightness.light : Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: t.accent,
    brightness: brightness,
    surface: t.obsidian,
    primary: t.accent,
    onPrimary:
        mode == AppearanceMode.light ? const Color(0xFF172126) : t.obsidian,
    secondary: t.accentBright,
    onSurface: t.textPrimary,
    error: t.error,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.obsidian,
    appBarTheme: AppBarTheme(
        backgroundColor: t.obsidian,
        foregroundColor: t.textPrimary,
        surfaceTintColor: Colors.transparent),
    dialogTheme: DialogThemeData(
        backgroundColor: t.surface1,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
            color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: t.textSecondary)),
    iconTheme: IconThemeData(color: t.textSecondary),
    progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accentDeep, linearTrackColor: t.surface3),
    extensions: [t],
    textTheme: TextTheme(
      displaySmall:
          TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
      headlineSmall:
          TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: t.textPrimary),
      bodyMedium: TextStyle(color: t.textSecondary),
      labelLarge: TextStyle(
          color: brightness == Brightness.light ? t.textPrimary : t.obsidian,
          fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: t.obsidianGlass,
      elevation: 0,
      shadowColor: t.shadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusMedium),
        side: BorderSide(color: t.borderColor(0.1)),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface2,
      hintStyle: TextStyle(color: t.textMuted),
      labelStyle: TextStyle(color: t.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusMedium),
        borderSide: BorderSide(color: t.borderColor(0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusMedium),
        borderSide: BorderSide(color: t.borderColor(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusMedium),
        borderSide: BorderSide(color: t.accent, width: 1.2),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.borderColor(0.08), thickness: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface1,
      indicatorColor: t.accent.withValues(alpha: 0.16),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(color: t.textSecondary)),
    ),
  );
}

class RodPlayerGlass extends StatelessWidget {
  const RodPlayerGlass(
      {required this.child, this.padding, this.margin, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(theme.radiusLarge),
        boxShadow: theme.glassShadow,
        border: Border.all(color: theme.borderColor(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.radiusLarge),
        child: BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: theme.glassBlur, sigmaY: theme.glassBlur),
          child: Container(
            padding: padding,
            color: theme.obsidianGlass,
            child: child,
          ),
        ),
      ),
    );
  }
}
