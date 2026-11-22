import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DataSaverMode {
  off,
  standard,
  extreme,
}

enum MediaAutoDownload {
  always,
  wifiOnly,
  never,
}

/// Centralized bandwidth and data optimization service for ZEV.
/// Tailored for cost-conscious users with expensive or slow mobile internet connections.
class ZevDataSaverService extends ChangeNotifier {
  static final ZevDataSaverService instance = ZevDataSaverService._internal();
  ZevDataSaverService._internal();

  static const String _keyMode = 'zev_data_saver_mode';
  static const String _keyAutoDownload = 'zev_media_auto_download';
  static const String _keyVideoQuality = 'zev_video_quality_pref';

  DataSaverMode _mode = DataSaverMode.off;
  MediaAutoDownload _autoDownload = MediaAutoDownload.wifiOnly;
  String _videoQuality = 'auto'; // 'low', 'medium', 'high', 'auto'
  bool _initialized = false;

  DataSaverMode get mode => _mode;
  bool get isDataSaverEnabled => _mode != DataSaverMode.off;
  bool get isExtremeSaver => _mode == DataSaverMode.extreme;
  MediaAutoDownload get autoDownload => _autoDownload;
  String get videoQuality => _videoQuality;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_keyMode) ?? 'off';
      _mode = DataSaverMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => DataSaverMode.off,
      );

      final dlStr = prefs.getString(_keyAutoDownload) ?? 'wifiOnly';
      _autoDownload = MediaAutoDownload.values.firstWhere(
        (d) => d.name == dlStr,
        orElse: () => MediaAutoDownload.wifiOnly,
      );

      _videoQuality = prefs.getString(_keyVideoQuality) ?? 'auto';
      _initialized = true;
      notifyListeners();

      // Background sync from remote database settings if user is signed in
      _syncFromRemote();
    } catch (e) {
      debugPrint('[ZevDataSaverService] init error: $e');
    }
  }

  Future<void> setMode(DataSaverMode newMode) async {
    _mode = newMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, newMode.name);
    _syncToRemote();
  }

  Future<void> toggleQuickSaver() async {
    if (_mode == DataSaverMode.off) {
      await setMode(DataSaverMode.standard);
    } else if (_mode == DataSaverMode.standard) {
      await setMode(DataSaverMode.extreme);
    } else {
      await setMode(DataSaverMode.off);
    }
  }

  Future<void> setAutoDownload(MediaAutoDownload setting) async {
    _autoDownload = setting;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAutoDownload, setting.name);
    _syncToRemote();
  }

  Future<void> setVideoQuality(String quality) async {
    _videoQuality = quality;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVideoQuality, quality);
    _syncToRemote();
  }

  /// Whether video player should autoplay in feed/reels
  bool shouldAutoplay({bool isWifi = false}) {
    if (_mode == DataSaverMode.extreme) return false;
    if (_mode == DataSaverMode.standard) {
      return isWifi;
    }
    return true;
  }

  /// Max image cache dimension to prevent large memory & decoding overhead
  int get maxImageCacheDimension {
    switch (_mode) {
      case DataSaverMode.extreme:
        return 480;
      case DataSaverMode.standard:
        return 720;
      case DataSaverMode.off:
        return 1440;
    }
  }

  /// Adjusts image CDN URLs (Cloudflare/Supabase) to request compressed variants
  String optimizeImageUrl(String originalUrl, {int? width}) {
    if (originalUrl.isEmpty) return originalUrl;
    if (_mode == DataSaverMode.off && width == null) return originalUrl;

    final targetW = width ?? maxImageCacheDimension;

    // Cloudflare Image Resizing CDN query
    if (originalUrl.contains('.r2.cloudflarestorage.com') ||
        originalUrl.contains('images.zevapp.com') ||
        originalUrl.contains('cloudflare')) {
      final sep = originalUrl.contains('?') ? '&' : '?';
      final q = _mode == DataSaverMode.extreme ? 60 : 75;
      return '$originalUrl${sep}width=$targetW&quality=$q&format=auto';
    }

    // Supabase Storage render endpoint transformation
    if (originalUrl.contains('/storage/v1/object/public/')) {
      final sep = originalUrl.contains('?') ? '&' : '?';
      final q = _mode == DataSaverMode.extreme ? 55 : 75;
      return '$originalUrl${sep}width=$targetW&quality=$q';
    }

    return originalUrl;
  }

  Future<void> _syncFromRemote() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final row = await client
          .from('user_settings')
          .select('data_saver_mode, auto_download_media, video_quality_preference')
          .eq('user_id', userId)
          .maybeSingle();

      if (row != null) {
        final remoteMode = row['data_saver_mode']?.toString();
        if (remoteMode != null && remoteMode != _mode.name) {
          _mode = DataSaverMode.values.firstWhere(
            (m) => m.name == remoteMode,
            orElse: () => _mode,
          );
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ZevDataSaverService] syncFromRemote notice: $e');
    }
  }

  Future<void> _syncToRemote() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await client.from('user_settings').upsert({
        'user_id': userId,
        'data_saver': isDataSaverEnabled,
        'data_saver_mode': _mode.name,
        'auto_download_media': _autoDownload.name,
        'video_quality_preference': _videoQuality,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[ZevDataSaverService] syncToRemote notice: $e');
    }
  }
}
