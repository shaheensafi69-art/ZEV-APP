# easy_compressor

[![pub package](https://img.shields.io/pub/v/easy_compressor.svg)](https://pub.dev/packages/easy_compressor)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A cross-platform Flutter plugin for high-quality video compression using **native platform APIs only** — no FFmpeg dependency. Compress videos with a simple 0-100 quality parameter on Android, iOS, macOS, and Windows.

## Features

- Simple 0-100 quality parameter for intuitive compression control
- Native APIs: Media3 Transformer (Android), AVFoundation (iOS/macOS), Media Foundation (Windows)
- No FFmpeg — smaller app size, no GPL licensing concerns
- Built-in presets: WhatsApp, Social Media, Light, Maximum compression
- Real-time progress tracking via Stream
- Compression cancellation support
- Video metadata extraction (resolution, bitrate, duration, codec, etc.)
- Thumbnail generation from any video position
- Automatic aspect ratio preservation
- Rotation-aware — handles phone video rotation metadata correctly
- Cache management for temp files

## Platform Support

| Feature            | Android | iOS  | macOS | Windows |
|-------------------|---------|------|-------|---------|
| Compress Video     | 24+     | 13+  | 10.15+| 10+     |
| Get Media Info     | 24+     | 13+  | 10.15+| 10+     |
| Get Thumbnail      | 24+     | 13+  | 10.15+| 10+     |
| H.264 Output       | 24+     | 13+  | 10.15+| 10+     |
| H.265 Output       | 24+     | 13+  | 10.15+| 10+     |
| Progress Tracking  | 24+     | 13+  | 10.15+| 10+     |
| Cancel Compression | 24+     | 13+  | 10.15+| 10+     |

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  easy_compressor: ^1.0.0
```

### Platform-Specific Setup

**Android**: Requires `minSdk 24`. No other setup needed — Media3 Transformer is included automatically.

**iOS**: Add to `Info.plist` if picking videos from the photo library:
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Select videos to compress</string>
```

**macOS**: Add file access entitlement to `DebugProfile.entitlements` and `Release.entitlements`:
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

**Windows**: No extra setup. Media Foundation is built into Windows 10+.

## Quick Start

```dart
import 'package:easy_compressor/easy_compressor.dart';

final compressor = EasyCompressor();
final result = await compressor.compressVideo(
  '/path/to/video.mp4',
  config: CompressionConfig(quality: 60),
  onProgress: (progress) => print('${(progress * 100).toInt()}%'),
);
print('Saved ${result.spaceSavedFormatted}');
```

## Usage

### Basic Compression

```dart
final compressor = EasyCompressor();
final result = await compressor.compressVideo('/path/to/video.mp4');
```

### Using Presets

```dart
// WhatsApp-like: 720p, quality 65, 30fps
await compressor.compressVideo(path, config: CompressionConfig.whatsapp());

// Social media: 1080p, quality 70, 30fps
await compressor.compressVideo(path, config: CompressionConfig.social());

// Light compression: keep original resolution, quality 90
await compressor.compressVideo(path, config: CompressionConfig.light());

// Maximum compression: 480p, quality 30, 24fps
await compressor.compressVideo(path, config: CompressionConfig.maximum());
```

### Progress Tracking

```dart
final result = await compressor.compressVideo(
  path,
  onProgress: (progress) {
    setState(() => _progress = progress); // 0.0 to 1.0
  },
);
```

### Getting Video Info

```dart
final info = await compressor.getMediaInfo('/path/to/video.mp4');
print('${info.resolution} - ${info.fileSizeFormatted}');
print('Duration: ${info.duration.inSeconds}s');
print('Bitrate: ${info.bitrate} bps');
```

### Getting Thumbnails

```dart
final bytes = await compressor.getThumbnail(
  '/path/to/video.mp4',
  position: Duration(seconds: 5),
  quality: 80,
  maxHeight: 200,
);
if (bytes != null) {
  Image.memory(bytes);
}
```

### Cancellation

```dart
// Start compression
compressor.compressVideo(path, config: config);

// Cancel later
await compressor.cancelCompression();
```

### Custom Output Path

```dart
final result = await compressor.compressVideo(
  inputPath,
  config: CompressionConfig(
    quality: 60,
    outputPath: '/custom/output/path.mp4',
  ),
);
```

## Quality Guide

| Quality | Typical Size Reduction | Visual Quality    | Use Case                  |
|---------|----------------------|-------------------|---------------------------|
| 0-20    | 85-95% smaller       | Noticeable loss   | Thumbnails, previews      |
| 20-40   | 70-85% smaller       | Some artifacts    | Quick sharing, low data   |
| 40-60   | 50-70% smaller       | Good              | Social media, messaging   |
| 60-80   | 30-50% smaller       | Very good         | General use (recommended) |
| 80-100  | 0-30% smaller        | Excellent         | Archival, professional    |

## Configuration Reference

| Parameter     | Type        | Default          | Description                                    |
|--------------|-------------|------------------|------------------------------------------------|
| quality      | int         | 70               | Compression quality (0 = max compression, 100 = best quality) |
| maxHeight    | int?        | null (original)  | Max output height in pixels                    |
| maxWidth     | int?        | null (auto)      | Max output width in pixels                     |
| frameRate    | int?        | null (original)  | Target frame rate                              |
| includeAudio | bool        | true             | Include audio track in output                  |
| audioBitrate | int         | 128000           | Audio bitrate in bps                           |
| videoCodec   | VideoCodec  | h264             | Output video codec (h264, h265, auto)          |
| audioCodec   | AudioCodec  | aac              | Output audio codec (aac, opus, auto)           |
| outputPath   | String?     | null (temp dir)  | Custom output file path                        |

## How It Works

Each platform uses its native video transcoding API:

- **Android**: Media3 Transformer API with hardware-accelerated encoding
- **iOS/macOS**: AVAssetWriter + AVAssetReader for sample-by-sample transcoding
- **Windows**: Media Foundation IMFSourceReader + IMFSinkWriter pipeline

The quality parameter (0-100) is mapped to a target bitrate using the formula:
`targetBitrate = originalBitrate * (0.05 + 0.95 * (quality / 100))`

Resolution-based caps prevent over-encoding (e.g., 720p capped at 5 Mbps).

## FAQ

**Q: Does this support web/Linux?**
A: Not yet. Web lacks native video encoding APIs, and Linux support is planned for a future release.

**Q: What video formats are supported as input?**
A: Any format supported by the platform's native decoder — MP4, MOV, AVI, MKV, WebM, and more.

**Q: What is the output format?**
A: MP4 container with H.264 video + AAC audio by default, ensuring maximum compatibility.

**Q: How does quality compare to FFmpeg?**
A: Native hardware encoders produce comparable quality at the same bitrates, often faster due to hardware acceleration.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License. See [LICENSE](LICENSE) for details.
