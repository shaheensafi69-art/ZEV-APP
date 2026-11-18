import 'package:flutter/material.dart';

/// Facebook-Style High-Impact Gradient Presets for Text Posts.
class ZevPostGradientPreset {
  final String key;
  final String name;
  final List<Color> colors;
  final Alignment begin;
  final Alignment end;

  const ZevPostGradientPreset({
    required this.key,
    required this.name,
    required this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  LinearGradient toGradient() => LinearGradient(
        colors: colors,
        begin: begin,
        end: end,
      );

  static const List<ZevPostGradientPreset> presets = [
    ZevPostGradientPreset(
      key: 'sunset',
      name: 'Sunset Blaze',
      colors: [Color(0xFFFF512F), Color(0xFFDD2476)],
    ),
    ZevPostGradientPreset(
      key: 'royal_neon',
      name: 'Royal Neon',
      colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
    ),
    ZevPostGradientPreset(
      key: 'ocean',
      name: 'Ocean Deep',
      colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
    ),
    ZevPostGradientPreset(
      key: 'emerald',
      name: 'Emerald Lush',
      colors: [Color(0xFF0BA360), Color(0xFF3CBA92)],
    ),
    ZevPostGradientPreset(
      key: 'cyberpunk',
      name: 'Cyberpunk',
      colors: [Color(0xFF654EA3), Color(0xFFEAAFC8)],
    ),
    ZevPostGradientPreset(
      key: 'velvet',
      name: 'Velvet Night',
      colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
    ),
    ZevPostGradientPreset(
      key: 'coral',
      name: 'Coral Sunrise',
      colors: [Color(0xFFFF5E62), Color(0xFFFF9966)],
    ),
    ZevPostGradientPreset(
      key: 'cosmic',
      name: 'Cosmic Purple',
      colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
    ),
  ];

  static ZevPostGradientPreset resolve(String? styleKey, {int seed = 0}) {
    if (styleKey != null && styleKey.isNotEmpty) {
      final clean = styleKey.replaceAll('gradient:', '').trim().toLowerCase();
      final match = presets.where((p) => p.key == clean);
      if (match.isNotEmpty) return match.first;
    }
    final idx = seed.abs() % presets.length;
    return presets[idx];
  }
}
