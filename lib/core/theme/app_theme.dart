import 'package:flutter/material.dart';

class AppTheme {
  // Ultra-Premium Absolute Dark Backgrounds
  static const Color darkBackground = Color(0xFF020202);
  static const Color darkSurface = Color(0xFF0A0A0F);
  static const Color darkGlass = Color(0x1AFFFFFF); // Low-opacity overlay
  static const Color darkGlassBorder = Color(0x33FFFFFF);

  // Glowing Accent Colors
  static const Color brandRose = Color(0xFFFC466B);
  static const Color brandGold = Color(0xFFF59E0B);
  static const Color brandCyan = Color(0xFF06B6D4);
  static const Color brandBlue = Color(0xFF3B82F6);
  static const Color brandEmerald = Color(0xFF10B981);

  // Typography & Text
  static const Color textLight = Color(0xFFF8FAFC);
  static const Color textMutedDark = Color(0xFF94A3B8);

  // Legacy Light Theme Support
  static const Color primary = Color(0xFF0284C7);
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Colors.white;
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);

  // Ultra-Premium Dark Theme Data
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: brandRose,
    scaffoldBackgroundColor: darkBackground,
    colorScheme: const ColorScheme.dark(
      primary: brandRose,
      secondary: brandCyan,
      surface: darkSurface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textLight,
      error: Color(0xFFEF4444),
    ),
    fontFamily: 'Inter',
    fontFamilyFallback: const ['Segoe UI', 'Roboto', 'Arial', 'sans-serif'],
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textLight),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textLight),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textLight),
      bodyLarge: TextStyle(fontSize: 16, color: textLight),
      bodyMedium: TextStyle(fontSize: 14, color: textMutedDark),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x14FFFFFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      labelStyle: const TextStyle(color: textMutedDark, fontSize: 14),
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: darkGlassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: darkGlassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: brandRose, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: brandRose,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 8,
        shadowColor: brandRose.withValues(alpha: 0.5),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primary,
    scaffoldBackgroundColor: backgroundLight,
    colorScheme: const ColorScheme.light(
      primary: primary,
      secondary: brandEmerald,
      surface: surfaceLight,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textDark,
      error: Color(0xFFEF4444),
    ),
    fontFamily: 'Inter',
    fontFamilyFallback: const ['Segoe UI', 'Roboto', 'Arial', 'sans-serif'],
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textDark),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textDark),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textDark),
      bodyLarge: TextStyle(fontSize: 16, color: textDark),
      bodyMedium: TextStyle(fontSize: 14, color: textMuted),
    ),
  );
}