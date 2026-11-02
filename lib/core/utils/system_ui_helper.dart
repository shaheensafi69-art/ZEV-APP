import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Helper to ensure the app runs in full-screen mode with the phone's
/// navigation bar hidden (immersiveSticky mode).
class SystemUiHelper {
  SystemUiHelper._();

  /// Enforce full-screen immersive mode and hide system navigation bar.
  static Future<void> enableFullScreen() async {
    try {
      // Hide navigation bar and status bar with sticky immersive mode
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );

      // Make system bars fully transparent and edge-to-edge
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
