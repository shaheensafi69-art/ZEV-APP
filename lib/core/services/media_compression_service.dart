import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class CompressedImageResult {
  final Uint8List bytes;
  final int? width;
  final int? height;
  final String contentType;
  final String extension;
  final bool wasCompressed;

  const CompressedImageResult({
    required this.bytes,
    required this.contentType,
    required this.extension,
    required this.wasCompressed,
    this.width,
    this.height,
  });
}

/// Off-main-thread media compression & thumbnail generation utility.
/// Uses Dart Isolates via [Isolate.run] to decode, bake EXIF orientation,
/// downsample large photos, and produce compact JPEG payloads before upload.
class MediaCompressionService {
  MediaCompressionService._();
  static final MediaCompressionService instance = MediaCompressionService._();

  /// Compresses JPEG / PNG / WebP images in a background isolate.
  /// Returns original bytes untouched for GIF, HEIC, or if re-encoding does not save bytes.
  Future<CompressedImageResult> compressImageBytes(
    Uint8List rawBytes, {
    required String originalContentType,
    required String originalFileName,
    int maxDimension = 1440,
    int quality = 84,
  }) async {
    final lowerMime = originalContentType.trim().toLowerCase();
    final lowerExt = originalFileName.contains('.')
        ? originalFileName.split('.').last.toLowerCase()
        : 'jpg';

    // Preserve animated GIFs, HEIC/HEIF (handled natively on Apple/Edge), and non-raster files
    const compressibleMimes = {'image/jpeg', 'image/png', 'image/webp'};
    if (!compressibleMimes.contains(lowerMime) || rawBytes.isEmpty) {
      return CompressedImageResult(
        bytes: rawBytes,
        contentType: lowerMime,
        extension: lowerExt,
        wasCompressed: false,
      );
    }

    // Small JPEGs (< 120 KB) don't benefit enough from decode/re-encode
    if (lowerMime == 'image/jpeg' && rawBytes.lengthInBytes < 120 * 1024) {
      return CompressedImageResult(
        bytes: rawBytes,
        contentType: lowerMime,
        extension: lowerExt,
        wasCompressed: false,
      );
    }

    try {
      final result = await Isolate.run(() {
        final decoded = img.decodeImage(rawBytes);
        if (decoded == null) {
          return null;
        }

        // Preserve transparent PNGs cleanly when relatively small (< 1.5 MB)
        if (lowerMime == 'image/png' &&
            decoded.hasAlpha &&
            rawBytes.lengthInBytes < 1500 * 1024) {
          if (decoded.width <= maxDimension && decoded.height <= maxDimension) {
            return (
              bytes: rawBytes,
              width: decoded.width,
              height: decoded.height,
              mime: 'image/png',
              ext: 'png',
              compressed: false,
            );
          }
        }

        var processed = img.bakeOrientation(decoded);
        final w = processed.width;
        final h = processed.height;

        if (w > maxDimension || h > maxDimension) {
          if (w >= h) {
            processed = img.copyResize(
              processed,
              width: maxDimension,
              interpolation: img.Interpolation.linear,
            );
          } else {
            processed = img.copyResize(
              processed,
              height: maxDimension,
              interpolation: img.Interpolation.linear,
            );
          }
        }

        final jpgBytes = Uint8List.fromList(
          img.encodeJpg(processed, quality: quality),
        );

        // If resized down OR JPEG saves meaningful bandwidth (>10%), adopt it
        final resized =
            processed.width != decoded.width || processed.height != decoded.height;
        if (!resized && jpgBytes.lengthInBytes >= (rawBytes.lengthInBytes * 0.92)) {
          return (
            bytes: rawBytes,
            width: decoded.width,
            height: decoded.height,
            mime: lowerMime,
            ext: lowerExt,
            compressed: false,
          );
        }

        return (
          bytes: jpgBytes,
          width: processed.width,
          height: processed.height,
          mime: 'image/jpeg',
          ext: 'jpg',
          compressed: true,
        );
      });

      if (result == null) {
        return CompressedImageResult(
          bytes: rawBytes,
          contentType: lowerMime,
          extension: lowerExt,
          wasCompressed: false,
        );
      }

      return CompressedImageResult(
        bytes: result.bytes,
        width: result.width,
        height: result.height,
        contentType: result.mime,
        extension: result.ext,
        wasCompressed: result.compressed,
      );
    } catch (e) {
      debugPrint('[MediaCompressionService] Compression skipped: $e');
      return CompressedImageResult(
        bytes: rawBytes,
        contentType: lowerMime,
        extension: lowerExt,
        wasCompressed: false,
      );
    }
  }

  /// Generates a lightweight JPEG thumbnail in a background isolate.
  Future<Uint8List?> generateImageThumbnail(
    Uint8List rawBytes, {
    int maxDimension = 420,
    int quality = 76,
  }) async {
    if (rawBytes.isEmpty) return null;
    try {
      return await Isolate.run(() {
        final decoded = img.decodeImage(rawBytes);
        if (decoded == null) return null;
        var processed = img.bakeOrientation(decoded);
        if (processed.width > maxDimension || processed.height > maxDimension) {
          processed = processed.width >= processed.height
              ? img.copyResize(
                  processed,
                  width: maxDimension,
                  interpolation: img.Interpolation.linear,
                )
              : img.copyResize(
                  processed,
                  height: maxDimension,
                  interpolation: img.Interpolation.linear,
                );
        }
        return Uint8List.fromList(img.encodeJpg(processed, quality: quality));
      });
    } catch (e) {
      debugPrint('[MediaCompressionService] Thumbnail generation skipped: $e');
      return null;
    }
  }
}
