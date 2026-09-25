import 'enums.dart';

/// Configuration for video compression.
///
/// The [quality] parameter controls the compression level from 0 (maximum
/// compression, smallest file) to 100 (minimum compression, highest quality).
///
/// ## Example
///
/// ```dart
/// // Custom quality
/// final config = CompressionConfig(quality: 60, maxHeight: 720);
///
/// // Use a preset
/// final whatsapp = CompressionConfig.whatsapp();
/// ```
class CompressionConfig {
  /// Quality from 0 (max compression, smallest size) to 100 (min compression, best quality).
  ///
  /// Default: 70 (good balance of quality and size).
  final int quality;

  /// Maximum output resolution height in pixels.
  ///
  /// Video will be scaled down if larger, preserving aspect ratio.
  /// `null` keeps the original resolution.
  final int? maxHeight;

  /// Maximum output resolution width in pixels.
  ///
  /// `null` means auto-calculated from [maxHeight] and aspect ratio.
  final int? maxWidth;

  /// Target frame rate in frames per second.
  ///
  /// `null` keeps the original frame rate.
  final int? frameRate;

  /// Whether to include audio in the output. Default: `true`.
  final bool includeAudio;

  /// Audio bitrate in bits per second. Default: 128000 (128 kbps).
  final int audioBitrate;

  /// Output video codec. Default: [VideoCodec.h264] (maximum compatibility).
  final VideoCodec videoCodec;

  /// Output audio codec. Default: [AudioCodec.aac].
  final AudioCodec audioCodec;

  /// Custom output file path.
  ///
  /// `null` means auto-generated in the system temp directory.
  final String? outputPath;

  /// Creates a compression configuration.
  ///
  /// [quality] must be between 0 and 100 inclusive.
  const CompressionConfig({
    this.quality = 70,
    this.maxHeight,
    this.maxWidth,
    this.frameRate,
    this.includeAudio = true,
    this.audioBitrate = 128000,
    this.videoCodec = VideoCodec.h264,
    this.audioCodec = AudioCodec.aac,
    this.outputPath,
  }) : assert(quality >= 0 && quality <= 100,
            'Quality must be between 0 and 100');

  /// WhatsApp-like compression: 720p, quality 65, 30fps.
  const CompressionConfig.whatsapp()
      : quality = 65,
        maxHeight = 720,
        maxWidth = null,
        frameRate = 30,
        includeAudio = true,
        audioBitrate = 96000,
        videoCodec = VideoCodec.h264,
        audioCodec = AudioCodec.aac,
        outputPath = null;

  /// Social media optimized: 1080p, quality 70, 30fps.
  const CompressionConfig.social()
      : quality = 70,
        maxHeight = 1080,
        maxWidth = null,
        frameRate = 30,
        includeAudio = true,
        audioBitrate = 128000,
        videoCodec = VideoCodec.h264,
        audioCodec = AudioCodec.aac,
        outputPath = null;

  /// Minimal compression: keep quality high.
  const CompressionConfig.light()
      : quality = 90,
        maxHeight = null,
        maxWidth = null,
        frameRate = null,
        includeAudio = true,
        audioBitrate = 192000,
        videoCodec = VideoCodec.h264,
        audioCodec = AudioCodec.aac,
        outputPath = null;

  /// Maximum compression: smallest possible file.
  const CompressionConfig.maximum()
      : quality = 30,
        maxHeight = 480,
        maxWidth = null,
        frameRate = 24,
        includeAudio = true,
        audioBitrate = 64000,
        videoCodec = VideoCodec.h264,
        audioCodec = AudioCodec.aac,
        outputPath = null;

  /// Serializes this config to a map for platform channel communication.
  Map<String, dynamic> toMap() => {
        'quality': quality,
        'maxHeight': maxHeight,
        'maxWidth': maxWidth,
        'frameRate': frameRate,
        'includeAudio': includeAudio,
        'audioBitrate': audioBitrate,
        'videoCodec': videoCodec.name,
        'audioCodec': audioCodec.name,
        'outputPath': outputPath,
      };

  @override
  String toString() =>
      'CompressionConfig(quality: $quality, maxHeight: $maxHeight, '
      'maxWidth: $maxWidth, frameRate: $frameRate, '
      'includeAudio: $includeAudio, videoCodec: ${videoCodec.name})';
}
