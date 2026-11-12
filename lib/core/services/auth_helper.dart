import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/welcome_screen.dart';
import '../../main.dart';
import '../config/app_config.dart';
import 'auth_session_manager.dart';
import 'badge_counter_service.dart';
import 'mfa_service.dart';
import 'notification_service.dart';

/// Central auth helper for managing user sign-in, device-scoped sign-out,
/// and authoritative FCM token registration (`profiles.fcm_token`, `user_devices`,
/// and `push_subscriptions`).
class AuthHelper {
  AuthHelper._();

  static const String keyUserLoggedIn = 'user_is_logged_in';
  static const String keyUserExplicitlyLoggedOut = 'user_explicitly_logged_out';
  static const String keyCachedUserRole = 'cached_user_role';
  static const String keyLoggedInUserId = 'logged_in_user_id';

  /// Record successful user sign-in in SharedPreferences and synchronize this device's FCM token.
  static Future<void> markUserLoggedIn({
    required String userId,
    String role = 'user',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyUserLoggedIn, true);
      await prefs.setBool(keyUserExplicitlyLoggedOut, false);
      await prefs.setString('cached_user_role_$userId', role);
      await prefs.setString(keyCachedUserRole, role);
      await prefs.setString(keyLoggedInUserId, userId);

      // Register current device FCM token upon login
      unawaited(syncZevFcmToken(userId));
    } catch (e) {
      debugPrint('AuthHelper markUserLoggedIn notice: $e');
    }
  }

  /// Synchronizes the current device's FCM token to `profiles.fcm_token`,
  /// `user_devices` (multi-device registry), and `push_subscriptions` without
  /// clobbering other active devices belonging to the same user.
  static Future<void> syncZevFcmToken(
    String userId, {
    String? explicitToken,
    bool forceSync = false,
  }) async {
    if (userId.isEmpty) return;

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      debugPrint('ZEV FCM token registration skipped on non-mobile platform.');
      return;
    }

    try {
      await NotificationService().ensureInitialized();

      String? token = explicitToken;
      if (token == null || token.isEmpty) {
        final messaging = FirebaseMessaging.instance;
        final vapidKey = AppConfig.firebaseVapidKey;
        token = await messaging.getToken(
          vapidKey: (kIsWeb && vapidKey.isNotEmpty) ? vapidKey : null,
        );
      }

      if (token == null || token.isEmpty) {
        debugPrint('ZEV FCM token is empty, skipping registration.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('zev_fmc_token_$userId'); // clean legacy pref key

      final cacheKey = 'zev_last_fcm_token_$userId';
      final lastSavedToken = prefs.getString(cacheKey);
      if (lastSavedToken == token && explicitToken == null && !forceSync) {
        // Touch device heartbeat timestamp cleanly without full duplicate writes
        try {
          final deviceId = await MfaService.instance.getOrCreateDeviceId();
          await Supabase.instance.client
              .from('user_devices')
              .update({
                'is_active': true,
                'app_version': '1.0.0+9',
                'last_seen_at': DateTime.now().toUtc().toIso8601String(),
              })
              .match({'user_id': userId, 'device_id': deviceId});
        } catch (_) {}
        return;
      }

      final supabase = Supabase.instance.client;
      final deviceId = await MfaService.instance.getOrCreateDeviceId();
      final deviceName = await MfaService.instance.getDeviceName();
      final platform = defaultTargetPlatform.name.toLowerCase();
      final nowIso = DateTime.now().toUtc().toIso8601String();

      // 1. Primary multi-device registration (`user_devices`)
      bool syncedAtLeastOne = false;
      try {
        await supabase.from('user_devices').upsert({
          'user_id': userId,
          'device_id': deviceId,
          'fcm_token': token,
          'platform': platform,
          'device_name': deviceName,
          'app_version': '1.0.0+9',
          'is_active': true,
          'last_seen_at': nowIso,
          'token_updated_at': nowIso,
          'updated_at': nowIso,
        }, onConflict: 'user_id,device_id');
        syncedAtLeastOne = true;
      } catch (devErr) {
        debugPrint('user_devices upsert notice: $devErr');
      }

      // 2. Single-device push_subscriptions upsert (never deletes other devices)
      try {
        await supabase.from('push_subscriptions').upsert({
          'user_id': userId,
          'fcm_token': token,
          'app_name': 'zev',
          'device_type': platform,
          'device_name': deviceName,
          'is_active': true,
          'updated_at': nowIso,
        }, onConflict: 'fcm_token');
        syncedAtLeastOne = true;
      } catch (subErr) {
        debugPrint('push_subscriptions upsert notice: $subErr');
      }

      // 3. Authoritative single column on profiles (fcm_token)
      try {
        await supabase
            .from('profiles')
            .update({'fcm_token': token, 'updated_at': nowIso})
            .eq('id', userId);
        syncedAtLeastOne = true;
      } catch (profErr) {
        debugPrint('profiles.fcm_token update notice: $profErr');
      }

      // 4. Cache locally only if registration succeeded
      if (syncedAtLeastOne) {
        await prefs.setString(cacheKey, token);
      }
      debugPrint(
        'ZEV FCM token registered cleanly for user $userId (device=$deviceId)',
      );
    } catch (e) {
      debugPrint('Error registering ZEV FCM token in AuthHelper: $e');
    }
  }

  /// Syncs current authenticated user's FCM token if logged in (throttled heartbeat).
  static Future<void> syncCurrentUserFcmTokenIfLoggedIn() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null && uid.isNotEmpty) {
      await syncZevFcmToken(uid);
    }
  }

  /// Get the currently logged-in user id from local cache or active session.
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

  /// Device-scoped sign-out that preserves other active devices' push tokens.
  static Future<void> logout(
    BuildContext context, {
    bool allDevices = false,
  }) async {
    try {
      BadgeCounterService.instance.stopListening();
      if (allDevices) {
        await AuthSessionManager.instance.signOutAllDevices();
      } else {
        await AuthSessionManager.instance.signOutCurrentDevice();
      }
    } catch (e) {
      debugPrint('AuthHelper logout error: $e');
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
