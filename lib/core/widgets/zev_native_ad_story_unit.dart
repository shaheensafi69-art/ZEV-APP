import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:video_player/video_player.dart';

import '../services/admob_service.dart';
import '../services/zev_ads_service.dart';
import '../theme/zev_theme.dart';
import 'zev_cached_image.dart';

/// Light Clearmorphic In-Stream Story Ad Unit for ZEV Stories.
/// Tries ZEV internal sponsored campaigns (`placement: 'story'`) first,
/// falling back gracefully to AdMob [NativeAd] on mobile.
class ZevNativeAdStoryUnit extends StatefulWidget {
  final String slotKey;
  final VoidCallback? onAdLoaded;
  final VoidCallback? onAdFailed;
  final void Function(ZevSponsoredAd? ad)? onSponsoredAdLoaded;

  const ZevNativeAdStoryUnit({
    super.key,
    this.slotKey = 'story_default',
    this.onAdLoaded,
    this.onAdFailed,
    this.onSponsoredAdLoaded,
  });

  @override
  State<ZevNativeAdStoryUnit> createState() => _ZevNativeAdStoryUnitState();
}

class _ZevNativeAdStoryUnitState extends State<ZevNativeAdStoryUnit> {
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

  Future<void> _loadAd() async {
    final ad = await ZevAdsService.instance.fetchEligibleAd(
      placement: 'story',
      slotKey: widget.slotKey,
    );

    if (!mounted) return;

    if (ad != null) {
      setState(() {
        _sponsoredAd = ad;
        _adFailed = false;
      });
      widget.onSponsoredAdLoaded?.call(ad);
      widget.onAdLoaded?.call();
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
              ctrl.play();
            }).catchError((_) {});
          } catch (_) {}
        }
      }
      return;
    }

    widget.onSponsoredAdLoaded?.call(null);
    _loadNativeAdFallback();
  }

  void _loadNativeAdFallback() {
    if (kIsWeb) {
      if (mounted) setState(() => _adFailed = true);
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
                _isAdMobLoaded = true;
                _adFailed = false;
              });
              widget.onAdLoaded?.call();
            }
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint(
              '[ZevNativeAdStoryUnit] Ad failed to load: ${error.message} (code ${error.code})',
            );
            ad.dispose();
            if (mounted) {
              setState(() {
                _nativeAd = null;
                _isAdMobLoaded = false;
                _adFailed = true;
              });
              widget.onAdFailed?.call();
            }
          },
        ),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.medium,
          mainBackgroundColor: ZevColors.white,
          cornerRadius: 22.0,
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: ZevColors.deepNavy,
            backgroundColor: ZevColors.primaryBlue,
            style: NativeTemplateFontStyle.bold,
            size: 15.0,
          ),
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: ZevColors.deepNavy,
            style: NativeTemplateFontStyle.bold,
            size: 15.0,
          ),
          secondaryTextStyle: NativeTemplateTextStyle(
            textColor: ZevColors.textSecondary,
            size: 12.5,
          ),
          tertiaryTextStyle: NativeTemplateTextStyle(
            textColor: ZevColors.textMuted,
            size: 11.5,
          ),
        ),
      )..load();
    } catch (e) {
      debugPrint('[ZevNativeAdStoryUnit] Ad initialization warning: $e');
      if (mounted) {
        setState(() {
          _nativeAd = null;
          _isAdMobLoaded = false;
          _adFailed = true;
        });
        widget.onAdFailed?.call();
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
    return Container(
      color: ZevColors.softSurface,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
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
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  const SizedBox(height: 82),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ZevColors.border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.deepNavy.withValues(alpha: 0.06),
                          blurRadius: 12,
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
                        Text(
                          _sponsoredAd != null
                              ? _sponsoredAd!.businessName
                              : 'Sponsored Story',
                          style: const TextStyle(
                            color: ZevColors.deepNavy,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
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
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_sponsoredAd != null)
                    _buildInternalSponsoredStoryCard(_sponsoredAd!)
                  else if (_isAdMobLoaded && _nativeAd != null)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: ZevColors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: ZevColors.border, width: 1.3),
                        boxShadow: [
                          BoxShadow(
                            color: ZevColors.deepNavy.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
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
                        color: ZevColors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: ZevColors.border),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: ZevColors.primaryBlue,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Loading sponsored story...',
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
                      height: 160,
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: Color(0xFF0284C7),
                            size: 34,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Enjoy your stories',
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
                    padding: EdgeInsets.only(bottom: 72),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          color: ZevColors.textMuted,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Tap right to skip • Hold to pause',
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

  Widget _buildInternalSponsoredStoryCard(ZevSponsoredAd ad) {
    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ad.mediaUrl.isNotEmpty)
            SizedBox(
              height: 290,
              child: ad.isVideo && _videoCtrl != null && _videoReady
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
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ad.title.isNotEmpty)
                  Text(
                    ad.title,
                    style: const TextStyle(
                      color: ZevColors.deepNavy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                if (ad.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    ad.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ZevColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
