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
import '../theme/zev_theme.dart';

/// Deep Linking and Universal App Links Service for ZEV.
/// Buffers cold-start URIs until [ZevSplashScreen] signals readiness via [markAppReady],
/// eliminating navigation races during app initialization.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  bool _isInitialized = false;
  bool _isAppReady = false;
  Uri? _pendingUri;
  final List<VoidCallback> _onReadyCallbacks = [];

  bool get isAppReady => _isAppReady;

  void addOnReadyCallback(VoidCallback cb) {
    if (_isAppReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) => cb());
    } else {
      _onReadyCallbacks.add(cb);
    }
  }

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    _appLinks = AppLinks();

    // 1. Cold Start - buffer initial link until splash navigation completes
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('[DeepLinkService] Cold start link buffered: $initialUri');
        if (_isAppReady) {
          await handleUri(initialUri);
        } else {
          _pendingUri = initialUri;
        }
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

  /// Called once [ZevSplashScreen] has pushed the primary screen into the Navigator.
  void markAppReady() {
    _isAppReady = true;
    final pending = _pendingUri;
    _pendingUri = null;
    final callbacks = List<VoidCallback>.from(_onReadyCallbacks);
    _onReadyCallbacks.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pending != null) {
        handleUri(pending);
      }
      for (final cb in callbacks) {
        cb();
      }
    });
  }

  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _isInitialized = false;
    _isAppReady = false;
    _pendingUri = null;
  }

  /// Public entry-point to handle any URI incoming from external links or notifications.
  Future<void> handleUri(Uri uri) async {
    final navContext = appNavigatorKey.currentContext;
    if (!_isAppReady || navContext == null || !navContext.mounted) {
      _pendingUri = uri;
      return;
    }

    final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final host = uri.host.toLowerCase();
    final scheme = uri.scheme.toLowerCase();

    debugPrint(
      '[DeepLinkService] Parsing URI: scheme=$scheme, host=$host, path=${uri.path}',
    );

    // Recovery / Password Reset deep-link detection
    if (uri.queryParameters['type'] == 'recovery' ||
        uri.path.contains('reset-password') ||
        host == 'reset-password') {
      final email = uri.queryParameters['email'] ?? '';
      final token = uri.queryParameters['token'] ?? uri.queryParameters['code'];
      ForgotPasswordScreen.open(navContext, email: email, token: token);
      return;
    }

    // Case 1: Custom Scheme "zev://..." or "zevapp://..."
    if (scheme == 'zev' || scheme == 'zevapp') {
      if (host == 'join' || (pathSegments.isNotEmpty && pathSegments[0] == 'join')) {
        final ref = uri.queryParameters['ref'] ?? '';
        await _openJoinReferral(navContext, ref);
        return;
      }
      if (host == 'post' && pathSegments.isNotEmpty) {
        _openPost(navContext, pathSegments.first);
        return;
      }
      if (host == 'reel' && pathSegments.isNotEmpty) {
        await _openReel(navContext, pathSegments.first);
        return;
      }
      if (host == 'chat' && pathSegments.isNotEmpty) {
        await _openChat(navContext, pathSegments.first);
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
          await _openReel(navContext, id);
          return;
        } else if (target == 'chat') {
          await _openChat(navContext, id);
          return;
        } else if (target == 'profile') {
          _openProfile(navContext, id);
          return;
        }
      }
    }

    // Case 2: Web Domain "zevapp.com" or "www.zevapp.com" (or relative paths starting with '/')
    if (host.contains('zevapp.com') || (scheme.isEmpty && host.isEmpty && pathSegments.isNotEmpty)) {
      if (pathSegments.isNotEmpty && pathSegments[0] == 'join') {
        final ref = uri.queryParameters['ref'] ?? '';
        await _openJoinReferral(navContext, ref);
        return;
      }

      if (pathSegments.isNotEmpty && pathSegments.first.startsWith('@')) {
        final username = pathSegments.first.substring(1);
        await _openProfileByUsername(navContext, username);
        return;
      }

      if (pathSegments.length >= 2 && pathSegments[0] == 'post') {
        _openPost(navContext, pathSegments[1]);
        return;
      }

      if (pathSegments.length >= 2 && pathSegments[0] == 'reel') {
        await _openReel(navContext, pathSegments[1]);
        return;
      }

      if (pathSegments.length >= 2 && pathSegments[0] == 'chat') {
        await _openChat(navContext, pathSegments[1]);
        return;
      }

      if (pathSegments.length >= 2 && pathSegments[0] == 'profile') {
        _openProfile(navContext, pathSegments[1]);
        return;
      }

      if (pathSegments.isNotEmpty && pathSegments[0] == 'notifications') {
        _openNotifications(navContext);
        return;
      }

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
    final cleanId = postId.trim();
    if (cleanId.isEmpty) return;
    PostDetailScreen.open(context, postId: cleanId);
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

      // Check if ID refers to a discussion post
      final postCheck = await Supabase.instance.client
          .from('discussion_posts')
          .select('id')
          .eq('id', cleanId)
          .maybeSingle();

      if (postCheck != null && context.mounted) {
        PostDetailScreen.open(context, postId: cleanId);
        return;
      }
    } catch (e) {
      debugPrint('[DeepLinkService] _openReel notice: $e');
    }

    if (context.mounted) {
      _showDeepLinkNotice(context, 'This reel could not be found or was removed.');
    }
  }

  Future<void> _openChat(BuildContext context, String rawTarget) async {
    var clean = Uri.decodeComponent(rawTarget.trim());
    if (clean.startsWith('/chat/')) {
      clean = clean.substring('/chat/'.length);
    } else if (clean.startsWith('chat/')) {
      clean = clean.substring('chat/'.length);
    }
    clean = clean.replaceAll(RegExp(r'^/+|/+$'), '');
    if (clean.isEmpty) return;

    if (clean.startsWith('conv:')) {
      final convId = clean.substring('conv:'.length).trim();
      if (convId.isEmpty || !context.mounted) return;
      try {
        final conv = await Supabase.instance.client
            .from('conversations')
            .select('id, is_group, title, avatar_url')
            .eq('id', convId)
            .maybeSingle();
        if (!context.mounted) return;
        if (conv != null) {
          final isGroup = conv['is_group'] == true;
          await ChatConversationScreen.open(
            context,
            conversationId: convId,
            isGroup: isGroup,
            groupTitle: conv['title']?.toString() ?? (isGroup ? 'Group Chat' : ''),
            groupAvatar: conv['avatar_url']?.toString() ?? '',
          );
          return;
        }
      } catch (e) {
        debugPrint('[DeepLinkService] _openChat conv lookup notice: $e');
      }
      if (context.mounted) {
        await ChatConversationScreen.open(
          context,
          conversationId: convId,
          isGroup: true,
        );
      }
      return;
    }

    // Check if clean UUID matches a conversation (e.g. group_invitation sends /chat/<conv_id>)
    try {
      final conv = await Supabase.instance.client
          .from('conversations')
          .select('id, is_group, title, avatar_url')
          .eq('id', clean)
          .maybeSingle();
      if (!context.mounted) return;
      if (conv != null) {
        final isGroup = conv['is_group'] == true;
        await ChatConversationScreen.open(
          context,
          conversationId: clean,
          isGroup: isGroup,
          groupTitle: conv['title']?.toString() ?? (isGroup ? 'Group Chat' : ''),
          groupAvatar: conv['avatar_url']?.toString() ?? '',
        );
        return;
      }
    } catch (_) {}

    if (context.mounted) {
      await ChatConversationScreen.open(context, peerId: clean);
    }
  }

  void _openProfile(BuildContext context, String userId) {
    final cleanId = userId.trim();
    if (cleanId.isEmpty) return;
    ProfileScreen.open(context, userId: cleanId);
  }

  void _openNotifications(BuildContext context) {
    NotificationsScreen.open(context);
  }

  Future<void> _openProfileByUsername(
    BuildContext context,
    String username,
  ) async {
    final clean = username.trim().replaceAll('@', '');
    if (clean.isEmpty) return;

    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .ilike('username', clean)
          .maybeSingle();

      if (res != null && context.mounted) {
        final userId = res['id']?.toString() ?? '';
        if (userId.isNotEmpty) {
          ProfileScreen.open(context, userId: userId);
          return;
        }
      }
    } catch (e) {
      debugPrint('[DeepLinkService] _openProfileByUsername notice: $e');
    }

    if (context.mounted) {
      _showDeepLinkNotice(context, 'Account @$clean was not found.');
    }
  }

  Future<void> _resolveMediaLinkToPost(
    BuildContext context,
    String rawUrl,
  ) async {
    try {
      final fileName = rawUrl.split('/').last.split('?').first;
      if (fileName.isEmpty) return;

      final res = await Supabase.instance.client
          .from('discussion_posts')
          .select('id')
          .ilike('image_url', '%$fileName%')
          .limit(1)
          .maybeSingle();

      if (res != null && context.mounted) {
        final postId = res['id']?.toString();
        if (postId != null && postId.isNotEmpty) {
          _openPost(context, postId);
          return;
        }
      }
    } catch (e) {
      debugPrint('[DeepLinkService] Media fallback error: $e');
    }
  }

  Future<void> _openJoinReferral(
    BuildContext context,
    String referralCode,
  ) async {
    final cleanRef = referralCode.trim().toLowerCase();
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null) {
      RegisterScreen.open(context, referralCode: cleanRef);
      return;
    }

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
        _showDeepLinkNotice(
          context,
          cleanRef.isNotEmpty
              ? 'You are already signed in! Opened your ZEV Blue referral hub.'
              : 'Welcome back to your referral & verification hub.',
        );
      }
    } catch (_) {}
  }

  void _showDeepLinkNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ZevColors.deepNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
