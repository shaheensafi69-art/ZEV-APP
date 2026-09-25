import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SystemUiHelper {
  static int _androidSdkVersion = 0;

  /// Initialize the Android SDK version checks and activate full screen immersive mode immediately.
  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        _androidSdkVersion = androidInfo.version.sdkInt;
      }
    } catch (e) {
      _androidSdkVersion = 0;
      debugPrint('SystemUiHelper initialization error: $e');
    }

    // Hide phone navigation bar for immersive mode
    await enableFullScreen();
  }

  /// Enables true fullscreen immersive sticky mode across the app.
  static Future<void> enableFullScreen() async {
    if (kIsWeb) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
  }

  /// Appends appropriate system bar styles depending on device capabilities and views.
  static void setSystemStyle({required bool isReels}) {
    if (kIsWeb) return;
    try {
      // Keep navigation bar hidden in sticky immersive mode
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      // On Android 15+ (API 35+), setting statusBarColor, systemNavigationBarColor,
      // and systemNavigationBarDividerColor is deprecated by Android and flagged by Play Console.
      // Edge-to-edge handles transparency automatically.
      final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      if (isAndroid && _androidSdkVersion >= 35) {
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            systemNavigationBarIconBrightness: isReels ? Brightness.light : Brightness.dark,
            statusBarIconBrightness: isReels ? Brightness.light : Brightness.dark,
          ),
        );
      } else {
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarIconBrightness: isReels ? Brightness.light : Brightness.dark,
            systemNavigationBarIconBrightness: isReels ? Brightness.light : Brightness.dark,
            statusBarColor: isAndroid ? Colors.transparent : null,
            systemNavigationBarColor: isAndroid ? Colors.transparent : null,
          ),
        );
      }
    } catch (_) {}
  }
}

