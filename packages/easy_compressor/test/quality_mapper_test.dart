import 'package:flutter_test/flutter_test.dart';
import 'package:easy_compressor/src/utils/quality_mapper.dart';

void main() {
  group('QualityMapper.calculateTargetBitrate', () {
    test('quality 0 returns 5% of original bitrate', () {
      final result = QualityMapper.calculateTargetBitrate(
        originalBitrate: 10000000,
        quality: 0,
        outputHeight: 1080,
      );
      expect(result, 500000); // 10M * 0.05 = 500K
    });

    test('quality 100 returns 100% of original bitrate (if under cap)', () {
      final result = QualityMapper.calculateTargetBitrate(
        originalBitrate: 5000000,
        quality: 100,
        outputHeight: 1080,
      );
      expect(result, 5000000);
    });

    test('quality 50 returns ~52.5% of original bitrate', () {
      final result = QualityMapper.calculateTargetBitrate(
        originalBitrate: 10000000,
        quality: 50,
        outputHeight: 1080,
      );
      // 0.05 + 0.95 * 0.5 = 0.525 → 5,250,000
      expect(result, 5250000);
    });

    test('quality 100 is capped by resolution for high bitrate', () {
      final result = QualityMapper.calculateTargetBitrate(
        originalBitrate: 50000000, // 50 Mbps
        quality: 100,
        outputHeight: 720,
      );
      // 720p cap is 5,000,000
      expect(result, 5000000);
    });

    test('480p resolution cap is 2.5 Mbps', () {
      final result = QualityMapper.calculateTargetBitrate(
        originalBitrate: 20000000,
        quality: 100,
        outputHeight: 480,
      );
      expect(result, 2500000);
    });

    test('1080p resolution cap is 8 Mbps', () {
      final result = QualityMapper.calculateTargetBitrate(
        originalBitrate: 50000000,
        quality: 100,
        outputHeight: 1080,
      );
      expect(result, 8000000);
    });

    test('4K resolution cap is 20 Mbps', () {
      final result = QualityMapper.calculateTargetBitrate(
        originalBitrate: 100000000,
        quality: 100,
        outputHeight: 2160,
      );
      expect(result, 20000000);
    });

    test('very low original bitrate stays low', () {
      final result = QualityMapper.calculateTargetBitrate(
        originalBitrate: 100000, // 100 kbps
        quality: 50,
        outputHeight: 480,
      );
      // 100K * 0.525 = 52,500 (below the 2.5M cap)
      expect(result, 52500);
    });

    test('quality clamps below 0', () {
      final result = QualityMapper.calculateTargetBitrate(
        originalBitrate: 10000000,
        quality: -10,
        outputHeight: 1080,
      );
      expect(result, 500000); // same as quality 0
    });

    test('quality clamps above 100', () {
      final result = QualityMapper.calculateTargetBitrate(
        originalBitrate: 5000000,
        quality: 150,
        outputHeight: 1080,
      );
      expect(result, 5000000); // same as quality 100
    });
  });

  group('QualityMapper.calculateOutputDimensions', () {
    test('no constraints returns original', () {
      final dims = QualityMapper.calculateOutputDimensions(
        originalWidth: 1920,
        originalHeight: 1080,
      );
      expect(dims.width, 1920);
      expect(dims.height, 1080);
    });

    test('maxHeight scales down preserving aspect ratio', () {
      final dims = QualityMapper.calculateOutputDimensions(
        originalWidth: 1920,
        originalHeight: 1080,
        maxHeight: 720,
      );
      expect(dims.height, 720);
      expect(dims.width, 1280);
    });

    test('maxWidth scales down preserving aspect ratio', () {
      final dims = QualityMapper.calculateOutputDimensions(
        originalWidth: 1920,
        originalHeight: 1080,
        maxWidth: 960,
      );
      expect(dims.width, 960);
      expect(dims.height, 540);
    });

    test('dimensions are always even', () {
      final dims = QualityMapper.calculateOutputDimensions(
        originalWidth: 1921,
        originalHeight: 1081,
      );
      expect(dims.width % 2, 0);
      expect(dims.height % 2, 0);
    });

    test('no scale down when already smaller than max', () {
      final dims = QualityMapper.calculateOutputDimensions(
        originalWidth: 640,
        originalHeight: 480,
        maxHeight: 1080,
      );
      expect(dims.width, 640);
      expect(dims.height, 480);
    });
  });
}
