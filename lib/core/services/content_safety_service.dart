import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:easy_compressor/easy_compressor.dart';

/// Result returned from ContentSafetyService inspection.
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

/// Enterprise-grade Content Safety & Moderation Service.
/// Powered by Google Cloud Vision SafeSearch & Gemini AI fallback.
/// Blocks +18 adult content, sexual exploitation, extreme gore, and violence
/// before files are uploaded to Cloudflare R2 or Supabase.
class ContentSafetyService {
  static ContentSafetyService? _instance;
  static ContentSafetyService get instance =>
      _instance ??= ContentSafetyService._();

  ContentSafetyService._();

  String get _visionApiKey {
    final visionKey = dotenv.env['GOOGLE_VISION_API_KEY'];
    if (visionKey != null && visionKey.trim().isNotEmpty) {
      return visionKey.trim();
    }
    // Fallback to Google Gemini API Key from .env
    return dotenv.env['GOOGLE_GEMINI_API_KEY']?.trim() ?? '';
  }

  /// Evaluates an image file or bytes for +18 adult or violent content.
  Future<SafetyCheckResult> checkImageSafety({
    File? file,
    Uint8List? bytes,
  }) async {
    final imageBytes =
        bytes ?? (file != null ? await file.readAsBytes() : null);
    if (imageBytes == null || imageBytes.isEmpty) {
      return SafetyCheckResult.safe;
    }

    final apiKey = _visionApiKey;
    if (apiKey.isEmpty) {
      debugPrint("[ContentSafetyService] Notice: No Google Vision API key configured in .env");
      return SafetyCheckResult.safe;
    }

    try {
      // 1. Primary: Google Cloud Vision SafeSearch Detection
      final visionResult = await _callGoogleCloudVision(imageBytes, apiKey);
      if (visionResult != null) {
        return visionResult;
      }
    } catch (e) {
      debugPrint("[ContentSafetyService] Google Vision error: $e, trying AI fallback...");
    }

    // 2. Fallback: Google Gemini Vision Content Safety Check
    try {
      return await _callGeminiVisionSafetyCheck(imageBytes, apiKey);
    } catch (e) {
      debugPrint("[ContentSafetyService] Gemini safety fallback error: $e");
      // Allow upload if safety API is temporarily unreachable to avoid hard-blocking users
      return SafetyCheckResult.safe;
    }
  }

  /// Evaluates a video file by extracting multiple keyframes across its duration
  /// and running Google Cloud Vision SafeSearch on each frame.
  Future<SafetyCheckResult> checkVideoSafety(File videoFile) async {
    if (!await videoFile.exists()) {
      return SafetyCheckResult.safe;
    }

    try {
      final compressor = EasyCompressor();
      final mediaInfo = await compressor.getMediaInfo(videoFile.path);
      final durationMs = mediaInfo.duration.inMilliseconds;

      // Extract up to 3 strategic keyframes: 10%, 50%, and 80% through the video
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
      debugPrint("[ContentSafetyService] Video safety scan notice: $e");
      return SafetyCheckResult.safe;
    }
  }

  /// Calls the official Google Cloud Vision REST API (SAFE_SEARCH_DETECTION).
  /// https://cloud.google.com/vision/docs/detecting-safe-search
  Future<SafetyCheckResult?> _callGoogleCloudVision(
    Uint8List imageBytes,
    String apiKey,
  ) async {
    final url = Uri.parse(
      'https://vision.googleapis.com/v1/images:annotate?key=$apiKey',
    );

    final base64Image = base64Encode(imageBytes);
    final requestBody = jsonEncode({
      "requests": [
        {
          "image": {"content": base64Image},
          "features": [
            {"type": "SAFE_SEARCH_DETECTION"}
          ]
        }
      ]
    });

    final response = await http
        .post(
          url,
          headers: {"Content-Type": "application/json; charset=utf-8"},
          body: requestBody,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      debugPrint(
        "[ContentSafetyService] Google Vision API HTTP ${response.statusCode}: ${response.body}",
      );
      return null;
    }

    final data = jsonDecode(response.body);
    final responses = data['responses'] as List?;
    if (responses == null || responses.isEmpty) return null;

    final safeSearch = responses[0]['safeSearchAnnotation'] as Map<String, dynamic>?;
    if (safeSearch == null) return null;

    final adult = (safeSearch['adult'] ?? 'UNKNOWN').toString().toUpperCase();
    final racy = (safeSearch['racy'] ?? 'UNKNOWN').toString().toUpperCase();
    final violence = (safeSearch['violence'] ?? 'UNKNOWN').toString().toUpperCase();

    final likelihoods = {
      'adult': adult,
      'racy': racy,
      'violence': violence,
      'medical': (safeSearch['medical'] ?? 'UNKNOWN').toString(),
      'spoof': (safeSearch['spoof'] ?? 'UNKNOWN').toString(),
    };

    // Google Cloud Vision Likelihood levels:
    // UNKNOWN, VERY_UNLIKELY, UNLIKELY, POSSIBLE, LIKELY, VERY_LIKELY
    final isAdult = adult == 'LIKELY' || adult == 'VERY_LIKELY';
    final isRacy = racy == 'VERY_LIKELY';
    final isViolence = violence == 'VERY_LIKELY';

    if (isAdult || isRacy) {
      return SafetyCheckResult(
        isSafe: false,
        blockedCategory: 'adult',
        errorMessage:
            'این محتوا شامل موارد غیراخلاقی یا نامناسب (+۱۸) تشخیص داده شد و امکان انتشار آن در زِو وجود ندارد.',
        likelihoods: likelihoods,
      );
    }

    if (isViolence) {
      return SafetyCheckResult(
        isSafe: false,
        blockedCategory: 'violence',
        errorMessage:
            'این محتوا حاوی صحنه‌های خشونت شدید یا نامناسب تشخیص داده شد و امکان انتشار آن در زِو وجود ندارد.',
        likelihoods: likelihoods,
      );
    }

    return SafetyCheckResult(isSafe: true, likelihoods: likelihoods);
  }

  /// AI-powered safety check fallback using Gemini Vision API.
  Future<SafetyCheckResult> _callGeminiVisionSafetyCheck(
    Uint8List imageBytes,
    String apiKey,
  ) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey',
    );

    final base64Image = base64Encode(imageBytes);
    final prompt =
        'Evaluate this image for moderation. Does this image depict explicit adult content, pornography, sexual nudity, or extreme violence? Respond ONLY with a JSON object: {"is_adult": true/false, "is_violence": true/false}';

    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": prompt},
            {
              "inline_data": {
                "mime_type": "image/jpeg",
                "data": base64Image,
              }
            }
          ]
        }
      ],
      "generationConfig": {"temperature": 0.0, "response_mime_type": "application/json"}
    });

    final res = await http
        .post(
          url,
          headers: {"Content-Type": "application/json"},
          body: body,
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final text =
          json['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
      if (text.isNotEmpty) {
        final parsed = jsonDecode(text);
        if (parsed['is_adult'] == true) {
          return const SafetyCheckResult(
            isSafe: false,
            blockedCategory: 'adult',
            errorMessage:
                'این محتوا به دلیل شامل بودن موارد غیراخلاقی (+۱۸) مسدود شد و در زِو مجاز نیست.',
          );
        }
        if (parsed['is_violence'] == true) {
          return const SafetyCheckResult(
            isSafe: false,
            blockedCategory: 'violence',
            errorMessage:
                'این محتوا به دلیل شامل بودن خشونت شدید مسدود شد و در زِو مجاز نیست.',
          );
        }
      }
    }

    return SafetyCheckResult.safe;
  }
}

