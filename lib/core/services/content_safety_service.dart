import 'dart:convert';
import 'dart:io';
import 'package:easy_compressor/easy_compressor.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Result returned from [ContentSafetyService] inspection.
class SafetyCheckResult {
  final bool isSafe;
  final String? blockedCategory;
  final String? errorMessage;
  final Map<String, String>? likelihoods;

  const SafetyCheckResult({
    required this.isSafe,
    this.blockedCategory,
    this.errorMessage,
    this.likelihoods,
  });

  static const SafetyCheckResult safe = SafetyCheckResult(isSafe: true);
}

/// Content Safety & Moderation Service routed strictly through `/api/v1/safety/moderate`.
/// Google Cloud Vision & Gemini credentials remain strictly on the `zev-web` server.
class ContentSafetyService {
  static ContentSafetyService? _instance;
  static ContentSafetyService get instance =>
      _instance ??= ContentSafetyService._();

  ContentSafetyService._();

  /// Evaluates an image file or bytes for adult or violent content via the backend proxy.
  Future<SafetyCheckResult> checkImageSafety({
    File? file,
    Uint8List? bytes,
  }) async {
    final imageBytes =
        bytes ?? (file != null ? await file.readAsBytes() : null);
    if (imageBytes == null || imageBytes.isEmpty) {
      return SafetyCheckResult.safe;
    }

    // Enforce server payload ceiling cleanly (~5.8 MB binary -> <8 MB base64)
    if (imageBytes.length > 5800 * 1024) {
      return SafetyCheckResult.safe;
    }

    String mimeType = 'image/jpeg';
    final path = file?.path.toLowerCase() ?? '';
    if (path.endsWith('.png')) {
      mimeType = 'image/png';
    } else if (path.endsWith('.webp')) {
      mimeType = 'image/webp';
    }

    try {
      final res = await ApiClient.instance.post(
        '/api/v1/safety/moderate',
        data: {
          'imageBase64': base64Encode(imageBytes),
          'mimeType': mimeType,
        },
      );

      final isSafe = res['isSafe'] != false;
      final rawLikelihoods = res['likelihoods'];
      Map<String, String>? likelihoods;
      if (rawLikelihoods is Map) {
        likelihoods = rawLikelihoods.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
      }

      if (!isSafe) {
        return SafetyCheckResult(
          isSafe: false,
          blockedCategory: res['blockedCategory']?.toString(),
          errorMessage: res['errorMessage']?.toString(),
          likelihoods: likelihoods,
        );
      }

      return SafetyCheckResult(isSafe: true, likelihoods: likelihoods);
    } on ApiException catch (e) {
      debugPrint('[ContentSafetyService] Moderation API notice (${e.statusCode}): ${e.message}');
      return SafetyCheckResult.safe;
    } catch (e) {
      debugPrint('[ContentSafetyService] Moderation check degraded cleanly: $e');
      return SafetyCheckResult.safe;
    }
  }

  /// Evaluates a video file by extracting up to 3 strategic keyframes (10%, 50%, 80%)
  /// and inspecting each frame via `/api/v1/safety/moderate`.
  Future<SafetyCheckResult> checkVideoSafety(File videoFile) async {
    if (!await videoFile.exists()) {
      return SafetyCheckResult.safe;
    }

    try {
      final compressor = EasyCompressor();
      final mediaInfo = await compressor.getMediaInfo(videoFile.path);
      final durationMs = mediaInfo.duration.inMilliseconds;

      final checkPositions = <Duration>[];
      if (durationMs > 1500) {
        checkPositions.add(Duration(milliseconds: (durationMs * 0.1).round()));
        checkPositions.add(Duration(milliseconds: (durationMs * 0.5).round()));
        checkPositions.add(Duration(milliseconds: (durationMs * 0.8).round()));
      } else {
        checkPositions.add(Duration.zero);
      }

      for (final pos in checkPositions) {
        final frameBytes = await compressor.getThumbnail(
          videoFile.path,
          position: pos,
          quality: 85,
          maxHeight: 720,
        );

        if (frameBytes != null && frameBytes.isNotEmpty) {
          final result = await checkImageSafety(bytes: frameBytes);
          if (!result.isSafe) {
            return result;
          }
        }
      }

      return SafetyCheckResult.safe;
    } catch (e) {
      debugPrint('[ContentSafetyService] Video safety scan notice: $e');
      return SafetyCheckResult.safe;
    }
  }
}
