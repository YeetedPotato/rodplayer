import 'package:flutter/material.dart';

@immutable
class RemuxTheme extends ThemeExtension<RemuxTheme> {
  const RemuxTheme({
    this.obsidian = const Color(0xFF000000),
    this.surface1 = const Color(0xFF121212),
    this.surface2 = const Color(0xFF171717),
    this.surface3 = const Color(0xFF1D1D1D),
    this.obsidianRaised = const Color(0xFF08090B),
    this.obsidianGlass = const Color(0xCC171717),
    this.obsidianGlassStrong = const Color(0xF01D1D1D),
    this.gold = const Color(0xFFEBCF52),
    this.goldBright = const Color(0xFFEBCF52),
    this.green = const Color(0xFF1C3421),
    this.textPrimary = const Color(0xFFF4F6F8),
    this.textSecondary = const Color(0xFFA2A9B3),
    this.textMuted = const Color(0xFF707780),
    this.success = const Color(0xFF83C98A),
    this.error = const Color(0xFFE27D72),
    this.radiusPill = 999.0,
    this.radiusSmall = 8.0,
    this.radiusMedium = 14.0,
    this.radiusLarge = 20.0,
    this.radiusXLarge = 22.0,
    this.glassBlur = 18.0,
    this.shadowColor = const Color(0x66000000),
  });
  final Color obsidian, surface1, surface2, surface3, obsidianRaised, obsidianGlass, obsidianGlassStrong, gold, goldBright, green, textPrimary, textSecondary, textMuted, success, error, shadowColor;
  final double radiusPill, radiusSmall, radiusMedium, radiusLarge, radiusXLarge, glassBlur;
  List<BoxShadow> get glassShadow => [BoxShadow(color: shadowColor, blurRadius: 24, offset: const Offset(0, 10))];
  List<BoxShadow> get goldGlow => [BoxShadow(color: gold.withValues(alpha: 0.22), blurRadius: 18, spreadRadius: 1)];
  Color borderColor([double alpha = 0.1]) => Colors.white.withValues(alpha: alpha);
  @override RemuxTheme copyWith({Color? obsidian, Color? surface1, Color? surface2, Color? surface3, Color? obsidianRaised, Color? obsidianGlass, Color? obsidianGlassStrong, Color? gold, Color? goldBright, Color? green, Color? textPrimary, Color? textSecondary, Color? textMuted, Color? success, Color? error, double? radiusPill, double? radiusSmall, double? radiusMedium, double? radiusLarge, double? radiusXLarge, double? glassBlur, Color? shadowColor}) => RemuxTheme(obsidian: obsidian ?? this.obsidian, surface1: surface1 ?? this.surface1, surface2: surface2 ?? this.surface2, surface3: surface3 ?? this.surface3, obsidianRaised: obsidianRaised ?? this.obsidianRaised, obsidianGlass: obsidianGlass ?? this.obsidianGlass, obsidianGlassStrong: obsidianGlassStrong ?? this.obsidianGlassStrong, gold: gold ?? this.gold, goldBright: goldBright ?? this.goldBright, green: green ?? this.green, textPrimary: textPrimary ?? this.textPrimary, textSecondary: textSecondary ?? this.textSecondary, textMuted: textMuted ?? this.textMuted, success: success ?? this.success, error: error ?? this.error, radiusPill: radiusPill ?? this.radiusPill, radiusSmall: radiusSmall ?? this.radiusSmall, radiusMedium: radiusMedium ?? this.radiusMedium, radiusLarge: radiusLarge ?? this.radiusLarge, radiusXLarge: radiusXLarge ?? this.radiusXLarge, glassBlur: glassBlur ?? this.glassBlur, shadowColor: shadowColor ?? this.shadowColor);
  @override RemuxTheme lerp(covariant RemuxTheme? other, double t) => other == null ? this : copyWith(obsidian: Color.lerp(obsidian, other.obsidian, t), gold: Color.lerp(gold, other.gold, t));
}

ThemeData remuxThemeData() {
  const t = RemuxTheme();
  final scheme = ColorScheme.fromSeed(seedColor: t.gold, brightness: Brightness.dark, surface: t.obsidian, primary: t.gold, onPrimary: t.obsidian, secondary: t.goldBright);
  return ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: t.obsidian, extensions: const [t], textTheme: TextTheme(bodyLarge: TextStyle(color: t.textPrimary), bodyMedium: TextStyle(color: t.textSecondary), titleLarge: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700)), cardTheme: CardThemeData(color: t.obsidianGlass, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusMedium)), margin: EdgeInsets.zero));
}
