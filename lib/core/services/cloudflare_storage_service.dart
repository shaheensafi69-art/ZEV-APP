import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'media_processing_service.dart';

/// Service to handle file uploads directly to Cloudflare R2 (S3 API compatible)
/// with seamless fallback to Supabase Storage if Cloudflare credentials are missing.
class CloudflareStorageService {
  static CloudflareStorageService? _instance;
  static CloudflareStorageService get instance =>
      _instance ??= CloudflareStorageService._();

  CloudflareStorageService._();

  String get _accountId => dotenv.env['CLOUDFLARE_ACCOUNT_ID'] ?? '';
  String get _accessKeyId => dotenv.env['CLOUDFLARE_R2_ACCESS_KEY_ID'] ?? '';
  String get _secretAccessKey =>
      dotenv.env['CLOUDFLARE_R2_SECRET_ACCESS_KEY'] ?? '';
  String get _defaultBucket => dotenv.env['CLOUDFLARE_R2_BUCKET_NAME'] ?? '';
  String get _publicDomain => dotenv.env['CLOUDFLARE_R2_PUBLIC_DOMAIN'] ?? '';

  bool get isConfigured {
    return _accountId.isNotEmpty &&
        _accessKeyId.isNotEmpty &&
        _secretAccessKey.isNotEmpty &&
        _secretAccessKey != 'your_secret_access_key' &&
        _accountId != 'your_account_id';
  }

  /// Main method to upload a file (from File or Uint8List bytes)
  /// Automatically compresses ALL images and videos before uploading to R2 / Supabase.
  /// Returns the public URL of the uploaded file.
  Future<String> upload({
    required String bucket,
    required String path,
    File? file,
    Uint8List? bytes,
    String? contentType,
    bool skipCompression = false,
  }) async {
    final initialBytes = bytes ?? (file != null ? await file.readAsBytes() : null);
    if (initialBytes == null) {
      throw Exception('No file data provided for upload.');
    }
    Uint8List fileBytes = initialBytes;

    final defaultBucket = _defaultBucket.isNotEmpty ? _defaultBucket : 'safiacademy-media';
    String targetBucket = defaultBucket;
    String sanitizedPath = path.startsWith('/') ? path.substring(1) : path;

    // If caller passed a subfolder name as 'bucket' (e.g. 'reels', 'story', 'feed', 'avatars', etc.),
    // automatically prepend it to path and set targetBucket to safiacademy-media!
    if (bucket != defaultBucket && bucket.isNotEmpty && !sanitizedPath.startsWith('$bucket/')) {
      sanitizedPath = '$bucket/$sanitizedPath';
    }

    final mimeType = contentType ?? _inferContentType(sanitizedPath);

    // ⚡ UNIVERSAL COMPRESSION FOR ALL IMAGES (Avatar, Cover, Feed, Story, Courses, etc.)
    final isImage = mimeType.startsWith('image/') ||
        sanitizedPath.endsWith('.jpg') ||
        sanitizedPath.endsWith('.jpeg') ||
        sanitizedPath.endsWith('.png') ||
        sanitizedPath.endsWith('.webp');

    if (!skipCompression && isImage && fileBytes.isNotEmpty) {
      try {
        final originalKb = fileBytes.length / 1024;
        fileBytes = await MediaProcessingService.instance.compressImageBytes(fileBytes);
        final newKb = fileBytes.length / 1024;
        debugPrint(
          '[CloudflareStorageService] 🖼️ Auto-compressed image: ${originalKb.toStringAsFixed(1)} KB -> ${newKb.toStringAsFixed(1)} KB',
        );
      } catch (e) {
        debugPrint('[CloudflareStorageService] Image compression bypass: $e');
      }
    }

    // ⚡ UNIVERSAL COMPRESSION FOR ALL VIDEOS (Reels, Story, Feed)
    final isVideo = mimeType.startsWith('video/') ||
        sanitizedPath.endsWith('.mp4') ||
        sanitizedPath.endsWith('.mov');

    final isAlreadyCompressed = file != null &&
        (file.path.contains('easy_compressor_cache') ||
            file.path.contains('compressed_') ||
            file.path.contains('_compressed'));

    if (!skipCompression && !isAlreadyCompressed && isVideo && file != null && file.existsSync()) {
      try {
        final originalMb = file.lengthSync() / (1024 * 1024);
        if (originalMb > 1.5) {
          debugPrint(
            '[CloudflareStorageService] 🎬 Auto-compressing video before upload: ${file.path} (${originalMb.toStringAsFixed(2)} MB)',
          );
          final compressedVideoFile =
              await MediaProcessingService.instance.compressVideo(file.path);
          if (compressedVideoFile.existsSync() &&
              compressedVideoFile.lengthSync() < file.lengthSync()) {
            fileBytes = await compressedVideoFile.readAsBytes();
            file = compressedVideoFile;
            debugPrint(
              '[CloudflareStorageService] ✅ Video auto-compressed: ${originalMb.toStringAsFixed(2)} MB -> ${(compressedVideoFile.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB',
            );
          }
        }
      } catch (e) {
        debugPrint('[CloudflareStorageService] Video compression bypass: $e');
      }
    }

    if (isConfigured) {
      try {
        debugPrint(
          '[CloudflareStorageService] Uploading to R2: $targetBucket/$sanitizedPath (${fileBytes.length} bytes)',
        );
        final r2Url = await _uploadToR2(
          bucket: targetBucket,
          path: sanitizedPath,
          bytes: fileBytes,
          contentType: mimeType,
        );
        debugPrint(
          '[CloudflareStorageService] Successfully uploaded to R2: $r2Url',
        );
        return r2Url;
      } catch (e) {
        debugPrint(
          '[CloudflareStorageService] R2 Upload failed: $e. Falling back to Supabase Storage.',
        );
      }
    } else {
      debugPrint(
        '[CloudflareStorageService] R2 not configured. Using Supabase Storage fallback.',
      );
    }

    // Supabase Storage Fallback
    return _uploadToSupabase(
      bucket: bucket,
      path: sanitizedPath,
      bytes: fileBytes,
      file: file,
      contentType: mimeType,
    );
  }

  /// Direct S3 SigV4 Upload to Cloudflare R2
  Future<String> _uploadToR2({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final targetBucket = bucket.isNotEmpty ? bucket : (_defaultBucket.isNotEmpty ? _defaultBucket : 'safiacademy-media');
    final host = '$_accountId.r2.cloudflarestorage.com';
    final requestPath = '/$targetBucket/$path';
    final uri = Uri.parse('https://$host$requestPath');

    final now = DateTime.now().toUtc();
    final isoDate = _formatIsoDate(now);
    final dateStamp = _formatDateStamp(now);
    const region = 'auto';
    const service = 's3';

    final payloadHash = sha256.convert(bytes).toString();

    // AWS SigV4 Auth String Calculation
    final signedHeaders = 'content-type;host;x-amz-content-sha256;x-amz-date';
    final canonicalHeaders =
        'content-type:$contentType\nhost:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$isoDate\n';

    final canonicalRequest = [
      'PUT',
      requestPath,
      '', // query string
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      isoDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _getSignatureKey(
      _secretAccessKey,
      dateStamp,
      region,
      service,
    );
    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    final authorization =
        'AWS4-HMAC-SHA256 Credential=$_accessKeyId/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';

    final requestHeaders = {
      'Host': host,
      'x-amz-date': isoDate,
      'x-amz-content-sha256': payloadHash,
      'Content-Type': contentType,
      'Content-Length': bytes.length.toString(),
      'Authorization': authorization,
    };

    final client = http.Client();
    try {
      final response = await client
          .put(uri, headers: requestHeaders, body: bytes)
          .timeout(const Duration(minutes: 5));

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (_publicDomain.isNotEmpty) {
          final domain = _publicDomain.endsWith('/')
              ? _publicDomain.substring(0, _publicDomain.length - 1)
              : _publicDomain;
          return '$domain/$path';
        }
        return 'https://$host$requestPath';
      } else {
        throw Exception(
          'R2 Upload HTTP Error ${response.statusCode}: ${response.body}',
        );
      }
    } finally {
      client.close();
    }
  }

  /// Supabase Storage Fallback method
  Future<String> _uploadToSupabase({
    required String bucket,
    required String path,
    required Uint8List bytes,
    File? file,
    required String contentType,
  }) async {
    final supabase = Supabase.instance.client;
    final fileOptions = FileOptions(contentType: contentType, upsert: true);

    if (file != null && !kIsWeb) {
      await supabase.storage
          .from(bucket)
          .upload(path, file, fileOptions: fileOptions);
    } else {
      await supabase.storage
          .from(bucket)
          .uploadBinary(path, bytes, fileOptions: fileOptions);
    }

    return supabase.storage.from(bucket).getPublicUrl(path);
  }

  // HMAC SigV4 Helper Functions
  List<int> _getSignatureKey(
    String key,
    String dateStamp,
    String regionName,
    String serviceName,
  ) {
    final kDate = Hmac(
      sha256,
      utf8.encode('AWS4$key'),
    ).convert(utf8.encode(dateStamp)).bytes;
    final kRegion = Hmac(sha256, kDate).convert(utf8.encode(regionName)).bytes;
    final kService = Hmac(
      sha256,
      kRegion,
    ).convert(utf8.encode(serviceName)).bytes;
    final kSigning = Hmac(
      sha256,
      kService,
    ).convert(utf8.encode('aws4_request')).bytes;
    return kSigning;
  }

  String _formatIsoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    final ss = date.second.toString().padLeft(2, '0');
    return '$y$m${d}T$hh$mm${ss}Z';
  }

  String _formatDateStamp(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  String _formatContentType(String path) {
    return _inferContentType(path);
  }

  String _inferContentType(String path) {
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
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'm4a':
      case 'mp3':
        return 'audio/mpeg';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
