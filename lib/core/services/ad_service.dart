import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Central Ad Service managing background preloading and non-intrusive Google AdMob ads for Feed & Reels
class AdService {
  AdService._privateConstructor();
  static final AdService instance = AdService._privateConstructor();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Non-intrusive frequency control
  static const int feedAdInterval = 3; // 1 ad every 3 user posts
  static const int reelsAdInterval = 5; // 1 ad every 5 reels

  // Ad cache pool for instant rendering without delays
  final List<NativeAd> _feedAdPool = [];
  final List<NativeAd> _reelsAdPool = [];
  BannerAd? _preloadedShopBanner;
  bool _isLoadingFeedAd = false;
  bool _isLoadingReelsAd = false;
  bool _isLoadingShopBanner = false;

  static const int maxPoolSize = 2;

  /// Check if the platform supports mobile ads
  bool get isPlatformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Initialize Google Mobile Ads SDK safely and start preloading immediately
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (!isPlatformSupported) {
      debugPrint('[AdService] Mobile ads skipped: platform not Android or iOS');
      return;
    }

    try {
      await MobileAds.instance.initialize();

      _isInitialized = true;
      debugPrint(
        '[AdService] Google Mobile Ads initialized successfully (Production Mode)',
      );

      // Preload ads in background on startup
      preloadAds();
    } catch (e) {
      debugPrint('[AdService] Failed to initialize MobileAds: $e');
    }
  }

  /// Start background preloading for Feed, Reels, and Shop
  void preloadAds() {
    preloadFeedAd();
    preloadReelsAd();
    preloadShopBannerAd();
  }

  /// Preload a Banner Ad for Shop ahead of time
  void preloadShopBannerAd() {
    if (!isPlatformSupported) return;
    if (_preloadedShopBanner != null || _isLoadingShopBanner) return;

    _isLoadingShopBanner = true;
    final adUnitId = dotenv.env['ADMOB_FEED_AD_UNIT_ID'] ?? prodNativeAdUnitId;

    final banner = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('[AdService] ✅ Shop Banner preloaded & ready in memory!');
          _preloadedShopBanner = ad as BannerAd;
          _isLoadingShopBanner = false;
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint(
            '[AdService] ❌ Failed to preload Shop Banner: ${error.message}',
          );
          ad.dispose();
          _isLoadingShopBanner = false;
        },
      ),
    );
    banner.load();
  }

  /// Get preloaded Shop Banner
  BannerAd? getPreloadedShopBannerAd() {
    if (_preloadedShopBanner != null) {
      final b = _preloadedShopBanner;
      _preloadedShopBanner = null;
      preloadShopBannerAd();
      return b;
    }
    preloadShopBannerAd();
    return null;
  }

  /// Preload a Native Ad for Feed into memory ahead of time
  void preloadFeedAd() {
    if (!isPlatformSupported) return;
    if (_feedAdPool.length >= maxPoolSize || _isLoadingFeedAd) return;

    final unitId = nativeAdUnitId;
    if (unitId.isEmpty) return;

    _isLoadingFeedAd = true;
    debugPrint('[AdService] ⏳ Preloading Feed Native Ad in background...');

    try {
      final ad = NativeAd(
        adUnitId: unitId,
        request: const AdRequest(),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.medium,
          mainBackgroundColor: Colors.white,
          cornerRadius: 24.0,
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: Colors.white,
            backgroundColor: const Color(0xFFFC466B),
            style: NativeTemplateFontStyle.bold,
            size: 14.0,
          ),
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: const Color(0xFF1E293B),
            style: NativeTemplateFontStyle.bold,
            size: 15.0,
          ),
          secondaryTextStyle: NativeTemplateTextStyle(
            textColor: const Color(0xFF64748B),
            style: NativeTemplateFontStyle.normal,
            size: 13.0,
          ),
        ),
        nativeAdOptions: NativeAdOptions(
          videoOptions: VideoOptions(
            startMuted: true,
            clickToExpandRequested: true,
          ),
        ),
        listener: NativeAdListener(
          onAdLoaded: (loadedAd) {
            debugPrint(
              '[AdService] ✅ Feed Native Ad preloaded & ready in memory!',
            );
            _feedAdPool.add(loadedAd as NativeAd);
            _isLoadingFeedAd = false;
            if (_feedAdPool.length < maxPoolSize) {
              preloadFeedAd();
            }
          },
          onAdFailedToLoad: (failedAd, error) {
            debugPrint(
              '[AdService] ❌ Failed to preload Feed Native Ad: ${error.message} (Code: ${error.code})',
            );
            try {
              failedAd.dispose();
            } catch (_) {}
            _isLoadingFeedAd = false;
          },
        ),
      );

      ad.load();
    } catch (e) {
      debugPrint('[AdService] ❌ preloadFeedAd failed: $e');
      _isLoadingFeedAd = false;
    }
  }

  /// Get a preloaded Feed ad immediately (0ms delay) and replenish the pool
  NativeAd? getPreloadedFeedAd() {
    if (_feedAdPool.isNotEmpty) {
      final ad = _feedAdPool.removeAt(0);
      debugPrint(
        '[AdService] ⚡ Consumed preloaded Feed ad from memory. Remaining: ${_feedAdPool.length}',
      );
      // Preload next ad in background to keep pool ready
      preloadFeedAd();
      return ad;
    }
    // If empty, trigger load immediately
    preloadFeedAd();
    return null;
  }

  /// Preload a Native Ad for Reels into memory ahead of time
  void preloadReelsAd() {
    if (!isPlatformSupported) return;
    if (_reelsAdPool.length >= maxPoolSize || _isLoadingReelsAd) return;

    final unitId = nativeAdUnitId;
    if (unitId.isEmpty) return;

    _isLoadingReelsAd = true;
    debugPrint('[AdService] ⏳ Preloading Reels Native Ad in background...');

    try {
      final ad = NativeAd(
        adUnitId: unitId,
        request: const AdRequest(),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.medium,
          mainBackgroundColor: const Color(0xFF1E293B),
          cornerRadius: 24.0,
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: Colors.white,
            backgroundColor: const Color(0xFFFC466B),
            style: NativeTemplateFontStyle.bold,
            size: 14.0,
          ),
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: Colors.white,
            style: NativeTemplateFontStyle.bold,
            size: 15.0,
          ),
          secondaryTextStyle: NativeTemplateTextStyle(
            textColor: const Color(0xFF94A3B8),
            style: NativeTemplateFontStyle.normal,
            size: 13.0,
          ),
        ),
        nativeAdOptions: NativeAdOptions(
          videoOptions: VideoOptions(
            startMuted: false,
            clickToExpandRequested: true,
          ),
          mediaAspectRatio: MediaAspectRatio.any,
        ),
        listener: NativeAdListener(
          onAdLoaded: (loadedAd) {
            debugPrint(
              '[AdService] ✅ Reels Native Ad preloaded & ready in memory!',
            );
            _reelsAdPool.add(loadedAd as NativeAd);
            _isLoadingReelsAd = false;
            if (_reelsAdPool.length < maxPoolSize) {
              preloadReelsAd();
            }
          },
          onAdFailedToLoad: (failedAd, error) {
            debugPrint(
              '[AdService] ❌ Failed to preload Reels Native Ad: ${error.message} (Code: ${error.code})',
            );
            try {
              failedAd.dispose();
            } catch (_) {}
            _isLoadingReelsAd = false;
          },
        ),
      );

      ad.load();
    } catch (e) {
      debugPrint('[AdService] ❌ preloadReelsAd failed: $e');
      _isLoadingReelsAd = false;
    }
  }

  /// Get a preloaded Reels ad immediately (0ms delay) and replenish the pool
  NativeAd? getPreloadedReelsAd() {
    if (_reelsAdPool.isNotEmpty) {
      final ad = _reelsAdPool.removeAt(0);
      debugPrint(
        '[AdService] ⚡ Consumed preloaded Reels ad from memory. Remaining: ${_reelsAdPool.length}',
      );
      preloadReelsAd();
      return ad;
    }
    preloadReelsAd();
    return null;
  }

  // AdMob native ad unit ID
  static const String prodNativeAdUnitId =
      'ca-app-pub-6551903544426492/4905894586';

  /// Official Native Ad Unit ID for Feed & Reels
  /// Dedicated native ad unit ID for monetization
  String get nativeAdUnitId {
    final envId = dotenv.env['ADMOB_FEED_AD_UNIT_ID'];
    if (envId != null && envId.isNotEmpty) return envId;
    return prodNativeAdUnitId;
  }

  /// Ad Unit ID for Feed Banner / Inline Ad
  String get feedBannerAdUnitId => nativeAdUnitId;

  /// Ad Unit ID for Reels In-Stream / Sponsored Ad
  String get reelsAdUnitId => nativeAdUnitId;

  /// Helper to calculate total count with ads interleaved every [interval] items
  int calculateTotalCount(int rawItemCount, int interval) {
    if (rawItemCount == 0 || interval <= 0) return 0;
    final adCount = rawItemCount ~/ interval;
    return rawItemCount + adCount;
  }

  /// Check if the index is an Ad slot
  bool isAdPosition(int index, int interval) {
    if (interval <= 0 || index < interval) return false;
    return (index + 1) % (interval + 1) == 0;
  }

  /// Map raw index (ignoring ad slots) from a combined index
  int getRawItemIndex(int index, int interval) {
    if (interval <= 0) return index;
    final adCountBefore = (index + 1) ~/ (interval + 1);
    return index - adCountBefore;
  }
}
