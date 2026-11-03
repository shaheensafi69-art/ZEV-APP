import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/feed/screens/post_detail_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../main.dart';

/// Flagship Deep Linking and Universal App Links Service for ZEV.
/// Handles:
/// - https://www.zevapp.com/post/:id
/// - https://zevapp.com/post/:id
/// - zev://post/:id
/// - https://www.zevapp.com/reel/:id
/// - https://zevapp.com/reel/:id
/// - zev://reel/:id
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
        _handleIncomingUri(uri);
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
      Future.delayed(const Duration(milliseconds: 600), () {
        _handleIncomingUri(uri);
      });
    });
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    final navContext = appNavigatorKey.currentContext;
    if (navContext == null) return;

    final pathSegments = uri.pathSegments;
    final host = uri.host.toLowerCase();
    final scheme = uri.scheme.toLowerCase();

    debugPrint('[DeepLinkService] Parsing URI: scheme=$scheme, host=$host, path=${uri.path}');

    // Case 1: Custom Scheme "zev://post/:id" or "zev://reel/:id"
    if (scheme == 'zev') {
      if (host == 'post' && pathSegments.isNotEmpty) {
        _openPost(navContext, pathSegments.first);
        return;
      }
      if (host == 'reel' && pathSegments.isNotEmpty) {
        _openReel(navContext, pathSegments.first);
        return;
      }
      if (pathSegments.length >= 2) {
        if (pathSegments[0] == 'post') {
          _openPost(navContext, pathSegments[1]);
          return;
        } else if (pathSegments[0] == 'reel') {
          _openReel(navContext, pathSegments[1]);
          return;
        }
      }
    }

    // Case 2: Web Domain "zevapp.com" or "www.zevapp.com"
    if (host.contains('zevapp.com')) {
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

  void _openReel(BuildContext context, String reelId) {
    if (reelId.trim().isEmpty) return;
    // Open post or reel screen
    PostDetailScreen.open(context, postId: reelId.trim());
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
      // Find post with matching image_url in discussion_posts
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
}
