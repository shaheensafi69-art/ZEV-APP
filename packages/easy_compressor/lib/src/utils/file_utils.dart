import 'dart:math';

/// Utility functions for file operations and formatting.
class FileUtils {
  FileUtils._();

  /// Formats a file size in bytes to a human-readable string.
  ///
  /// Examples:
  /// - `formatFileSize(1024)` → `"1.0 KB"`
  /// - `formatFileSize(1048576)` → `"1.0 MB"`
  /// - `formatFileSize(47453696)` → `"45.3 MB"`
  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor().clamp(0, suffixes.length - 1);
    final size = bytes / pow(1024, i);
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  /// Formats a [Duration] to a human-readable string.
  ///
  /// Examples:
  /// - `formatDuration(Duration(seconds: 45))` → `"0:45"`
  /// - `formatDuration(Duration(minutes: 3, seconds: 12))` → `"3:12"`
  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
