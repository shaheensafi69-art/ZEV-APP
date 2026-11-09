import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Helper to ensure the app runs in true full-screen immersive mode
/// hiding the system navigation bar (3-button / gesture bar) on Android and iOS.
class SystemUiHelper {
  SystemUiHelper._();

  /// Enforce true full-screen mode by completely hiding the system navigation bar.
  /// Uses immersiveSticky so transient navigation overlays auto-hide immediately.
  static Future<void> enableFullScreen() async {
    try {
      // 1. Completely hide the bottom navigation bar while preserving the top status bar
      // or immersive sticky for complete edge-to-edge fullscreen
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );

      // 2. Make system bars fully transparent and disable contrast enforcement
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
      );
    } catch (e) {
      debugPrint("SystemUiHelper enableFullScreen warning: $e");
    }
  }
}
