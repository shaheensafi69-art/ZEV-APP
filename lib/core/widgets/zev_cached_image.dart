import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/zev_theme.dart';

/// Flagship High-Performance Cached Image for ZEV.
/// Optimizations:
/// 1. Dual Cache: Instant disk + memory LRU caching via CachedNetworkImage.
/// 2. Downsampling: Caps [memCacheWidth] & [memCacheHeight] to prevent huge 4K
///    uncompressed bitmaps from hogging RAM and blocking the main UI thread.
/// 3. RepaintBoundary isolation to eliminate scrolling jank.
/// 4. Graceful fade-in (150ms) matching Instagram.
class ZevCachedImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const ZevCachedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth,
    this.memCacheHeight,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  /// Factory for user avatars (downsampled to 160px for buttery smooth 120 FPS)
  factory ZevCachedImage.avatar({
    Key? key,
    required String imageUrl,
    double size = 42,
    BorderRadius? borderRadius,
  }) {
    return ZevCachedImage(
      key: key,
      imageUrl: imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      memCacheWidth: 160,
      memCacheHeight: 160,
      borderRadius: borderRadius ?? BorderRadius.circular(size / 2),
      placeholder: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          shape: borderRadius != null ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: borderRadius,
        ),
        child: Icon(Icons.person_rounded, size: size * 0.55, color: ZevColors.textMuted),
      ),
      errorWidget: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          shape: borderRadius != null ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: borderRadius,
        ),
        child: Icon(Icons.person_rounded, size: size * 0.55, color: ZevColors.textMuted),
      ),
    );
  }

  /// Factory for 3-column Grid Thumbnails (e.g. Explore, Profile) downsampled to 400px
  factory ZevCachedImage.grid({
    Key? key,
    required String imageUrl,
    double? width,
    double? height,
    BorderRadius? borderRadius,
  }) {
    return ZevCachedImage(
      key: key,
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
      memCacheWidth: 400,
      memCacheHeight: 400,
      borderRadius: borderRadius,
    );
  }

  /// Factory for Feed Post Canvas (downsampled to 1080px for crispness with zero lag)
  factory ZevCachedImage.feedPost({
    Key? key,
    required String imageUrl,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    BorderRadius? borderRadius,
  }) {
    return ZevCachedImage(
      key: key,
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: 1080,
      memCacheHeight: 1440,
      borderRadius: borderRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _buildFallback();
    }

    Widget image = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholder: (context, url) =>
          placeholder ??
          Container(
            width: width,
            height: height,
            color: const Color(0xFFF1F5F9),
          ),
      errorWidget: (context, url, error) => errorWidget ?? _buildFallback(),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return RepaintBoundary(child: image);
  }

  Widget _buildFallback() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF1F5F9),
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          color: ZevColors.textMuted,
          size: 28,
        ),
      ),
    );
  }
}

