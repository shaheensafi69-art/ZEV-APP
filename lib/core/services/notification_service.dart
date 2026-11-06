import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Top-level background message handler required by Firebase Messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint(
      "ZEV FCM Background notification: ${message.messageId} - ${message.notification?.title}",
    );
  } catch (e) {
    debugPrint("ZEV FCM background message error: $e");
  }
}

/// Production In-App & Push Notification Display Service for ZEV.
/// Handles Firebase App initialization, notification permission prompts,
/// foreground notification listening, and writing in-app notifications
/// to the `user_notifications` table in Supabase.
///
/// NOTE: FCM token registration and device synchronization is strictly handled
/// by [AuthHelper.syncZevFcmToken] upon user authentication to prevent duplicate
/// push registrations and duplicate message deliveries.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  NotificationService._internal();

  final supabase = Supabase.instance.client;
  bool _isInitialized = false;

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

      // 4. Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          'ZEV Foreground notification: ${message.notification?.title} | ${message.notification?.body}',
        );
      });

      // 5. Notification tap handler (when app was opened from background)
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
