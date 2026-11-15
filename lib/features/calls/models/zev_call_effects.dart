import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

/// Categories for ZEV Calling System 2.0 Beauty, Lighting & Camera Studio.
enum ZevCallEffectCategory {
  lighting('Lighting', Icons.wb_sunny_rounded),
  beauty('Skin Tuning', Icons.face_retouching_natural_rounded),
  color('Color Tone', Icons.palette_rounded),
  background('Blur', Icons.blur_on_rounded);

  final String label;
  final IconData icon;
  const ZevCallEffectCategory(this.label, this.icon);
}

/// Advanced Video Effect Configuration for Agora RTC Camera Pipeline.
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

/// Dynamic user tuning state for granular sliders in CallScreen.
class ZevBeautyTuning {
  final double smoothness; // 0.0 to 1.0 (Skin smoothing)
  final double lightening; // 0.0 to 1.0 (Skin whitening/brightening)
  final double redness; // 0.0 to 1.0 (Rosy cheek tint)
  final double sharpness; // 0.0 to 1.0 (Fine detail sharpness)
  final int blurDegree; // 0 = off, 1 = low, 2 = medium, 3 = high
  final bool lowlightBoost; // AI low-light sensor boost

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

/// Comprehensive Catalog of Production Beauty, Lighting, and Color Studio Presets.
class ZevEffectsCatalog {
  ZevEffectsCatalog._();

  static const ZevCallEffect none = ZevCallEffect(
    id: 'none',
    name: 'Normal',
    category: ZevCallEffectCategory.lighting,
    icon: Icons.not_interested_rounded,
  );

  static const List<ZevCallEffect> all = [
    none,

    // ====================================================
    // 1. LIGHTING CATEGORY (Studio & AI Lowlight)
    // ====================================================
    ZevCallEffect(
      id: 'light_studio',
      name: 'Studio Light',
      category: ZevCallEffectCategory.lighting,
      icon: Icons.wb_sunny_rounded,
      lowlightEnhance: LowlightEnhanceOptions(
        mode: LowLightEnhanceMode.lowLightEnhanceAuto,
        level: LowLightEnhanceLevel.lowLightEnhanceLevelHighQuality,
      ),
    ),
    ZevCallEffect(
      id: 'light_sunset',
      name: 'Sunset Bronze',
      category: ZevCallEffectCategory.lighting,
      icon: Icons.wb_twilight_rounded,
      matrixFilter: ColorFilter.matrix(<double>[
        1.25, 0, 0, 0, 20,
        0, 1.05, 0, 0, 10,
        0, 0, 0.85, 0, -10,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'light_cyber',
      name: 'Cyber Blue',
      category: ZevCallEffectCategory.lighting,
      icon: Icons.fluorescent_rounded,
      matrixFilter: ColorFilter.matrix(<double>[
        0.85, 0, 0, 0, -10,
        0, 1.15, 0, 0, 10,
        0, 0, 1.35, 0, 25,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'light_golden',
      name: 'Golden Hour',
      category: ZevCallEffectCategory.lighting,
      icon: Icons.light_mode_rounded,
      matrixFilter: ColorFilter.matrix(<double>[
        1.20, 0.05, 0, 0, 25,
        0, 1.10, 0, 0, 15,
        0, 0, 0.80, 0, -15,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'light_emerald',
      name: 'Emerald Mist',
      category: ZevCallEffectCategory.lighting,
      icon: Icons.lens_blur_rounded,
      matrixFilter: ColorFilter.matrix(<double>[
        0.90, 0, 0, 0, -5,
        0, 1.25, 0, 0, 20,
        0, 0, 1.10, 0, 10,
        0, 0, 0, 1, 0,
      ]),
    ),

    // ====================================================
    // 2. SKIN TUNING & BEAUTY CATEGORY (Hardware Accelerated)
    // ====================================================
    ZevCallEffect(
      id: 'beauty_natural',
      name: 'Natural Fresh',
      category: ZevCallEffectCategory.beauty,
      icon: Icons.face_retouching_natural_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.40,
        smoothnessLevel: 0.45,
        rednessLevel: 0.20,
        sharpnessLevel: 0.25,
      ),
    ),
    ZevCallEffect(
      id: 'beauty_smooth',
      name: 'Silk Smooth',
      category: ZevCallEffectCategory.beauty,
      icon: Icons.spa_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.50,
        smoothnessLevel: 0.80,
        rednessLevel: 0.25,
        sharpnessLevel: 0.15,
      ),
    ),
    ZevCallEffect(
      id: 'beauty_porcelain',
      name: 'Velvet Clean',
      category: ZevCallEffectCategory.beauty,
      icon: Icons.clean_hands_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastHigh,
        lighteningLevel: 0.70,
        smoothnessLevel: 0.85,
        rednessLevel: 0.15,
        sharpnessLevel: 0.35,
      ),
    ),
    ZevCallEffect(
      id: 'beauty_rosy',
      name: 'Rosy Glow',
      category: ZevCallEffectCategory.beauty,
      icon: Icons.favorite_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.55,
        smoothnessLevel: 0.65,
        rednessLevel: 0.55,
        sharpnessLevel: 0.25,
      ),
    ),
    ZevCallEffect(
      id: 'beauty_sculpt',
      name: 'Sculpt Sharp',
      category: ZevCallEffectCategory.beauty,
      icon: Icons.filter_center_focus_rounded,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastHigh,
        lighteningLevel: 0.45,
        smoothnessLevel: 0.60,
        rednessLevel: 0.20,
        sharpnessLevel: 0.70,
      ),
    ),

    // ====================================================
    // 3. COLOR & CINEMA CATEGORY
    // ====================================================
    ZevCallEffect(
      id: 'color_cinema',
      name: 'Cinema Film',
      category: ZevCallEffectCategory.color,
      icon: Icons.movie_rounded,
      colorEnhance: ColorEnhanceOptions(
        strengthLevel: 0.80,
        skinProtectLevel: 0.85,
      ),
    ),
    ZevCallEffect(
      id: 'color_noir',
      name: 'Noir B&W',
      category: ZevCallEffectCategory.color,
      icon: Icons.filter_b_and_w_rounded,
      matrixFilter: ColorFilter.matrix(<double>[
        0.299, 0.587, 0.114, 0, 0,
        0.299, 0.587, 0.114, 0, 0,
        0.299, 0.587, 0.114, 0, 0,
        0,     0,     0,     1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'color_vintage',
      name: 'Vintage 90s',
      category: ZevCallEffectCategory.color,
      icon: Icons.camera_alt_rounded,
      matrixFilter: ColorFilter.matrix(<double>[
        1.10, 0.05, 0, 0, 15,
        0, 1.05, 0.05, 0, 10,
        0, 0.05, 0.90, 0, -5,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'color_vivid',
      name: 'Vivid Warm',
      category: ZevCallEffectCategory.color,
      icon: Icons.local_fire_department_rounded,
      colorEnhance: ColorEnhanceOptions(
        strengthLevel: 0.95,
        skinProtectLevel: 0.70,
      ),
    ),

    // ====================================================
    // 4. VIRTUAL BACKGROUND & BLUR CATEGORY
    // ====================================================
    ZevCallEffect(
      id: 'bg_blur_low',
      name: 'Subtle Blur',
      category: ZevCallEffectCategory.background,
      icon: Icons.blur_linear_rounded,
      virtualBackground: VirtualBackgroundSource(
        backgroundSourceType: BackgroundSourceType.backgroundBlur,
        blurDegree: BackgroundBlurDegree.blurDegreeLow,
      ),
    ),
    ZevCallEffect(
      id: 'bg_blur_med',
      name: 'Portrait Blur',
      category: ZevCallEffectCategory.background,
      icon: Icons.blur_on_rounded,
      virtualBackground: VirtualBackgroundSource(
        backgroundSourceType: BackgroundSourceType.backgroundBlur,
        blurDegree: BackgroundBlurDegree.blurDegreeMedium,
      ),
    ),
    ZevCallEffect(
      id: 'bg_blur_high',
      name: 'Studio Bokeh',
      category: ZevCallEffectCategory.background,
      icon: Icons.blur_circular_rounded,
      virtualBackground: VirtualBackgroundSource(
        backgroundSourceType: BackgroundSourceType.backgroundBlur,
        blurDegree: BackgroundBlurDegree.blurDegreeHigh,
      ),
    ),
  ];

  static List<ZevCallEffect> byCategory(ZevCallEffectCategory cat) {
    return all.where((e) => e.category == cat || e.id == 'none').toList();
  }

  static ZevCallEffect findById(String id) {
    return all.firstWhere((e) => e.id == id, orElse: () => none);
  }
}
