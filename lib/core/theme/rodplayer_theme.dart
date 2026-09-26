import 'dart:ui';

import 'package:flutter/material.dart';

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
  });

  final Color obsidian, surface1, surface2, surface3, obsidianRaised;
  final Color obsidianGlass, obsidianGlassStrong, accent, accentBright, accentDeep;
  final Color textPrimary, textSecondary, textMuted, success, error, shadowColor;
  final double radiusPill, radiusSmall, radiusMedium, radiusLarge, radiusXLarge;
  final double glassBlur;

  List<BoxShadow> get glassShadow => [
        BoxShadow(color: shadowColor, blurRadius: 24, offset: const Offset(0, 10)),
      ];

  List<BoxShadow> get accentGlow => [
        BoxShadow(
          color: accent.withValues(alpha: 0.22),
          blurRadius: 18,
          spreadRadius: 1,
        ),
      ];

  Color borderColor([double alpha = 0.1]) => Colors.white.withValues(alpha: alpha);

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
  }) => RodPlayerTheme(
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
      );

  @override
  RodPlayerTheme lerp(covariant RodPlayerTheme? other, double t) {
    if (other == null) return this;
    return copyWith(
      obsidian: Color.lerp(obsidian, other.obsidian, t),
      accent: Color.lerp(accent, other.accent, t),
      accentBright: Color.lerp(accentBright, other.accentBright, t),
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t),
    );
  }
}

ThemeData rodPlayerThemeData() {
  const t = RodPlayerTheme();
  final scheme = ColorScheme.fromSeed(
    seedColor: t.accent,
    brightness: Brightness.dark,
    surface: t.obsidian,
    primary: t.accent,
    onPrimary: t.obsidian,
    secondary: t.accentBright,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.obsidian,
    extensions: const [t],
    textTheme: TextTheme(
      displaySmall: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
      headlineSmall: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: t.textPrimary),
      bodyMedium: TextStyle(color: t.textSecondary),
      labelLarge: TextStyle(color: t.obsidian, fontWeight: FontWeight.w700),
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
  const RodPlayerGlass({required this.child, this.padding, this.margin, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
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
          filter: ImageFilter.blur(sigmaX: theme.glassBlur, sigmaY: theme.glassBlur),
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
