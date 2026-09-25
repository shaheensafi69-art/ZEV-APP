import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/theme/app_theme_service.dart';

class SponsoredStoryScreen extends StatefulWidget {
  const SponsoredStoryScreen({super.key});

  @override
  State<SponsoredStoryScreen> createState() => _SponsoredStoryScreenState();
}

class _SponsoredStoryScreenState extends State<SponsoredStoryScreen> {
  NativeAd? _nativeAd;
  bool _isAdLoaded = false;

  Timer? _timer;
  double _progress = 0.0;
  static const int _durationSeconds = 6;

  @override
  void initState() {
    super.initState();
    _loadAd();
    _startTimer();
  }

  void _startTimer() {
    const tick = Duration(milliseconds: 50);
    final totalTicks = (_durationSeconds * 1000) / 50;
    _timer = Timer.periodic(tick, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _progress += 1.0 / totalTicks;
        if (_progress >= 1.0) {
          t.cancel();
          Navigator.pop(context);
        }
      });
    });
  }

  void _loadAd() {
    if (!AdService.instance.isPlatformSupported) return;

    final adUnitId = AdService.instance.nativeAdUnitId;

    _nativeAd = NativeAd(
      adUnitId: adUnitId,
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
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _isAdLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[SponsoredStoryScreen] Ad failed: ${error.message}');
          try {
            ad.dispose();
          } catch (_) {}
          if (mounted) {
            setState(() {
              _isAdLoaded = false;
            });
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.instance.current;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D),
      body: SafeArea(
        child: GestureDetector(
          onTapDown: (_) => _timer?.cancel(),
          onTapUp: (_) => _startTimer(),
          child: Stack(
            children: [
              // Top Progress Bar
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: LinearProgressIndicator(
                  value: _progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
                  minHeight: 3.5,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),

              // Header: Sponsored Info + Close
              Positioned(
                top: 20,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        gradient: palette.gradient,
                        shape: BoxShape.circle,
                      ),
                      child: const CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.black,
                        child: Icon(
                          Icons.campaign_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ZEV Official Partner',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: palette.primary.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Sponsored Ad',
                            style: TextStyle(
                              color: palette.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Center: Native Ad or Sponsored Card
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _isAdLoaded && _nativeAd != null
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 320,
                            minHeight: 340,
                            maxWidth: 380,
                            maxHeight: 400,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: AdWidget(ad: _nativeAd!),
                          ),
                        )
                      : _buildSponsoredCard(palette),
                ),
              ),

              // Bottom CTA
              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Special partner offer from ZEV'),
                          backgroundColor: Colors.blue,
                        ),
                      );
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text(
                      'View Offer Details',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSponsoredCard(LuxuryPalette palette) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.cardBorder),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: 0.15),
            blurRadius: 30,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: palette.gradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.star_rounded,
              color: Colors.white,
              size: 42,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Safi Elite Trader Club',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Exclusive access to algorithmic trading bots, crypto & forex signals with guaranteed quality.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _featureChip('3-Year Backtest', palette),
              const SizedBox(width: 8),
              _featureChip('24/7 Support', palette),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featureChip(String label, LuxuryPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.primary.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.primary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
