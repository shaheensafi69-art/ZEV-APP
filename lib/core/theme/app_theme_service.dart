import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LuxuryPalette {
  final String id;
  final String name;
  final String description;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color cardBorder;
  final bool isDark;
  final LinearGradient gradient;

  const LuxuryPalette({
    required this.id,
    required this.name,
    required this.description,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.cardBorder,
    required this.isDark,
    required this.gradient,
  });

  ThemeData toThemeData() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      cardColor: surface,
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: secondary,
        tertiary: accent,
        surface: surface,
        surfaceContainerHighest: const Color(0xFFF1F5F9),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        error: const Color(0xFFEF4444),
        outline: cardBorder,
      ),
      fontFamily: 'Inter',
      fontFamilyFallback: const ['Segoe UI', 'Roboto', 'Arial', 'sans-serif'],
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shadowColor: primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cardBorder, width: 1.2),
        ),
      ),
      // ⚠️ NEVER set minimumSize to double.infinity globally, as it crushes sibling Expanded widgets in Rows!
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: primary.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        labelStyle: TextStyle(color: textSecondary, fontSize: 14),
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.6), fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: cardBorder),
        ),
      ),
    );
  }
}

class AppThemeService {
  AppThemeService._();
  static final AppThemeService instance = AppThemeService._();

  static const String _prefKey = 'selected_luxury_theme_index';

  // Official unified theme: Default Pink & Luxury White
  static const List<LuxuryPalette> luxuryPalettes = [
    LuxuryPalette(
      id: 'default_pink_white',
      name: 'ZEV Luxury Pink & White',
      description: 'Original luxury pink & white design for ZEV Social Network',
      primary: Color(0xFFFC466B),
      secondary: Color(0xFFFF6584),
      accent: Color(0xFFFF94A8),
      background: Colors.white,
      surface: Colors.white,
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF64748B),
      cardBorder: Color(0xFFF1F5F9),
      isDark: false,
      gradient: LinearGradient(
        colors: [Color(0xFFFC466B), Color(0xFFFF6584)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  ];

  final ValueNotifier<LuxuryPalette> currentPaletteNotifier =
      ValueNotifier<LuxuryPalette>(luxuryPalettes[0]);

  LuxuryPalette get current => luxuryPalettes[0];

  int get currentIndex => 0;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Always reset to original pink and white theme
      await prefs.setInt(_prefKey, 0);
      currentPaletteNotifier.value = luxuryPalettes[0];
    } catch (e) {
      debugPrint('AppThemeService initialize error: $e');
    }
  }

  Future<void> setPalette(int index) async {
    currentPaletteNotifier.value = luxuryPalettes[0];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKey, 0);
    } catch (e) {
      debugPrint('AppThemeService setPalette error: $e');
    }
  }
}
