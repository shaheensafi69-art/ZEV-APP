import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/screens/welcome_screen.dart';

/// Central auth helper for managing user sign-in and sign-out
class AuthHelper {
  AuthHelper._();

  static const String keyUserLoggedIn = 'user_is_logged_in';
  static const String keyUserExplicitlyLoggedOut = 'user_explicitly_logged_out';
  static const String keyCachedUserRole = 'cached_user_role';

  /// Record successful user sign-in
  static Future<void> markUserLoggedIn({
    required String userId,
    required String role,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyUserLoggedIn, true);
      await prefs.setBool(keyUserExplicitlyLoggedOut, false);
      await prefs.setString('cached_user_role_$userId', role);
      await prefs.setString(keyCachedUserRole, role);
      await prefs.setString('logged_in_user_id', userId);
    } catch (e) {
      debugPrint("AuthHelper markUserLoggedIn warning: $e");
    }
  }

  /// Reliable, instant and secure account sign-out
  static Future<void> logout(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyUserLoggedIn, false);
      await prefs.setBool(keyUserExplicitlyLoggedOut, true);
      await prefs.remove(keyCachedUserRole);

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await prefs.remove('cached_user_role_${user.id}');
        await prefs.remove('logged_in_user_id');
      }

      // 1. Instant local session cleanup
      try {
        await Supabase.instance.client.auth
            .signOut(scope: SignOutScope.local)
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("Local sign-out notice: $e");
      }

      // 2. Background server sign-out (best-effort)
      Supabase.instance.client.auth.signOut().catchError((err) {
        debugPrint("Remote sign-out background notice: $err");
        return null;
      });
    } catch (e) {
      debugPrint("AuthHelper logout error: $e");
    } finally {
      // 3. Clear navigation stack and redirect to welcome/login screen
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    }
  }
}
