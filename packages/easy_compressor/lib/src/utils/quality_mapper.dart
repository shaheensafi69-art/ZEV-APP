import 'dart:math';

/// Maps user-friendly quality (0-100) to platform-specific encoding parameters.
///
/// The core formula:
///   `targetBitrate = originalBitrate * (0.05 + 0.95 * (quality / 100.0))`
///
/// This means:
/// - quality 0   → 5% of original bitrate (aggressive compression)
/// - quality 25  → ~29% of original
/// - quality 50  → ~52% of original
/// - quality 65  → ~67% of original (WhatsApp level)
/// - quality 70  → ~72% of original
/// - quality 100 → 100% of original (no bitrate reduction)
///
/// Resolution-based bitrate caps prevent wasteful over-encoding:
/// - 480p  → max 2,500 kbps
/// - 720p  → max 5,000 kbps
/// - 1080p → max 8,000 kbps
/// - 1440p → max 14,000 kbps
/// - 4K    → max 20,000 kbps
class QualityMapper {
  QualityMapper._();

  /// Calculates the target video bitrate based on quality and resolution.
  ///
  /// Returns the bitrate in bits per second.
  ///
  /// The lower of the quality-derived bitrate and the resolution cap is used.
  static int calculateTargetBitrate({
    required int originalBitrate,
    required int quality,
    required int outputHeight,
  }) {
    final clampedQuality = quality.clamp(0, 100);

    // Quality-derived bitrate
    final factor = 0.05 + 0.95 * (clampedQuality / 100.0);
    final qualityBitrate = (originalBitrate * factor).round();

    // Resolution-based cap
    final capBitrate = _getResolutionCap(outputHeight);

    return min(qualityBitrate, capBitrate);
  }

  /// Returns the maximum recommended bitrate for a given resolution height.
  static int _getResolutionCap(int height) {
    if (height <= 480) return 2500000;
    if (height <= 720) return 5000000;
    if (height <= 1080) return 8000000;
    if (height <= 1440) return 14000000;
    return 20000000; // 4K and above
  }

  /// Calculates the output dimensions preserving aspect ratio.
  ///
  /// Returns a `(width, height)` record with both values even
  /// (required by most video encoders).
  static ({int width, int height}) calculateOutputDimensions({
    required int originalWidth,
    required int originalHeight,
    int? maxWidth,
    int? maxHeight,
  }) {
    var targetWidth = originalWidth;
    var targetHeight = originalHeight;

    if (maxHeight != null && targetHeight > maxHeight) {
      final scale = maxHeight / targetHeight;
      targetHeight = maxHeight;
      targetWidth = (originalWidth * scale).round();
    }

    if (maxWidth != null && targetWidth > maxWidth) {
      final scale = maxWidth / targetWidth;
      targetWidth = maxWidth;
      targetHeight = (targetHeight * scale).round();
    }

    // Ensure dimensions are even (encoder requirement)
    targetWidth = (targetWidth ~/ 2) * 2;
    targetHeight = (targetHeight ~/ 2) * 2;

    // Ensure minimum dimensions
    targetWidth = max(targetWidth, 2);
    targetHeight = max(targetHeight, 2);

    return (width: targetWidth, height: targetHeight);
  }
}
