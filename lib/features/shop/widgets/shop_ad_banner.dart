import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/theme/app_theme_service.dart';

class ShopAdBanner extends StatefulWidget {
  const ShopAdBanner({super.key});

  @override
  State<ShopAdBanner> createState() => _ShopAdBannerState();
}

class _ShopAdBannerState extends State<ShopAdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    if (AdService.instance.isPlatformSupported) {
      final preloaded = AdService.instance.getPreloadedShopBannerAd();
      if (preloaded != null) {
        _bannerAd = preloaded;
        _isLoaded = true;
      } else {
        _loadBanner();
      }
    }
  }

  void _loadBanner() {
    final adUnitId = AdService.instance.nativeAdUnitId;

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[ShopAdBanner] Banner failed to load: ${error.message}');
          ad.dispose();
          if (mounted) {
            setState(() {
              _isLoaded = false;
            });
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.instance.current;

    // If Google Ads is loaded, show it inside a luxury container
    if (_isLoaded && _bannerAd != null) {
      return Container(
        width: double.infinity,
        height: _bannerAd!.size.height.toDouble() + 16,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.cardBorder),
        ),
        child: AdWidget(ad: _bannerAd!),
      );
    }

    return const SizedBox.shrink();
  }
}

