import 'package:flutter/material.dart';

/// Official ZEV Design System & Color Palette.
/// Designed and specified by ZEV Brand Identity:
/// - Primary Blue: #00D4FF (Brand Primary Color)
/// - Deep Navy: #080D1A (Text & Important Elements)
/// - White: #FFFFFF (Main Background)
/// - Soft Surface: #F5F8FC (Cards & Sections)
/// - Border: #E7EDF5 (Outlines & Dividers)
/// - Secondary Blue: #536DFE (Links & Special Interactions)
class ZevColors {
  ZevColors._();

  // Official ZEV Palette
  static const Color primaryBlue = Color(0xFF00D4FF);
  static const Color deepNavy = Color(0xFF080D1A);
  static const Color white = Color(0xFFFFFFFF);
  static const Color softSurface = Color(0xFFF5F8FC);
  static const Color border = Color(0xFFE7EDF5);
  static const Color secondaryBlue = Color(0xFF536DFE);

  // Semantic mappings
  static const Color primary = primaryBlue;
  static const Color background = white;
  static const Color surface = white;
  static const Color cardSurface = softSurface;
  static const Color textPrimary = deepNavy;
  static const Color textSecondary = Color(0xFF4A5568);
  static const Color textMuted = Color(0xFF718096);

  // Brand Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primaryBlue, secondaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient brandGradientHorizontal = LinearGradient(
    colors: [primaryBlue, secondaryBlue],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: white,
      primaryColor: primaryBlue,
      colorScheme: const ColorScheme.light(
        primary: primaryBlue,
        secondary: secondaryBlue,
        surface: white,
        onPrimary: deepNavy,
        onSecondary: Colors.white,
        onSurface: deepNavy,
        outline: border,
      ),
      fontFamily: 'Inter',
      fontFamilyFallback: const ['Segoe UI', 'Roboto', 'Arial', 'sans-serif'],
      appBarTheme: const AppBarTheme(
        backgroundColor: white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: deepNavy),
        titleTextStyle: TextStyle(
          color: deepNavy,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: deepNavy,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
