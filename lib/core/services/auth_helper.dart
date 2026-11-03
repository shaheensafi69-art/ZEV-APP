import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../main.dart';

/// Central auth helper for managing user sign-in and sign-out states.
class AuthHelper {
  AuthHelper._();

  static const String keyUserLoggedIn = 'user_is_logged_in';
  static const String keyUserExplicitlyLoggedOut = 'user_explicitly_logged_out';
  static const String keyCachedUserRole = 'cached_user_role';
  static const String keyLoggedInUserId = 'logged_in_user_id';

  /// Record successful user sign-in in SharedPreferences.
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
      await prefs.setString(keyLoggedInUserId, userId);
    } catch (e) {
      debugPrint("AuthHelper markUserLoggedIn notice: $e");
    }
  }

  /// Get the currently logged-in user id from local cache.
  static Future<String?> getLoggedInUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(keyLoggedInUserId) ??
          Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return Supabase.instance.client.auth.currentUser?.id;
    }
  }

  /// Check if a user is currently authenticated locally.
  static Future<bool> isUserLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final explicitLogout =
          prefs.getBool(keyUserExplicitlyLoggedOut) ?? false;
      if (explicitLogout) return false;
      final session = Supabase.instance.client.auth.currentSession;
      return session != null;
    } catch (_) {
      return false;
    }
  }

  /// Reliable and instant account sign-out.
  static Future<void> logout(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyUserLoggedIn, false);
      await prefs.setBool(keyUserExplicitlyLoggedOut, true);
      await prefs.remove(keyCachedUserRole);

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await prefs.remove('cached_user_role_${user.id}');
        await prefs.remove(keyLoggedInUserId);
      }

      // Fast local signout
      try {
        await Supabase.instance.client.auth
            .signOut(scope: SignOutScope.local)
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("Local sign-out notice: $e");
      }

      // Background remote signout
      Supabase.instance.client.auth.signOut().catchError((err) {
        debugPrint("Remote sign-out notice: $err");
        return null;
      });
    } catch (e) {
      debugPrint("AuthHelper logout error: $e");
    } finally {
      final navKey = appNavigatorKey.currentState;
      if (navKey != null) {
        navKey.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      } else if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    }
  }
}

