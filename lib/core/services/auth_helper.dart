import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../main.dart';

/// Central auth helper for managing user sign-in, sign-out states,
/// and single authoritative FCM (zev_fmc) token registration.
class AuthHelper {
  AuthHelper._();

  static const String keyUserLoggedIn = 'user_is_logged_in';
  static const String keyUserExplicitlyLoggedOut = 'user_explicitly_logged_out';
  static const String keyCachedUserRole = 'cached_user_role';
  static const String keyLoggedInUserId = 'logged_in_user_id';

  /// Record successful user sign-in in SharedPreferences and register single FCM token.
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

      // Register single FCM token specifically for ZEV (zev_fmc) upon login
      unawaited(syncZevFcmToken(userId));
    } catch (e) {
      debugPrint("AuthHelper markUserLoggedIn notice: $e");
    }
  }

  /// Safely generate and synchronize the single ZEV FCM token for the user.
  /// Guarantees that only ONE active push subscription exists in `push_subscriptions`
  /// and updates `profiles.zev_fmc` (and `zev_fcm`, `fcm_token`) to prevent duplicate push notifications.
  static Future<void> syncZevFcmToken(String userId) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      debugPrint("ZEV FCM token generation skipped on non-mobile platform.");
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;

      // 1. Request notification permissions from device
      await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // 2. Fetch the device FCM token
      final vapidKey = dotenv.env['FIREBASE_VAPID_KEY'];
      final token = await messaging.getToken(
        vapidKey: kIsWeb ? vapidKey : null,
      );

      if (token == null || token.isEmpty) {
        debugPrint("ZEV FCM token is empty, skipping registration.");
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final lastSavedToken = prefs.getString('zev_fmc_token_$userId');
      if (lastSavedToken == token) {
        debugPrint("ZEV FCM token already up-to-date for user: $userId");
        return;
      }

      final supabase = Supabase.instance.client;

      // 3. Remove any previous duplicate subscriptions for this user in ZEV app
      // to guarantee only 1 push notification is ever dispatched per event.
      try {
        await supabase
            .from('push_subscriptions')
            .delete()
            .match({'user_id': userId, 'app_name': 'zev'});
      } catch (cleanErr) {
        debugPrint("Push subscription cleanup notice: $cleanErr");
      }

      final deviceType = defaultTargetPlatform.name.toLowerCase();
      final deviceName = '${defaultTargetPlatform.name} Device';

      // 4. Upsert single authoritative push subscription
      await supabase.from('push_subscriptions').upsert({
        'user_id': userId,
        'fcm_token': token,
        'app_name': 'zev',
        'device_type': deviceType,
        'device_name': deviceName,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'fcm_token');

      // 5. Update profiles table with zev_fmc (custom for ZEV app), zev_fcm, and fcm_token
      await supabase
          .from('profiles')
          .update({
            'zev_fmc': token,
            'zev_fcm': token,
            'fcm_token': token,
          })
          .eq('id', userId);

      // 6. Cache token locally to avoid repeated network calls
      await prefs.setString('zev_fmc_token_$userId', token);
      debugPrint("Single ZEV FCM token successfully registered for user $userId (saved in zev_fmc)");
    } catch (e) {
      debugPrint("Error registering ZEV FCM token in AuthHelper: $e");
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

  /// Reliable and instant account sign-out with token deactivation.
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
        await prefs.remove('zev_fmc_token_${user.id}');

        // Clean up push subscription & nullify zev_fmc in profiles
        try {
          await Supabase.instance.client
              .from('push_subscriptions')
              .delete()
              .match({'user_id': user.id, 'app_name': 'zev'});

          await Supabase.instance.client
              .from('profiles')
              .update({'zev_fmc': null, 'zev_fcm': null})
              .eq('id', user.id);
        } catch (_) {}
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

