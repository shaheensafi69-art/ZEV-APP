import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/chat/screens/chat_conversation_screen.dart';
import '../../features/feed/screens/post_detail_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/zev_blue_verification_screen.dart';
import '../../features/reels/models/reel_item.dart';
import '../../features/reels/widgets/reel_player_item.dart';
import '../../main.dart';

/// Flagship Deep Linking and Universal App Links Service for ZEV.
/// Handles:
/// - https://www.zevapp.com/post/:id
/// - https://zevapp.com/post/:id
/// - zev://post/:id
/// - https://www.zevapp.com/reel/:id
/// - https://zevapp.com/reel/:id
/// - zev://reel/:id
/// - https://zevapp.com/chat/:peerId
/// - zev://chat/:peerId
/// - https://zevapp.com/notifications
/// - zev://notifications
/// - https://zevapp.com/profile/:id
/// - zev://profile/:id
/// - https://zevapp.com/@username
/// - https://media.zevapp.com/zev/feed/:file (fallback resolution)
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    _appLinks = AppLinks();

    // 1. Cold Start - handle initial link if launched from terminated state
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('[DeepLinkService] Cold start link: $initialUri');
        _scheduleUriHandling(initialUri);
      }
    } catch (e) {
      debugPrint('[DeepLinkService] Initial link error: $e');
    }

    // 2. Warm Start / Foreground - listen for link stream
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('[DeepLinkService] Stream incoming link: $uri');
        handleUri(uri);
      },
      onError: (err) {
        debugPrint('[DeepLinkService] Link stream error: $err');
      },
    );
  }

  void dispose() {
    _linkSubscription?.cancel();
    _isInitialized = false;
  }

  void _scheduleUriHandling(Uri uri) {
    // Small delay on cold start to ensure NavigatorState is attached
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 700), () {
        handleUri(uri);
      });
    });
  }

  /// Public entry-point to handle any URI incoming from external links, notifications, or deep links
  Future<void> handleUri(Uri uri) async {
    final navContext = appNavigatorKey.currentContext;
    if (navContext == null) {
      _scheduleUriHandling(uri);
      return;
    }

    final pathSegments = uri.pathSegments;
    final host = uri.host.toLowerCase();
    final scheme = uri.scheme.toLowerCase();

    debugPrint('[DeepLinkService] Parsing URI: scheme=$scheme, host=$host, path=${uri.path}');

    // Recovery / Password Reset deep-link detection
    if (uri.queryParameters['type'] == 'recovery' ||
        uri.path.contains('reset-password') ||
        uri.host == 'reset-password') {
      final email = uri.queryParameters['email'] ?? '';
      final token = uri.queryParameters['token'] ?? uri.queryParameters['code'];
      ForgotPasswordScreen.open(navContext, email: email, token: token);
      return;
    }

    // Case 1: Custom Scheme "zev://..." or "zevapp://..."
    if (scheme == 'zev' || scheme == 'zevapp') {
      if (host == 'join' || (pathSegments.isNotEmpty && pathSegments[0] == 'join')) {
        final ref = uri.queryParameters['ref'] ?? '';
        _openJoinReferral(navContext, ref);
        return;
      }
      if (host == 'post' && pathSegments.isNotEmpty) {
        _openPost(navContext, pathSegments.first);
        return;
      }
      if (host == 'reel' && pathSegments.isNotEmpty) {
        _openReel(navContext, pathSegments.first);
        return;
      }
      if (host == 'chat' && pathSegments.isNotEmpty) {
        _openChat(navContext, pathSegments.first);
        return;
      }
      if (host == 'profile' && pathSegments.isNotEmpty) {
        _openProfile(navContext, pathSegments.first);
        return;
      }
      if (host == 'notifications') {
        _openNotifications(navContext);
        return;
      }
      if (host == 'reset-password' || host == 'recovery') {
        final email = uri.queryParameters['email'] ?? '';
        final token = uri.queryParameters['token'] ?? uri.queryParameters['code'];
        ForgotPasswordScreen.open(navContext, email: email, token: token);
        return;
      }

      if (pathSegments.length >= 2) {
        final target = pathSegments[0].toLowerCase();
        final id = pathSegments[1];
        if (target == 'post') {
          _openPost(navContext, id);
          return;
        } else if (target == 'reel') {
          _openReel(navContext, id);
          return;
        } else if (target == 'chat') {
          _openChat(navContext, id);
          return;
        } else if (target == 'profile') {
          _openProfile(navContext, id);
          return;
        }
      }
    }

    // Case 2: Web Domain "zevapp.com" or "www.zevapp.com"
    if (host.contains('zevapp.com')) {
      // /join?ref=...
      if (pathSegments.isNotEmpty && pathSegments[0] == 'join') {
        final ref = uri.queryParameters['ref'] ?? '';
        _openJoinReferral(navContext, ref);
        return;
      }

      // Profile @username: e.g. /@shaheensafi011
      if (pathSegments.isNotEmpty && pathSegments.first.startsWith('@')) {
        final username = pathSegments.first.substring(1);
        _openProfileByUsername(navContext, username);
        return;
      }

      // /post/:id
      if (pathSegments.length >= 2 && pathSegments[0] == 'post') {
        _openPost(navContext, pathSegments[1]);
        return;
      }

      // /reel/:id
      if (pathSegments.length >= 2 && pathSegments[0] == 'reel') {
        _openReel(navContext, pathSegments[1]);
        return;
      }

      // /chat/:peerId
      if (pathSegments.length >= 2 && pathSegments[0] == 'chat') {
        _openChat(navContext, pathSegments[1]);
        return;
      }

      // /profile/:id
      if (pathSegments.length >= 2 && pathSegments[0] == 'profile') {
        _openProfile(navContext, pathSegments[1]);
        return;
      }

      // /notifications
      if (pathSegments.isNotEmpty && pathSegments[0] == 'notifications') {
        _openNotifications(navContext);
        return;
      }

      // Fallback: Raw Media CDN Link resolution (e.g. media.zevapp.com/zev/feed/feed_...)
      if (host.contains('media.zevapp.com')) {
        await _resolveMediaLinkToPost(navContext, uri.toString());
        return;
      }
    }

    // Case 3: Direct resolution if URL contains a feed filename
    if (uri.path.contains('feed_')) {
      await _resolveMediaLinkToPost(navContext, uri.toString());
    }
  }

  void _openPost(BuildContext context, String postId) {
    if (postId.trim().isEmpty) return;
    PostDetailScreen.open(context, postId: postId.trim());
  }

  Future<void> _openReel(BuildContext context, String reelId) async {
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

  void _openChat(BuildContext context, String peerId) {
    final cleanId = peerId.trim();
    if (cleanId.isEmpty) return;
    ChatConversationScreen.open(context, peerId: cleanId);
  }

  void _openProfile(BuildContext context, String userId) {
    final cleanId = userId.trim();
    if (cleanId.isEmpty) return;
    ProfileScreen.open(context, userId: cleanId);
  }

  void _openNotifications(BuildContext context) {
    NotificationsScreen.open(context);
  }

  Future<void> _openProfileByUsername(BuildContext context, String username) async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('username', username)
          .maybeSingle();

      if (res != null && context.mounted) {
        final userId = res['id']?.toString() ?? '';
        ProfileScreen.open(context, userId: userId);
      }
    } catch (_) {}
  }

  Future<void> _resolveMediaLinkToPost(BuildContext context, String rawUrl) async {
    try {
      final res = await Supabase.instance.client
          .from('discussion_posts')
          .select('id')
          .ilike('image_url', '%${rawUrl.split('/').last}%')
          .limit(1)
          .maybeSingle();

      if (res != null && context.mounted) {
        final postId = res['id']?.toString();
        if (postId != null) {
          _openPost(context, postId);
        }
      }
    } catch (e) {
      debugPrint('[DeepLinkService] Media fallback error: $e');
    }
  }

  Future<void> _openJoinReferral(BuildContext context, String referralCode) async {
    final cleanRef = referralCode.trim().toLowerCase();
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null) {
      RegisterScreen.open(context, referralCode: cleanRef);
    } else {
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('*')
            .eq('id', currentUser.id)
            .maybeSingle();

        if (context.mounted) {
          if (profile != null) {
            ZevBlueVerificationScreen.open(context, userProfile: profile);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0284C7),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      cleanRef.isNotEmpty
                          ? "You are already a member! Switched to your referral hub."
                          : "Welcome back! Here is your referral & verification hub.",
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } catch (_) {}
    }
  }
}
