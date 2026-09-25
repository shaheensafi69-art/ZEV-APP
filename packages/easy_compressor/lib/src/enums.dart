/// Supported video codecs for compression output.
enum VideoCodec {
  /// H.264 / AVC — maximum compatibility across all devices and browsers.
  h264,

  /// H.265 / HEVC — better compression ratio but less device support.
  h265,

  /// Let the platform choose the best available codec.
  auto,
}

/// Supported audio codecs for compression output.
enum AudioCodec {
  /// AAC — standard audio codec, compatible with all platforms.
  aac,

  /// Opus — modern codec with better quality at low bitrates.
  opus,

  /// Let the platform choose the best available codec.
  auto,
}

/// Status of a compression operation.
enum CompressionStatus {
  /// Compression completed successfully.
  success,

  /// Compression was cancelled by the user.
  cancelled,

  /// Compression failed due to an error.
  failed,
}
