/// A cross-platform Flutter plugin for high-quality video compression
/// using native platform APIs.
///
/// Supports Android, iOS, macOS, and Windows with no FFmpeg dependency.
/// Compress videos with a simple 0-100 quality parameter.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:easy_compressor/easy_compressor.dart';
///
/// final compressor = EasyCompressor();
/// final result = await compressor.compressVideo(
///   '/path/to/video.mp4',
///   config: CompressionConfig(quality: 60),
///   onProgress: (progress) => print('${(progress * 100).toInt()}%'),
/// );
/// print('Saved ${result.spaceSavedFormatted}');
/// ```
library;

export 'src/compressor.dart';
export 'src/compression_config.dart';
export 'src/compression_result.dart';
export 'src/media_info.dart';
export 'src/enums.dart';
export 'src/exceptions.dart';
