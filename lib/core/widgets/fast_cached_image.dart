import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Central, high-performance image caching component for Safi Academy.
/// Features:
/// 1. Persistent disk caching: Download once, instant load thereafter.
/// 2. Strict RAM memory caching ([memCacheWidth], [memCacheHeight]) to prevent decoding multi-megapixel photos in RAM.
/// 3. Zero frame-drops and sub-second load times on low-bandwidth Afghan internet connections.
/// 4. Graceful shimmer / pulsing placeholder and fallback error handling.
class FastCachedImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Widget? placeholder;
  final Widget? errorWidget;
  final VoidCallback? onTap;

  const FastCachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.memCacheWidth = 720,
    this.memCacheHeight,
    this.placeholder,
    this.errorWidget,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final validUrl = imageUrl?.trim();

    Widget imageContent;

    if (validUrl == null || validUrl.isEmpty) {
      imageContent = _buildPlaceholder(context);
    } else {
      imageContent = CachedNetworkImage(
        imageUrl: validUrl,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        fadeInDuration: const Duration(milliseconds: 180),
        fadeOutDuration: const Duration(milliseconds: 180),
        placeholder: (context, url) => placeholder ?? _buildShimmerPlaceholder(),
        errorWidget: (context, url, error) =>
            errorWidget ?? _buildErrorWidget(context),
      );
    }

    if (borderRadius != null) {
      imageContent = ClipRRect(
        borderRadius: borderRadius!,
        child: imageContent,
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: imageContent,
      );
    }

    return imageContent;
  }

  Widget _buildShimmerPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF3F4F6),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            color: Color(0xFFFC466B),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF3F4F6),
      child: const Icon(
        Icons.image_outlined,
        color: Color(0xFF9CA3AF),
        size: 28,
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFFEE2E2),
      child: const Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: Color(0xFFEF4444),
          size: 24,
        ),
      ),
    );
  }
}

/// High-performance circular avatar with cached network image and initials fallback
class FastCircleAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final String fallbackText;
  final Color backgroundColor;
  final Color textColor;
  final BoxBorder? border;
  final VoidCallback? onTap;

  const FastCircleAvatar({
    super.key,
    required this.imageUrl,
    this.radius = 20,
    this.fallbackText = 'U',
    this.backgroundColor = const Color(0xFFFAF4F6),
    this.textColor = const Color(0xFFFC466B),
    this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final validUrl = imageUrl?.trim();
    final hasUrl = validUrl != null && validUrl.isNotEmpty;

    Widget avatar = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        color: backgroundColor,
      ),
      child: ClipOval(
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: validUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                memCacheWidth: (radius * 4).round(),
                memCacheHeight: (radius * 4).round(),
                placeholder: (context, url) => Container(
                  color: backgroundColor,
                  child: Center(
                    child: SizedBox(
                      width: radius * 0.8,
                      height: radius * 0.8,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => _buildInitials(),
              )
            : _buildInitials(),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatar,
      );
    }

    return avatar;
  }

  Widget _buildInitials() {
    final initial = fallbackText.trim().isNotEmpty ? fallbackText.trim()[0] : 'U';
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}

/// Helper to asynchronously pre-cache network images into disk/memory cache
void precacheNetworkImages(BuildContext context, List<String> urls) {
  for (final rawUrl in urls) {
    final url = rawUrl.trim();
    if (url.isNotEmpty && url.startsWith('http')) {
      try {
        precacheImage(CachedNetworkImageProvider(url), context);
      } catch (_) {}
    }
  }
}
