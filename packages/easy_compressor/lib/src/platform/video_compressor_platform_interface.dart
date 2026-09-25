import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../compression_config.dart';
import 'video_compressor_method_channel.dart';

/// The interface that platform-specific implementations must implement.
///
/// Platform implementations should extend this class rather than implement it.
abstract class VideoCompressorPlatform extends PlatformInterface {
  VideoCompressorPlatform() : super(token: _token);

  static final Object _token = Object();

  static VideoCompressorPlatform _instance = MethodChannelVideoCompressor();

  /// The current platform implementation.
  static VideoCompressorPlatform get instance => _instance;

  /// Set the platform implementation (for testing or custom implementations).
  static set instance(VideoCompressorPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Compress a video file with the given configuration.
  Future<Map<String, dynamic>> compressVideo(
    String inputPath,
    CompressionConfig config,
  );

  /// Get metadata for a video file.
  Future<Map<String, dynamic>> getMediaInfo(String inputPath);

  /// Get a thumbnail from a video file.
  Future<Uint8List?> getThumbnail(
    String inputPath, {
    int positionMs = 0,
    int quality = 80,
    int? maxHeight,
  });

  /// Cancel the current compression operation.
  Future<void> cancelCompression();

  /// Delete all temporary compressed files.
  Future<void> clearCache();

  /// Stream of compression progress values (0.0 to 1.0).
  Stream<double> get progressStream;
}
