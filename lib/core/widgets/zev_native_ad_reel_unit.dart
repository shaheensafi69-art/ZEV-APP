import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/admob_service.dart';

/// Flagship Claymorphic In-Stream Native Ad Unit for ZEV Reels.
/// Rendered every 4 reels as a seamless, swipeable reel page.
/// Non-intrusive: zero countdown timers, zero popup dialogs, fully swipeable.
class ZevNativeAdReelUnit extends StatefulWidget {
  final bool isActive;
  const ZevNativeAdReelUnit({super.key, this.isActive = true});

  @override
  State<ZevNativeAdReelUnit> createState() => _ZevNativeAdReelUnitState();
}

class _ZevNativeAdReelUnitState extends State<ZevNativeAdReelUnit> {
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

    try {
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
            debugPrint('[ZevNativeAdReelUnit] Ad failed to load: ${error.message} (code ${error.code})');
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
          cornerRadius: 20.0,
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: Colors.black,
            backgroundColor: const Color(0xFF00D4FF),
            style: NativeTemplateFontStyle.bold,
            size: 16.0,
          ),
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: Colors.white,
            style: NativeTemplateFontStyle.bold,
            size: 16.0,
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
    } catch (e) {
      debugPrint('[ZevNativeAdReelUnit] Ad initialization warning: $e');
      if (mounted) {
        setState(() {
          _adFailed = true;
          _isAdLoaded = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF080D1A),
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        children: [
          // Ambient Gradient Glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.1),
                  radius: 0.95,
                  colors: [
                    const Color(0xFF00D4FF).withValues(alpha: 0.12),
                    const Color(0xFF0D1424),
                    const Color(0xFF080D1A),
                  ],
                ),
              ),
            ),
          ),

          // Main Ad Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 56),

                  // Header Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.campaign_rounded,
                          size: 16,
                          color: Color(0xFF00D4FF),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Sponsored Reel",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "AD",
                            style: TextStyle(
                              color: Color(0xFF00D4FF),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Center Claymorphic Card
                  if (_isAdLoaded && _nativeAd != null)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B132B),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.3),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.12),
                            blurRadius: 20,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        height: 380,
                        child: AdWidget(ad: _nativeAd!),
                      ),
                    )
                  else if (!_adFailed)
                    Container(
                      height: 340,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                          width: 1.0,
                        ),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF00D4FF),
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            "Loading recommendation...",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    // Graceful fallback if ad network returned no fill
                    Container(
                      height: 200,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.6),
                            size: 36,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "You're all caught up!",
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Spacer(),

                  // Bottom Swipe-Up Hint (User is never stuck!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 26,
                        ),
                        Text(
                          "Swipe up for next reel",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

