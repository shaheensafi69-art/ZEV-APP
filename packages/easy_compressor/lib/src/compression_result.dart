import 'enums.dart';
import 'utils/file_utils.dart';

/// The result of a video compression operation.
///
/// Contains the output file path, size statistics, and compression metadata.
class CompressionResult {
  /// Path to the compressed output file.
  final String outputPath;

  /// Size of the original input file in bytes.
  final int originalSize;

  /// Size of the compressed output file in bytes.
  final int compressedSize;

  /// Duration of the video.
  final Duration duration;

  /// How long the compression took.
  final Duration compressionTime;

  /// Width of the output video in pixels.
  final int width;

  /// Height of the output video in pixels.
  final int height;

  /// Status of the compression operation.
  final CompressionStatus status;

  const CompressionResult({
    required this.outputPath,
    required this.originalSize,
    required this.compressedSize,
    required this.duration,
    required this.compressionTime,
    required this.width,
    required this.height,
    required this.status,
  });

  /// Compression ratio as a fraction (e.g., 0.35 means output is 35% of original).
  double get compressionRatio =>
      originalSize > 0 ? compressedSize / originalSize : 1.0;

  /// Percentage of space saved (e.g., 65.0 means 65% smaller).
  double get spaceSavedPercent => (1.0 - compressionRatio) * 100;

  /// Human-readable original file size (e.g., "45.2 MB").
  String get originalSizeFormatted => FileUtils.formatFileSize(originalSize);

  /// Human-readable compressed file size (e.g., "15.8 MB").
  String get compressedSizeFormatted =>
      FileUtils.formatFileSize(compressedSize);

  /// Human-readable space saved summary (e.g., "29.4 MB saved (65%)").
  String get spaceSavedFormatted {
    final saved = originalSize - compressedSize;
    final percent = spaceSavedPercent.toStringAsFixed(1);
    return '${FileUtils.formatFileSize(saved)} saved ($percent%)';
  }

  /// Creates a [CompressionResult] from a platform channel response map.
  factory CompressionResult.fromMap(Map<String, dynamic> map) {
    return CompressionResult(
      outputPath: map['outputPath'] as String,
      originalSize: map['originalSize'] as int,
      compressedSize: map['compressedSize'] as int,
      duration: Duration(milliseconds: map['duration'] as int),
      compressionTime: Duration(milliseconds: map['compressionTime'] as int),
      width: map['width'] as int,
      height: map['height'] as int,
      status: CompressionStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => CompressionStatus.failed,
      ),
    );
  }

  @override
  String toString() => 'CompressionResult(status: ${status.name}, '
      '$originalSizeFormatted → $compressedSizeFormatted, '
      'saved: ${spaceSavedPercent.toStringAsFixed(1)}%, '
      '${width}x$height)';
}
