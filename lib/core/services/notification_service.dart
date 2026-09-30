import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint("Handling background notification: ${message.messageId}");
  } catch (e) {
    debugPrint("Error handling background message: $e");
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal() {
    supabase.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.signedOut) {
        _lastSavedUserId = null;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('fcm_last_saved_user_id');
        } catch (_) {}
      }
    });
  }

  final supabase = Supabase.instance.client;
  String? _lastSavedUserId;
  bool _isSavingToken = false;

  /// Initialize push notifications & Firebase
  Future<void> initPushNotifications() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      debugPrint(
        "FCM notifications are only supported on Android/iOS. Skipping Firebase initialization on macOS/desktop.",
      );
      return;
    }
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      final messaging = FirebaseMessaging.instance;

      // Request notification permissions from user
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint(
        "User notification permission status: ${settings.authorizationStatus}",
      );

      // Save token if user is signed in
      if (supabase.auth.currentUser != null) {
        await saveFCMTokenToDatabase();
      }

      // Listen to device token refresh events
      messaging.onTokenRefresh.listen((newToken) {
        _lastSavedUserId = null; // Reset to force updating the new token
        _updateTokenInSupabase(newToken);
      });

      // Foreground notification handler
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          'Foreground Message received: ${message.notification?.title}',
        );
      });
    } catch (e) {
      debugPrint("Push notification initialization error: $e");
    }
  }

  /// Store FCM token in profiles table (deduplicated)
  Future<void> saveFCMTokenToDatabase() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    // Prevent concurrent token save calls (Mutex)
    if (_isSavingToken) {
      debugPrint("FCM token registration already in-flight, skipping duplicate call.");
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) return;

    _isSavingToken = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString('fcm_last_saved_user_id');
      final savedToken = prefs.getString('fcm_last_saved_token');

      final messaging = FirebaseMessaging.instance;
      String? token = await messaging.getToken();

      if (token == null || token.isEmpty) {
        return;
      }

      // Skip query if token is unchanged
      if (savedUserId == user.id && savedToken == token && _lastSavedUserId == user.id) {
        debugPrint("FCM token already up to date for user ${user.id}. Skipping duplicate registration.");
        return;
      }

      await _updateTokenInSupabase(token);
      await prefs.setString('fcm_last_saved_user_id', user.id);
      await prefs.setString('fcm_last_saved_token', token);
      _lastSavedUserId = user.id;
    } catch (e) {
      debugPrint("Error saving FCM Token to Supabase: $e");
    } finally {
      _isSavingToken = false;
    }
  }

  Future<void> _updateTokenInSupabase(String token) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // 1. Update push_subscriptions (multi-device & multi-app safe)
      final deviceType = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
      final deviceName = kIsWeb ? 'Web Browser' : '${defaultTargetPlatform.name} Device';

      await supabase.from('push_subscriptions').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'app_name': 'zev',
        'device_type': deviceType,
        'device_name': deviceName,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'fcm_token');

      // 2. Also update profiles.fcm_token for backwards compatibility
      await supabase
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', user.id);

      _lastSavedUserId = user.id;
      debugPrint(
        "Successfully saved FCM token to push_subscriptions (ZEV) for user: ${user.id}",
      );
    } catch (e) {
      debugPrint("Error updating push_subscriptions in Supabase: $e");
    }
  }

  /// Helper to insert new notification in database tagged with app_source
  Future<void> sendNotificationToUser({
    required String targetUserId,
    required String title,
    required String message,
    required String
    notificationType, // 'like_comment', 'chat', 'class_reminder', 'admin_announcement', 'scheduled'
    String? linkUrl,
    String? senderId,
    String appSource = 'zev',
  }) async {
    try {
      await supabase.from("user_notifications").insert({
        'user_id': targetUserId,
        'sender_id': senderId,
        'title': title,
        'message': message,
        'notification_type': notificationType,
        'link_url': linkUrl,
        'is_read': false,
        'app_source': appSource,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint("Error creating notification record in Supabase: $e");
    }
  }
}
