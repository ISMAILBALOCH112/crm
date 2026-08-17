import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Warm canvas + soft blue actions (content you liked) + pink decor (first design).
  static const background = Color(0xFFFFF8F5);
  static const surfaceSolid = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFFFF0EB);
  static const surfaceBorder = Color(0xFFF3E4E8);

  static const primary = Color(0xFF5B7FFF);
  static const primaryLight = Color(0xFF93AAFF);
  static const accent = Color(0xFFFF7FA6);
  static const accentViolet = Color(0xFF8B5CF6);
  static const accentWarm = Color(0xFFFFB37B);
  static const accentPinkLight = Color(0xFFFFB0C6);

  static const heroDark = Color(0xFF1F2937);

  static const textPrimary = Color(0xFF2D2430);
  static const textSecondary = Color(0xFF8E7A86);
  static const error = Color(0xFFEF4444);

  static const primaryGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF6B8AFF), primary, Color(0xFF4468E8)],
  );

  static List<BoxShadow> cardShadow([Color? tint]) => [
        BoxShadow(
          color: (tint ?? primary).withValues(alpha: 0.18),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> floatShadow([Color? tint]) => [
        BoxShadow(
          color: (tint ?? accent).withValues(alpha: 0.15),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];
}

class AppDecorations {
  AppDecorations._();

  static BoxDecoration card({double radius = 16}) => BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: AppColors.cardShadow(AppColors.accent),
      );

  static BoxDecoration glassCard({double radius = 20}) => card(radius: radius);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surfaceSolid,
        error: AppColors.error,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: AppColors.heroDark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceSolid,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
        floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
