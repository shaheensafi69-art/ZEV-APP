import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Top-level background message handler required by Firebase Messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint("ZEV FCM Background notification: ${message.messageId} - ${message.notification?.title}");
  } catch (e) {
    debugPrint("ZEV FCM background message error: $e");
  }
}

/// Production Notification Service for ZEV.
/// Handles Firebase App initialization, FCM push token generation,
/// device synchronization with Supabase push_subscriptions & profiles,
/// and in-app/foreground notification listening.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  NotificationService._internal() {
    _listenToAuthChanges();
  }

  final supabase = Supabase.instance.client;
  String? _lastSavedUserId;
  bool _isSavingToken = false;
  bool _isInitialized = false;

  void _listenToAuthChanges() {
    supabase.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.signedOut) {
        _lastSavedUserId = null;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('fcm_last_saved_user_id');
        } catch (_) {}
      } else if (data.event == AuthChangeEvent.signedIn) {
        // Automatically register FCM token for the newly signed in user
        unawaited(saveFCMTokenToDatabase());
      }
    });
  }

  /// Initialize Firebase & Push Notifications safely across platforms
  Future<void> initPushNotifications() async {
    if (_isInitialized) return;

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      debugPrint(
        "FCM push notifications are optimized for Android & iOS. Skipping Firebase init on desktop.",
      );
      return;
    }

    try {
      // 1. Initialize Firebase App
      await Firebase.initializeApp();

      // 2. Set background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;

      // 3. Request permissions from user
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint(
        "ZEV Notification authorization status: ${settings.authorizationStatus}",
      );

      // 4. Save device token if user is already authenticated
      if (supabase.auth.currentUser != null) {
        await saveFCMTokenToDatabase();
      }

      // 5. Listen to token refresh events
      messaging.onTokenRefresh.listen((newToken) {
        _lastSavedUserId = null; // force token refresh
        _updateTokenInSupabase(newToken);
      });

      // 6. Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          'ZEV Foreground notification: ${message.notification?.title} | ${message.notification?.body}',
        );
      });

      // 7. Notification tap handler (when app was opened from background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint(
          'ZEV Notification opened from background: ${message.data}',
        );
      });

      _isInitialized = true;
      debugPrint("ZEV Firebase Messaging initialized successfully.");
    } catch (e) {
      debugPrint("ZEV Push notification initialization notice: $e");
    }
  }

  /// Retrieve device FCM token and persist to Supabase
  Future<void> saveFCMTokenToDatabase() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    if (_isSavingToken) {
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
      final vapidKey = dotenv.env['FIREBASE_VAPID_KEY'];

      String? token;
      try {
        token = await messaging.getToken(
          vapidKey: kIsWeb ? vapidKey : null,
        );
      } catch (tokenErr) {
        debugPrint("Error fetching FCM token: $tokenErr");
      }

      if (token == null || token.isEmpty) {
        return;
      }

      // Skip redundant remote sync if already saved
      if (savedUserId == user.id && savedToken == token && _lastSavedUserId == user.id) {
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

  /// Upsert token into `push_subscriptions` and `profiles`
  Future<void> _updateTokenInSupabase(String token) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final deviceType = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
      final deviceName = kIsWeb ? 'Web Browser' : '${defaultTargetPlatform.name} Device';

      // 1. Upsert into push_subscriptions
      await supabase.from('push_subscriptions').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'app_name': 'zev',
        'device_type': deviceType,
        'device_name': deviceName,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'fcm_token');

      // 2. Also update profiles table for direct lookup
      await supabase
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', user.id);

      _lastSavedUserId = user.id;
      debugPrint("ZEV FCM token successfully registered for user: ${user.id}");
    } catch (e) {
      debugPrint("Notice: Updating push_subscriptions in Supabase: $e");
    }
  }

  /// Helper to record an in-app notification in Supabase
  Future<void> sendNotificationToUser({
    required String targetUserId,
    required String title,
    required String message,
    required String notificationType, // 'like', 'comment', 'repost', 'follow', 'chat'
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
      debugPrint("Notice: Creating notification record in Supabase: $e");
    }
  }
}
