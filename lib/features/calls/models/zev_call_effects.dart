import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

/// Categories for ZEV Calling System 2.0 camera filters and effects.
enum ZevCallEffectCategory {
  beauty('Beauty', Icons.face_retouching_natural_rounded),
  lighting('Lighting', Icons.wb_sunny_rounded),
  background('Background', Icons.blur_on_rounded),
  color('Color', Icons.palette_rounded),
  special('Special', Icons.auto_awesome_rounded);

  final String label;
  final IconData icon;
  const ZevCallEffectCategory(this.label, this.icon);
}

/// Advanced Video Effect Configuration for Agora RTC Camera Pipeline.
/// Applied at the hardware capture layer so outgoing stream is processed
/// without affecting other participants.
class ZevCallEffect {
  final String id;
  final String name;
  final ZevCallEffectCategory category;
  final IconData icon;
  final BeautyOptions? agoraBeauty;
  final VirtualBackgroundSource? virtualBackground;
  final ColorEnhanceOptions? colorEnhance;
  final LowlightEnhanceOptions? lowlightEnhance;
  final ColorFilter? matrixFilter;

  const ZevCallEffect({
    required this.id,
    required this.name,
    required this.category,
    required this.icon,
    this.agoraBeauty,
    this.virtualBackground,
    this.colorEnhance,
    this.lowlightEnhance,
    this.matrixFilter,
  });

  bool get isNone => id == 'none';
}

/// Granular slider parameters for fine-tuning beauty and camera enhancements.
class ZevBeautyTuning {
  final double smoothness; // 0.0 to 1.0
  final double lightening; // 0.0 to 1.0
  final double redness;    // 0.0 to 1.0
  final double sharpness;  // 0.0 to 1.0
  final int blurDegree;    // 0 = off, 1 = low, 2 = medium, 3 = high
  final bool lowlightBoost;

  const ZevBeautyTuning({
    this.smoothness = 0.0,
    this.lightening = 0.0,
    this.redness = 0.0,
    this.sharpness = 0.0,
    this.blurDegree = 0,
    this.lowlightBoost = false,
  });

  bool get isActive =>
      smoothness > 0 ||
      lightening > 0 ||
      redness > 0 ||
      sharpness > 0 ||
      blurDegree > 0 ||
      lowlightBoost;

  ZevBeautyTuning copyWith({
    double? smoothness,
    double? lightening,
    double? redness,
    double? sharpness,
    int? blurDegree,
    bool? lowlightBoost,
  }) {
    return ZevBeautyTuning(
      smoothness: smoothness ?? this.smoothness,
      lightening: lightening ?? this.lightening,
      redness: redness ?? this.redness,
      sharpness: sharpness ?? this.sharpness,
      blurDegree: blurDegree ?? this.blurDegree,
      lowlightBoost: lowlightBoost ?? this.lowlightBoost,
    );
  }

  BeautyOptions toBeautyOptions() {
    return BeautyOptions(
      lighteningContrastLevel: lightening > 0.6
          ? LighteningContrastLevel.lighteningContrastHigh
          : LighteningContrastLevel.lighteningContrastNormal,
      lighteningLevel: lightening,
      smoothnessLevel: smoothness,
      rednessLevel: redness,
      sharpnessLevel: sharpness,
    );
  }

  VirtualBackgroundSource? toVirtualBackgroundSource() {
    if (blurDegree <= 0) return null;
    final degree = switch (blurDegree) {
      1 => BackgroundBlurDegree.blurDegreeLow,
      2 => BackgroundBlurDegree.blurDegreeMedium,
      _ => BackgroundBlurDegree.blurDegreeHigh,
    };
    return VirtualBackgroundSource(
      backgroundSourceType: BackgroundSourceType.backgroundBlur,
      blurDegree: degree,
    );
  }
}

/// Catalog of production-grade effects for ZEV Calling System 2.0.
class ZevEffectsCatalog {
  ZevEffectsCatalog._();

  static const ZevCallEffect none = ZevCallEffect(
    id: 'none',
    name: 'Normal',
    category: ZevCallEffectCategory.beauty,
    icon: Icons.not_interested_rounded,
  );

  static const List<ZevCallEffect> all = [
    // ----------------------------------------------------
    // BEAUTY CATEGORY
    // ----------------------------------------------------
    none,
    ZevCallEffect(
      id: 'beauty_natural',
      name: 'Natural',
      category: ZevCallEffectCategory.beauty,
      icon: Icons.face_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.40,
        smoothnessLevel: 0.55,
        rednessLevel: 0.20,
        sharpnessLevel: 0.30,
      ),
    ),
    ZevCallEffect(
      id: 'beauty_smooth',
      name: 'Smooth',
      category: ZevCallEffectCategory.beauty,
      icon: Icons.auto_fix_high_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.55,
        smoothnessLevel: 0.85,
        rednessLevel: 0.30,
        sharpnessLevel: 0.45,
      ),
    ),
    ZevCallEffect(
      id: 'beauty_soft_portrait',
      name: 'Portrait',
      category: ZevCallEffectCategory.beauty,
      icon: Icons.portrait_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.60,
        smoothnessLevel: 0.70,
        rednessLevel: 0.35,
        sharpnessLevel: 0.50,
      ),
    ),
    ZevCallEffect(
      id: 'beauty_bright',
      name: 'Brighten',
      category: ZevCallEffectCategory.beauty,
      icon: Icons.brightness_high_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastHigh,
        lighteningLevel: 0.85,
        smoothnessLevel: 0.60,
        rednessLevel: 0.20,
        sharpnessLevel: 0.40,
      ),
    ),
    ZevCallEffect(
      id: 'beauty_glam',
      name: 'Glam',
      category: ZevCallEffectCategory.beauty,
      icon: Icons.auto_awesome_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastHigh,
        lighteningLevel: 0.70,
        smoothnessLevel: 0.90,
        rednessLevel: 0.50,
        sharpnessLevel: 0.55,
      ),
    ),
    ZevCallEffect(
      id: 'beauty_studio',
      name: 'Studio',
      category: ZevCallEffectCategory.beauty,
      icon: Icons.camera_indoor_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.75,
        smoothnessLevel: 0.75,
        rednessLevel: 0.30,
        sharpnessLevel: 0.60,
      ),
    ),

    // ----------------------------------------------------
    // LIGHTING CATEGORY
    // ----------------------------------------------------
    ZevCallEffect(
      id: 'light_studio',
      name: 'Studio Light',
      category: ZevCallEffectCategory.lighting,
      icon: Icons.light_mode_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastHigh,
        lighteningLevel: 0.85,
        smoothnessLevel: 0.50,
        sharpnessLevel: 0.50,
      ),
      lowlightEnhance: LowlightEnhanceOptions(
        level: LowLightEnhanceLevel.lowLightEnhanceLevelFast,
        mode: LowLightEnhanceMode.lowLightEnhanceAuto,
      ),
    ),
    ZevCallEffect(
      id: 'light_ring',
      name: 'Ring Light',
      category: ZevCallEffectCategory.lighting,
      icon: Icons.panorama_fish_eye_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.90,
        smoothnessLevel: 0.65,
        rednessLevel: 0.25,
      ),
    ),
    ZevCallEffect(
      id: 'light_warm',
      name: 'Warm Light',
      category: ZevCallEffectCategory.lighting,
      icon: Icons.wb_incandescent_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.65,
        smoothnessLevel: 0.55,
        rednessLevel: 0.45,
      ),
      matrixFilter: ColorFilter.matrix(<double>[
        1.10, 0, 0, 0, 10,
        0, 1.02, 0, 0, 5,
        0, 0, 0.90, 0, -10,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'light_lowlight_boost',
      name: 'Low Light',
      category: ZevCallEffectCategory.lighting,
      icon: Icons.nightlight_round,
      lowlightEnhance: LowlightEnhanceOptions(
        level: LowLightEnhanceLevel.lowLightEnhanceLevelHighQuality,
        mode: LowLightEnhanceMode.lowLightEnhanceManual,
      ),
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastHigh,
        lighteningLevel: 0.70,
        smoothnessLevel: 0.40,
      ),
    ),

    // ----------------------------------------------------
    // BACKGROUND VIRTUALIZATION CATEGORY
    // ----------------------------------------------------
    ZevCallEffect(
      id: 'bg_blur_soft',
      name: 'Soft Blur',
      category: ZevCallEffectCategory.background,
      icon: Icons.blur_linear_rounded,
      virtualBackground: VirtualBackgroundSource(
        backgroundSourceType: BackgroundSourceType.backgroundBlur,
        blurDegree: BackgroundBlurDegree.blurDegreeLow,
      ),
    ),
    ZevCallEffect(
      id: 'bg_blur_medium',
      name: 'Deep Blur',
      category: ZevCallEffectCategory.background,
      icon: Icons.blur_circular_rounded,
      virtualBackground: VirtualBackgroundSource(
        backgroundSourceType: BackgroundSourceType.backgroundBlur,
        blurDegree: BackgroundBlurDegree.blurDegreeMedium,
      ),
    ),
    ZevCallEffect(
      id: 'bg_blur_heavy',
      name: 'Max Blur',
      category: ZevCallEffectCategory.background,
      icon: Icons.blur_on_rounded,
      virtualBackground: VirtualBackgroundSource(
        backgroundSourceType: BackgroundSourceType.backgroundBlur,
        blurDegree: BackgroundBlurDegree.blurDegreeHigh,
      ),
    ),
    ZevCallEffect(
      id: 'bg_studio_dark',
      name: 'Dark Studio',
      category: ZevCallEffectCategory.background,
      icon: Icons.lens_rounded,
      virtualBackground: VirtualBackgroundSource(
        backgroundSourceType: BackgroundSourceType.backgroundColor,
        color: 0xFF0B0F19,
      ),
    ),

    // ----------------------------------------------------
    // COLOR & CINEMATIC CATEGORY
    // ----------------------------------------------------
    ZevCallEffect(
      id: 'color_sunset',
      name: 'Sunset',
      category: ZevCallEffectCategory.color,
      icon: Icons.wb_twilight_rounded,
      colorEnhance: ColorEnhanceOptions(
        strengthLevel: 0.8,
        skinProtectLevel: 0.7,
      ),
      matrixFilter: ColorFilter.matrix(<double>[
        1.15, 0, 0, 0, 15,
        0, 1.00, 0, 0, 2,
        0, 0, 0.82, 0, -12,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'color_cinematic',
      name: 'Cinema',
      category: ZevCallEffectCategory.color,
      icon: Icons.movie_filter_rounded,
      colorEnhance: ColorEnhanceOptions(
        strengthLevel: 0.9,
        skinProtectLevel: 0.8,
      ),
      matrixFilter: ColorFilter.matrix(<double>[
        1.12, 0, 0, 0, 8,
        0, 1.08, 0, 0, 8,
        0, 0, 1.20, 0, 14,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'color_golden',
      name: 'Golden',
      category: ZevCallEffectCategory.color,
      icon: Icons.flare_rounded,
      matrixFilter: ColorFilter.matrix(<double>[
        1.18, 0, 0, 0, 20,
        0, 1.05, 0, 0, 10,
        0, 0, 0.75, 0, -18,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'color_noir',
      name: 'Noir B&W',
      category: ZevCallEffectCategory.color,
      icon: Icons.filter_b_and_w_rounded,
      matrixFilter: ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'color_cyber',
      name: 'Cyber Neon',
      category: ZevCallEffectCategory.color,
      icon: Icons.electric_bolt_rounded,
      matrixFilter: ColorFilter.matrix(<double>[
        1.25, 0, 0.15, 0, 12,
        0, 1.05, 0, 0, 0,
        0.15, 0, 1.35, 0, 24,
        0, 0, 0, 1, 0,
      ]),
    ),

    // ----------------------------------------------------
    // SPECIAL EFFECTS CATEGORY
    // ----------------------------------------------------
    ZevCallEffect(
      id: 'special_glow',
      name: 'Dreamy Glow',
      category: ZevCallEffectCategory.special,
      icon: Icons.shutter_speed_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastHigh,
        lighteningLevel: 0.85,
        smoothnessLevel: 0.90,
        rednessLevel: 0.40,
        sharpnessLevel: 0.30,
      ),
    ),
    ZevCallEffect(
      id: 'special_vintage',
      name: 'Vintage 35mm',
      category: ZevCallEffectCategory.special,
      icon: Icons.camera_roll_rounded,
      matrixFilter: ColorFilter.matrix(<double>[
        0.393, 0.769, 0.189, 0, 0,
        0.349, 0.686, 0.168, 0, 0,
        0.272, 0.534, 0.131, 0, 0,
        0, 0, 0, 1, 0,
      ]),
    ),
  ];

  static List<ZevCallEffect> byCategory(ZevCallEffectCategory category) {
    return all.where((e) => e.isNone || e.category == category).toList();
  }
}
