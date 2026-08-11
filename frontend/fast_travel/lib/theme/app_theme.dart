// GlobeTrotter design tokens — modern travel-tech: warm off-white canvas,
// a single confident coral accent, deep indigo for immersive dark surfaces
// (the video feed), soft elevation, and fully-rounded components.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const canopy =
      Color(0xFF171932); // deep indigo — dark surfaces (nav rail, video feed)
  static const canopyLight = Color(0xFF272B52);
  static const sand = Color(0xFFFAF9F6); // warm off-white — light surfaces
  static const sandDim = Color(0xFFF0EEE8);
  static const ochre = Color(0xFFFF6A4D); // coral — primary CTA
  static const clay = Color(0xFFE14C3C); // rose-red — secondary / likes
  static const teal = Color(0xFF14B8A6); // teal — tertiary accent
  static const ink = Color(0xFF16181D); // near-black charcoal text
  static const inkSoft = Color(0xFF6B7280);

  // Region gradient used for the region ribbon signature.
  static const regionGradient = [
    teal,
    canopyLight,
    Color(0xFF6D5BD0),
    ochre,
    clay,
  ];
}

class AppText {
  static TextTheme textTheme(Brightness brightness) {
    final onColor =
        brightness == Brightness.dark ? AppColors.sand : AppColors.ink;
    final display = GoogleFonts.manrope(
      color: onColor,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    );
    final body = GoogleFonts.inter(color: onColor);
    return TextTheme(
      displayLarge: display.copyWith(fontSize: 40, height: 1.08),
      displayMedium: display.copyWith(fontSize: 32, height: 1.12),
      headlineMedium: display.copyWith(fontSize: 24, height: 1.2),
      titleLarge: display.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium: body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: body.copyWith(fontSize: 16, height: 1.45),
      bodyMedium: body.copyWith(fontSize: 14, height: 1.45),
      labelLarge: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      labelSmall: body.copyWith(
        color: onColor.withValues(alpha: 0.65),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
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
      // Transparent by default so the app-wide background photo (see
      // AppBackground, layered in behind every screen via MaterialApp's
      // builder) shows through instead of a solid page color.
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: AppText.textTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: AppText.textTheme(Brightness.light).headlineMedium,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ochre,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          elevation: 0,
          shadowColor: AppColors.ochre.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: BorderSide(color: AppColors.ink.withValues(alpha: 0.14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.sandDim,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 15,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.55),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.ink.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.canopy.withValues(alpha: 0.75),
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
