import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../localization/zev_localizations.dart';
import '../theme/app_theme_service.dart';

/// Central, high-performance image caching component for Safi Academy.
/// Features:
/// 1. Persistent disk caching: Download once, instant load thereafter.
/// 2. Strict RAM memory caching ([memCacheWidth], [memCacheHeight]) to prevent decoding multi-megapixel photos in RAM.
/// 3. Zero frame-drops and sub-second load times on low-bandwidth Afghan internet connections.
/// 4. Graceful shimmer / pulsing placeholder and fallback error handling with retry.
class FastCachedImage extends StatefulWidget {
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
  State<FastCachedImage> createState() => _FastCachedImageState();
}

class _FastCachedImageState extends State<FastCachedImage> {
  int _retryKey = 0;
  bool _isRetrying = false;

  @override
  Widget build(BuildContext context) {
    final validUrl = widget.imageUrl?.trim();

    Widget imageContent;

    if (validUrl == null || validUrl.isEmpty) {
      imageContent = _buildPlaceholder(context);
    } else {
      imageContent = CachedNetworkImage(
        key: ValueKey('${validUrl}_$_retryKey'),
        imageUrl: validUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        memCacheWidth: widget.memCacheWidth,
        memCacheHeight: widget.memCacheHeight,
        fadeInDuration: const Duration(milliseconds: 180),
        fadeOutDuration: const Duration(milliseconds: 180),
        placeholder: (context, url) => widget.placeholder ?? _buildShimmerPlaceholder(),
        errorWidget: (context, url, error) =>
            widget.errorWidget ?? _buildErrorWidget(context, validUrl),
      );
    }

    if (widget.borderRadius != null) {
      imageContent = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: imageContent,
      );
    }

    if (widget.onTap != null) {
      return GestureDetector(
        onTap: widget.onTap,
        child: imageContent,
      );
    }

    return imageContent;
  }

  Widget _buildShimmerPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
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
      width: widget.width,
      height: widget.height,
      color: const Color(0xFFF3F4F6),
      child: const Icon(
        Icons.image_outlined,
        color: Color(0xFF9CA3AF),
        size: 28,
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, String validUrl) {
    final palette = AppThemeService.instance.current;
    final isDark = palette.isDark;

    // For compact icons or small circles (e.g. height < 65)
    if (widget.height != null && widget.height! < 65) {
      return InkWell(
        onTap: () => _handleRetry(validUrl),
        child: Container(
          width: widget.width,
          height: widget.height,
          color: isDark ? const Color(0xFF242436) : const Color(0xFFF1F5F9),
          child: Center(
            child: Icon(
              Icons.refresh_rounded,
              color: palette.primary,
              size: 20,
            ),
          ),
        ),
      );
    }

    return Container(
      width: widget.width,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2D) : const Color(0xFFF8FAFC),
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.broken_image_rounded,
                color: palette.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              context.zevTr('imageLoadFailed'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (_isRetrying)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: palette.primary,
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: () => _handleRetry(validUrl),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  context.zevTr('tryAgain'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRetry(String validUrl) async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    try {
      await CachedNetworkImage.evictFromCache(validUrl);
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) {
      setState(() {
        _retryKey++;
        _isRetrying = false;
      });
    }
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
