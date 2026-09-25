import 'package:flutter/services.dart';

import '../compression_config.dart';
import 'video_compressor_platform_interface.dart';

/// Method channel implementation of [VideoCompressorPlatform].
class MethodChannelVideoCompressor extends VideoCompressorPlatform {
  /// The method channel used to interact with the native platform.
  final MethodChannel _channel = const MethodChannel('easy_compressor');

  /// The event channel for receiving progress updates.
  final EventChannel _progressChannel =
      const EventChannel('easy_compressor/progress');

  Stream<double>? _progressStreamCache;

  @override
  Future<Map<String, dynamic>> compressVideo(
    String inputPath,
    CompressionConfig config,
  ) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'compressVideo',
      {
        'inputPath': inputPath,
        ...config.toMap(),
      },
    );
    if (result == null) {
      throw PlatformException(
        code: 'NULL_RESULT',
        message: 'Compression returned null',
      );
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> getMediaInfo(String inputPath) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getMediaInfo',
      {'inputPath': inputPath},
    );
    if (result == null) {
      throw PlatformException(
        code: 'NULL_RESULT',
        message: 'getMediaInfo returned null',
      );
    }
    return result;
  }

  @override
  Future<Uint8List?> getThumbnail(
    String inputPath, {
    int positionMs = 0,
    int quality = 80,
    int? maxHeight,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      'getThumbnail',
      {
        'inputPath': inputPath,
        'positionMs': positionMs,
        'quality': quality,
        'maxHeight': maxHeight,
      },
    );
    return result;
  }

  @override
  Future<void> cancelCompression() async {
    await _channel.invokeMethod<void>('cancelCompression');
  }

  @override
  Future<void> clearCache() async {
    await _channel.invokeMethod<void>('clearCache');
  }

  @override
  Stream<double> get progressStream {
    _progressStreamCache ??= _progressChannel
        .receiveBroadcastStream()
        .map((event) => (event as num).toDouble());
    return _progressStreamCache!;
  }
}
