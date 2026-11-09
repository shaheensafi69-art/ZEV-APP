import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/admob_service.dart';

/// Flagship Claymorphic In-Stream Native Ad Unit for ZEV Stories.
/// Rendered seamlessly within the Story Viewer flow (e.g., every 3 stories or between friend stories).
/// Non-intrusive: 5-second timer, hold-to-pause, instant tap-to-skip, zero blocking popups.
class ZevNativeAdStoryUnit extends StatefulWidget {
  final VoidCallback? onAdLoaded;
  final VoidCallback? onAdFailed;

  const ZevNativeAdStoryUnit({
    super.key,
    this.onAdLoaded,
    this.onAdFailed,
  });

  @override
  State<ZevNativeAdStoryUnit> createState() => _ZevNativeAdStoryUnitState();
}

class _ZevNativeAdStoryUnitState extends State<ZevNativeAdStoryUnit> {
  NativeAd? _nativeAd;
  bool _isAdLoaded = false;
  bool _adFailed = false;

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  void _loadNativeAd() {
    if (kIsWeb) {
      widget.onAdFailed?.call();
      return;
    }

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
              widget.onAdLoaded?.call();
            }
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('[ZevNativeAdStoryUnit] Ad failed to load: ${error.message} (code ${error.code})');
            ad.dispose();
            if (mounted) {
              setState(() {
                _nativeAd = null;
                _isAdLoaded = false;
                _adFailed = true;
              });
              widget.onAdFailed?.call();
            }
          },
        ),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.medium,
          mainBackgroundColor: const Color(0xFF0F172A),
          cornerRadius: 22.0,
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
            size: 12.5,
          ),
          tertiaryTextStyle: NativeTemplateTextStyle(
            textColor: const Color(0xFF64748B),
            size: 11.5,
          ),
        ),
      )..load();
    } catch (e) {
      debugPrint('[ZevNativeAdStoryUnit] Ad initialization warning: $e');
      if (mounted) {
        setState(() {
          _nativeAd = null;
          _isAdLoaded = false;
          _adFailed = true;
        });
        widget.onAdFailed?.call();
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
        fit: StackFit.expand,
        children: [
          // Ambient Cyber-Cyan Radial Glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 0.95,
                  colors: [
                    const Color(0xFF00D4FF).withValues(alpha: 0.15),
                    const Color(0xFF0D1424),
                    const Color(0xFF080D1A),
                  ],
                ),
              ),
            ),
          ),

          // Main Ad Content & Glass Card
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  const SizedBox(height: 72),

                  // Sponsored Story Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.18),
                          blurRadius: 12,
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
                          "Sponsored Story",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            "AD",
                            style: TextStyle(
                              color: Color(0xFF00D4FF),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Center Ad Container
                  if (_isAdLoaded && _nativeAd != null)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B132B),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.65),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
                            blurRadius: 22,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        height: 360,
                        child: AdWidget(ad: _nativeAd!),
                      ),
                    )
                  else if (!_adFailed)
                    Container(
                      height: 320,
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
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Color(0xFF00D4FF),
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            "Loading sponsored content...",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    // Graceful fallback
                    Container(
                      height: 160,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.6),
                            size: 34,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Enjoy your stories",
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Spacer(),

                  // Bottom Navigation Hint
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Tap right to continue",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
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

