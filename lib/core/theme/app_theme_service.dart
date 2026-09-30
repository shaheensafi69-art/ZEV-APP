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
    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: primary,
            secondary: secondary,
            tertiary: accent,
            surface: surface,
            surfaceContainerHighest: const Color(0xFF1A2234),
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onSurface: textPrimary,
            error: const Color(0xFFEF4444),
            outline: cardBorder,
          )
        : ColorScheme.light(
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
          );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: surface,
      colorScheme: colorScheme,
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
        elevation: isDark ? 4 : 2,
        shadowColor: isDark
            ? Colors.black.withValues(alpha: 0.4)
            : primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cardBorder, width: 1.0),
        ),
      ),
      // ⚠️ NEVER set minimumSize to double.infinity globally, as it crushes sibling Expanded widgets in Rows!
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: isDark ? 4 : 2,
          shadowColor: primary.withValues(alpha: isDark ? 0.4 : 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF161D2E) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        labelStyle: TextStyle(color: textSecondary, fontSize: 14),
        hintStyle: TextStyle(
          color: textSecondary.withValues(alpha: 0.6),
          fontSize: 14,
        ),
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
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
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

  // Two Official Master Themes:
  // 1. ZEV Midnight Glow (Dark Mode - Exactly as in the design preview)
  // 2. ZEV Luxury Pink & White (Light Mode)
  static const List<LuxuryPalette> luxuryPalettes = [
    // Index 0: Dark Mode (Default)
    LuxuryPalette(
      id: 'zev_midnight_glow',
      name: 'ZEV Midnight Glow',
      description: 'Luxury deep midnight charcoal with glowing pink accents',
      primary: Color(0xFFFC466B),
      secondary: Color(0xFFC850C0),
      accent: Color(0xFFF494AC),
      background: Color(0xFF0B0F19),
      surface: Color(0xFF131926),
      textPrimary: Color(0xFFFFFFFF),
      textSecondary: Color(0xFF94A3B8),
      cardBorder: Color(0xFF1E293B),
      isDark: true,
      gradient: LinearGradient(
        colors: [Color(0xFFFC466B), Color(0xFFC850C0)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    // Index 1: Light Mode
    LuxuryPalette(
      id: 'default_pink_white',
      name: 'ZEV Luxury Pink & White',
      description: 'Clean luxury white background with vibrant pink accents',
      primary: Color(0xFFFC466B),
      secondary: Color(0xFFFF6584),
      accent: Color(0xFFFF94A8),
      background: Color(0xFFF8FAFC),
      surface: Colors.white,
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF64748B),
      cardBorder: Color(0xFFE2E8F0),
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

  LuxuryPalette get current => currentPaletteNotifier.value;

  bool get isDark => current.isDark;

  int get currentIndex {
    final idx = luxuryPalettes.indexWhere((p) => p.id == current.id);
    return idx >= 0 ? idx : 0;
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt(_prefKey) ?? 0;
      if (savedIndex >= 0 && savedIndex < luxuryPalettes.length) {
        currentPaletteNotifier.value = luxuryPalettes[savedIndex];
      } else {
        currentPaletteNotifier.value = luxuryPalettes[0];
      }
    } catch (e) {
      debugPrint('AppThemeService initialize error: $e');
    }
  }

  Future<void> setPalette(int index) async {
    if (index < 0 || index >= luxuryPalettes.length) return;
    currentPaletteNotifier.value = luxuryPalettes[index];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKey, index);
    } catch (e) {
      debugPrint('AppThemeService setPalette error: $e');
    }
  }

  Future<void> toggleTheme() async {
    final nextIndex = currentIndex == 0 ? 1 : 0;
    await setPalette(nextIndex);
  }
}
