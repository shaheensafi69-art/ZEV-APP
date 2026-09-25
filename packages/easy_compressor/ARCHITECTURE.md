# Architecture

## Overview

easy_compressor is a Flutter plugin that uses native platform APIs for video compression. It follows the standard Flutter plugin architecture with platform channels.

## Layer Diagram

```
+-------------------------------------------------------------+
|                    DART LAYER (lib/)                         |
|                                                             |
|   EasyCompressor                                            |
|   +-- compressVideo(path, config, onProgress)               |
|   +-- getMediaInfo(path)                                    |
|   +-- getThumbnail(path, position)                          |
|   +-- cancelCompression()                                   |
|   +-- clearCache()                                          |
|                         |                                   |
|              +----------+----------+                        |
|              |  PlatformInterface  |                        |
|              |  (MethodChannel)    |                        |
|              +----------+----------+                        |
+---------------------+---+-----------------------------------+
                      |   |
  MethodChannel: "easy_compressor"
  EventChannel:  "easy_compressor/progress"
                      |
          +-----------+-----------+-----------+
          |           |           |           |
    +-----+-----+ +--+-------+ +-+--------+ +-----+-----+
    |  ANDROID   | |   iOS    | |  macOS   | |  WINDOWS  |
    |            | |          | |          | |           |
    |  Media3    | |AVAsset-  | |AVAsset-  | |  Media    |
    | Transformer| | Writer   | | Writer   | | Foundation|
    |            | |          | |          | |           |
    |  Kotlin    | |  Swift   | |  Swift   | |   C++     |
    |  minSdk 24 | |  iOS 13+ | |macOS10.15| |  Win10+   |
    +------------+ +----------+ +----------+ +-----------+
```

## MethodChannel Protocol

**Channel name**: `easy_compressor`

### Methods

| Method              | Arguments                                                    | Returns                                                       |
|---------------------|--------------------------------------------------------------|---------------------------------------------------------------|
| `compressVideo`     | inputPath, quality, maxHeight, maxWidth, frameRate, includeAudio, audioBitrate, videoCodec, audioCodec, outputPath | outputPath, originalSize, compressedSize, duration, compressionTime, width, height, status |
| `getMediaInfo`      | inputPath                                                    | path, fileSize, duration, width, height, frameRate, bitrate, videoCodec, audioCodec, audioBitrate, rotation, hasAudio |
| `getThumbnail`      | inputPath, positionMs, quality, maxHeight                    | Uint8List (JPEG bytes)                                        |
| `cancelCompression` | none                                                         | void                                                          |
| `clearCache`        | none                                                         | void                                                          |

### EventChannel

**Channel name**: `easy_compressor/progress`

Emits `double` values from 0.0 to 1.0 representing compression progress.

## Quality Mapping

All platforms use the same bitrate calculation formula:

```
targetBitrate = originalBitrate * (0.05 + 0.95 * (quality / 100.0))
```

Resolution-based caps are applied to prevent over-encoding:

| Resolution | Max Bitrate |
|-----------|-------------|
| 480p      | 2.5 Mbps    |
| 720p      | 5.0 Mbps    |
| 1080p     | 8.0 Mbps    |
| 1440p     | 14.0 Mbps   |
| 4K        | 20.0 Mbps   |

The lower of the quality-derived bitrate and the resolution cap is used.

## Platform Implementations

### Android (Media3 Transformer)

Uses `Transformer` from AndroidX Media3 for hardware-accelerated transcoding. Resolution scaling via `ScaleAndRotateTransformation`. Progress polled via `Transformer.getProgress()`.

### iOS / macOS (AVFoundation)

Uses `AVAssetReader` + `AVAssetWriter` for sample-by-sample transcoding with fine-grained bitrate control via `AVVideoAverageBitRateKey`. Progress calculated from sample timestamps vs total duration.

### Windows (Media Foundation)

Uses `IMFSourceReader` + `IMFSinkWriter` for reading and writing samples. H.264 encoding via `MFVideoFormat_H264`. Progress calculated from sample timestamp vs total duration.
