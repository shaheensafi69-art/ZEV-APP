import 'dart:typed_data';

import '../compression_config.dart';
import '../exceptions.dart';
import 'video_compressor_platform_interface.dart';

/// Stub implementation for unsupported platforms.
///
/// All methods throw [PlatformNotSupportedException].
class StubVideoCompressor extends VideoCompressorPlatform {
  @override
  Future<Map<String, dynamic>> compressVideo(
    String inputPath,
    CompressionConfig config,
  ) {
    throw const PlatformNotSupportedException();
  }

  @override
  Future<Map<String, dynamic>> getMediaInfo(String inputPath) {
    throw const PlatformNotSupportedException();
  }

  @override
  Future<Uint8List?> getThumbnail(
    String inputPath, {
    int positionMs = 0,
    int quality = 80,
    int? maxHeight,
  }) {
    throw const PlatformNotSupportedException();
  }

  @override
  Future<void> cancelCompression() {
    throw const PlatformNotSupportedException();
  }

  @override
  Future<void> clearCache() {
    throw const PlatformNotSupportedException();
  }

  @override
  Stream<double> get progressStream =>
      Stream.error(const PlatformNotSupportedException());
}
