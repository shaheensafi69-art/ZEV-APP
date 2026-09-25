import 'dart:async';
import 'dart:typed_data';

import 'compression_config.dart';
import 'compression_result.dart';
import 'enums.dart';
import 'exceptions.dart';
import 'media_info.dart';
import 'platform/video_compressor_platform_interface.dart';

/// The main entry point for video compression.
///
/// Provides methods to compress videos, extract metadata, generate thumbnails,
/// and manage compression tasks across Android, iOS, macOS, and Windows.
///
/// ## Example
///
/// ```dart
/// final compressor = EasyCompressor();
///
/// // Compress with default settings (quality 70)
/// final result = await compressor.compressVideo('/path/to/video.mp4');
/// print('Saved ${result.spaceSavedFormatted}');
///
/// // Compress with custom config
/// final result2 = await compressor.compressVideo(
///   '/path/to/video.mp4',
///   config: CompressionConfig(quality: 50, maxHeight: 720),
///   onProgress: (p) => print('${(p * 100).toInt()}%'),
/// );
/// ```
class EasyCompressor {
  bool _isCompressing = false;
  StreamSubscription<double>? _progressSubscription;

  /// Whether a compression operation is currently in progress.
  bool get isCompressing => _isCompressing;

  /// Stream of progress updates (0.0 to 1.0) for the current compression.
  ///
  /// Listen to this stream to receive real-time progress updates.
  ///
  /// ```dart
  /// compressor.progressStream.listen((progress) {
  ///   print('Progress: ${(progress * 100).toInt()}%');
  /// });
  /// ```
  Stream<double> get progressStream =>
      VideoCompressorPlatform.instance.progressStream;

  /// Compresses a video file.
  ///
  /// [inputPath] — Absolute path to the input video file.
  ///
  /// [config] — Compression configuration. Defaults to quality 70.
  ///
  /// [onProgress] — Optional callback receiving progress from 0.0 to 1.0.
  ///
  /// Returns a [CompressionResult] with the output path and statistics.
  ///
  /// Throws [InputFileException] if the input file doesn't exist.
  /// Throws [CompressionFailedException] if compression fails.
  /// Throws [CompressionCancelledException] if cancelled.
  ///
  /// ```dart
  /// final result = await compressor.compressVideo(
  ///   '/path/to/video.mp4',
  ///   config: CompressionConfig.whatsapp(),
  ///   onProgress: (progress) => setState(() => _progress = progress),
  /// );
  /// ```
  Future<CompressionResult> compressVideo(
    String inputPath, {
    CompressionConfig config = const CompressionConfig(),
    void Function(double progress)? onProgress,
  }) async {
    if (_isCompressing) {
      throw const CompressorException(
        'A compression is already in progress. Cancel it first.',
        code: 'ALREADY_COMPRESSING',
      );
    }

    _isCompressing = true;

    if (onProgress != null) {
      _progressSubscription = progressStream.listen(
        onProgress,
        onError: (_) {},
      );
    }

    try {
      final resultMap = await VideoCompressorPlatform.instance.compressVideo(
        inputPath,
        config,
      );

      final result = CompressionResult.fromMap(resultMap);

      if (result.status == CompressionStatus.cancelled) {
        throw const CompressionCancelledException();
      }

      if (result.status == CompressionStatus.failed) {
        throw const CompressionFailedException('Compression failed');
      }

      return result;
    } catch (e) {
      if (e is CompressorException) rethrow;
      throw CompressionFailedException(e.toString());
    } finally {
      _isCompressing = false;
      await _progressSubscription?.cancel();
      _progressSubscription = null;
    }
  }

  /// Gets metadata for a video file.
  ///
  /// Returns a [MediaInfo] object with duration, resolution, bitrate, etc.
  ///
  /// ```dart
  /// final info = await compressor.getMediaInfo('/path/to/video.mp4');
  /// print('${info.resolution} - ${info.fileSizeFormatted}');
  /// ```
  Future<MediaInfo> getMediaInfo(String inputPath) async {
    try {
      final map =
          await VideoCompressorPlatform.instance.getMediaInfo(inputPath);
      return MediaInfo.fromMap(map);
    } catch (e) {
      if (e is CompressorException) rethrow;
      throw CompressorException('Failed to get media info: $e');
    }
  }

  /// Gets a thumbnail image (JPEG bytes) from a video.
  ///
  /// [position] — Position in the video (default: first frame).
  ///
  /// [quality] — JPEG quality 0-100.
  ///
  /// [maxHeight] — Maximum thumbnail height in pixels.
  ///
  /// Returns JPEG bytes, or `null` if thumbnail generation fails.
  ///
  /// ```dart
  /// final bytes = await compressor.getThumbnail(
  ///   '/path/to/video.mp4',
  ///   position: Duration(seconds: 5),
  ///   quality: 80,
  ///   maxHeight: 200,
  /// );
  /// if (bytes != null) {
  ///   Image.memory(bytes);
  /// }
  /// ```
  Future<Uint8List?> getThumbnail(
    String inputPath, {
    Duration position = Duration.zero,
    int quality = 80,
    int? maxHeight,
  }) async {
    try {
      return await VideoCompressorPlatform.instance.getThumbnail(
        inputPath,
        positionMs: position.inMilliseconds,
        quality: quality,
        maxHeight: maxHeight,
      );
    } catch (e) {
      if (e is CompressorException) rethrow;
      throw CompressorException('Failed to get thumbnail: $e');
    }
  }

  /// Cancels the current compression operation.
  ///
  /// Does nothing if no compression is in progress.
  Future<void> cancelCompression() async {
    if (!_isCompressing) return;
    try {
      await VideoCompressorPlatform.instance.cancelCompression();
    } catch (e) {
      if (e is CompressorException) rethrow;
      throw CompressorException('Failed to cancel compression: $e');
    }
  }

  /// Deletes all temporary compressed files created by this plugin.
  ///
  /// Call this to free disk space when compressed files are no longer needed.
  Future<void> clearCache() async {
    try {
      await VideoCompressorPlatform.instance.clearCache();
    } catch (e) {
      if (e is CompressorException) rethrow;
      throw CompressorException('Failed to clear cache: $e');
    }
  }
}
