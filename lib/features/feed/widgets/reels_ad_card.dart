import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/language_service.dart';

/// A full-screen non-intrusive Reel Ad card that users can effortlessly swipe past
class ReelsAdCard extends StatefulWidget {
  const ReelsAdCard({super.key});

  @override
  State<ReelsAdCard> createState() => _ReelsAdCardState();
}

class _ReelsAdCardState extends State<ReelsAdCard> {
  NativeAd? _nativeAd;
  bool _isAdLoaded = false;
  bool _hasError = false;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color bgDark = Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    _initAd();
  }

  void _initAd() {
    // 1. Instant cache check for sponsored reel
    final preloadedAd = AdService.instance.getPreloadedReelsAd();
    if (preloadedAd != null) {
      _nativeAd = preloadedAd;
      _isAdLoaded = true;
      return; // ⚡ Shows immediately without loading delay
    }

    // 2. If mobile platform, start loading
    if (AdService.instance.isPlatformSupported) {
      _loadFreshAd();
    }
  }

  void _loadFreshAd() {
    final adUnitId = AdService.instance.nativeAdUnitId;
    if (adUnitId.isEmpty) return;

    _nativeAd = NativeAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFF1E293B),
        cornerRadius: 24.0,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: primaryPink,
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
            '[ReelsAdCard] Ad failed to load: ${error.message} (Code: ${error.code})',
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
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only show if real native ad is loaded successfully; otherwise show nothing
    if (!AdService.instance.isPlatformSupported ||
        !_isAdLoaded ||
        _nativeAd == null ||
        _hasError) {
      return const SizedBox.shrink();
    }

    return Container(
      color: bgDark,
      child: SafeArea(
        child: Stack(
          children: [
            // Ambient background glow
            Positioned(
              top: MediaQuery.of(context).size.height * 0.2,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryPink.withOpacity(0.18),
                        blurRadius: 90,
                        spreadRadius: 40,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Main Content: Preloaded Native Ad
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Sponsored badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: primaryPink.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: primaryPink.withOpacity(0.4),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.campaign_rounded,
                          size: 16,
                          color: primaryPink,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.sponsored,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // The Native Ad container (Instant render)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        width: double.infinity,
                        height: 365,
                        child: AdWidget(ad: _nativeAd!),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Swipe hint
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.keyboard_double_arrow_up_rounded,
                        color: Colors.white.withOpacity(0.6),
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.l10n.swipeUpForNextReel,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

