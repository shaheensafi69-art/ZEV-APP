import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
  String get _defaultBucket =>
      dotenv.env['CLOUDFLARE_R2_BUCKET_NAME'] ?? 'safiacademy-media';
  String get _publicDomain => dotenv.env['CLOUDFLARE_R2_PUBLIC_DOMAIN'] ?? '';

  bool get isConfigured {
    return _accountId.isNotEmpty &&
        _accessKeyId.isNotEmpty &&
        _secretAccessKey.isNotEmpty;
  }

  /// Upload a file or bytes to Cloudflare R2 or Supabase fallback.
  Future<String> upload({
    required String bucket,
    required String path,
    File? file,
    Uint8List? bytes,
    String? contentType,
  }) async {
    final initialBytes =
        bytes ?? (file != null ? await file.readAsBytes() : null);
    if (initialBytes == null) {
      throw Exception('No file data provided for upload.');
    }

    final targetBucket =
        _defaultBucket.isNotEmpty ? _defaultBucket : 'safiacademy-media';
    String sanitizedPath = path.startsWith('/') ? path.substring(1) : path;

    if (bucket != targetBucket &&
        bucket.isNotEmpty &&
        !sanitizedPath.startsWith('$bucket/')) {
      sanitizedPath = '$bucket/$sanitizedPath';
    }

    final mimeType = contentType ?? _inferContentType(sanitizedPath);

    if (isConfigured) {
      try {
        return await _uploadToR2(
          bucket: targetBucket,
          path: sanitizedPath,
          bytes: initialBytes,
          contentType: mimeType,
        );
      } catch (e) {
        debugPrint('[CloudflareStorageService] R2 Upload failed: $e, falling back to Supabase');
      }
    }

    return await _uploadToSupabase(
      bucket: bucket.isNotEmpty ? bucket : 'avatars',
      path: sanitizedPath,
      bytes: initialBytes,
      file: file,
      contentType: mimeType,
    );
  }

  Future<String> _uploadToR2({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final host = '$_accountId.r2.cloudflarestorage.com';
    final requestPath = '/$bucket/$path';
    final uri = Uri.parse('https://$host$requestPath');

    final now = DateTime.now().toUtc();
    final isoDate = _formatIsoDate(now);
    final dateStamp = _formatDateStamp(now);

    const region = 'auto';
    const service = 's3';

    final payloadHash = sha256.convert(bytes).toString();

    final canonicalHeaders =
        'content-length:${bytes.length}\ncontent-type:$contentType\nhost:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$isoDate\n';
    final signedHeaders =
        'content-length;content-type;host;x-amz-content-sha256;x-amz-date';

    final canonicalRequest = [
      'PUT',
      requestPath,
      '',
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
          .timeout(const Duration(minutes: 2));

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
      default:
        return 'application/octet-stream';
    }
  }
}

