import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:video_player/video_player.dart';

import '../services/admob_service.dart';
import '../services/zev_ads_service.dart';
import '../theme/zev_theme.dart';
import 'zev_cached_image.dart';

/// Light Clearmorphic In-Stream Ad Unit for ZEV Reels.
/// Renders ZEV internal sponsored Reel creatives first, with mobile AdMob fallback.
class ZevNativeAdReelUnit extends StatefulWidget {
  final bool isActive;
  final String slotKey;

  const ZevNativeAdReelUnit({
    super.key,
    this.isActive = true,
    this.slotKey = 'reel_default',
  });

  @override
  State<ZevNativeAdReelUnit> createState() => _ZevNativeAdReelUnitState();
}

class _ZevNativeAdReelUnitState extends State<ZevNativeAdReelUnit> {
  ZevSponsoredAd? _sponsoredAd;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  NativeAd? _nativeAd;
  bool _isAdMobLoaded = false;
  bool _adFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAd());
  }

  @override
  void didUpdateWidget(covariant ZevNativeAdReelUnit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive && _videoCtrl != null && _videoReady) {
      if (widget.isActive) {
        _videoCtrl!.play();
      } else {
        _videoCtrl!.pause();
      }
    }
  }

  Future<void> _loadAd() async {
    final ad = await ZevAdsService.instance.fetchEligibleAd(
      placement: 'reel',
      slotKey: widget.slotKey,
    );

    if (!mounted) return;

    if (ad != null) {
      setState(() {
        _sponsoredAd = ad;
        _adFailed = false;
      });
      unawaited(
        ZevAdsService.instance.recordImpressionOnce(
          slotKey: widget.slotKey,
          ad: ad,
        ),
      );
      if (ad.isVideo && ad.mediaUrl.isNotEmpty) {
        final uri = Uri.tryParse(ad.mediaUrl);
        if (uri != null && uri.hasScheme) {
          try {
            final ctrl = VideoPlayerController.networkUrl(uri)
              ..setLooping(true);
            _videoCtrl = ctrl;
            ctrl.initialize().then((_) {
              if (!mounted) return;
              setState(() => _videoReady = true);
              if (widget.isActive) ctrl.play();
            }).catchError((_) {});
          } catch (_) {}
        }
      }
      return;
    }

    _loadNativeAdFallback();
  }

  void _loadNativeAdFallback() {
    if (kIsWeb) {
      if (mounted) setState(() => _adFailed = true);
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
                _isAdMobLoaded = true;
                _adFailed = false;
              });
            }
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint(
              '[ZevNativeAdReelUnit] Ad failed to load: ${error.message} (code ${error.code})',
            );
            ad.dispose();
            if (mounted) {
              setState(() {
                _nativeAd = null;
                _isAdMobLoaded = false;
                _adFailed = true;
              });
            }
          },
        ),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.medium,
          mainBackgroundColor: ZevColors.white,
          cornerRadius: 20.0,
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: ZevColors.deepNavy,
            backgroundColor: ZevColors.primaryBlue,
            style: NativeTemplateFontStyle.bold,
            size: 16.0,
          ),
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: ZevColors.deepNavy,
            style: NativeTemplateFontStyle.bold,
            size: 16.0,
          ),
          secondaryTextStyle: NativeTemplateTextStyle(
            textColor: ZevColors.textSecondary,
            size: 13.0,
          ),
          tertiaryTextStyle: NativeTemplateTextStyle(
            textColor: ZevColors.textMuted,
            size: 12.0,
          ),
        ),
      )..load();
    } catch (e) {
      debugPrint('[ZevNativeAdReelUnit] Ad initialization warning: $e');
      if (mounted) {
        setState(() {
          _adFailed = true;
          _isAdMobLoaded = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sponsoredAd != null) {
      return _buildInternalSponsoredReel(_sponsoredAd!);
    }

    return Container(
      color: ZevColors.softSurface,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 1.0,
                  colors: [
                    ZevColors.primaryBlue.withValues(alpha: 0.14),
                    ZevColors.softSurface,
                    ZevColors.white,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 58),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: ZevColors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ZevColors.border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.deepNavy.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.campaign_rounded,
                          size: 16,
                          color: Color(0xFF0284C7),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Sponsored Reel',
                          style: TextStyle(
                            color: ZevColors.deepNavy,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: ZevColors.primaryBlue.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'AD',
                            style: TextStyle(
                              color: Color(0xFF0284C7),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_isAdMobLoaded && _nativeAd != null)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: ZevColors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: ZevColors.border, width: 1.4),
                        boxShadow: [
                          BoxShadow(
                            color: ZevColors.deepNavy.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
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
                        color: ZevColors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: ZevColors.border),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: ZevColors.primaryBlue,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Loading recommendation...',
                            style: TextStyle(
                              color: ZevColors.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      height: 200,
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: Color(0xFF0284C7),
                            size: 36,
                          ),
                          SizedBox(height: 10),
                          Text(
                            "You're all caught up!",
                            style: TextStyle(
                              color: ZevColors.deepNavy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: ZevColors.textMuted,
                          size: 26,
                        ),
                        Text(
                          'Swipe up for next reel',
                          style: TextStyle(
                            color: ZevColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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

  Widget _buildInternalSponsoredReel(ZevSponsoredAd ad) {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ad.mediaUrl.isNotEmpty)
            ad.isVideo && _videoCtrl != null && _videoReady
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _videoCtrl!.value.size.width,
                      height: _videoCtrl!.value.size.height,
                      child: VideoPlayer(_videoCtrl!),
                    ),
                  )
                : ZevCachedImage.feedPost(
                    imageUrl: ad.mediaUrl,
                    fit: BoxFit.cover,
                  ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.65),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 86),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.campaign_rounded,
                            size: 15,
                            color: Color(0xFF0284C7),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Sponsored • ${ad.businessName}',
                            style: const TextStyle(
                              color: ZevColors.deepNavy,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Light Clearmorphic floating card overlay
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: ZevColors.border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.deepNavy.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (ad.title.isNotEmpty)
                          Text(
                            ad.title,
                            style: const TextStyle(
                              color: ZevColors.deepNavy,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        if (ad.body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            ad.body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ZevColors.textSecondary,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => ZevAdsService.instance.openAdDestination(
                            slotKey: widget.slotKey,
                            ad: ad,
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: ZevColors.brandGradientHorizontal,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  ad.ctaLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.open_in_new_rounded,
                                  color: Colors.white,
                                  size: 15,
                                ),
                              ],
                            ),
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
