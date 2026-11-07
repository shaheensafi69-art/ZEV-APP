import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Centralized Google AdMob Service for ZEV.
/// Strict Ad Policy:
/// - Real production Ad Unit ID (ca-app-pub-6551903544426492/4905894586).
/// - ONLY Native in-stream units in Feed, Reels & Stories (strictly NO fullscreen popups/interstitials).
/// - Feed: 1 Ad every 3 posts.
/// - Reels: 1 Ad every 4 reels.
/// - Stories: 1 Ad every 3 stories or between friend stories.
class AdmobService {
  AdmobService._();
  static final AdmobService instance = AdmobService._();

  /// Real Production Native Ad Unit ID provided by user
  static const String nativeAdUnitId = 'ca-app-pub-6551903544426492/4905894586';

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (kIsWeb) return; // Google Mobile Ads Flutter SDK is mobile-native
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      debugPrint('[AdmobService] Google Mobile Ads initialized successfully with real Ad Unit IDs.');
    } catch (e) {
      debugPrint('[AdmobService] Initialization failed: $e');
    }
  }
}

