import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/language_service.dart';

/// A non-intrusive in-feed Native Ad Card that matches Safi Academy post styling
class FeedAdCard extends StatefulWidget {
  const FeedAdCard({super.key});

  @override
  State<FeedAdCard> createState() => _FeedAdCardState();
}

class _FeedAdCardState extends State<FeedAdCard> {
  NativeAd? _nativeAd;
  bool _isAdLoaded = false;
  bool _hasError = false;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color surfaceWhite = Colors.white;
  static const Color cardBorder = Color(0xFFF1F5F9);

  @override
  void initState() {
    super.initState();
    _initAd();
  }

  void _initAd() {
    // 1. Instant cache check: Is ad preloaded in RAM?
    final preloadedAd = AdService.instance.getPreloadedFeedAd();
    if (preloadedAd != null) {
      _nativeAd = preloadedAd;
      _isAdLoaded = true;
      return; // ⚡ Renders instantly without loading delay
    }

    // 2. If mobile and not in cache, trigger background load
    if (AdService.instance.isPlatformSupported) {
      _loadFreshNativeAd();
    }
  }

  void _loadFreshNativeAd() {
    try {
      final adUnitId = AdService.instance.nativeAdUnitId;
      if (adUnitId.isEmpty) return;

      _nativeAd = NativeAd(
        adUnitId: adUnitId,
        request: const AdRequest(),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.medium,
          mainBackgroundColor: Colors.white,
          cornerRadius: 24.0,
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: Colors.white,
            backgroundColor: primaryPink,
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
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            if (mounted) {
              setState(() {
                _isAdLoaded = true;
                _hasError = false;
              });
            }
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint(
              '[FeedAdCard] Ad failed to load: ${error.message} (Code: ${error.code})',
            );
            try {
              ad.dispose();
            } catch (_) {}
            if (mounted) {
              setState(() {
                _isAdLoaded = false;
                _hasError = true;
              });
            }
          },
        ),
      );

      _nativeAd?.load();
    } catch (e) {
      debugPrint('[FeedAdCard] _loadFreshNativeAd catch: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only show if real ad is loaded successfully; otherwise show nothing
    if (!AdService.instance.isPlatformSupported ||
        !_isAdLoaded ||
        _nativeAd == null ||
        _hasError) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cardBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Sponsor Badge + Google Ads tag
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primaryPink.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: primaryPink.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.campaign_rounded,
                        size: 14,
                        color: primaryPink,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.l10n.sponsored,
                        style: const TextStyle(
                          color: primaryPink,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Text(
                  "Google Ads",
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // In-feed Native Template Ad widget (rendered instantly with zero wait)
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: double.infinity,
              height: 365,
              child: AdWidget(ad: _nativeAd!),
            ),
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

