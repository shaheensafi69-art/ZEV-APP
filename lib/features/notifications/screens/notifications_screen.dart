import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/badge_counter_service.dart';
import '../../../core/services/deep_link_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/time_ago.dart';
import '../../chat/screens/chat_conversation_screen.dart';
import '../../feed/screens/post_detail_screen.dart';
import '../../profile/screens/notification_settings_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../reels/models/reel_item.dart';
import '../../reels/widgets/reel_player_item.dart';
import '../../stories/screens/story_viewer_screen.dart';
import '../models/notification_item.dart';

/// Light Clearmorphic Notifications & Activity Screen for ZEV.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  static Future<void> open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final ScrollController _scrollCtrl = ScrollController();

  String? get currentUserId => supabase.auth.currentUser?.id;

  static List<NotificationItem> _staticCache = [];
  static const String _prefsCacheKey = 'zev_notifications_cache_v3';
  static const int _pageSize = 60;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreNotifs = true;
  String? _oldestNotifCursor;
  String _selectedFilter = 'All';
  String _currentUsername = '';
  List<NotificationItem> _notifications = [];
  final Set<String> _hiddenLocalIds = {};
  final Set<String> _busyRequestIds = {};
  RealtimeChannel? _realtimeChannel;

  final List<String> _filters = [
    'All',
    'Follows',
    'Likes',
    'Comments',
    'Mentions',
  ];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadCacheFirst();
    _fetchActivity(isBackgroundSync: _notifications.isNotEmpty);
    _subscribeToRealtimeActivity();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasMoreNotifs) return;
    if (_scrollCtrl.hasClients &&
        _scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 240) {
      _loadMoreNotifications();
    }
  }

  Future<void> _loadCacheFirst() async {
    if (_staticCache.isNotEmpty) {
      if (mounted) {
        setState(() {
          _notifications = List.from(_staticCache);
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_prefsCacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List decoded = jsonDecode(cachedJson);
        final list = decoded
            .map((e) => NotificationItem.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        if (list.isNotEmpty && mounted) {
          setState(() {
            _notifications = list;
            _staticCache = List.from(list);
            _isLoading = false;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveCacheToDisk(List<NotificationItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = items.take(50).map((e) => e.toMap()).toList();
      await prefs.setString(_prefsCacheKey, jsonEncode(raw));
    } catch (_) {}
  }

  void _subscribeToRealtimeActivity() {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      _realtimeChannel = supabase
          .channel('public:user_activity:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'user_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: (_) => _fetchActivity(isBackgroundSync: true),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'user_follows',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'following_id',
              value: uid,
            ),
            callback: (_) => _fetchActivity(isBackgroundSync: true),
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime activity subscription notice: $e');
    }
  }

  Future<void> _fetchActivity({bool isBackgroundSync = false}) async {
    final uid = currentUserId;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (!isBackgroundSync && _notifications.isEmpty && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final List<NotificationItem> items = [];
      final Set<String> allSenderIds = {};
      final Set<String> uniqueKeys = {};

      final phase1 = await Future.wait<dynamic>([
        supabase
            .from('user_notifications')
            .select(
              'id, user_id, sender_id, title, message, notification_type, link_url, is_read, created_at',
            )
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(_pageSize)
            .catchError((_) => []),
        supabase
            .from('user_follows')
            .select('id, follower_id, following_id, created_at')
            .eq('following_id', uid)
            .order('created_at', ascending: false)
            .limit(40)
            .catchError((_) => []),
        supabase
            .from('discussion_posts')
            .select('id, student_id, title, content, image_url, created_at')
            .eq('student_id', uid)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .limit(20)
            .catchError((_) => []),
        supabase
            .from('reels')
            .select('id, user_id, title, thumbnail_url, created_at')
            .eq('user_id', uid)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .limit(20)
            .catchError((_) => []),
        supabase
            .from('profiles')
            .select('username')
            .eq('id', uid)
            .maybeSingle()
            .catchError((_) => null),
        supabase
            .from('user_stories')
            .select('id, user_id, media_url, created_at')
            .eq('user_id', uid)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .limit(20)
            .catchError((_) => []),
        supabase
            .from('follow_requests')
            .select('id, requester_id, status, created_at')
            .eq('target_id', uid)
            .eq('status', 'pending')
            .order('created_at', ascending: false)
            .limit(30)
            .catchError((_) => []),
      ]);

      final rawNotifs = List.from(phase1[0] as List? ?? []);
      final rawFollows = List.from(phase1[1] as List? ?? []);
      final rawPosts = List.from(phase1[2] as List? ?? []);
      final rawReels = List.from(phase1[3] as List? ?? []);
      final myProfile = phase1[4] as Map<String, dynamic>?;
      final rawStories = List.from(phase1[5] as List? ?? []);
      final rawFollowRequests = List.from(phase1[6] as List? ?? []);

      _hasMoreNotifs = rawNotifs.length >= _pageSize;
      _oldestNotifCursor = rawNotifs.isNotEmpty
          ? rawNotifs.last['created_at']?.toString()
          : null;

      if (myProfile != null) {
        _currentUsername = myProfile['username']?.toString() ?? '';
      }

      final List<String> myPostIds = [];
      final Map<String, String?> postThumbnails = {};
      for (final p in rawPosts) {
        final pId = p['id']?.toString() ?? '';
        if (pId.isNotEmpty) {
          myPostIds.add(pId);
          postThumbnails[pId] = p['image_url']?.toString();
        }
      }

      final List<String> myReelIds = [];
      final Map<String, String?> reelThumbnails = {};
      for (final r in rawReels) {
        final rId = r['id']?.toString() ?? '';
        if (rId.isNotEmpty) {
          myReelIds.add(rId);
          reelThumbnails[rId] = r['thumbnail_url']?.toString();
        }
      }

      final List<String> myStoryIds = [];
      final Map<String, String?> storyThumbnails = {};
      for (final s in rawStories) {
        final sId = s['id']?.toString() ?? '';
        if (sId.isNotEmpty) {
          myStoryIds.add(sId);
          storyThumbnails[sId] = s['media_url']?.toString();
        }
      }

      final Set<String> seenActions = {};
      final Map<String, String> reqIdByRequester = {};
      for (final fr in rawFollowRequests) {
        final rId = fr['requester_id']?.toString() ?? '';
        final id = fr['id']?.toString() ?? '';
        if (rId.isNotEmpty && id.isNotEmpty) {
          reqIdByRequester[rId] = id;
        }
      }

      for (final r in rawNotifs) {
        final sId = r['sender_id']?.toString() ?? '';
        final nType = r['notification_type']?.toString().toLowerCase() ?? '';

        // Direct & group message notifications belong in Chat inbox; keep group invitations here
        if (nType == 'chat' ||
            nType == 'message' ||
            nType == 'direct_message' ||
            nType == 'group_message') {
          continue;
        }

        final notifId = r['id']?.toString() ?? '';
        if (notifId.isNotEmpty &&
            !_hiddenLocalIds.contains(notifId) &&
            uniqueKeys.add('notif_$notifId')) {
          final link = r['link_url']?.toString();
          if (sId.isNotEmpty && link != null && link.isNotEmpty) {
            seenActions.add('${sId}_${nType}_$link');
            seenActions.add('${sId}_like_$link');
            seenActions.add('${sId}_comment_$link');
          }
          if (sId.isNotEmpty && nType == 'follow') {
            seenActions.add('${sId}_follow_');
          }
          if (sId.isNotEmpty && nType == 'follow_request') {
            seenActions.add('${sId}_follow_request');
          }

          final isSystem =
              sId.isEmpty || sId == uid || nType == 'system' || nType == 'verified';
          if (!isSystem && sId.isNotEmpty) {
            allSenderIds.add(sId);
          }

          final mediaThumb = (link != null && link.isNotEmpty)
              ? (postThumbnails[link] ??
                  reelThumbnails[link] ??
                  storyThumbnails[link])
              : null;

          items.add(
            NotificationItem(
              id: notifId,
              userId: uid,
              senderId: sId,
              senderUsername: isSystem ? 'ZEV' : 'user',
              title: r['title']?.toString() ?? 'Notification',
              message: r['message']?.toString() ?? '',
              notificationType: (r['notification_type'] != null &&
                      r['notification_type'].toString().isNotEmpty)
                  ? r['notification_type'].toString()
                  : 'system',
              linkUrl: link,
              mediaThumbnail: mediaThumb,
              isRead: r['is_read'] == true,
              createdAt:
                  DateTime.tryParse(r['created_at']?.toString() ?? '') ??
                      DateTime.now(),
              canDelete: true,
              requestId:
                  nType == 'follow_request' ? reqIdByRequester[sId] : null,
            ),
          );
        }
      }

      // Live pending follow_requests from private account flow
      for (final fr in rawFollowRequests) {
        final requesterId = fr['requester_id']?.toString() ?? '';
        final reqId = fr['id']?.toString() ?? '';
        if (requesterId.isEmpty || requesterId == uid) continue;
        if (seenActions.contains('${requesterId}_follow_request')) continue;
        allSenderIds.add(requesterId);
        final key = 'freq_$reqId';
        if (!_hiddenLocalIds.contains(key) && uniqueKeys.add(key)) {
          items.add(
            NotificationItem(
              id: key,
              userId: uid,
              senderId: requesterId,
              senderUsername: 'user',
              title: 'Follow Request',
              message: 'requested to follow you.',
              notificationType: 'follow_request',
              isRead: false,
              requestId: reqId,
              createdAt:
                  DateTime.tryParse(fr['created_at']?.toString() ?? '') ??
                      DateTime.now(),
            ),
          );
        }
      }

      // Incoming follows fallback
      for (final f in rawFollows) {
        final followerId = f['follower_id']?.toString() ?? '';
        if (followerId.isNotEmpty && followerId != uid) {
          if (seenActions.contains('${followerId}_follow_')) continue;
          allSenderIds.add(followerId);
          final key = 'follow_${f['id']}';
          if (!_hiddenLocalIds.contains(key) && uniqueKeys.add(key)) {
            items.add(
              NotificationItem(
                id: key,
                userId: uid,
                senderId: followerId,
                senderUsername: 'user',
                title: 'New Follower',
                message: 'started following you.',
                notificationType: 'follow',
                isRead: true,
                createdAt:
                    DateTime.tryParse(f['created_at']?.toString() ?? '') ??
                        DateTime.now(),
              ),
            );
          }
        }
      }

      // Phase 2 parallel enrichment (post likes/comments, reel likes/comments with `comment_text`, mentions, reposts, story likes)
      final List<Future> phase2Futures = [
        if (myPostIds.isNotEmpty)
          supabase
              .from('discussion_likes')
              .select('id, post_id, student_id, created_at')
              .inFilter('post_id', myPostIds)
              .order('created_at', ascending: false)
              .limit(40)
              .catchError((_) => [])
        else
          Future.value([]),
        if (myPostIds.isNotEmpty)
          supabase
              .from('discussion_comments')
              .select('id, post_id, student_id, comment_text, created_at')
              .inFilter('post_id', myPostIds)
              .isFilter('deleted_at', null)
              .order('created_at', ascending: false)
              .limit(40)
              .catchError((_) => [])
        else
          Future.value([]),
        if (myReelIds.isNotEmpty)
          supabase
              .from('reel_likes')
              .select('id, reel_id, user_id, created_at')
              .inFilter('reel_id', myReelIds)
              .order('created_at', ascending: false)
              .limit(40)
              .catchError((_) => [])
        else
          Future.value([]),
        if (myReelIds.isNotEmpty)
          supabase
              .from('reel_comments')
              .select('id, reel_id, user_id, comment_text, created_at')
              .inFilter('reel_id', myReelIds)
              .isFilter('deleted_at', null)
              .order('created_at', ascending: false)
              .limit(40)
              .catchError((_) => [])
        else
          Future.value([]),
        if (_currentUsername.isNotEmpty)
          supabase
              .from('discussion_comments')
              .select('id, post_id, student_id, comment_text, created_at')
              .ilike('comment_text', '%@$_currentUsername%')
              .isFilter('deleted_at', null)
              .order('created_at', ascending: false)
              .limit(15)
              .catchError((_) => [])
        else
          Future.value([]),
        if (myPostIds.isNotEmpty)
          supabase
              .from('post_reposts')
              .select('id, post_id, user_id, created_at')
              .inFilter('post_id', myPostIds)
              .order('created_at', ascending: false)
              .limit(30)
              .catchError((_) => [])
        else
          Future.value([]),
        if (myStoryIds.isNotEmpty)
          supabase
              .from('story_likes')
              .select('id, story_id, user_id, created_at')
              .inFilter('story_id', myStoryIds)
              .order('created_at', ascending: false)
              .limit(30)
              .catchError((_) => [])
        else
          Future.value([]),
      ];

      final phase2Results = await Future.wait(phase2Futures);
      final rawPostLikes = List.from(phase2Results[0] as List? ?? []);
      final rawPostComments = List.from(phase2Results[1] as List? ?? []);
      final rawReelLikes = List.from(phase2Results[2] as List? ?? []);
      final rawReelComments = List.from(phase2Results[3] as List? ?? []);
      final rawMentions = List.from(phase2Results[4] as List? ?? []);
      final rawReposts = List.from(phase2Results[5] as List? ?? []);
      final rawStoryLikes = List.from(phase2Results[6] as List? ?? []);

      for (final l in rawPostLikes) {
        final uId = l['student_id']?.toString() ?? '';
        final pId = l['post_id']?.toString() ?? '';
        if (uId.isNotEmpty && uId != uid) {
          if (seenActions.contains('${uId}_like_$pId') ||
              seenActions.contains('${uId}_post_like_$pId')) {
            continue;
          }
          allSenderIds.add(uId);
          final key = 'post_like_${l['id']}';
          if (!_hiddenLocalIds.contains(key) && uniqueKeys.add(key)) {
            items.add(
              NotificationItem(
                id: key,
                userId: uid,
                senderId: uId,
                senderUsername: 'user',
                title: 'Post Liked',
                message: 'liked your post.',
                notificationType: 'post_like',
                linkUrl: pId,
                mediaThumbnail: postThumbnails[pId],
                isRead: true,
                createdAt:
                    DateTime.tryParse(l['created_at']?.toString() ?? '') ??
                        DateTime.now(),
              ),
            );
          }
        }
      }

      for (final c in rawPostComments) {
        final uId = c['student_id']?.toString() ?? '';
        final pId = c['post_id']?.toString() ?? '';
        final text = (c['comment_text']?.toString() ?? '').trim();
        if (uId.isNotEmpty && uId != uid) {
          if (seenActions.contains('${uId}_comment_$pId') ||
              seenActions.contains('${uId}_post_comment_$pId')) {
            continue;
          }
          allSenderIds.add(uId);
          final key = 'post_comment_${c['id']}';
          if (!_hiddenLocalIds.contains(key) && uniqueKeys.add(key)) {
            items.add(
              NotificationItem(
                id: key,
                userId: uid,
                senderId: uId,
                senderUsername: 'user',
                title: 'New Comment',
                message: text.isNotEmpty
                    ? 'commented: "$text"'
                    : 'commented on your post.',
                notificationType: 'post_comment',
                linkUrl: pId,
                mediaThumbnail: postThumbnails[pId],
                additionalText: text,
                isRead: true,
                createdAt:
                    DateTime.tryParse(c['created_at']?.toString() ?? '') ??
                        DateTime.now(),
              ),
            );
          }
        }
      }

      for (final l in rawReelLikes) {
        final uId = l['user_id']?.toString() ?? '';
        final rId = l['reel_id']?.toString() ?? '';
        if (uId.isNotEmpty && uId != uid) {
          if (seenActions.contains('${uId}_like_$rId') ||
              seenActions.contains('${uId}_reel_like_$rId')) {
            continue;
          }
          allSenderIds.add(uId);
          final key = 'reel_like_${l['id']}';
          if (!_hiddenLocalIds.contains(key) && uniqueKeys.add(key)) {
            items.add(
              NotificationItem(
                id: key,
                userId: uid,
                senderId: uId,
                senderUsername: 'user',
                title: 'Reel Liked',
                message: 'liked your reel.',
                notificationType: 'reel_like',
                linkUrl: rId,
                mediaThumbnail: reelThumbnails[rId],
                isRead: true,
                createdAt:
                    DateTime.tryParse(l['created_at']?.toString() ?? '') ??
                        DateTime.now(),
              ),
            );
          }
        }
      }

      for (final c in rawReelComments) {
        final uId = c['user_id']?.toString() ?? '';
        final rId = c['reel_id']?.toString() ?? '';
        final text = (c['comment_text']?.toString() ?? '').trim();
        if (uId.isNotEmpty && uId != uid) {
          if (seenActions.contains('${uId}_comment_$rId') ||
              seenActions.contains('${uId}_reel_comment_$rId')) {
            continue;
          }
          allSenderIds.add(uId);
          final key = 'reel_comment_${c['id']}';
          if (!_hiddenLocalIds.contains(key) && uniqueKeys.add(key)) {
            items.add(
              NotificationItem(
                id: key,
                userId: uid,
                senderId: uId,
                senderUsername: 'user',
                title: 'Reel Comment',
                message: text.isNotEmpty
                    ? 'commented: "$text"'
                    : 'commented on your reel.',
                notificationType: 'reel_comment',
                linkUrl: rId,
                mediaThumbnail: reelThumbnails[rId],
                additionalText: text,
                isRead: true,
                createdAt:
                    DateTime.tryParse(c['created_at']?.toString() ?? '') ??
                        DateTime.now(),
              ),
            );
          }
        }
      }

      for (final m in rawMentions) {
        final uId = m['student_id']?.toString() ?? '';
        final pId = m['post_id']?.toString() ?? '';
        final text = (m['comment_text']?.toString() ?? '').trim();
        if (uId.isNotEmpty && uId != uid) {
          allSenderIds.add(uId);
          final key = 'mention_${m['id']}';
          if (!_hiddenLocalIds.contains(key) && uniqueKeys.add(key)) {
            items.add(
              NotificationItem(
                id: key,
                userId: uid,
                senderId: uId,
                senderUsername: 'user',
                title: 'Mentioned You',
                message: 'mentioned you: "$text"',
                notificationType: 'mention',
                linkUrl: pId,
                mediaThumbnail: postThumbnails[pId],
                additionalText: text,
                isRead: true,
                createdAt:
                    DateTime.tryParse(m['created_at']?.toString() ?? '') ??
                        DateTime.now(),
              ),
            );
          }
        }
      }

      for (final r in rawReposts) {
        final uId = r['user_id']?.toString() ?? '';
        final pId = r['post_id']?.toString() ?? '';
        if (uId.isNotEmpty && uId != uid) {
          if (seenActions.contains('${uId}_repost_$pId')) continue;
          allSenderIds.add(uId);
          final key = 'post_repost_${r['id']}';
          if (!_hiddenLocalIds.contains(key) && uniqueKeys.add(key)) {
            items.add(
              NotificationItem(
                id: key,
                userId: uid,
                senderId: uId,
                senderUsername: 'user',
                title: 'Post Reposted',
                message: 'reposted your post.',
                notificationType: 'repost',
                linkUrl: pId,
                mediaThumbnail: postThumbnails[pId],
                isRead: true,
                createdAt:
                    DateTime.tryParse(r['created_at']?.toString() ?? '') ??
                        DateTime.now(),
              ),
            );
          }
        }
      }

      for (final s in rawStoryLikes) {
        final uId = s['user_id']?.toString() ?? '';
        final sId = s['story_id']?.toString() ?? '';
        if (uId.isNotEmpty && uId != uid) {
          if (seenActions.contains('${uId}_story_like_$sId')) continue;
          allSenderIds.add(uId);
          final key = 'story_like_${s['id']}';
          if (!_hiddenLocalIds.contains(key) && uniqueKeys.add(key)) {
            items.add(
              NotificationItem(
                id: key,
                userId: uid,
                senderId: uId,
                senderUsername: 'user',
                title: 'Story Liked',
                message: 'liked your story.',
                notificationType: 'story_like',
                linkUrl: sId,
                mediaThumbnail: storyThumbnails[sId],
                isRead: true,
                createdAt:
                    DateTime.tryParse(s['created_at']?.toString() ?? '') ??
                        DateTime.now(),
              ),
            );
          }
        }
      }

      final enriched = await _enrichItemsWithProfiles(uid, items, allSenderIds);
      enriched.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      _staticCache = List.from(enriched);
      _saveCacheToDisk(enriched);

      if (mounted) {
        setState(() {
          _notifications = enriched;
          _isLoading = false;
        });
      }

      if (!isBackgroundSync) {
        await _markAllUnreadAsReadInDatabase();
      }
    } catch (e) {
      debugPrint('Notifications parallel fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<NotificationItem>> _enrichItemsWithProfiles(
    String uid,
    List<NotificationItem> items,
    Set<String> senderIds,
  ) async {
    final Map<String, Map<String, dynamic>> profilesMap = {};
    final Set<String> myFollowing = {};

    if (senderIds.isNotEmpty) {
      final results = await Future.wait([
        supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .inFilter('id', senderIds.toList())
            .catchError((_) => []),
        supabase
            .from('user_follows')
            .select('following_id')
            .eq('follower_id', uid)
            .inFilter('following_id', senderIds.toList())
            .catchError((_) => []),
      ]);

      for (final p in (results[0] as List? ?? [])) {
        if (p is Map) {
          profilesMap[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }
      for (final f in (results[1] as List? ?? [])) {
        if (f is Map) {
          final fid = f['following_id']?.toString() ?? '';
          if (fid.isNotEmpty) myFollowing.add(fid);
        }
      }
    }

    return items.map((item) {
      final profile = profilesMap[item.senderId];
      String username = item.senderUsername;
      String fullName = '';
      String avatar = '';
      bool isVerified = false;

      if (profile != null) {
        final uName = profile['username']?.toString() ?? '';
        if (uName.isNotEmpty) username = uName;
        fullName =
            '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
        avatar = profile['avatar_url']?.toString() ?? '';
        isVerified = profile['is_verified'] == true;
      }

      return item.copyWith(
        senderUsername: username,
        senderFullName: fullName,
        senderAvatar: avatar,
        isSenderVerified: isVerified,
        isFollowingSender: myFollowing.contains(item.senderId),
      );
    }).toList();
  }

  Future<void> _loadMoreNotifications() async {
    final uid = currentUserId;
    final cursor = _oldestNotifCursor;
    if (uid == null || cursor == null || _isLoadingMore || !_hasMoreNotifs) {
      return;
    }

    setState(() => _isLoadingMore = true);
    try {
      final rows = await supabase
          .from('user_notifications')
          .select(
            'id, user_id, sender_id, title, message, notification_type, link_url, is_read, created_at',
          )
          .eq('user_id', uid)
          .lt('created_at', cursor)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      final rawList = List<Map<String, dynamic>>.from(rows as List);
      _hasMoreNotifs = rawList.length >= _pageSize;
      if (rawList.isNotEmpty) {
        _oldestNotifCursor = rawList.last['created_at']?.toString();
      }

      final existingIds = _notifications.map((e) => e.id).toSet();
      final List<NotificationItem> older = [];
      final Set<String> senderIds = {};

      for (final r in rawList) {
        final nType = r['notification_type']?.toString().toLowerCase() ?? '';
        if (nType == 'chat' ||
            nType == 'message' ||
            nType == 'direct_message' ||
            nType == 'group_message') {
          continue;
        }
        final id = r['id']?.toString() ?? '';
        if (id.isEmpty || existingIds.contains(id) || _hiddenLocalIds.contains(id)) {
          continue;
        }
        final sId = r['sender_id']?.toString() ?? '';
        final isSystem =
            sId.isEmpty || sId == uid || nType == 'system' || nType == 'verified';
        if (!isSystem && sId.isNotEmpty) senderIds.add(sId);

        older.add(
          NotificationItem(
            id: id,
            userId: uid,
            senderId: sId,
            senderUsername: isSystem ? 'ZEV' : 'user',
            title: r['title']?.toString() ?? 'Notification',
            message: r['message']?.toString() ?? '',
            notificationType: nType.isNotEmpty ? nType : 'system',
            linkUrl: r['link_url']?.toString(),
            isRead: r['is_read'] == true,
            canDelete: true,
            createdAt:
                DateTime.tryParse(r['created_at']?.toString() ?? '') ??
                    DateTime.now(),
          ),
        );
      }

      final enriched = await _enrichItemsWithProfiles(uid, older, senderIds);
      if (mounted) {
        setState(() {
          _notifications = [..._notifications, ...enriched]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
      }
    } catch (e) {
      debugPrint('Load older notifications notice: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _markAllUnreadAsReadInDatabase() async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await supabase
          .from('user_notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false);
      BadgeCounterService.instance.markNotificationsReadOptimistic();
    } catch (e) {
      debugPrint('Notice: Updating is_read in database: $e');
    }
  }

  Future<void> _deleteNotification(NotificationItem item) async {
    HapticFeedback.lightImpact();
    setState(() {
      _hiddenLocalIds.add(item.id);
      _notifications.removeWhere((n) => n.id == item.id);
    });
    _staticCache = List.from(_notifications);
    _saveCacheToDisk(_notifications);

    if (!item.canDelete) return;
    final uid = currentUserId;
    if (uid == null) return;

    try {
      await supabase
          .from('user_notifications')
          .delete()
          .eq('id', item.id)
          .eq('user_id', uid);
      BadgeCounterService.instance.refreshCounts();
    } catch (e) {
      debugPrint('Delete notification error: $e');
    }
  }

  Future<void> _respondFollowRequest(
    NotificationItem item, {
    required bool accept,
  }) async {
    var reqId = item.requestId;
    final uid = currentUserId;
    if (uid == null || item.senderId.isEmpty) return;

    HapticFeedback.mediumImpact();
    setState(() => _busyRequestIds.add(item.id));

    try {
      if (reqId == null || reqId.isEmpty) {
        final reqRow = await supabase
            .from('follow_requests')
            .select('id')
            .eq('target_id', uid)
            .eq('requester_id', item.senderId)
            .eq('status', 'pending')
            .maybeSingle();
        reqId = reqRow?['id']?.toString();
      }

      bool ok = false;
      if (reqId != null && reqId.isNotEmpty) {
        ok = accept
            ? await SocialGraphService.instance.acceptFollowRequest(reqId)
            : await SocialGraphService.instance.rejectFollowRequest(reqId);
      }

      if (ok && mounted) {
        setState(() {
          if (accept) {
            _notifications = _notifications.map((n) {
              if (n.id == item.id) {
                return n.copyWith(
                  notificationType: 'follow',
                  title: 'New Follower',
                  message: 'started following you.',
                  isRead: true,
                );
              }
              return n;
            }).toList();
          } else {
            _notifications.removeWhere((n) => n.id == item.id);
          }
        });
        if (accept) {
          unawaited(
            NotificationService().sendNotificationToUser(
              targetUserId: item.senderId,
              title: 'Follow Accepted',
              message: 'accepted your follow request.',
              notificationType: 'follow',
              linkUrl: uid,
            ),
          );
        }
        BadgeCounterService.instance.refreshCounts();
      }
    } finally {
      if (mounted) setState(() => _busyRequestIds.remove(item.id));
    }
  }

  List<NotificationItem> get _filteredNotifications {
    if (_selectedFilter == 'All') return _notifications;
    if (_selectedFilter == 'Follows') {
      return _notifications
          .where((n) => n.isFollow || n.isFollowRequest)
          .toList();
    }
    if (_selectedFilter == 'Likes') {
      return _notifications.where((n) => n.isLike).toList();
    }
    if (_selectedFilter == 'Comments') {
      return _notifications.where((n) => n.isComment).toList();
    }
    if (_selectedFilter == 'Mentions') {
      return _notifications.where((n) => n.isMention).toList();
    }
    return _notifications;
  }

  /// Groups notifications chronologically AND coalesces repeated same-type likes/reposts on the same target.
  Map<String, List<NotificationItem>> _groupNotifications(
    List<NotificationItem> list,
  ) {
    final Map<String, List<NotificationItem>> rawBuckets = {
      'New': [],
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'Earlier': [],
    };

    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final yesterdayMidnight = todayMidnight.subtract(const Duration(days: 1));
    final weekMidnight = todayMidnight.subtract(const Duration(days: 7));

    for (final item in list) {
      if (!item.isRead) {
        rawBuckets['New']!.add(item);
      } else if (item.createdAt.isAfter(todayMidnight)) {
        rawBuckets['Today']!.add(item);
      } else if (item.createdAt.isAfter(yesterdayMidnight)) {
        rawBuckets['Yesterday']!.add(item);
      } else if (item.createdAt.isAfter(weekMidnight)) {
        rawBuckets['This Week']!.add(item);
      } else {
        rawBuckets['Earlier']!.add(item);
      }
    }

    final Map<String, List<NotificationItem>> coalesced = {};
    for (final entry in rawBuckets.entries) {
      if (entry.value.isEmpty) continue;
      coalesced[entry.key] = _coalesceSimilarItems(entry.value);
    }
    return coalesced;
  }

  List<NotificationItem> _coalesceSimilarItems(List<NotificationItem> items) {
    final List<NotificationItem> result = [];
    final Map<String, int> clusterIndexByKey = {};

    for (final item in items) {
      final link = item.linkUrl ?? '';
      final canCluster =
          (item.isLike || item.isRepost) && link.isNotEmpty && !item.isSystem;
      if (!canCluster) {
        result.add(item);
        continue;
      }

      final clusterKey = '${item.notificationType}_$link';
      final existingIdx = clusterIndexByKey[clusterKey];
      if (existingIdx == null) {
        clusterIndexByKey[clusterKey] = result.length;
        result.add(
          item.copyWith(
            groupAvatars:
                item.senderAvatar.isNotEmpty ? [item.senderAvatar] : const [],
            groupUsernames: [item.senderUsername],
          ),
        );
      } else {
        final head = result[existingIdx];
        if (head.groupUsernames.contains(item.senderUsername)) {
          continue;
        }
        final nextCount = head.groupCount + 1;
        final nextAvatars = [...head.groupAvatars];
        if (item.senderAvatar.isNotEmpty && nextAvatars.length < 3) {
          nextAvatars.add(item.senderAvatar);
        }
        final nextUsernames = [...head.groupUsernames, item.senderUsername];
        final othersCount = nextCount - 1;
        final targetNoun = item.isReel
            ? 'reel'
            : (item.isStory ? 'story' : 'post');
        final verb = item.isRepost ? 'reposted' : 'liked';

        result[existingIdx] = head.copyWith(
          groupCount: nextCount,
          groupAvatars: nextAvatars,
          groupUsernames: nextUsernames,
          canDelete: false,
          message:
              'and $othersCount other${othersCount == 1 ? '' : 's'} $verb your $targetNoun.',
        );
      }
    }
    return result;
  }

  Future<void> _toggleFollowUser(NotificationItem item) async {
    final uid = currentUserId;
    if (uid == null || item.senderId.isEmpty) return;

    HapticFeedback.mediumImpact();
    final prevState = item.isFollowingSender;

    setState(() {
      _notifications = _notifications.map((n) {
        if (n.senderId == item.senderId) {
          return n.copyWith(isFollowingSender: !prevState);
        }
        return n;
      }).toList();
    });

    final status = await SocialGraphService.instance.toggleFollow(item.senderId);
    if (!mounted) return;

    if (status == FollowToggleStatus.following) {
      unawaited(
        NotificationService().sendNotificationToUser(
          targetUserId: item.senderId,
          title: 'New Follower',
          message: 'followed you back on ZEV.',
          notificationType: 'follow',
          linkUrl: uid,
          senderId: uid,
        ),
      );
    } else if (status == FollowToggleStatus.error ||
        status == FollowToggleStatus.blocked) {
      setState(() {
        _notifications = _notifications.map((n) {
          if (n.senderId == item.senderId) {
            return n.copyWith(isFollowingSender: prevState);
          }
          return n;
        }).toList();
      });
    }
  }

  Future<void> _markAsRead(NotificationItem item) async {
    if (item.isRead) return;

    setState(() {
      _notifications = _notifications.map((n) {
        if (n.id == item.id) return n.copyWith(isRead: true);
        return n;
      }).toList();
    });

    if (!item.canDelete) return;
    try {
      await supabase
          .from('user_notifications')
          .update({'is_read': true})
          .eq('id', item.id);
      BadgeCounterService.instance.refreshCounts();
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    final uid = currentUserId;
    if (uid == null) return;

    HapticFeedback.lightImpact();
    setState(() {
      _notifications =
          _notifications.map((n) => n.copyWith(isRead: true)).toList();
    });

    try {
      await supabase
          .from('user_notifications')
          .update({'is_read': true})
          .eq('user_id', uid);
      BadgeCounterService.instance.markNotificationsReadOptimistic();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'All notifications marked as read',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: ZevColors.deepNavy,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error marking all read: $e');
    }
  }

  Future<void> _openNotificationTarget(NotificationItem item) async {
    _markAsRead(item);
    HapticFeedback.lightImpact();

    if (item.isGroupInvitation &&
        item.linkUrl != null &&
        item.linkUrl!.isNotEmpty) {
      final cleaned = item.linkUrl!
          .replaceFirst(RegExp(r'^/chat/'), '')
          .replaceFirst(RegExp(r'^conv:'), '')
          .trim();
      if (cleaned.isNotEmpty) {
        await ChatConversationScreen.open(
          context,
          conversationId: cleaned,
          isGroup: true,
        );
        return;
      }
    }

    if (item.isFollow || item.isFollowRequest) {
      if (item.senderId.isNotEmpty) {
        await ProfileScreen.open(context, userId: item.senderId);
      }
      return;
    }

    if (item.isReel && item.linkUrl != null && item.linkUrl!.isNotEmpty) {
      final reelId = item.linkUrl!;
      try {
        final res = await supabase
            .from('reels')
            .select(
              'id, user_id, title, description, video_url, thumbnail_url, category, views_count, likes_count, comments_count, created_at',
            )
            .eq('id', reelId)
            .maybeSingle();

        if (res != null && mounted) {
          final reel = ReelItem(
            id: res['id'].toString(),
            userId: res['user_id']?.toString() ?? '',
            authorUsername: item.senderUsername,
            authorFullName: item.senderFullName,
            authorAvatar: item.senderAvatar,
            isVerified: item.isSenderVerified,
            videoUrl: res['video_url']?.toString() ?? '',
            thumbnailUrl: res['thumbnail_url']?.toString(),
            title: res['title']?.toString() ?? '',
            description: res['description']?.toString() ?? '',
            viewsCount: (res['views_count'] as num?)?.toInt() ?? 0,
            likesCount: (res['likes_count'] as num?)?.toInt() ?? 0,
            commentsCount: (res['comments_count'] as num?)?.toInt() ?? 0,
            createdAt:
                DateTime.tryParse(res['created_at']?.toString() ?? '') ??
                    DateTime.now(),
          );

          await Navigator.of(context).push(
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
    }

    if (!mounted) return;

    if (item.isStory) {
      final rawLink = (item.linkUrl ?? '').trim();
      final cleanStoryId = rawLink.replaceFirst(RegExp(r'^/story/'), '').trim();
      final isUuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(cleanStoryId);
      if (isUuid && cleanStoryId != item.senderId) {
        await StoryViewerScreen.openByStoryId(
          context,
          storyId: cleanStoryId,
          fallbackUserId: item.senderId,
        );
        return;
      }
      if (item.senderId.isNotEmpty) {
        await ProfileScreen.open(context, userId: item.senderId);
        return;
      }
    }

    if ((item.isLike || item.isComment || item.isMention || item.isRepost) &&
        item.linkUrl != null &&
        item.linkUrl!.isNotEmpty) {
      PostDetailScreen.open(context, postId: item.linkUrl!);
      return;
    }

    if (item.linkUrl != null && item.linkUrl!.startsWith('/')) {
      final uri = Uri.tryParse(item.linkUrl!);
      if (uri != null) {
        await DeepLinkService.instance.handleUri(uri);
        return;
      }
    }

    if (item.senderId.isNotEmpty && item.senderId != currentUserId) {
      ProfileScreen.open(context, userId: item.senderId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;
    final filtered = _filteredNotifications;
    final grouped = _groupNotifications(filtered);

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: ZevColors.deepNavy.withValues(alpha: 0.06),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Text(
              'Notifications',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
                letterSpacing: -0.4,
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.5,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  gradient: ZevColors.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.secondaryBlue.withValues(alpha: 0.28),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '$unreadCount new',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (unreadCount > 0)
            IconButton(
              icon: const Icon(
                Icons.done_all_rounded,
                color: ZevColors.secondaryBlue,
                size: 22,
              ),
              tooltip: 'Mark all as read',
              onPressed: _markAllAsRead,
            ),
          IconButton(
            icon: const Icon(
              Icons.tune_rounded,
              color: ZevColors.deepNavy,
              size: 21,
            ),
            tooltip: 'Notification Settings',
            onPressed: () => NotificationSettingsScreen.open(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildCategoryFilterRow(),
            Expanded(
              child: RefreshIndicator(
                color: ZevColors.primaryBlue,
                onRefresh: () => _fetchActivity(isBackgroundSync: false),
                child: _isLoading && _notifications.isEmpty
                    ? _buildLoadingShimmer()
                    : filtered.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _scrollCtrl,
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(14, 6, 14, 40),
                            itemCount:
                                grouped.keys.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= grouped.keys.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 18),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: ZevColors.primaryBlue,
                                    ),
                                  ),
                                );
                              }

                              final groupTitle = grouped.keys.elementAt(index);
                              final groupItems = grouped[groupTitle]!;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      14,
                                      8,
                                      8,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          groupTitle,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                            color: ZevColors.deepNavy,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        if (groupTitle == 'New') ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: const BoxDecoration(
                                              color: ZevColors.secondaryBlue,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: groupItems.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (_, itemIdx) {
                                      return _buildNotificationCard(
                                        groupItems[itemIdx],
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilterRow() {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = filter == _selectedFilter;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedFilter = filter);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                gradient: isSelected ? ZevColors.brandGradient : null,
                color: isSelected ? null : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : ZevColors.border,
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: ZevColors.secondaryBlue.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: ZevColors.deepNavy.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Center(
                child: Text(
                  filter,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    color: isSelected ? Colors.white : ZevColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard(NotificationItem item) {
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openNotificationTarget(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: item.isRead
                ? ZevColors.border
                : ZevColors.primaryBlue.withValues(alpha: 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: item.isRead
                  ? ZevColors.deepNavy.withValues(alpha: 0.04)
                  : ZevColors.secondaryBlue.withValues(alpha: 0.09),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.9),
              blurRadius: 2,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                if (item.senderId.isNotEmpty) {
                  ProfileScreen.open(context, userId: item.senderId);
                }
              },
              child: _buildAvatarOrCluster(item),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        color: ZevColors.deepNavy,
                        height: 1.35,
                      ),
                      children: [
                        TextSpan(
                          text: item.isSystem || item.senderUsername == 'ZEV'
                              ? '${item.title} '
                              : (item.senderUsername.startsWith('@')
                                  ? '${item.senderUsername} '
                                  : '@${item.senderUsername} '),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: (item.isSystem || item.senderUsername == 'ZEV')
                                ? ZevColors.primaryBlue
                                : ZevColors.deepNavy,
                          ),
                        ),
                        TextSpan(
                          text: '${item.message} ',
                          style: TextStyle(
                            fontWeight:
                                item.isRead ? FontWeight.w500 : FontWeight.w700,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        TextSpan(
                          text: '• ${TimeAgo.format(item.createdAt)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: item.isRead
                                ? ZevColors.textMuted
                                : ZevColors.secondaryBlue,
                            fontWeight:
                                item.isRead ? FontWeight.w500 : FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _buildRightAction(item),
          ],
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteNotification(item),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: ZevColors.errorRed.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: ZevColors.errorRed.withValues(alpha: 0.35),
          ),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: ZevColors.errorRed,
        ),
      ),
      child: card,
    );
  }

  Widget _buildAvatarOrCluster(NotificationItem item) {
    if (item.groupCount > 1 && item.groupAvatars.length >= 2) {
      return SizedBox(
        width: 52,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: CircleAvatar(
                radius: 17,
                backgroundColor: const Color(0xFFE2E8F0),
                backgroundImage:
                    CachedNetworkImageProvider(item.groupAvatars[0]),
              ),
            ),
            Positioned(
              right: 2,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFFE2E8F0),
                  backgroundImage:
                      CachedNetworkImageProvider(item.groupAvatars[1]),
                ),
              ),
            ),
            Positioned(
              bottom: -2,
              right: -2,
              child: _buildBadgeForType(item.notificationType),
            ),
          ],
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: ZevColors.deepNavy.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 23,
            backgroundColor: const Color(0xFFE2E8F0),
            backgroundImage: item.senderAvatar.isNotEmpty
                ? CachedNetworkImageProvider(item.senderAvatar)
                : null,
            child: item.senderAvatar.isEmpty
                ? (item.isSystem
                    ? const Icon(
                        Icons.star_rounded,
                        color: ZevColors.primaryBlue,
                        size: 24,
                      )
                    : const Icon(
                        Icons.person,
                        color: Color(0xFF94A3B8),
                        size: 22,
                      ))
                : null,
          ),
        ),
        Positioned(
          bottom: -2,
          right: -2,
          child: _buildBadgeForType(item.notificationType),
        ),
      ],
    );
  }

  Widget _buildBadgeForType(String type) {
    IconData icon;
    List<Color> gradientColors;

    if (type == 'follow_request') {
      icon = Icons.person_add_alt_1_rounded;
      gradientColors = [const Color(0xFF6366F1), const Color(0xFF4F46E5)];
    } else if (type.contains('follow')) {
      icon = Icons.person_add_rounded;
      gradientColors = [ZevColors.primaryBlue, ZevColors.secondaryBlue];
    } else if (type == 'group_invitation') {
      icon = Icons.group_add_rounded;
      gradientColors = [const Color(0xFF10B981), const Color(0xFF059669)];
    } else if (type.contains('repost')) {
      icon = Icons.repeat_rounded;
      gradientColors = [const Color(0xFF10B981), const Color(0xFF059669)];
    } else if (type.contains('story')) {
      icon = Icons.star_rounded;
      gradientColors = [const Color(0xFFFF8A00), const Color(0xFFE52E71)];
    } else if (type.contains('reel')) {
      icon = Icons.play_arrow_rounded;
      gradientColors = [const Color(0xFF8B5CF6), const Color(0xFF6D28D9)];
    } else if (type.contains('comment') || type.contains('reply')) {
      icon = Icons.chat_bubble_rounded;
      gradientColors = [const Color(0xFF06B6D4), const Color(0xFF0891B2)];
    } else if (type.contains('mention') || type.contains('tag')) {
      icon = Icons.alternate_email_rounded;
      gradientColors = [const Color(0xFFF59E0B), const Color(0xFFD97706)];
    } else if (type.contains('system') || type.contains('verified')) {
      icon = Icons.verified_rounded;
      gradientColors = [const Color(0xFF10B981), const Color(0xFF059669)];
    } else {
      icon = Icons.favorite_rounded;
      gradientColors = [const Color(0xFFFF4D6D), const Color(0xFFC9184A)];
    }

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white, width: 1.8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      child: Center(child: Icon(icon, color: Colors.white, size: 10.5)),
    );
  }

  Widget _buildRightAction(NotificationItem item) {
    if (item.isFollowRequest) {
      final isBusy = _busyRequestIds.contains(item.id);
      if (isBusy) {
        return const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _respondFollowRequest(item, accept: true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
              decoration: BoxDecoration(
                gradient: ZevColors.brandGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Confirm',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _respondFollowRequest(item, accept: false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6.5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (item.isFollow) {
      final isFollowing = item.isFollowingSender;
      return GestureDetector(
        onTap: () => _toggleFollowUser(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            gradient: isFollowing ? null : ZevColors.brandGradient,
            color: isFollowing ? const Color(0xFFF1F5F9) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isFollowing ? const Color(0xFFCBD5E1) : Colors.transparent,
              width: 1,
            ),
            boxShadow: isFollowing
                ? null
                : [
                    BoxShadow(
                      color: ZevColors.secondaryBlue.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Text(
            isFollowing ? 'Following' : 'Follow Back',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isFollowing ? ZevColors.textSecondary : Colors.white,
            ),
          ),
        ),
      );
    }

    if (item.mediaThumbnail != null && item.mediaThumbnail!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: ZevColors.deepNavy.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: item.mediaThumbnail!,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    Container(color: const Color(0xFFE2E8F0)),
                errorWidget: (_, _, _) =>
                    Container(color: const Color(0xFFE2E8F0)),
              ),
              if (item.isReel)
                const Positioned(
                  top: 3,
                  right: 3,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 14,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (!item.isRead) {
      return Container(
        width: 8.5,
        height: 8.5,
        decoration: BoxDecoration(
          color: ZevColors.secondaryBlue,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: ZevColors.secondaryBlue.withValues(alpha: 0.5),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildLoadingShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: ZevColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Color(0xFFE2E8F0),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 140,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 210,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: ZevColors.border, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.deepNavy.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  size: 44,
                  color: ZevColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No Notifications Yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'When people like, comment, follow, or mention you on ZEV, all alerts appear right here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: ZevColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
