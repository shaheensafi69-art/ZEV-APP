import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

/// Top-level Mode: Beauty & Lighting vs AR Face Effects
enum ZevFilterMode {
  beauty('Beauty & Lighting', Icons.auto_awesome_rounded),
  effects('AR Face Effects', Icons.face_rounded);

  final String label;
  final IconData icon;
  const ZevFilterMode(this.label, this.icon);
}

/// Categories for ZEV Calling System 2.0 camera filters and effects.
enum ZevCallEffectCategory {
  // Effects mode
  animals('Animals', Icons.pets_rounded),
  morphs('Face Warp', Icons.mood_rounded),
  props('Props', Icons.emoji_events_rounded),
  // Beauty mode
  lighting('Lighting', Icons.wb_sunny_rounded),
  beauty('Skin Tuning', Icons.face_retouching_natural_rounded),
  color('Color Tone', Icons.palette_rounded),
  background('Blur', Icons.blur_on_rounded);

  final String label;
  final IconData icon;
  const ZevCallEffectCategory(this.label, this.icon);

  ZevFilterMode get filterMode {
    switch (this) {
      case ZevCallEffectCategory.animals:
      case ZevCallEffectCategory.morphs:
      case ZevCallEffectCategory.props:
        return ZevFilterMode.effects;
      case ZevCallEffectCategory.lighting:
      case ZevCallEffectCategory.beauty:
      case ZevCallEffectCategory.color:
      case ZevCallEffectCategory.background:
        return ZevFilterMode.beauty;
    }
  }
}

/// Types of Funny Face Morphs, Animal Filters and AR Overlays.
enum ZevFaceOverlayType {
  none,
  // Animals
  dog,
  monkey,
  cat,
  lion,
  panda,
  bunny,
  fox,
  bear,
  piggy,
  koala,
  // Face Warps / Morphs
  bigNose,
  bigMouth,
  chubbyFace,
  alien,
  tinyFace,
  fisheye,
  longChin,
  squareHead,
  // Props & Accessories
  crown,
  disguise,
  sunglasses,
  pirate,
  angel,
  cyberpunk,
  party,
  wizard,
}

/// Advanced Video Effect Configuration for Agora RTC Camera Pipeline.
class ZevCallEffect {
  final String id;
  final String name;
  final ZevCallEffectCategory category;
  final IconData icon;
  final ZevFaceOverlayType faceOverlayType;
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
    this.faceOverlayType = ZevFaceOverlayType.none,
    this.agoraBeauty,
    this.virtualBackground,
    this.colorEnhance,
    this.lowlightEnhance,
    this.matrixFilter,
  });

  bool get isNone => id == 'none';
  bool get hasFaceOverlay => faceOverlayType != ZevFaceOverlayType.none;
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

/// Comprehensive Catalog of Production AR Filters & Effects for ZEV.
class ZevEffectsCatalog {
  ZevEffectsCatalog._();

  static const ZevCallEffect none = ZevCallEffect(
    id: 'none',
    name: 'Normal',
    category: ZevCallEffectCategory.animals,
    icon: Icons.not_interested_rounded,
    faceOverlayType: ZevFaceOverlayType.none,
  );

  static const List<ZevCallEffect> all = [
    none,

    // ====================================================
    // 1. ANIMALS CATEGORY
    // ====================================================
    ZevCallEffect(
      id: 'face_dog',
      name: 'Puppy Dog',
      category: ZevCallEffectCategory.animals,
      icon: Icons.pets_rounded,
      faceOverlayType: ZevFaceOverlayType.dog,
      agoraBeauty: BeautyOptions(
        lighteningLevel: 0.45,
        smoothnessLevel: 0.55,
      ),
    ),
    ZevCallEffect(
      id: 'face_monkey',
      name: 'Crazy Monkey',
      category: ZevCallEffectCategory.animals,
      icon: Icons.cruelty_free_rounded,
      faceOverlayType: ZevFaceOverlayType.monkey,
      agoraBeauty: BeautyOptions(
        lighteningLevel: 0.40,
        smoothnessLevel: 0.50,
      ),
    ),
    ZevCallEffect(
      id: 'face_cat',
      name: 'Cute Kitty',
      category: ZevCallEffectCategory.animals,
      icon: Icons.catching_pokemon_rounded,
      faceOverlayType: ZevFaceOverlayType.cat,
      agoraBeauty: BeautyOptions(
        lighteningLevel: 0.60,
        smoothnessLevel: 0.75,
        rednessLevel: 0.35,
      ),
    ),
    ZevCallEffect(
      id: 'face_lion',
      name: 'King Lion',
      category: ZevCallEffectCategory.animals,
      icon: Icons.wb_sunny_rounded,
      faceOverlayType: ZevFaceOverlayType.lion,
      colorEnhance: ColorEnhanceOptions(
        strengthLevel: 0.75,
        skinProtectLevel: 0.8,
      ),
    ),
    ZevCallEffect(
      id: 'face_panda',
      name: 'Panda Bear',
      category: ZevCallEffectCategory.animals,
      icon: Icons.favorite_rounded,
      faceOverlayType: ZevFaceOverlayType.panda,
      agoraBeauty: BeautyOptions(
        lighteningLevel: 0.55,
        smoothnessLevel: 0.65,
      ),
    ),
    ZevCallEffect(
      id: 'face_bunny',
      name: 'Bunny Rabbit',
      category: ZevCallEffectCategory.animals,
      icon: Icons.cruelty_free_rounded,
      faceOverlayType: ZevFaceOverlayType.bunny,
      agoraBeauty: BeautyOptions(
        lighteningLevel: 0.60,
        smoothnessLevel: 0.80,
      ),
    ),
    ZevCallEffect(
      id: 'face_fox',
      name: 'Cunning Fox',
      category: ZevCallEffectCategory.animals,
      icon: Icons.terrain_rounded,
      faceOverlayType: ZevFaceOverlayType.fox,
      colorEnhance: ColorEnhanceOptions(
        strengthLevel: 0.8,
        skinProtectLevel: 0.7,
      ),
    ),
    ZevCallEffect(
      id: 'face_bear',
      name: 'Teddy Bear',
      category: ZevCallEffectCategory.animals,
      icon: Icons.child_care_rounded,
      faceOverlayType: ZevFaceOverlayType.bear,
    ),
    ZevCallEffect(
      id: 'face_piggy',
      name: 'Funny Piggy',
      category: ZevCallEffectCategory.animals,
      icon: Icons.mood_rounded,
      faceOverlayType: ZevFaceOverlayType.piggy,
    ),
    ZevCallEffect(
      id: 'face_koala',
      name: 'Fluffy Koala',
      category: ZevCallEffectCategory.animals,
      icon: Icons.face_rounded,
      faceOverlayType: ZevFaceOverlayType.koala,
    ),

    // ====================================================
    // 2. FACE WARPS & MORPHS
    // ====================================================
    ZevCallEffect(
      id: 'face_big_nose',
      name: 'Big Nose',
      category: ZevCallEffectCategory.morphs,
      icon: Icons.sentiment_very_satisfied_rounded,
      faceOverlayType: ZevFaceOverlayType.bigNose,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastHigh,
        lighteningLevel: 0.50,
      ),
    ),
    ZevCallEffect(
      id: 'face_big_mouth',
      name: 'Big Mouth',
      category: ZevCallEffectCategory.morphs,
      icon: Icons.sentiment_satisfied_alt_rounded,
      faceOverlayType: ZevFaceOverlayType.bigMouth,
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastHigh,
        lighteningLevel: 0.50,
      ),
    ),
    ZevCallEffect(
      id: 'face_chubby',
      name: 'Chubby Face',
      category: ZevCallEffectCategory.morphs,
      icon: Icons.face_retouching_natural_rounded,
      faceOverlayType: ZevFaceOverlayType.chubbyFace,
      agoraBeauty: BeautyOptions(
        lighteningLevel: 0.55,
        smoothnessLevel: 0.70,
        rednessLevel: 0.40,
      ),
    ),
    ZevCallEffect(
      id: 'face_alien',
      name: 'Alien Eyes',
      category: ZevCallEffectCategory.morphs,
      icon: Icons.visibility_rounded,
      faceOverlayType: ZevFaceOverlayType.alien,
      matrixFilter: ColorFilter.matrix(<double>[
        1.10, 0, 0, 0, 0,
        0, 1.25, 0, 0, 10,
        0, 0, 1.30, 0, 20,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'face_tiny_face',
      name: 'Tiny Face',
      category: ZevCallEffectCategory.morphs,
      icon: Icons.child_care_rounded,
      faceOverlayType: ZevFaceOverlayType.tinyFace,
    ),
    ZevCallEffect(
      id: 'face_fisheye',
      name: 'Fish Eye',
      category: ZevCallEffectCategory.morphs,
      icon: Icons.lens_rounded,
      faceOverlayType: ZevFaceOverlayType.fisheye,
      colorEnhance: ColorEnhanceOptions(
        strengthLevel: 0.85,
        skinProtectLevel: 0.8,
      ),
    ),
    ZevCallEffect(
      id: 'face_long_chin',
      name: 'Long Chin',
      category: ZevCallEffectCategory.morphs,
      icon: Icons.south_rounded,
      faceOverlayType: ZevFaceOverlayType.longChin,
    ),
    ZevCallEffect(
      id: 'face_square',
      name: 'Block Head',
      category: ZevCallEffectCategory.morphs,
      icon: Icons.crop_square_rounded,
      faceOverlayType: ZevFaceOverlayType.squareHead,
    ),

    // ====================================================
    // 3. PROPS & ACCESSORIES
    // ====================================================
    ZevCallEffect(
      id: 'face_crown',
      name: 'King Crown',
      category: ZevCallEffectCategory.props,
      icon: Icons.emoji_events_rounded,
      faceOverlayType: ZevFaceOverlayType.crown,
      agoraBeauty: BeautyOptions(
        lighteningLevel: 0.65,
        smoothnessLevel: 0.65,
      ),
    ),
    ZevCallEffect(
      id: 'face_disguise',
      name: 'Detective',
      category: ZevCallEffectCategory.props,
      icon: Icons.face_rounded,
      faceOverlayType: ZevFaceOverlayType.disguise,
    ),
    ZevCallEffect(
      id: 'face_sunglasses',
      name: 'Cool Shades',
      category: ZevCallEffectCategory.props,
      icon: Icons.remove_red_eye_rounded,
      faceOverlayType: ZevFaceOverlayType.sunglasses,
      colorEnhance: ColorEnhanceOptions(
        strengthLevel: 0.8,
        skinProtectLevel: 0.8,
      ),
    ),
    ZevCallEffect(
      id: 'face_pirate',
      name: 'Pirate Captain',
      category: ZevCallEffectCategory.props,
      icon: Icons.sailing_rounded,
      faceOverlayType: ZevFaceOverlayType.pirate,
    ),
    ZevCallEffect(
      id: 'face_angel',
      name: 'Angel Halo',
      category: ZevCallEffectCategory.props,
      icon: Icons.brightness_high_rounded,
      faceOverlayType: ZevFaceOverlayType.angel,
      agoraBeauty: BeautyOptions(
        lighteningLevel: 0.70,
        smoothnessLevel: 0.80,
      ),
    ),
    ZevCallEffect(
      id: 'face_cyberpunk',
      name: 'Cyber Neon',
      category: ZevCallEffectCategory.props,
      icon: Icons.blur_linear_rounded,
      faceOverlayType: ZevFaceOverlayType.cyberpunk,
      matrixFilter: ColorFilter.matrix(<double>[
        1.15, 0, 0, 0, 10,
        0, 1.30, 0, 0, 20,
        0, 0, 1.45, 0, 30,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'face_party',
      name: 'Celebration',
      category: ZevCallEffectCategory.props,
      icon: Icons.celebration_rounded,
      faceOverlayType: ZevFaceOverlayType.party,
    ),
    ZevCallEffect(
      id: 'face_wizard',
      name: 'Wizard Hat',
      category: ZevCallEffectCategory.props,
      icon: Icons.auto_awesome_rounded,
      faceOverlayType: ZevFaceOverlayType.wizard,
    ),

    // ====================================================
    // 4. BEAUTY CATEGORY
    // ====================================================
    ZevCallEffect(
      id: 'beauty_natural',
      name: 'Natural',
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
      name: 'Clean Skin',
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

    // ====================================================
    // 5. LIGHTING CATEGORY
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

    // ====================================================
    // 6. BACKGROUND BLUR CATEGORY
    // ====================================================
    ZevCallEffect(
      id: 'bg_blur_low',
      name: 'Soft Blur',
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
      name: 'Heavy Blur',
      category: ZevCallEffectCategory.background,
      icon: Icons.blur_circular_rounded,
      virtualBackground: VirtualBackgroundSource(
        backgroundSourceType: BackgroundSourceType.backgroundBlur,
        blurDegree: BackgroundBlurDegree.blurDegreeHigh,
      ),
    ),

    // ====================================================
    // 7. COLOR & CINEMA CATEGORY
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
  ];

  static List<ZevCallEffect> byCategory(ZevCallEffectCategory cat) {
    return all.where((e) => e.category == cat || e.id == 'none').toList();
  }

  static ZevCallEffect findById(String id) {
    return all.firstWhere((e) => e.id == id, orElse: () => none);
  }
}
