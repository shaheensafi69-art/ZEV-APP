import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Helper to ensure the app runs in full edge-to-edge display mode
/// compliant with Android 15 & modern iOS design guidelines.
class SystemUiHelper {
  SystemUiHelper._();

  /// Enforce true edge-to-edge mode with transparent system bars.
  static Future<void> enableFullScreen() async {
    try {
      // Enable modern edge-to-edge display mode
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
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

