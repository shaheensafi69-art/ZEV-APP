import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_compressor/easy_compressor.dart';
import 'package:easy_compressor/src/utils/file_utils.dart';

void main() {
  group('CompressionConfig', () {
    test('default values', () {
      const config = CompressionConfig();
      expect(config.quality, 70);
      expect(config.maxHeight, isNull);
      expect(config.maxWidth, isNull);
      expect(config.frameRate, isNull);
      expect(config.includeAudio, true);
      expect(config.audioBitrate, 128000);
      expect(config.videoCodec, VideoCodec.h264);
      expect(config.audioCodec, AudioCodec.aac);
      expect(config.outputPath, isNull);
    });

    test('whatsapp preset', () {
      const config = CompressionConfig.whatsapp();
      expect(config.quality, 65);
      expect(config.maxHeight, 720);
      expect(config.frameRate, 30);
      expect(config.audioBitrate, 96000);
    });

    test('social preset', () {
      const config = CompressionConfig.social();
      expect(config.quality, 70);
      expect(config.maxHeight, 1080);
      expect(config.frameRate, 30);
    });

    test('light preset', () {
      const config = CompressionConfig.light();
      expect(config.quality, 90);
      expect(config.maxHeight, isNull);
      expect(config.audioBitrate, 192000);
    });

    test('maximum preset', () {
      const config = CompressionConfig.maximum();
      expect(config.quality, 30);
      expect(config.maxHeight, 480);
      expect(config.frameRate, 24);
      expect(config.audioBitrate, 64000);
    });

    test('toMap serializes all fields', () {
      const config = CompressionConfig(
        quality: 50,
        maxHeight: 720,
        frameRate: 30,
        includeAudio: false,
      );
      final map = config.toMap();
      expect(map['quality'], 50);
      expect(map['maxHeight'], 720);
      expect(map['frameRate'], 30);
      expect(map['includeAudio'], false);
      expect(map['videoCodec'], 'h264');
      expect(map['audioCodec'], 'aac');
    });

    test('quality assertion bounds', () {
      expect(() => CompressionConfig(quality: -1), throwsAssertionError);
      expect(() => CompressionConfig(quality: 101), throwsAssertionError);
      expect(() => const CompressionConfig(quality: 0), returnsNormally);
      expect(() => const CompressionConfig(quality: 100), returnsNormally);
    });
  });

  group('CompressionResult', () {
    test('computed properties', () {
      const result = CompressionResult(
        outputPath: '/tmp/out.mp4',
        originalSize: 100000000, // 100 MB
        compressedSize: 35000000, // 35 MB
        duration: Duration(seconds: 60),
        compressionTime: Duration(seconds: 5),
        width: 1280,
        height: 720,
        status: CompressionStatus.success,
      );

      expect(result.compressionRatio, closeTo(0.35, 0.01));
      expect(result.spaceSavedPercent, closeTo(65.0, 0.1));
      expect(result.originalSizeFormatted, contains('MB'));
      expect(result.compressedSizeFormatted, contains('MB'));
      expect(result.spaceSavedFormatted, contains('saved'));
      expect(result.spaceSavedFormatted, contains('65'));
    });

    test('fromMap', () {
      final result = CompressionResult.fromMap({
        'outputPath': '/tmp/test.mp4',
        'originalSize': 50000000,
        'compressedSize': 15000000,
        'duration': 30000,
        'compressionTime': 2000,
        'width': 1920,
        'height': 1080,
        'status': 'success',
      });

      expect(result.outputPath, '/tmp/test.mp4');
      expect(result.originalSize, 50000000);
      expect(result.compressedSize, 15000000);
      expect(result.duration, const Duration(seconds: 30));
      expect(result.compressionTime, const Duration(seconds: 2));
      expect(result.width, 1920);
      expect(result.height, 1080);
      expect(result.status, CompressionStatus.success);
    });

    test('zero original size does not divide by zero', () {
      const result = CompressionResult(
        outputPath: '/tmp/out.mp4',
        originalSize: 0,
        compressedSize: 0,
        duration: Duration.zero,
        compressionTime: Duration.zero,
        width: 0,
        height: 0,
        status: CompressionStatus.success,
      );
      expect(result.compressionRatio, 1.0);
      expect(result.spaceSavedPercent, 0.0);
    });
  });

  group('MediaInfo', () {
    test('fromMap', () {
      final info = MediaInfo.fromMap({
        'path': '/test/video.mp4',
        'fileSize': 47453696,
        'duration': 120000,
        'width': 1920,
        'height': 1080,
        'frameRate': 29.97,
        'bitrate': 3000000,
        'videoCodec': 'h264',
        'audioCodec': 'aac',
        'audioBitrate': 128000,
        'rotation': 0,
        'hasAudio': true,
      });

      expect(info.path, '/test/video.mp4');
      expect(info.resolution, '1920 x 1080');
      expect(info.fileSizeFormatted, contains('MB'));
      expect(info.hasAudio, true);
      expect(info.duration, const Duration(minutes: 2));
    });
  });

  group('FileUtils', () {
    test('formatFileSize', () {
      expect(FileUtils.formatFileSize(0), '0 B');
      expect(FileUtils.formatFileSize(500), '500.0 B');
      expect(FileUtils.formatFileSize(1024), '1.0 KB');
      expect(FileUtils.formatFileSize(1048576), '1.0 MB');
      expect(FileUtils.formatFileSize(1073741824), '1.0 GB');
    });

    test('formatDuration', () {
      expect(FileUtils.formatDuration(const Duration(seconds: 45)), '0:45');
      expect(FileUtils.formatDuration(const Duration(minutes: 3, seconds: 12)),
          '3:12');
      expect(FileUtils.formatDuration(const Duration(minutes: 10, seconds: 5)),
          '10:05');
    });
  });

  group('Enums', () {
    test('VideoCodec values', () {
      expect(VideoCodec.values.length, 3);
      expect(VideoCodec.h264.name, 'h264');
      expect(VideoCodec.h265.name, 'h265');
      expect(VideoCodec.auto.name, 'auto');
    });

    test('AudioCodec values', () {
      expect(AudioCodec.values.length, 3);
      expect(AudioCodec.aac.name, 'aac');
    });

    test('CompressionStatus values', () {
      expect(CompressionStatus.values.length, 3);
      expect(CompressionStatus.success.name, 'success');
      expect(CompressionStatus.cancelled.name, 'cancelled');
      expect(CompressionStatus.failed.name, 'failed');
    });
  });

  group('EasyCompressor (mocked)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late MethodChannel channel;

    setUp(() {
      channel = const MethodChannel('easy_compressor');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        switch (call.method) {
          case 'getMediaInfo':
            return {
              'path': call.arguments['inputPath'],
              'fileSize': 10000000,
              'duration': 5000,
              'width': 1920,
              'height': 1080,
              'frameRate': 30.0,
              'bitrate': 5000000,
              'videoCodec': 'h264',
              'audioCodec': 'aac',
              'audioBitrate': 128000,
              'rotation': 0,
              'hasAudio': true,
            };
          case 'compressVideo':
            return {
              'outputPath': '/tmp/compressed.mp4',
              'originalSize': 10000000,
              'compressedSize': 3000000,
              'duration': 5000,
              'compressionTime': 1000,
              'width': 1280,
              'height': 720,
              'status': 'success',
            };
          case 'cancelCompression':
            return null;
          case 'clearCache':
            return null;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('getMediaInfo returns MediaInfo', () async {
      final compressor = EasyCompressor();
      final info = await compressor.getMediaInfo('/test/video.mp4');
      expect(info.width, 1920);
      expect(info.height, 1080);
      expect(info.hasAudio, true);
    });

    test('compressVideo returns CompressionResult', () async {
      final compressor = EasyCompressor();
      final result = await compressor.compressVideo('/test/video.mp4');
      expect(result.status, CompressionStatus.success);
      expect(result.compressedSize, 3000000);
      expect(result.width, 1280);
    });

    test('isCompressing state management', () async {
      final compressor = EasyCompressor();
      expect(compressor.isCompressing, false);
      // After compress completes it should be false again
      await compressor.compressVideo('/test/video.mp4');
      expect(compressor.isCompressing, false);
    });
  });
}
