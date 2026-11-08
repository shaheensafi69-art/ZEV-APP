import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Centralized Google AdMob Service for ZEV.
/// Strict Ad Policy:
/// - Real production Ad Unit IDs for Android and iOS.
/// - Android App ID: ca-app-pub-6551903544426492~5253464669
/// - iOS App ID: ca-app-pub-6551903544426492~4786844584
/// - Android Native Ad Unit ID: ca-app-pub-6551903544426492/4905894586
/// - iOS Native Ad Unit ID: ca-app-pub-6551903544426492/3940495638
/// - ONLY Native in-stream units in Feed, Reels & Stories (strictly NO fullscreen popups/interstitials).
/// - Feed: 1 Ad every 3 posts.
/// - Reels: 1 Ad every 4 reels.
/// - Stories: 1 Ad every 3 stories or between friend stories.
class AdmobService {
  AdmobService._();
  static final AdmobService instance = AdmobService._();

  /// Real Production Native Ad Unit IDs
  static const String androidNativeAdUnitId =
      'ca-app-pub-6551903544426492/4905894586';
  static const String iosNativeAdUnitId =
      'ca-app-pub-6551903544426492/3940495638';

  /// Resolves the correct platform-specific Native Ad Unit ID
  static String get nativeAdUnitId {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return iosNativeAdUnitId;
    }
    return androidNativeAdUnitId;
  }

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (kIsWeb) return; // Google Mobile Ads Flutter SDK is mobile-native
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      debugPrint(
        '[AdmobService] Google Mobile Ads initialized successfully with real Ad Unit IDs.',
      );
    } catch (e) {
      debugPrint('[AdmobService] Initialization failed: $e');
    }
  }
}
