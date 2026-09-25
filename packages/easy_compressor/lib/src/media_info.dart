import 'utils/file_utils.dart';

/// Metadata information about a video file.
///
/// Retrieved using [EasyCompressor.getMediaInfo].
class MediaInfo {
  /// Absolute path to the video file.
  final String path;

  /// File size in bytes.
  final int fileSize;

  /// Duration of the video.
  final Duration duration;

  /// Video width in pixels.
  final int width;

  /// Video height in pixels.
  final int height;

  /// Frame rate in frames per second.
  final double frameRate;

  /// Total video bitrate in bits per second.
  final int bitrate;

  /// Video codec name (e.g., "h264", "hevc").
  final String? videoCodec;

  /// Audio codec name (e.g., "aac", "mp3").
  final String? audioCodec;

  /// Audio bitrate in bits per second.
  final int? audioBitrate;

  /// Rotation in degrees (0, 90, 180, or 270).
  final int? rotation;

  /// Whether the video contains an audio track.
  final bool hasAudio;

  const MediaInfo({
    required this.path,
    required this.fileSize,
    required this.duration,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.bitrate,
    this.videoCodec,
    this.audioCodec,
    this.audioBitrate,
    this.rotation,
    required this.hasAudio,
  });

  /// Human-readable file size (e.g., "45.2 MB").
  String get fileSizeFormatted => FileUtils.formatFileSize(fileSize);

  /// Resolution string (e.g., "1920 x 1080").
  String get resolution => '$width x $height';

  /// Creates a [MediaInfo] from a platform channel response map.
  factory MediaInfo.fromMap(Map<String, dynamic> map) {
    return MediaInfo(
      path: map['path'] as String,
      fileSize: map['fileSize'] as int,
      duration: Duration(milliseconds: map['duration'] as int),
      width: map['width'] as int,
      height: map['height'] as int,
      frameRate: (map['frameRate'] as num).toDouble(),
      bitrate: map['bitrate'] as int,
      videoCodec: map['videoCodec'] as String?,
      audioCodec: map['audioCodec'] as String?,
      audioBitrate: map['audioBitrate'] as int?,
      rotation: map['rotation'] as int?,
      hasAudio: map['hasAudio'] as bool,
    );
  }

  @override
  String toString() => 'MediaInfo($resolution, $fileSizeFormatted, '
      '${duration.inSeconds}s, ${(bitrate / 1000).toStringAsFixed(0)} kbps)';
}
