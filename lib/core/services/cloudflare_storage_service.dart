import 'dart:io';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'media_compression_service.dart';

/// Client-side media upload service routed strictly through `/api/v1/media/presign`
/// and direct presigned PUT URLs into Cloudflare R2 under the isolated `zev/` prefix.
/// Features off-main-thread image optimization & exponential-backoff retries.
class CloudflareStorageService {
  static CloudflareStorageService? _instance;
  static CloudflareStorageService get instance =>
      _instance ??= CloudflareStorageService._();

  CloudflareStorageService._();

  static const Set<String> _allowedFolders = {
    'avatars',
    'covers',
    'feed',
    'posts',
    'reels',
    'stories',
    'direct_messages',
    'highlights',
    'ads',
    'temp',
  };

  /// Uploads a file or bytes to Cloudflare R2 via a short-lived server-presigned PUT URL.
  /// Automatically compresses large JPEG/PNG/WebP images in a background isolate unless
  /// [compressImage] is set to false, and retries transient failures up to [maxRetries].
  Future<String> upload({
    required String bucket,
    required String path,
    File? file,
    Uint8List? bytes,
    String? contentType,
    bool compressImage = true,
    int maxImageDimension = 1440,
    int imageQuality = 84,
    int maxRetries = 3,
    void Function(double progress)? onProgress,
  }) async {
    final initialBytes =
        bytes ?? (file != null ? await file.readAsBytes() : null);
    if (initialBytes == null || initialBytes.isEmpty) {
      throw Exception('No file data provided for upload.');
    }

    final folder = _normalizeFolder(bucket);
    final parsed = _extractFileAndSubPath(path);
    final rawFileName = parsed.fileName;
    var resolvedContentType =
        _normalizeContentType(contentType, rawFileName);
    var uploadBytes = initialBytes;
    var effectiveName = rawFileName;

    if (compressImage &&
        (resolvedContentType == 'image/jpeg' ||
            resolvedContentType == 'image/png' ||
            resolvedContentType == 'image/webp')) {
      final optimized = await MediaCompressionService.instance.compressImageBytes(
        initialBytes,
        originalContentType: resolvedContentType,
        originalFileName: rawFileName,
        maxDimension: maxImageDimension,
        quality: imageQuality,
      );
      uploadBytes = optimized.bytes;
      resolvedContentType = optimized.contentType;
      if (optimized.wasCompressed && !effectiveName.toLowerCase().endsWith('.${optimized.extension}')) {
        final stem = effectiveName.contains('.')
            ? effectiveName.substring(0, effectiveName.lastIndexOf('.'))
            : effectiveName;
        effectiveName = '$stem.${optimized.extension}';
      }
    }

    final fileName = _ensureMatchingExtension(effectiveName, resolvedContentType);
    final attempts = maxRetries.clamp(1, 5);
    Object? lastError;

    for (int attempt = 1; attempt <= attempts; attempt++) {
      try {
        onProgress?.call(0.02);
        final presignRes = await ApiClient.instance.post(
          '/api/v1/media/presign',
          data: {
            'folder': folder,
            'contentType': resolvedContentType,
            'fileSize': uploadBytes.length,
            'fileName': fileName,
            if (parsed.subPath.isNotEmpty) 'subPath': parsed.subPath,
          },
        );

        final uploadUrl = presignRes['uploadUrl']?.toString() ?? '';
        final publicUrl = presignRes['publicUrl']?.toString() ?? '';
        if (uploadUrl.isEmpty || publicUrl.isEmpty) {
          throw Exception('Server did not return a valid presigned upload URL.');
        }

        final rawHeaders = presignRes['headers'] ?? presignRes['requiredHeaders'];
        final headers = <String, String>{};
        if (rawHeaders is Map) {
          rawHeaders.forEach((key, value) {
            if (key != null && value != null) {
              headers[key.toString()] = value.toString();
            }
          });
        }
        headers.putIfAbsent('Content-Type', () => resolvedContentType);

        await ApiClient.instance.uploadToPresignedUrl(
          uploadUrl: uploadUrl,
          bytes: uploadBytes,
          headers: headers,
          onProgress: (p) => onProgress?.call((0.05 + p * 0.95).clamp(0.0, 1.0)),
        );

        onProgress?.call(1.0);
        return publicUrl;
      } catch (e) {
        lastError = e;
        if (e is ApiException &&
            e.statusCode != null &&
            e.statusCode! >= 400 &&
            e.statusCode! < 500 &&
            e.statusCode != 408 &&
            e.statusCode != 429) {
          rethrow;
        }
        if (attempt >= attempts) rethrow;
        final backoffMs = 500 * attempt * attempt;
        debugPrint(
          '[CloudflareStorageService] Upload attempt $attempt/$attempts failed ($e); retrying in ${backoffMs}ms',
        );
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
      }
    }

    throw lastError ?? Exception('Upload failed.');
  }

  /// Requests verified R2 object cleanup via `/api/v1/media/delete`.
  Future<bool> deleteByUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return true;
    try {
      final res = await ApiClient.instance.post(
        '/api/v1/media/delete',
        data: {'url': trimmed},
      );
      return res['ok'] == true;
    } catch (e) {
      debugPrint('[CloudflareStorageService] deleteByUrl notice: $e');
      return false;
    }
  }

  /// Requests batch deletion of owned R2 URLs via `/api/v1/media/delete`.
  Future<bool> deleteUrls(List<String> urls) async {
    final clean = urls.map((u) => u.trim()).where((u) => u.isNotEmpty).toList();
    if (clean.isEmpty) return true;
    try {
      final res = await ApiClient.instance.post(
        '/api/v1/media/delete',
        data: {'urls': clean},
      );
      return res['ok'] == true;
    } catch (e) {
      debugPrint('[CloudflareStorageService] deleteUrls notice: $e');
      return false;
    }
  }

  String _normalizeFolder(String bucket) {
    final lower = bucket.trim().toLowerCase();
    if (lower == 'chat' || lower == 'messages') return 'direct_messages';
    if (lower == 'posts') return 'feed';
    if (_allowedFolders.contains(lower)) return lower;
    return 'temp';
  }

  ({String fileName, String subPath}) _extractFileAndSubPath(String rawPath) {
    var clean = rawPath.replaceAll('\\', '/').trim();
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    final segments = clean.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return (fileName: 'upload.jpg', subPath: '');
    }

    final fileName = segments.last;
    final dirSegments = segments.take(segments.length - 1).where((s) {
      final l = s.toLowerCase();
      return l != 'zev' &&
          l != 'chat' &&
          l != 'direct_messages' &&
          !_allowedFolders.contains(l);
    }).toList();

    final subPath = dirSegments
        .join('_')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '');

    return (fileName: fileName, subPath: subPath);
  }

  String _normalizeContentType(String? explicit, String fileName) {
    if (explicit != null && explicit.trim().isNotEmpty) {
      final mime = explicit.trim().toLowerCase();
      if (mime == 'image/jpg') return 'image/jpeg';
      if (mime != 'application/octet-stream') return mime;
    }
    return _inferContentType(fileName);
  }

  String _ensureMatchingExtension(String fileName, String mimeType) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';

    const validMap = <String, List<String>>{
      'image/jpeg': ['jpg', 'jpeg'],
      'image/png': ['png'],
      'image/webp': ['webp'],
      'image/gif': ['gif'],
      'image/heic': ['heic', 'heif'],
      'image/heif': ['heif', 'heic'],
      'video/mp4': ['mp4', 'm4v'],
      'video/quicktime': ['mov'],
      'video/webm': ['webm'],
      'video/x-m4v': ['m4v', 'mp4'],
      'audio/m4a': ['m4a'],
      'audio/x-m4a': ['m4a'],
      'audio/mp4': ['m4a', 'mp4'],
      'audio/aac': ['aac'],
      'audio/mpeg': ['mp3'],
      'audio/wav': ['wav'],
      'audio/ogg': ['ogg'],
      'audio/webm': ['weba', 'webm'],
      'application/pdf': ['pdf'],
      'text/plain': ['txt'],
      'text/csv': ['csv'],
      'application/json': ['json'],
      'application/zip': ['zip'],
      'application/msword': ['doc'],
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document': ['docx'],
      'application/vnd.ms-excel': ['xls'],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': ['xlsx'],
      'application/vnd.ms-powerpoint': ['ppt'],
      'application/vnd.openxmlformats-officedocument.presentationml.presentation': ['pptx'],
    };

    final allowedExts = validMap[mimeType];
    if (allowedExts == null) return fileName;
    if (allowedExts.contains(ext)) return fileName;

    final stem = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final cleanStem = stem.isEmpty ? 'upload' : stem;
    return '$cleanStem.${allowedExts.first}';
  }

  /// Infers MIME type for supported images, video, audio, and chat documents.
  static String inferMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'm4a':
        return 'audio/m4a';
      case 'aac':
        return 'audio/aac';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'weba':
        return 'audio/webm';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'zip':
        return 'application/zip';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }

  String _inferContentType(String path) => inferMimeType(path);
}
