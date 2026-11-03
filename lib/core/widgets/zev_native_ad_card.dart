import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/admob_service.dart';

/// Claymorphic Native Ad Card for ZEV Feed.
/// Displays an in-stream native ad unit every 3 posts.
/// Uses the real production ad unit ID: ca-app-pub-6551903544426492/4905894586
/// Strictly non-intrusive (never shows fullscreen popups/interstitials).
class ZevNativeAdCard extends StatefulWidget {
  const ZevNativeAdCard({super.key});

  @override
  State<ZevNativeAdCard> createState() => _ZevNativeAdCardState();
}

class _ZevNativeAdCardState extends State<ZevNativeAdCard> {
  NativeAd? _nativeAd;
  bool _isAdLoaded = false;
  bool _adFailed = false;

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  void _loadNativeAd() {
    if (kIsWeb) return;

    _nativeAd = NativeAd(
      adUnitId: AdmobService.nativeAdUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _isAdLoaded = true;
              _adFailed = false;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[ZevNativeAdCard] Ad failed to load: ${error.message} (code ${error.code})');
          ad.dispose();
          if (mounted) {
            setState(() {
              _nativeAd = null;
              _isAdLoaded = false;
              _adFailed = true;
            });
          }
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFF0F172A),
        cornerRadius: 18.0,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.black,
          backgroundColor: const Color(0xFF00D4FF),
          style: NativeTemplateFontStyle.bold,
          size: 15.0,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          style: NativeTemplateFontStyle.bold,
          size: 15.0,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFF94A3B8),
          size: 13.0,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFF64748B),
          size: 12.0,
        ),
      ),
    )..load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If ad failed to load or on unsupported platform, hide gracefully without empty space
    if (kIsWeb || _adFailed || (!_isAdLoaded && _nativeAd == null)) {
      return const SizedBox.shrink();
    }

    // While loading, do not pop empty space; wait for load
    if (!_isAdLoaded || _nativeAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF00D4FF).withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFF00D4FF).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sponsored Header Pill
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.campaign_rounded,
                        size: 13,
                        color: const Color(0xFF00D4FF),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Sponsored",
                        style: TextStyle(
                          color: const Color(0xFF00D4FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  "Ad",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Native Ad Platform View
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(22),
              bottomRight: Radius.circular(22),
            ),
            child: SizedBox(
              height: 360,
              child: AdWidget(ad: _nativeAd!),
            ),
          ),
        ],
      ),
    );
  }
}

