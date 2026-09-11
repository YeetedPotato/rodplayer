import 'package:flutter/material.dart';

@immutable
class RemuxTheme extends ThemeExtension<RemuxTheme> {
  const RemuxTheme({
    this.obsidian = const Color(0xFF0B0D10),
    this.obsidianRaised = const Color(0xFF12161C),
    this.obsidianGlass = const Color(0xCC171C23),
    this.obsidianGlassStrong = const Color(0xF01D232C),
    this.gold = const Color(0xFFD6A84F),
    this.goldBright = const Color(0xFFF0C76A),
    this.textPrimary = const Color(0xFFF4F0E8),
    this.textSecondary = const Color(0xFFB5B0A6),
    this.textMuted = const Color(0xFF77746E),
    this.success = const Color(0xFF83C98A),
    this.error = const Color(0xFFE27D72),
    this.radiusSmall = 8,
    this.radiusMedium = 14,
    this.radiusLarge = 22,
    this.radiusPill = 999,
    this.shadowColor = const Color(0x66000000),
  });

  final Color obsidian, obsidianRaised, obsidianGlass, obsidianGlassStrong;
  final Color gold, goldBright, textPrimary, textSecondary, textMuted, success, error;
  final double radiusSmall, radiusMedium, radiusLarge, radiusPill;
  final Color shadowColor;

  List<BoxShadow> get glassShadow => [BoxShadow(color: shadowColor, blurRadius: 24, offset: const Offset(0, 10))];
  List<BoxShadow> get goldGlow => [BoxShadow(color: gold.withOpacity(.22), blurRadius: 18, spreadRadius: 1)];

  @override
  RemuxTheme copyWith({Color? obsidian, Color? obsidianRaised, Color? obsidianGlass, Color? obsidianGlassStrong, Color? gold, Color? goldBright, Color? textPrimary, Color? textSecondary, Color? textMuted, Color? success, Color? error, double? radiusSmall, double? radiusMedium, double? radiusLarge, double? radiusPill, Color? shadowColor}) => RemuxTheme(obsidian: obsidian ?? this.obsidian, obsidianRaised: obsidianRaised ?? this.obsidianRaised, obsidianGlass: obsidianGlass ?? this.obsidianGlass, obsidianGlassStrong: obsidianGlassStrong ?? this.obsidianGlassStrong, gold: gold ?? this.gold, goldBright: goldBright ?? this.goldBright, textPrimary: textPrimary ?? this.textPrimary, textSecondary: textSecondary ?? this.textSecondary, textMuted: textMuted ?? this.textMuted, success: success ?? this.success, error: error ?? this.error, radiusSmall: radiusSmall ?? this.radiusSmall, radiusMedium: radiusMedium ?? this.radiusMedium, radiusLarge: radiusLarge ?? this.radiusLarge, radiusPill: radiusPill ?? this.radiusPill, shadowColor: shadowColor ?? this.shadowColor);

  @override
  RemuxTheme lerp(covariant RemuxTheme? other, double t) => other == null ? this : RemuxTheme(obsidian: Color.lerp(obsidian, other.obsidian, t)!, obsidianRaised: Color.lerp(obsidianRaised, other.obsidianRaised, t)!, obsidianGlass: Color.lerp(obsidianGlass, other.obsidianGlass, t)!, obsidianGlassStrong: Color.lerp(obsidianGlassStrong, other.obsidianGlassStrong, t)!, gold: Color.lerp(gold, other.gold, t)!, goldBright: Color.lerp(goldBright, other.goldBright, t)!, textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!, textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!, textMuted: Color.lerp(textMuted, other.textMuted, t)!, success: Color.lerp(success, other.success, t)!, error: Color.lerp(error, other.error, t)!);
}

ThemeData remuxThemeData() {
  const t = RemuxTheme();
  final scheme = ColorScheme.fromSeed(seedColor: t.gold, brightness: Brightness.dark, surface: t.obsidian, primary: t.gold, onPrimary: t.obsidian, secondary: t.goldBright);
  return ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: t.obsidian, extensions: const [t], textTheme: TextTheme(bodyLarge: TextStyle(color: t.textPrimary), bodyMedium: TextStyle(color: t.textSecondary), titleLarge: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700), labelLarge: TextStyle(color: t.obsidian, fontWeight: FontWeight.w700)), cardTheme: CardThemeData(color: t.obsidianGlass, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusMedium))));
}
