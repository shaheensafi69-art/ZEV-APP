import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/calls/screens/call_screen.dart';
import '../../features/chat/screens/chat_conversation_screen.dart';
import '../../features/chat/screens/chat_list_screen.dart';
import '../../features/feed/screens/post_detail_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/user_follows_screen.dart';
import '../../features/reels/models/reel_item.dart';
import '../../features/reels/widgets/reel_player_item.dart';
import '../../features/stories/screens/story_viewer_screen.dart';
import '../../firebase_options.dart';
import '../../main.dart';
import '../theme/zev_theme.dart';
import '../widgets/zev_cached_image.dart';
import 'api_client.dart';
import 'auth_helper.dart';
import 'badge_counter_service.dart';
import 'deep_link_service.dart';
import 'zev_notification_channels.dart';
import 'zev_notification_media_helper.dart';
import 'zev_rtc_service.dart';

/// Top-level background action handler for interactive Android/iOS notification actions.
@pragma('vm:entry-point')
Future<void> _notificationActionHandler(NotificationResponse response) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {}
  await NotificationService.handleNotificationAction(response);
}

/// Top-level background message handler required by Firebase Messaging.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final rawType = (message.data['notification_type'] ??
            message.data['type'] ??
            'general')
        .toString();
    final isCall = rawType == 'voice_call' || rawType == 'video_call';

    // If message already has notification payload, Android OS displays it natively.
    // Suppress local notification to prevent duplicate notification cards in system tray,
    // except for urgent incoming calls requiring full-screen intent.
    if (message.notification == null || isCall) {
      await NotificationService.showBackgroundNotification(message);
    }
  } catch (e) {
    debugPrint('ZEV FCM background message error: $e');
  }
}

/// Production Notification & Deep-Link Dispatcher Service for ZEV.
/// - Initializes Firebase with [DefaultFirebaseOptions.currentPlatform]
/// - Configures Android `zev_notifications_channel` via `flutter_local_notifications`
/// - Listens to FCM `onTokenRefresh` and keeps `user_devices` / `profiles.fcm_token` synced
/// - Handles foreground banners, background taps, and race-free cold-start routing
/// - Writes in-app notifications (`user_notifications`) and triggers server `/api/v1/push/send`
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  NotificationService._internal();

  static const String androidChannelId = 'zev_notifications_channel';
  static const String androidChannelName = 'ZEV Activity & Messages';
  static const String androidChannelDescription =
      'Real-time messages, followers, likes, comments, and security alerts on ZEV.';

  static const String androidCallsChannelId = 'zev_calls_channel';
  static const String androidCallsChannelName = 'ZEV Calls & Rings';
  static const String androidCallsChannelDescription =
      'High-priority incoming voice and video call notifications.';

  final SupabaseClient supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  StreamSubscription<String>? _tokenRefreshSub;
  RealtimeChannel? _realtimeChannel;
  String? _realtimeUserId;
  final Map<String, DateTime> _recentAlertKeys = <String, DateTime>{};
  static bool isAppInForeground = true;
  static String? activeChatConversationId;
  static String? activeChatPeerId;

  static OverlayEntry? _activeBannerEntry;
  static Timer? _bannerDismissTimer;
  static Map<String, dynamic>? _pendingColdStartData;

  /// Ensures Firebase & NotificationService are initialized (singleflight).
  Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    await initPushNotifications();
  }

  /// Checks whether OS notification permission is currently granted.
  Future<bool> hasOsNotificationPermission() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return true;
    }
    try {
      await ensureInitialized();
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      final fcmAllowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin = _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final enabled = await androidPlugin?.areNotificationsEnabled();
        if (enabled != null) return enabled && fcmAllowed;
      }
      return fcmAllowed;
    } catch (_) {
      return false;
    }
  }

  /// Explicitly requests OS notification permission and syncs the FCM token.
  Future<bool> requestOsPermission() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return true;
    }
    try {
      await ensureInitialized();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin = _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await androidPlugin?.requestNotificationsPermission();
      }
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      final uid = supabase.auth.currentUser?.id;
      if (uid != null && uid.isNotEmpty) {
        unawaited(AuthHelper.syncZevFcmToken(uid, forceSync: true));
      }
      return granted;
    } catch (e) {
      debugPrint('ZEV requestOsPermission notice: $e');
      return false;
    }
  }

  /// Initialize Firebase, Local Notifications Channel & Push Listeners safely.
  Future<void> initPushNotifications() async {
    if (_isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      debugPrint(
        'FCM push notifications are optimized for Android & iOS. Skipping Firebase init on desktop.',
      );
      return;
    }

    final completer = Completer<void>();
    _initCompleter = completer;

    try {
      // 1. Initialize Firebase App deterministically
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // 2. Register background handler & local notification channels
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      await _initLocalNotifications();

      final messaging = FirebaseMessaging.instance;

      // 3. Configure iOS foreground options & request permissions (including Android 13+)
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin = _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await androidPlugin?.requestNotificationsPermission();
      }

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
        'ZEV Notification authorization status: ${settings.authorizationStatus}',
      );

      // 4. Listen for rotated FCM tokens and persist cleanly
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) {
        final uid = supabase.auth.currentUser?.id;
        if (uid != null && uid.isNotEmpty) {
          unawaited(
            AuthHelper.syncZevFcmToken(
              uid,
              explicitToken: newToken,
              forceSync: true,
            ),
          );
        }
      });

      // 5. Foreground messages -> refresh badge counts + show banner/tray alert
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        BadgeCounterService.instance.refreshCounts();

        final type = (message.data['notification_type'] ??
                message.data['type'] ??
                'general')
            .toString();
        final senderId = (message.data['sender_id'] ?? '').toString().trim();
        final convId = (message.data['conversation_id'] ?? '').toString().trim();
        if (_isViewingActiveChat(
          type: type,
          senderId: senderId,
          conversationId: convId,
        )) {
          return;
        }
        final link = (message.data['deep_link'] ??
                message.data['link_url'] ??
                message.data['link'] ??
                '')
            .toString();
        if ((type == 'voice_call' || type == 'video_call') &&
            isAppInForeground &&
            ZevRtcService.instance.activeCallId != null) {
          return;
        }
        final title = (message.notification?.title ??
                message.data['title'] ??
                'ZEV Activity')
            .toString();
        final body = (message.notification?.body ??
                message.data['body'] ??
                message.data['message'] ??
                'You have a new update on ZEV.')
            .toString();

        final dedupKey = (message.messageId?.isNotEmpty ?? false)
            ? 'fcm:${message.messageId}'
            : '$type|$link|$title|$body';
        if (_isDuplicateAlert(dedupKey)) return;

        final prefs = await SharedPreferences.getInstance();
        if (!_shouldAlertForType(prefs, type)) return;

        final vibrate = prefs.getBool('pref_notif_vibrate') ?? true;
        final overlayReady =
            isAppInForeground && appNavigatorKey.currentState?.overlay != null;

        if (overlayReady) {
          showInAppBanner(
            title: title,
            body: body,
            data: message.data,
            vibrate: vibrate,
          );
        } else {
          await _showTrayLocalNotification(
            title: title,
            body: body,
            data: message.data,
            vibrate: vibrate,
          );
        }
      });

      // 6. Background tap handler
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('ZEV Notification opened from background: ${message.data}');
        _dispatchOrQueueNotificationClick(message.data);
      });

      // 7. Cold-start tap handler (Firebase + Local Notifications) synced with DeepLinkService readiness
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          'ZEV Notification cold start initial message: ${initialMessage.data}',
        );
        _dispatchOrQueueNotificationClick(initialMessage.data);
      } else {
        final launchDetails =
            await _localNotifications.getNotificationAppLaunchDetails();
        final rawPayload = launchDetails?.notificationResponse?.payload;
        if ((launchDetails?.didNotificationLaunchApp ?? false) &&
            rawPayload != null &&
            rawPayload.isNotEmpty) {
          try {
            final parsed = jsonDecode(rawPayload);
            if (parsed is Map) {
              _dispatchOrQueueNotificationClick(
                Map<String, dynamic>.from(parsed),
              );
            }
          } catch (_) {}
        }
      }

      DeepLinkService.instance.addOnReadyCallback(() {
        flushPendingNotificationClick();
      });

      _isInitialized = true;
      debugPrint('ZEV Firebase Messaging & Local Notifications initialized.');

      final currentUid = supabase.auth.currentUser?.id;
      if (currentUid != null && currentUid.isNotEmpty) {
        unawaited(AuthHelper.syncZevFcmToken(currentUid));
        startRealtimeNotifications();
      }
    } catch (e) {
      debugPrint('ZEV Push notification initialization notice: $e');
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      _initCompleter = null;
    }
  }

  /// Subscribes to live `public.user_notifications` inserts so alerts created by
  /// DB triggers or admin actions also push immediately when connected.
  void startRealtimeNotifications() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      stopRealtimeNotifications();
      return;
    }
    if (_realtimeUserId == uid && _realtimeChannel != null) return;

    stopRealtimeNotifications();
    _realtimeUserId = uid;

    try {
      _realtimeChannel = supabase
          .channel('push_alerts:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'user_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: (payload) async {
              final row = payload.newRecord;
              if (row.isEmpty) return;

              final myId = supabase.auth.currentUser?.id;
              final senderId = row['sender_id']?.toString() ?? '';
              if (senderId.isNotEmpty && senderId == myId) return;

              final type = (row['notification_type'] ?? 'general').toString();
              final link = (row['link_url'] ?? '').toString();
              final title = (row['title'] ?? 'ZEV').toString().trim();
              final body = (row['message'] ?? '').toString().trim();
              if (title.isEmpty && body.isEmpty) return;

              // Check if user is actively viewing this chat conversation
              String linkedConvId = '';
              String linkedPeerId = senderId;
              if (link.contains('/chat/')) {
                final chatTarget = link.split('/chat/').last.split('?').first.trim();
                if (chatTarget.startsWith('conv:')) {
                  linkedConvId = chatTarget.replaceFirst('conv:', '');
                } else if (chatTarget.isNotEmpty) {
                  linkedPeerId = chatTarget;
                }
              }

              if (_isViewingActiveChat(
                type: type,
                senderId: linkedPeerId.isNotEmpty ? linkedPeerId : senderId,
                conversationId: linkedConvId,
              )) {
                // User is actively reading this conversation right now! Suppress in-app banner.
                return;
              }

              final notifId = row['id']?.toString() ?? '';
              final keyByContent = '$type|$link|$title|$body';
              if (_isDuplicateAlert(keyByContent) ||
                  (notifId.isNotEmpty && _isDuplicateAlert('row:$notifId'))) {
                return;
              }

              final prefs = await SharedPreferences.getInstance();
              if (!_shouldAlertForType(prefs, type)) return;

              final vibrate = prefs.getBool('pref_notif_vibrate') ?? true;
              final data = <String, dynamic>{
                'notification_id': notifId,
                'type': type,
                'notification_type': type,
                'sender_id': senderId,
                if (link.isNotEmpty) 'link_url': link,
                if (link.isNotEmpty) 'deep_link': link,
              };

              BadgeCounterService.instance.refreshCounts();

              final overlayReady = isAppInForeground &&
                  appNavigatorKey.currentState?.overlay != null;
              if (overlayReady) {
                showInAppBanner(
                  title: title.isNotEmpty ? title : 'ZEV Activity',
                  body: body.isNotEmpty ? body : 'You have a new notification.',
                  data: data,
                  vibrate: vibrate,
                );
              } else {
                await _showTrayLocalNotification(
                  title: title.isNotEmpty ? title : 'ZEV Activity',
                  body: body.isNotEmpty ? body : 'You have a new notification.',
                  data: data,
                  vibrate: vibrate,
                );
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'direct_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'receiver_id',
              value: uid,
            ),
            callback: (payload) async {
              final row = payload.newRecord;
              if (row.isEmpty) return;

              final myId = supabase.auth.currentUser?.id;
              final senderId = row['sender_id']?.toString().trim() ?? '';
              if (senderId.isEmpty || senderId == myId) return;

              final convId = row['conversation_id']?.toString().trim() ?? '';
              if (_isViewingActiveChat(
                type: 'message',
                senderId: senderId,
                conversationId: convId,
              )) {
                return;
              }

              final msgId = row['id']?.toString() ?? '';
              if (msgId.isNotEmpty && _isDuplicateAlert('dm:$msgId')) return;

              final prefs = await SharedPreferences.getInstance();
              if (!_shouldAlertForType(prefs, 'message')) return;

              final msgType = (row['message_type'] ?? 'text').toString();
              final rawText = (row['message_text'] ?? '').toString().trim();
              final fileName = (row['file_name'] ?? '').toString().trim();
              final body = switch (msgType) {
                'image' => 'Sent a photo',
                'video' => 'Sent a video',
                'audio' => 'Sent a voice message',
                'file' => fileName.isNotEmpty ? 'Sent $fileName' : 'Sent a file',
                'post_share' => 'Shared a post with you',
                'reel_share' => 'Shared a reel with you',
                _ => rawText.isNotEmpty ? rawText : 'Sent you a message',
              };

              String senderTitle = 'New Message';
              try {
                final prof = await supabase
                    .from('profiles')
                    .select('username')
                    .eq('id', senderId)
                    .maybeSingle();
                final uname = prof?['username']?.toString().trim() ?? '';
                if (uname.isNotEmpty) senderTitle = '@$uname';
              } catch (_) {}

              final deepLink = '/chat/$senderId';
              final dedupKey = 'message|$deepLink|$senderTitle|$body';
              if (_isDuplicateAlert(dedupKey)) return;

              final vibrate = prefs.getBool('pref_notif_vibrate') ?? true;
              final data = <String, dynamic>{
                'type': 'chat',
                'notification_type': 'message',
                'sender_id': senderId,
                if (convId.isNotEmpty) 'conversation_id': convId,
                'deep_link': deepLink,
                'link_url': deepLink,
              };

              BadgeCounterService.instance.refreshCounts();

              final overlayReady = isAppInForeground &&
                  appNavigatorKey.currentState?.overlay != null;
              if (overlayReady) {
                showInAppBanner(
                  title: senderTitle,
                  body: body,
                  data: data,
                  vibrate: vibrate,
                );
              } else {
                await _showTrayLocalNotification(
                  title: senderTitle,
                  body: body,
                  data: data,
                  vibrate: vibrate,
                );
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[NotificationService] Realtime push subscription notice: $e');
    }
  }

  bool _isViewingActiveChat({
    required String type,
    required String senderId,
    required String conversationId,
  }) {
    if (!isAppInForeground) return false;
    final t = type.toLowerCase();
    final isChat = t == 'message' ||
        t.contains('chat') ||
        t.contains('message') ||
        t == 'dm' ||
        t == 'direct_message' ||
        t == 'group_message';
    if (!isChat) return false;

    final curConv = activeChatConversationId?.trim().toLowerCase();
    final curPeer = activeChatPeerId?.trim().toLowerCase();
    final targetConv = conversationId.trim().toLowerCase();
    final targetSender = senderId.trim().toLowerCase();

    if (curConv != null && curConv.isNotEmpty && targetConv.isNotEmpty) {
      if (curConv == targetConv) return true;
    }
    if (curPeer != null && curPeer.isNotEmpty && targetSender.isNotEmpty) {
      if (curPeer == targetSender) return true;
    }
    return false;
  }

  void stopRealtimeNotifications() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _realtimeUserId = null;
  }

  bool _isDuplicateAlert(String key) {
    if (key.isEmpty) return false;
    final now = DateTime.now();
    _recentAlertKeys.removeWhere(
      (_, ts) => now.difference(ts) > const Duration(seconds: 20),
    );
    if (_recentAlertKeys.containsKey(key)) {
      return true;
    }
    _recentAlertKeys[key] = now;
    return false;
  }

  bool _shouldAlertForType(SharedPreferences prefs, String rawType) {
    final pushEnabled = prefs.getBool('pref_notif_push_enabled') ?? true;
    final pausedAll = prefs.getBool('pref_notif_pause_all') ?? false;
    if (!pushEnabled || pausedAll) return false;

    final t = rawType.toLowerCase();
    if (t == 'message' ||
        t.contains('chat') ||
        t == 'dm' ||
        t == 'direct_message' ||
        t == 'group_message' ||
        t == 'group_invitation') {
      return prefs.getBool('pref_notif_dms') ?? true;
    }
    if (t.contains('like')) {
      return prefs.getBool('pref_notif_likes') ?? true;
    }
    if (t.contains('comment') || t.contains('reply')) {
      return prefs.getBool('pref_notif_comments') ?? true;
    }
    if (t.contains('follow')) {
      return prefs.getBool('pref_notif_followers') ?? true;
    }
    if (t.contains('mention') || t.contains('tag')) {
      return prefs.getBool('pref_notif_mentions') ?? true;
    }
    if (t.contains('story')) {
      return prefs.getBool('pref_notif_stories') ?? true;
    }
    if (t.contains('live')) {
      return prefs.getBool('pref_notif_live') ?? true;
    }
    if (t.contains('marketing') || t.contains('promo')) {
      return prefs.getBool('pref_notif_marketing') ?? false;
    }
    return true;
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );

    final darwinCategories = <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        'zev_category_message',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.text(
            'action_reply',
            'Reply',
            buttonTitle: 'Send',
            placeholder: 'Type a message...',
          ),
          DarwinNotificationAction.plain(
            'action_mark_read',
            'Mark as Read',
          ),
        ],
        options: <DarwinNotificationCategoryOption>{
          DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
        },
      ),
      DarwinNotificationCategory(
        'zev_category_call',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain(
            'action_accept_call',
            'Accept',
            options: <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.foreground,
            },
          ),
          DarwinNotificationAction.plain(
            'action_decline_call',
            'Decline',
            options: <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.destructive,
            },
          ),
        ],
      ),
      DarwinNotificationCategory(
        'zev_category_friend_request',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain(
            'action_accept_friend',
            'Accept',
          ),
          DarwinNotificationAction.plain(
            'action_decline_friend',
            'Decline',
            options: <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.destructive,
            },
          ),
        ],
      ),
      DarwinNotificationCategory(
        'zev_category_comment',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.text(
            'action_reply_comment',
            'Reply',
            buttonTitle: 'Post',
            placeholder: 'Write a reply...',
          ),
          DarwinNotificationAction.plain(
            'action_open_post',
            'View',
            options: <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.foreground,
            },
          ),
        ],
      ),
      DarwinNotificationCategory(
        'zev_category_social',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain(
            'action_view',
            'View',
            options: <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.foreground,
            },
          ),
        ],
      ),
    ];

    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: darwinCategories,
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        handleNotificationAction(response);
      },
      onDidReceiveBackgroundNotificationResponse: _notificationActionHandler,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      for (final ch in ZevNotificationChannels.all) {
        await androidPlugin.createNotificationChannel(ch.toAndroidChannel());
      }
    }
  }

  /// Interactive Notification Action handler for both foreground & background clicks.
  static Future<void> handleNotificationAction(NotificationResponse response) async {
    final actionId = response.actionId;
    final rawPayload = response.payload;
    if (rawPayload == null || rawPayload.isEmpty) return;

    Map<String, dynamic> data = {};
    try {
      final parsed = jsonDecode(rawPayload);
      if (parsed is Map) {
        data = Map<String, dynamic>.from(parsed);
      }
    } catch (_) {
      return;
    }

    if (actionId == null || actionId.isEmpty) {
      _dispatchOrQueueNotificationClick(data);
      return;
    }

    final supabase = Supabase.instance.client;
    final currentUserId = supabase.auth.currentUser?.id;
    final senderId = (data['sender_id'] ?? data['peer_id'] ?? data['user_id'] ?? '').toString().trim();
    final convId = (data['conversation_id'] ?? '').toString().trim();

    switch (actionId) {
      case 'action_reply':
        final text = response.input?.trim() ?? '';
        if (text.isNotEmpty && currentUserId != null) {
          try {
            await supabase.from('direct_messages').insert({
              'sender_id': currentUserId,
              'receiver_id': senderId,
              if (convId.isNotEmpty) 'conversation_id': convId,
              'message_text': text,
              'message_type': 'text',
              'is_read': false,
            });
            await supabase
                .from('direct_messages')
                .update({'is_read': true})
                .eq('sender_id', senderId)
                .eq('receiver_id', currentUserId);
            BadgeCounterService.instance.refreshCounts();
          } catch (e) {
            debugPrint('[NotificationService] reply send notice: $e');
          }
        }
        break;

      case 'action_reply_comment':
        final text = response.input?.trim() ?? '';
        final postId = (data['post_id'] ?? data['target_id'] ?? '').toString().trim();
        if (text.isNotEmpty && currentUserId != null && postId.isNotEmpty) {
          try {
            await supabase.from('post_comments').insert({
              'post_id': postId,
              'user_id': currentUserId,
              'comment_text': text,
              if (data['comment_id'] != null) 'parent_comment_id': data['comment_id'],
            });
          } catch (e) {
            debugPrint('[NotificationService] comment reply notice: $e');
          }
        }
        break;

      case 'action_mark_read':
        if (currentUserId != null && senderId.isNotEmpty) {
          try {
            await supabase
                .from('direct_messages')
                .update({'is_read': true})
                .eq('sender_id', senderId)
                .eq('receiver_id', currentUserId);
            BadgeCounterService.instance.refreshCounts();
          } catch (_) {}
        }
        break;

      case 'action_accept_call':
        _dispatchOrQueueNotificationClick(data);
        break;

      case 'action_decline_call':
        final callId = (data['call_id'] ?? data['channel_name'] ?? '').toString().trim();
        if (callId.isNotEmpty) {
          unawaited(
            ZevRtcService.instance.respondCall(callId: callId, action: 'rejected'),
          );
        }
        break;

      case 'action_accept_friend':
        final reqId = (data['request_id'] ?? '').toString().trim();
        if (reqId.isNotEmpty) {
          try {
            await supabase
                .from('user_follows')
                .update({'status': 'accepted'})
                .eq('id', reqId);
          } catch (_) {}
        } else if (currentUserId != null && senderId.isNotEmpty) {
          try {
            await supabase
                .from('user_follows')
                .update({'status': 'accepted'})
                .eq('follower_id', senderId)
                .eq('following_id', currentUserId);
          } catch (_) {}
        }
        break;

      case 'action_decline_friend':
        final reqId = (data['request_id'] ?? '').toString().trim();
        if (reqId.isNotEmpty) {
          try {
            await supabase
                .from('user_follows')
                .delete()
                .eq('id', reqId);
          } catch (_) {}
        } else if (currentUserId != null && senderId.isNotEmpty) {
          try {
            await supabase
                .from('user_follows')
                .delete()
                .eq('follower_id', senderId)
                .eq('following_id', currentUserId);
          } catch (_) {}
        }
        break;

      case 'action_view_profile':
      case 'action_open_post':
      case 'action_view':
        _dispatchOrQueueNotificationClick(data);
        break;
    }
  }

  /// Displays an immediate high-priority notification when the app is killed or running in background.
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    try {
      final local = FlutterLocalNotificationsPlugin();
      const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
      await local.initialize(const InitializationSettings(android: androidSettings));

      final data = Map<String, dynamic>.from(message.data);
      final title = (message.notification?.title ?? data['title'] ?? 'ZEV').toString();
      final body = (message.notification?.body ?? data['body'] ?? data['message'] ?? 'New notification on ZEV').toString();

      await _renderNativeNotification(
        localPlugin: local,
        title: title,
        body: body,
        data: data,
        vibrate: true,
      );
    } catch (e) {
      debugPrint('Background notification display error: $e');
    }
  }

  Future<void> _showTrayLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
    bool vibrate = true,
  }) async {
    await _renderNativeNotification(
      localPlugin: _localNotifications,
      title: title,
      body: body,
      data: data,
      vibrate: vibrate,
    );
  }

  /// Unified native renderer for both background isolates and foreground tray notifications.
  static Future<void> _renderNativeNotification({
    required FlutterLocalNotificationsPlugin localPlugin,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    bool vibrate = true,
  }) async {
    try {
      final rawType = (data['notification_type'] ?? data['type'] ?? 'general').toString();
      final config = ZevNotificationChannels.resolve(rawType);

      final avatarUrl = (data['avatar_url'] ??
              data['sender_avatar'] ??
              data['user_avatar'] ??
              '')
          .toString()
          .trim();

      final mediaUrl = (data['image'] ??
              data['image_url'] ??
              data['media_url'] ??
              data['thumbnail_url'] ??
              '')
          .toString()
          .trim();

      final senderName = (data['sender_name'] ?? data['user_name'] ?? title).toString().trim();
      final senderId = (data['sender_id'] ?? data['user_id'] ?? '').toString().trim();

      // Parallel download circular avatar and media thumbnail using ZevNotificationMediaHelper
      final avatarBytes = await ZevNotificationMediaHelper.getCircularAvatarBytes(avatarUrl);
      final pictureBytes = await ZevNotificationMediaHelper.getMediaThumbnailBytes(mediaUrl);

      ByteArrayAndroidBitmap? largeIconBitmap;
      if (avatarBytes != null) {
        largeIconBitmap = ByteArrayAndroidBitmap(avatarBytes);
      }

      StyleInformation styleInfo;
      List<AndroidNotificationAction> actions = [];

      if (config.type == ZevNotificationCategoryType.messages ||
          config.type == ZevNotificationCategoryType.groups) {
        final isGroup = config.type == ZevNotificationCategoryType.groups;
        final groupTitle = (data['group_name'] ??
                data['conversation_title'] ??
                'Group Chat')
            .toString();

        final person = Person(
          name: senderName.isNotEmpty ? senderName : 'ZEV User',
          key: senderId.isNotEmpty ? senderId : null,
          icon: avatarBytes != null ? ByteArrayAndroidIcon(avatarBytes) : null,
          bot: false,
          important: true,
        );

        styleInfo = MessagingStyleInformation(
          person,
          conversationTitle: isGroup ? groupTitle : null,
          groupConversation: isGroup,
          messages: [
            Message(
              body,
              DateTime.now(),
              person,
            ),
          ],
          htmlFormatContent: true,
          htmlFormatTitle: true,
        );

        actions = [
          const AndroidNotificationAction(
            'action_reply',
            'Reply',
            icon: DrawableResourceAndroidBitmap('@drawable/ic_notif_message'),
            inputs: [
              AndroidNotificationActionInput(
                label: 'Type a message...',
              ),
            ],
            showsUserInterface: false,
          ),
          const AndroidNotificationAction(
            'action_mark_read',
            'Mark as Read',
            cancelNotification: true,
            showsUserInterface: false,
          ),
        ];
      } else if (pictureBytes != null) {
        final picBitmap = ByteArrayAndroidBitmap(pictureBytes);
        styleInfo = BigPictureStyleInformation(
          picBitmap,
          largeIcon: largeIconBitmap,
          contentTitle: title,
          summaryText: body,
          htmlFormatContent: true,
          htmlFormatContentTitle: true,
        );

        if (config.type == ZevNotificationCategoryType.comments) {
          actions = [
            const AndroidNotificationAction(
              'action_reply_comment',
              'Reply',
              icon: DrawableResourceAndroidBitmap('@drawable/ic_notif_comment'),
              inputs: [
                AndroidNotificationActionInput(
                  label: 'Write a reply...',
                ),
              ],
              showsUserInterface: false,
            ),
            const AndroidNotificationAction(
              'action_open_post',
              'View',
              showsUserInterface: true,
            ),
          ];
        }
      } else {
        styleInfo = BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'ZEV',
          htmlFormatContent: true,
          htmlFormatContentTitle: true,
        );
      }

      final isCall = config.type == ZevNotificationCategoryType.voiceCalls ||
          config.type == ZevNotificationCategoryType.videoCalls;

      if (isCall) {
        actions = [
          const AndroidNotificationAction(
            'action_accept_call',
            'Accept',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          const AndroidNotificationAction(
            'action_decline_call',
            'Decline',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ];
      } else if (config.type == ZevNotificationCategoryType.friendRequests) {
        actions = [
          const AndroidNotificationAction(
            'action_accept_friend',
            'Accept',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          const AndroidNotificationAction(
            'action_decline_friend',
            'Decline',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ];
      } else if (config.type == ZevNotificationCategoryType.followers) {
        actions = [
          const AndroidNotificationAction(
            'action_view_profile',
            'View Profile',
            showsUserInterface: true,
          ),
        ];
      }

      final androidDetails = AndroidNotificationDetails(
        config.channelId,
        config.channelName,
        channelDescription: config.channelDescription,
        importance: config.importance,
        priority: config.priority,
        category: config.androidCategory,
        fullScreenIntent: config.fullScreenIntent,
        ongoing: isCall,
        autoCancel: !isCall,
        icon: config.smallIcon,
        color: const Color(0xFF2563EB),
        largeIcon: largeIconBitmap,
        styleInformation: styleInfo,
        actions: actions,
        groupKey: config.groupKey,
        subText: 'ZEV',
        ticker: title,
        enableVibration: vibrate,
        vibrationPattern: isCall
            ? Int64List.fromList([0, 1000, 1000, 1000, 1000, 1000])
            : null,
      );

      List<DarwinNotificationAttachment>? darwinAttachments;
      final attachPath = await ZevNotificationMediaHelper.getAttachmentFilePath(
        mediaUrl.isNotEmpty ? mediaUrl : avatarUrl,
      );
      if (attachPath != null) {
        darwinAttachments = [DarwinNotificationAttachment(attachPath)];
      }

      final darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: config.darwinCategory,
        attachments: darwinAttachments,
      );

      final notifId = data['notification_id']?.hashCode.remainder(100000).abs() ??
          DateTime.now().millisecondsSinceEpoch.remainder(100000).abs();

      await localPlugin.show(
        notifId,
        title,
        body,
        NotificationDetails(android: androidDetails, iOS: darwinDetails),
        payload: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('[NotificationService] _renderNativeNotification error: $e');
    }
  }

  static void _dispatchOrQueueNotificationClick(Map<String, dynamic> data) {
    final navContext = appNavigatorKey.currentContext;
    if (!DeepLinkService.instance.isAppReady ||
        navContext == null ||
        !navContext.mounted) {
      _pendingColdStartData = Map<String, dynamic>.from(data);
      return;
    }
    handleNotificationClick(data);
  }

  static void flushPendingNotificationClick() {
    final pending = _pendingColdStartData;
    _pendingColdStartData = null;
    if (pending != null) {
      handleNotificationClick(pending);
    }
  }

  /// Global notification click router that immediately navigates to the relevant screen.
  static void handleNotificationClick(Map<String, dynamic> data) {
    final navContext = appNavigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) {
      _pendingColdStartData = Map<String, dynamic>.from(data);
      return;
    }

    final type =
        (data['notification_type'] ?? data['type'] ?? '').toString().toLowerCase();
    final linkUrl = (data['deep_link'] ??
            data['link_url'] ??
            data['link'] ??
            data['target_id'] ??
            data['id'] ??
            '')
        .toString()
        .trim();
    final senderId =
        (data['sender_id'] ?? data['peer_id'] ?? data['user_id'] ?? '')
            .toString()
            .trim();

    debugPrint(
      'ZEV Routing notification click: type=$type, linkUrl=$linkUrl, senderId=$senderId',
    );

    // 0. Incoming Voice / Video Call
    if (type == 'voice_call' ||
        type == 'video_call' ||
        linkUrl.startsWith('/call/')) {
      final callId = linkUrl
          .replaceFirst(RegExp(r'^/call/'), '')
          .replaceFirst(RegExp(r'^call/'), '')
          .trim();
      if (callId.isNotEmpty) {
        unawaited(CallScreen.openById(navContext, callSessionId: callId));
        return;
      }
      if (senderId.isNotEmpty) {
        ChatConversationScreen.open(navContext, peerId: senderId);
        return;
      }
    }

    // 1. Direct Message / Group Chat / Group Invitation
    if (type.contains('chat') ||
        type.contains('message') ||
        type == 'dm' ||
        type == 'group_invitation') {
      final explicitConvId = (data['conversation_id'] ?? '').toString().trim();
      var cleanedLink = linkUrl;
      if (cleanedLink.startsWith('/chat/')) {
        cleanedLink = cleanedLink.substring('/chat/'.length);
      } else if (cleanedLink.startsWith('chat/')) {
        cleanedLink = cleanedLink.substring('chat/'.length);
      }

      if (explicitConvId.isNotEmpty) {
        ChatConversationScreen.open(
          navContext,
          conversationId: explicitConvId,
          isGroup: type.contains('group'),
        );
        return;
      }

      if (cleanedLink.startsWith('conv:')) {
        final convId = cleanedLink.substring('conv:'.length).trim();
        if (convId.isNotEmpty) {
          if (type.contains('group')) {
            ChatConversationScreen.open(
              navContext,
              conversationId: convId,
              isGroup: true,
            );
          } else {
            DeepLinkService.instance.handleUri(Uri.parse('/chat/conv:$convId'));
          }
          return;
        }
      }

      if (type == 'group_message' || type == 'group_invitation') {
        if (cleanedLink.isNotEmpty) {
          ChatConversationScreen.open(
            navContext,
            conversationId: cleanedLink,
            isGroup: true,
          );
          return;
        }
      }

      if (linkUrl.startsWith('/chat/')) {
        final uri = Uri.tryParse(linkUrl);
        if (uri != null) {
          DeepLinkService.instance.handleUri(uri);
          return;
        }
      }

      final peer = senderId.isNotEmpty ? senderId : cleanedLink;
      if (peer.isNotEmpty) {
        ChatConversationScreen.open(navContext, peerId: peer);
        return;
      }
      ChatListScreen.open(navContext);
      return;
    }

    // 2. Follow Request -> Open Requests tab directly for account owner
    if (type == 'follow_request') {
      final myId = Supabase.instance.client.auth.currentUser?.id;
      if (myId != null && myId.isNotEmpty) {
        UserFollowsScreen.open(
          navContext,
          userId: myId,
          username: 'you',
          initialTabIndex: 2,
        );
        return;
      }
    }

    // 3. Follow / Follow Accepted / Friend
    if (type.contains('follow') || type.contains('friend')) {
      final targetUser = senderId.isNotEmpty ? senderId : linkUrl;
      if (targetUser.isNotEmpty) {
        ProfileScreen.open(navContext, userId: targetUser);
        return;
      }
      NotificationsScreen.open(navContext);
      return;
    }

    // 4. Story (Like, Reaction, Reply, New Story) — check BEFORE generic like/reply!
    if (type.contains('story')) {
      final cleanStoryId = linkUrl
          .replaceFirst(RegExp(r'^/story/'), '')
          .trim();
      final isUuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(cleanStoryId);
      if (isUuid && cleanStoryId != senderId) {
        unawaited(
          StoryViewerScreen.openByStoryId(
            navContext,
            storyId: cleanStoryId,
            fallbackUserId: senderId,
          ),
        );
        return;
      }
      final targetUser = senderId.isNotEmpty ? senderId : linkUrl;
      if (targetUser.isNotEmpty) {
        ProfileScreen.open(navContext, userId: targetUser);
        return;
      }
    }

    // 5. Reel (Like, Comment, Reply, New Reel)
    if (type.contains('reel')) {
      final reelId = linkUrl.replaceFirst(RegExp(r'^/reel/'), '');
      if (reelId.isNotEmpty) {
        _openReelInPlayer(navContext, reelId);
        return;
      }
    }

    // 6. Post (Like, Comment, Reply, Mention, Repost)
    if (type.contains('post') ||
        type == 'like' ||
        type.contains('comment') ||
        type.contains('reply') ||
        type.contains('mention') ||
        type.contains('repost')) {
      final postId = linkUrl.replaceFirst(RegExp(r'^/post/'), '');
      if (postId.isNotEmpty) {
        PostDetailScreen.open(navContext, postId: postId);
        return;
      }
    }

    // 7. Web URL, deep link scheme, or relative internal route
    if (linkUrl.startsWith('http://') ||
        linkUrl.startsWith('https://') ||
        linkUrl.startsWith('zev://') ||
        linkUrl.startsWith('zevapp://') ||
        linkUrl.startsWith('/')) {
      final uri = Uri.tryParse(linkUrl);
      if (uri != null) {
        DeepLinkService.instance.handleUri(uri);
        return;
      }
    }

    // 8. Default fallback: Open NotificationsScreen
    NotificationsScreen.open(navContext);
  }

  /// Opens the full reel player from notification tap.
  static Future<void> _openReelInPlayer(
    BuildContext context,
    String reelId,
  ) async {
    final cleanId = reelId.trim();
    if (cleanId.isEmpty) return;

    try {
      final res = await Supabase.instance.client
          .from('reels')
          .select(
            'id, user_id, title, description, video_url, thumbnail_url, category, views_count, likes_count, comments_count, created_at',
          )
          .eq('id', cleanId)
          .maybeSingle();

      if (res != null && context.mounted) {
        final reel = ReelItem(
          id: res['id'].toString(),
          userId: res['user_id']?.toString() ?? '',
          authorUsername: res['title']?.toString() ?? 'Reel',
          authorFullName: '',
          authorAvatar: '',
          isVerified: false,
          videoUrl: res['video_url']?.toString() ?? '',
          thumbnailUrl: res['thumbnail_url']?.toString(),
          title: res['title']?.toString() ?? '',
          description: res['description']?.toString() ?? '',
          viewsCount: (res['views_count'] as num?)?.toInt() ?? 0,
          likesCount: (res['likes_count'] as num?)?.toInt() ?? 0,
          commentsCount: (res['comments_count'] as num?)?.toInt() ?? 0,
          createdAt: DateTime.tryParse(res['created_at']?.toString() ?? '') ??
              DateTime.now(),
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(reel.title.isNotEmpty ? reel.title : 'Reel'),
              ),
              body: ReelPlayerItem(
                reel: reel,
                isActive: true,
                isGlobalMuted: false,
                onToggleMute: () {},
              ),
            ),
          ),
        );
        return;
      }
    } catch (_) {}

    if (context.mounted) {
      PostDetailScreen.open(context, postId: cleanId);
    }
  }

  /// Displays a Light Clearmorphic floating top banner when notifications arrive in foreground.
  static void showInAppBanner({
    required String title,
    required String body,
    required Map<String, dynamic> data,
    bool vibrate = true,
  }) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _bannerDismissTimer?.cancel();
    _activeBannerEntry?.remove();
    _activeBannerEntry = null;

    if (vibrate) {
      HapticFeedback.mediumImpact();
    }

    final rawType = (data['notification_type'] ?? data['type'] ?? 'general').toString().toLowerCase();
    final avatarUrl = (data['avatar_url'] ?? data['sender_avatar'] ?? data['user_avatar'] ?? '').toString().trim();
    final mediaUrl = (data['image'] ?? data['image_url'] ?? data['media_url'] ?? data['thumbnail_url'] ?? '').toString().trim();

    final (badgeIcon, badgeColor, categoryLabel) = switch (true) {
      _ when rawType == 'voice_call' => (Icons.phone_rounded, const Color(0xFF10B981), 'Voice Call'),
      _ when rawType == 'video_call' => (Icons.videocam_rounded, const Color(0xFF8B5CF6), 'Video Call'),
      _ when rawType == 'message' || rawType.contains('chat') || rawType == 'dm' => (Icons.chat_bubble_rounded, const Color(0xFF2563EB), 'Chat'),
      _ when rawType.contains('group') => (Icons.group_rounded, const Color(0xFF0284C7), 'Group'),
      _ when rawType.contains('like') => (Icons.favorite_rounded, const Color(0xFFEF4444), 'Liked your post'),
      _ when rawType.contains('comment') || rawType.contains('reply') => (Icons.chat_bubble_outline_rounded, const Color(0xFF3B82F6), 'Commented'),
      _ when rawType == 'friend_request' || rawType == 'follow_request' => (Icons.person_add_rounded, const Color(0xFFF59E0B), 'Friend Request'),
      _ when rawType.contains('follow') => (Icons.person_add_alt_1_rounded, const Color(0xFF06B6D4), 'New Follower'),
      _ when rawType.contains('story') => (Icons.motion_photos_on_rounded, const Color(0xFFEC4899), 'Story'),
      _ when rawType.contains('share') => (Icons.share_rounded, const Color(0xFF6366F1), 'Shared'),
      _ when rawType.contains('security') || rawType.contains('login') => (Icons.shield_rounded, const Color(0xFFDC2626), 'Security Alert'),
      _ => (Icons.notifications_active_rounded, const Color(0xFF2563EB), 'Activity'),
    };

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 14,
          right: 14,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {
                entry.remove();
                _activeBannerEntry = null;
                _bannerDismissTimer?.cancel();
                handleNotificationClick(data);
              },
              onVerticalDragEnd: (_) {
                entry.remove();
                _activeBannerEntry = null;
                _bannerDismissTimer?.cancel();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: ZevColors.primaryBlue.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.secondaryBlue.withValues(alpha: 0.16),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: ZevColors.deepNavy.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Sender Avatar with Category Badge Overlay
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          avatarUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: ZevCachedImage(
                                    imageUrl: avatarUrl,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    gradient: ZevColors.brandGradient,
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Z',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: badgeColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Icon(badgeIcon, size: 10, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: ZevColors.deepNavy,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '• $categoryLabel',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: badgeColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: ZevColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (mediaUrl.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ZevCachedImage(
                          imageUrl: mediaUrl,
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: ZevColors.primaryBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    _activeBannerEntry = entry;
    overlay.insert(entry);

    _bannerDismissTimer = Timer(const Duration(seconds: 4), () {
      if (_activeBannerEntry == entry) {
        entry.remove();
        _activeBannerEntry = null;
      }
    });
  }

  /// Tests local OS tray notifications AND live server `/api/v1/push/send` (`testSelf: true`).
  Future<({bool localShown, bool serverSent, int tokensTargeted, String detail})>
      sendTestNotification() async {
    await ensureInitialized();
    final granted = await requestOsPermission();

    const title = 'ZEV Push Test';
    const body = 'Notifications are active on this device.';
    await _showTrayLocalNotification(
      title: title,
      body: body,
      data: const {'type': 'general'},
      vibrate: true,
    );

    final uid = supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      return (
        localShown: granted,
        serverSent: false,
        tokensTargeted: 0,
        detail: granted
            ? 'Local tray notification shown (sign in to test server FCM).'
            : 'Please enable OS notification permission in system settings.',
      );
    }

    await AuthHelper.syncZevFcmToken(uid, forceSync: true);

    try {
      final res = await ApiClient.instance.post(
        '/api/v1/push/send',
        data: {
          'recipientUserId': uid,
          'testSelf': true,
          'title': title,
          'body': body,
          'notificationType': 'general',
          'data': {'type': 'general', 'sender_id': uid},
        },
      );
      final sent = (res['sentCount'] as num?)?.toInt() ?? 0;
      final failed = (res['failedCount'] as num?)?.toInt() ?? 0;
      return (
        localShown: true,
        serverSent: sent > 0,
        tokensTargeted: sent + failed,
        detail: sent > 0
            ? 'Delivered to $sent active device(s) via FCM.'
            : (res['reason']?.toString() ??
                res['skipped']?.toString() ??
                'Server accepted request (0 active FCM tokens).'),
      );
    } on ApiException catch (e) {
      return (
        localShown: true,
        serverSent: false,
        tokensTargeted: 0,
        detail: 'Local alert shown; server FCM (${e.statusCode ?? 'err'}): ${e.message}',
      );
    } catch (e) {
      return (
        localShown: true,
        serverSent: false,
        tokensTargeted: 0,
        detail: 'Local alert shown; server FCM error: $e',
      );
    }
  }

  /// Dispatches an asynchronous server-side FCM HTTP v1 notification through `/api/v1/push/send`.
  /// Never blocks UI or leaks private keys on the client.
  Future<void> dispatchPushNotification({
    required String recipientUserId,
    required String title,
    required String body,
    required String notificationType,
    String? deepLink,
    Map<String, String>? extraData,
  }) async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null ||
        recipientUserId.isEmpty ||
        recipientUserId == myId) {
      return;
    }

    try {
      final res = await ApiClient.instance.post(
        '/api/v1/push/send',
        data: {
          'recipientUserId': recipientUserId,
          'title': title,
          'body': body,
          'notificationType': notificationType,
          if (deepLink != null && deepLink.isNotEmpty) 'deepLink': deepLink,
          'data': {
            'type': notificationType,
            'notification_type': notificationType,
            'sender_id': myId,
            if (deepLink != null && deepLink.isNotEmpty) 'link_url': deepLink,
            ...?extraData,
          },
        },
      );
      if (res['ok'] == false) {
        debugPrint(
          '[NotificationService] push/send returned non-ok: ${res['error'] ?? res}',
        );
      }
    } on ApiException catch (e) {
      debugPrint(
        '[NotificationService] push/send HTTP ${e.statusCode}: ${e.message}',
      );
    } catch (e) {
      debugPrint('[NotificationService] dispatchPushNotification notice: $e');
    }
  }

  /// Records an in-app notification row in `user_notifications` and optionally triggers server FCM push.
  Future<void> sendNotificationToUser({
    required String targetUserId,
    required String title,
    required String message,
    required String notificationType,
    String? linkUrl,
    String? senderId,
    String appSource = 'zev',
    bool insertDatabaseRow = true,
    bool dispatchPush = true,
  }) async {
    final myId = senderId ?? supabase.auth.currentUser?.id;
    if (targetUserId.isEmpty || targetUserId == myId) return;

    if (insertDatabaseRow) {
      try {
        await supabase.from('user_notifications').insert({
          'user_id': targetUserId,
          'sender_id': myId,
          'title': title,
          'message': message,
          'notification_type': notificationType,
          'link_url': linkUrl,
          'is_read': false,
          'app_source': appSource,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (e) {
        debugPrint('Notice: Creating notification record in Supabase: $e');
      }
    }

    if (dispatchPush) {
      unawaited(
        dispatchPushNotification(
          recipientUserId: targetUserId,
          title: title,
          body: message,
          notificationType: notificationType,
          deepLink: linkUrl,
        ),
      );
    }
  }
}
