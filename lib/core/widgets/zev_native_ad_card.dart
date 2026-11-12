import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:video_player/video_player.dart';

import '../services/admob_service.dart';
import '../services/zev_ads_service.dart';
import '../theme/zev_theme.dart';
import 'zev_cached_image.dart';

/// Light Clearmorphic In-Stream Ad Card for ZEV Feed & Explore.
/// Prioritizes active ZEV Ads Manager campaigns via `/api/v1/ads/serve`,
/// falling back cleanly to AdMob [NativeAd] on mobile when no internal ad matches.
class ZevNativeAdCard extends StatefulWidget {
  final String placement;
  final String slotKey;
  final String? country;
  final String? interest;

  const ZevNativeAdCard({
    super.key,
    this.placement = 'feed',
    this.slotKey = 'feed_default',
    this.country,
    this.interest,
  });

  @override
  State<ZevNativeAdCard> createState() => _ZevNativeAdCardState();
}

class _ZevNativeAdCardState extends State<ZevNativeAdCard> {
  ZevSponsoredAd? _sponsoredAd;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  bool _isMuted = true;

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
      placement: widget.placement,
      slotKey: widget.slotKey,
      country: widget.country,
      interest: widget.interest,
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
        _initAdVideo(ad.mediaUrl);
      }
      return;
    }

    _loadAdMobFallback();
  }

  void _initAdVideo(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    try {
      final ctrl = VideoPlayerController.networkUrl(uri)
        ..setLooping(true)
        ..setVolume(0.0);
      _videoCtrl = ctrl;
      ctrl.initialize().then((_) {
        if (!mounted) return;
        setState(() => _videoReady = true);
        ctrl.play();
      }).catchError((_) {});
    } catch (_) {}
  }

  void _loadAdMobFallback() {
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
              '[ZevNativeAdCard] Ad failed to load: ${error.message} (code ${error.code})',
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
          cornerRadius: 18.0,
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: ZevColors.deepNavy,
            backgroundColor: ZevColors.primaryBlue,
            style: NativeTemplateFontStyle.bold,
            size: 14.5,
          ),
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: ZevColors.deepNavy,
            style: NativeTemplateFontStyle.bold,
            size: 15.0,
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
      debugPrint('[ZevNativeAdCard] Ad initialization warning: $e');
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
      return _buildInternalSponsoredCard(_sponsoredAd!);
    }

    if (kIsWeb || _adFailed || !_isAdMobLoaded || _nativeAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ZevColors.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSponsoredHeader(partnerName: 'Promoted', badgeText: 'Ad'),
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

  Widget _buildSponsoredHeader({
    required String partnerName,
    required String badgeText,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: ZevColors.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: ZevColors.primaryBlue.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.campaign_rounded,
                  size: 13.5,
                  color: Color(0xFF0284C7),
                ),
                const SizedBox(width: 4),
                Text(
                  badgeText,
                  style: const TextStyle(
                    color: Color(0xFF0284C7),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              partnerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ZevColors.deepNavy,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Text(
            'ZEV Ads',
            style: TextStyle(
              color: ZevColors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInternalSponsoredCard(ZevSponsoredAd ad) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ZevColors.border, width: 1.3),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: ZevColors.primaryBlue.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSponsoredHeader(
            partnerName: ad.businessName,
            badgeText: 'Sponsored',
          ),
          if (ad.mediaUrl.isNotEmpty)
            GestureDetector(
              onTap: () => ZevAdsService.instance.openAdDestination(
                slotKey: widget.slotKey,
                ad: ad,
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: ZevColors.softSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ZevColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: ad.isVideo && _videoCtrl != null && _videoReady
                    ? Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          AspectRatio(
                            aspectRatio: _videoCtrl!.value.aspectRatio > 0
                                ? _videoCtrl!.value.aspectRatio
                                : 16 / 9,
                            child: VideoPlayer(_videoCtrl!),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isMuted = !_isMuted;
                                  _videoCtrl?.setVolume(_isMuted ? 0.0 : 1.0);
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isMuted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  size: 16,
                                  color: ZevColors.deepNavy,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : SizedBox(
                        height: 220,
                        width: double.infinity,
                        child: ZevCachedImage.feedPost(
                          imageUrl: ad.mediaUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ad.title.isNotEmpty)
                  Text(
                    ad.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: ZevColors.deepNavy,
                      height: 1.25,
                    ),
                  ),
                if (ad.body.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    ad.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ZevColors.textSecondary,
                      height: 1.4,
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
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ad.ctaLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
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
    );
  }
}
