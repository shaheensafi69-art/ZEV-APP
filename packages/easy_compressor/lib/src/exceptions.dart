/// Base exception for all easy_compressor errors.
class CompressorException implements Exception {
  /// Human-readable error message.
  final String message;

  /// Optional platform-specific error code.
  final String? code;

  /// Optional underlying error details.
  final dynamic details;

  const CompressorException(this.message, {this.code, this.details});

  @override
  String toString() => 'CompressorException($code): $message';
}

/// Thrown when the input file is not found or cannot be read.
class InputFileException extends CompressorException {
  const InputFileException(super.message, {super.code, super.details});
}

/// Thrown when the input file format is not supported.
class UnsupportedFormatException extends CompressorException {
  const UnsupportedFormatException(super.message, {super.code, super.details});
}

/// Thrown when compression fails due to a platform-specific error.
class CompressionFailedException extends CompressorException {
  const CompressionFailedException(super.message, {super.code, super.details});
}

/// Thrown when the operation is cancelled.
class CompressionCancelledException extends CompressorException {
  const CompressionCancelledException(
      [super.message = 'Compression was cancelled']);
}

/// Thrown when the current platform is not supported.
class PlatformNotSupportedException extends CompressorException {
  const PlatformNotSupportedException(
      [super.message = 'This platform is not supported']);
}

/// Thrown when an output path cannot be created or written to.
class OutputPathException extends CompressorException {
  const OutputPathException(super.message, {super.code, super.details});
}
