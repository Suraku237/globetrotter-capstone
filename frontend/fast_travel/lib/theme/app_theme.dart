// GlobeTrotter design tokens.
// Palette grounded in Cameroon's geography: rainforest canopy, savanna sand,
// Waza sun, highland clay, Atlantic coast teal.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const canopy = Color(0xFF14291F); // deep rainforest — dark base
  static const canopyLight = Color(0xFF1E3A2C);
  static const sand = Color(0xFFF4EDD9); // savanna — light surfaces
  static const sandDim = Color(0xFFE8DFC4);
  static const ochre = Color(0xFFE2A33D); // Waza sun — primary CTA
  static const clay = Color(0xFFB5482E); // highland terracotta — secondary
  static const teal = Color(0xFF2C7A73); // Atlantic coast — tertiary
  static const ink = Color(0xFF1B1A17); // dark text
  static const inkSoft = Color(0xFF4A473F);

  // Region gradient — forest (Far North excluded from green end; order is
  // purely visual, not geographic) used for the region ribbon signature.
  static const regionGradient = [
    teal,
    canopyLight,
    Color(0xFF4E7A3B),
    ochre,
    clay,
  ];
}

class AppText {
  static TextTheme textTheme(Brightness brightness) {
    final onColor = brightness == Brightness.dark
        ? AppColors.sand
        : AppColors.ink;
    final display = GoogleFonts.fraunces(
      color: onColor,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
    );
    final body = GoogleFonts.inter(color: onColor);
    return TextTheme(
      displayLarge: display.copyWith(fontSize: 40, height: 1.05),
      displayMedium: display.copyWith(fontSize: 32, height: 1.1),
      headlineMedium: display.copyWith(fontSize: 24, height: 1.15),
      titleLarge: display.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
      titleMedium: body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: body.copyWith(fontSize: 16, height: 1.4),
      bodyMedium: body.copyWith(fontSize: 14, height: 1.4),
      labelLarge: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      labelSmall: GoogleFonts.ibmPlexMono(
        color: onColor.withValues(alpha: 0.7),
        fontSize: 12,
        letterSpacing: 0.4,
      ),
    );
  }
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.ochre,
      brightness: Brightness.light,
      primary: AppColors.ochre,
      secondary: AppColors.clay,
      tertiary: AppColors.teal,
      surface: AppColors.sand,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.sand,
      textTheme: AppText.textTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.sand,
        foregroundColor: AppColors.ink,
        elevation: 0,
        titleTextStyle: AppText.textTheme(Brightness.light).headlineMedium,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.canopy,
          foregroundColor: AppColors.sand,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.65),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.canopy,
        selectedIconTheme: const IconThemeData(color: AppColors.ochre),
        unselectedIconTheme: IconThemeData(
          color: AppColors.sand.withValues(alpha: 0.6),
        ),
        selectedLabelTextStyle: const TextStyle(color: AppColors.ochre),
        unselectedLabelTextStyle: TextStyle(
          color: AppColors.sand.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
