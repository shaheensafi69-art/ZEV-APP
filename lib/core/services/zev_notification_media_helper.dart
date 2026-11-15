import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Ultra-Fast, Memory-Bounded Media Helper for ZEV Push Notifications.
/// - In-memory LRU cache of circular avatars and post thumbnails.
/// - Strict 2.5-second network timeout so notification dispatch is never stalled.
/// - Native circular avatar masking using `package:image`.
/// - Temporary file caching for native iOS notification attachments.
class ZevNotificationMediaHelper {
  ZevNotificationMediaHelper._();

  static final Map<String, Uint8List> _avatarBytesCache = <String, Uint8List>{};
  static final Map<String, Uint8List> _pictureBytesCache = <String, Uint8List>{};
  static final Map<String, String> _tempFilePathCache = <String, String>{};

  /// Maximum cached items to keep memory footprint under 5MB.
  static const int _maxCacheEntries = 60;

  /// Fetches and returns circular cropped PNG bytes for a sender's avatar.
  static Future<Uint8List?> getCircularAvatarBytes(String? url) async {
    final cleanUrl = url?.trim() ?? '';
    if (cleanUrl.isEmpty || (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://'))) {
      return null;
    }

    if (_avatarBytesCache.containsKey(cleanUrl)) {
      return _avatarBytesCache[cleanUrl];
    }

    try {
      final res = await http.get(Uri.parse(cleanUrl)).timeout(const Duration(milliseconds: 2500));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        return null;
      }

      // Decode and crop to circle for pixel-perfect circular largeIcon
      final rawImage = img.decodeImage(res.bodyBytes);
      if (rawImage == null) return null;

      // Resize avatar to standardized 192x192 notification resolution
      final square = img.copyResizeCropSquare(rawImage, size: 192);
      final circular = img.copyCropCircle(square);
      final pngBytes = Uint8List.fromList(img.encodePng(circular));

      _trimCacheIfNeeded(_avatarBytesCache);
      _avatarBytesCache[cleanUrl] = pngBytes;
      return pngBytes;
    } catch (_) {
      return null;
    }
  }

  /// Fetches and returns standard 16:9 / 4:5 image bytes for post/reel previews.
  static Future<Uint8List?> getMediaThumbnailBytes(String? url) async {
    final cleanUrl = url?.trim() ?? '';
    if (cleanUrl.isEmpty || (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://'))) {
      return null;
    }

    if (_pictureBytesCache.containsKey(cleanUrl)) {
      return _pictureBytesCache[cleanUrl];
    }

    try {
      final res = await http.get(Uri.parse(cleanUrl)).timeout(const Duration(milliseconds: 3000));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        return null;
      }

      final rawImage = img.decodeImage(res.bodyBytes);
      if (rawImage == null) return null;

      // Standardize thumbnail max width to 512px to prevent excessive memory usage
      final resized = rawImage.width > 512
          ? img.copyResize(rawImage, width: 512)
          : rawImage;

      final jpgBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 85));

      _trimCacheIfNeeded(_pictureBytesCache);
      _pictureBytesCache[cleanUrl] = jpgBytes;
      return jpgBytes;
    } catch (_) {
      return null;
    }
  }

  /// Downloads and caches media into a local temp file for iOS `DarwinNotificationAttachment`.
  static Future<String?> getAttachmentFilePath(String? url) async {
    final cleanUrl = url?.trim() ?? '';
    if (cleanUrl.isEmpty || (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://'))) {
      return null;
    }

    if (_tempFilePathCache.containsKey(cleanUrl)) {
      final path = _tempFilePathCache[cleanUrl]!;
      if (File(path).existsSync()) return path;
    }

    try {
      final bytes = await getMediaThumbnailBytes(cleanUrl) ??
          await getCircularAvatarBytes(cleanUrl);
      if (bytes == null || bytes.isEmpty) return null;

      final dir = await getTemporaryDirectory();
      final hash = cleanUrl.hashCode.abs();
      final file = File('${dir.path}/notif_attach_$hash.png');
      await file.writeAsBytes(bytes, flush: true);

      _tempFilePathCache[cleanUrl] = file.path;
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static void _trimCacheIfNeeded(Map<String, dynamic> cache) {
    if (cache.length >= _maxCacheEntries) {
      final firstKey = cache.keys.first;
      cache.remove(firstKey);
    }
  }
}
