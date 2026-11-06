import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chat/screens/chat_conversation_screen.dart';
import '../../features/chat/screens/chat_list_screen.dart';
import '../../features/feed/screens/post_detail_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/reels/models/reel_item.dart';
import '../../features/reels/widgets/reel_player_item.dart';
import '../../main.dart';
import 'deep_link_service.dart';

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

/// Production Notification & Deep-Link Dispatcher Service for ZEV.
/// Handles Firebase App initialization, notification permission prompts,
/// foreground in-app floating banner display, notification tap routing (cold start + warm start),
/// and writing in-app notifications to the `user_notifications` table in Supabase.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  NotificationService._internal();

  final supabase = Supabase.instance.client;
  bool _isInitialized = false;

  static OverlayEntry? _activeBannerEntry;
  static Timer? _bannerDismissTimer;

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

      // 4. Foreground message listener (renders sleek in-app banner)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          'ZEV Foreground notification: ${message.notification?.title} | ${message.notification?.body}',
        );
        final title = message.notification?.title ?? 'New Activity';
        final body = message.notification?.body ?? 'You have a new update on ZEV.';
        showInAppBanner(title: title, body: body, data: message.data);
      });

      // 5. Notification tap handler (when app was opened from background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint(
          'ZEV Notification opened from background: ${message.data}',
        );
        handleNotificationClick(message.data);
      });

      // 6. Cold Start notification tap handler (when app launched from terminated state)
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          'ZEV Notification cold start initial message: ${initialMessage.data}',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 700), () {
            handleNotificationClick(initialMessage.data);
          });
        });
      }

      _isInitialized = true;
      debugPrint("ZEV Firebase Messaging initialized successfully.");
    } catch (e) {
      debugPrint("ZEV Push notification initialization notice: $e");
    }
  }

  /// Global notification click router that immediately navigates to the relevant screen
  static void handleNotificationClick(Map<String, dynamic> data) {
    final navContext = appNavigatorKey.currentContext;
    if (navContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 600), () {
          handleNotificationClick(data);
        });
      });
      return;
    }

    final type =
        (data['notification_type'] ?? data['type'] ?? '').toString().toLowerCase();
    final linkUrl = (data['link_url'] ??
            data['link'] ??
            data['target_id'] ??
            data['id'] ??
            '')
        .toString();
    final senderId =
        (data['sender_id'] ?? data['peer_id'] ?? data['user_id'] ?? '').toString();

    debugPrint(
      "ZEV Routing notification click: type=$type, linkUrl=$linkUrl, senderId=$senderId",
    );

    // 1. Direct Message / Chat
    if (type.contains('chat') ||
        type.contains('message') ||
        type.contains('dm')) {
      final peer = senderId.isNotEmpty ? senderId : linkUrl;
      if (peer.isNotEmpty) {
        ChatConversationScreen.open(navContext, peerId: peer);
        return;
      }
      ChatListScreen.open(navContext);
      return;
    }

    // 2. Follow / New Follower
    if (type.contains('follow')) {
      final targetUser = senderId.isNotEmpty ? senderId : linkUrl;
      if (targetUser.isNotEmpty) {
        ProfileScreen.open(navContext, userId: targetUser);
        return;
      }
      NotificationsScreen.open(navContext);
      return;
    }

    // 3. Post (Like, Comment, Mention, Repost)
    if (type.contains('post') ||
        type == 'like' ||
        type == 'comment' ||
        type == 'mention' ||
        type == 'repost') {
      if (linkUrl.isNotEmpty) {
        PostDetailScreen.open(navContext, postId: linkUrl);
        return;
      }
    }

    // 4. Reel (Like, Comment, or New Reel)
    if (type.contains('reel')) {
      if (linkUrl.isNotEmpty) {
        _openReelInPlayer(navContext, linkUrl);
        return;
      }
    }

    // 5. If linkUrl is a web URL or deep link scheme
    if (linkUrl.startsWith('http://') ||
        linkUrl.startsWith('https://') ||
        linkUrl.startsWith('zev://')) {
      final uri = Uri.tryParse(linkUrl);
      if (uri != null) {
        DeepLinkService.instance.handleUri(uri);
        return;
      }
    }

    // 6. Default fallback: Open NotificationsScreen
    NotificationsScreen.open(navContext);
  }

  /// Opens the full reel player
  static Future<void> _openReelInPlayer(BuildContext context, String reelId) async {
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
          authorUsername: res['title'] ?? 'Reel',
          authorFullName: '',
          authorAvatar: '',
          isVerified: false,
          videoUrl: res['video_url'] ?? '',
          thumbnailUrl: res['thumbnail_url'],
          title: res['title'] ?? '',
          description: res['description'] ?? '',
          createdAt: DateTime.now(),
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(reel.title.isNotEmpty ? reel.title : "Reel"),
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

    // Fallback: open post detail
    if (context.mounted) {
      PostDetailScreen.open(context, postId: cleanId);
    }
  }

  /// Displays a floating top in-app notification banner when messages arrive in foreground
  static void showInAppBanner({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _bannerDismissTimer?.cancel();
    _activeBannerEntry?.remove();
    _activeBannerEntry = null;

    HapticFeedback.mediumImpact();

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
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // ZEV Logo Badge
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00D4FF), Color(0xFF0284C7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          "Z",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00D4FF),
                        shape: BoxShape.circle,
                      ),
                    ),
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
