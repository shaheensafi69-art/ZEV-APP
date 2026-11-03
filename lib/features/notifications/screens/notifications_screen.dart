import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/time_ago.dart';
import '../../feed/models/feed_post_item.dart';
import '../../feed/widgets/feed_post_card.dart';
import '../../profile/screens/profile_screen.dart';
import '../../reels/models/reel_item.dart';
import '../../reels/widgets/reel_player_item.dart';
import '../models/notification_item.dart';

/// Flagship Instagram-Caliber Notifications & Activity Screen for ZEV.
/// Features:
/// - Real-time incoming activity (Follows, Likes, Comments, Story Likes, Mentions)
/// - Time-grouped sections (Today, Yesterday, This Week, Earlier)
/// - Claymorphic category filter pills (All, Follows, Likes, Comments)
/// - Instant 1-tap "Follow Back" with optimistic state
/// - Real-time Supabase subscription
/// - Direct deep-link navigation to sender profiles, posts, and reels
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  /// Opens the notifications screen with standard iOS/Android page transition
  static Future<void> open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NotificationsScreen(),
      ),
    );
  }

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<NotificationItem> _notifications = [];
  String _selectedFilter = "All"; // "All", "Follows", "Likes", "Comments"
  RealtimeChannel? _realtimeChannel;

  final List<String> _filters = ["All", "Follows", "Likes", "Comments"];

  @override
  void initState() {
    super.initState();
    _fetchActivity();
    _subscribeToRealtimeNotifications();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  /// Sets up live real-time listener for incoming notifications
  void _subscribeToRealtimeNotifications() {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      _realtimeChannel = supabase
          .channel('public:user_notifications:$currentUserId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'user_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: currentUserId,
            ),
            callback: (payload) {
              _handleIncomingNotification(payload.newRecord);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint("Realtime notifications subscription notice: $e");
    }
  }

  Future<void> _handleIncomingNotification(Map<String, dynamic> record) async {
    final senderId = record['sender_id']?.toString() ?? '';
    if (senderId.isEmpty) return;

    // Direct Messages and Chats belong exclusively in the Direct Chat module, not social notifications
    final type = record['notification_type']?.toString().toLowerCase() ?? '';
    if (type == 'chat' || type == 'message' || type == 'direct_message') return;

    try {
      // Fetch sender profile
      final prof = await supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified')
          .eq('id', senderId)
          .maybeSingle();

      if (prof != null && mounted) {
        final currentUserId = supabase.auth.currentUser?.id ?? '';
        bool isFollowing = false;
        if (currentUserId.isNotEmpty) {
          final followCheck = await supabase
              .from('user_follows')
              .select('id')
              .eq('follower_id', currentUserId)
              .eq('following_id', senderId)
              .maybeSingle();
          isFollowing = followCheck != null;
        }

        final newItem = NotificationItem(
          id: record['id']?.toString() ?? 'notif_${DateTime.now().millisecondsSinceEpoch}',
          userId: currentUserId,
          senderId: senderId,
          senderUsername: prof['username'] ?? 'user',
          senderFullName: "${prof['first_name'] ?? ''} ${prof['last_name'] ?? ''}".trim(),
          senderAvatar: prof['avatar_url'] ?? '',
          isSenderVerified: prof['is_verified'] == true,
          title: record['title'] ?? '',
          message: record['message'] ?? '',
          notificationType: record['notification_type'] ?? 'like',
          linkUrl: record['link_url'],
          isRead: false,
          createdAt: DateTime.tryParse(record['created_at']?.toString() ?? '') ?? DateTime.now(),
          isFollowingSender: isFollowing,
        );

        HapticFeedback.mediumImpact();
        setState(() {
          _notifications.insert(0, newItem);
        });
      }
    } catch (e) {
      debugPrint("Error handling real-time notification: $e");
    }
  }

  /// Aggregates real notifications from `user_notifications` and joins with Supabase activity
  Future<void> _fetchActivity() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final List<NotificationItem> items = [];
      final Set<String> allSenderIds = {};

      // 1. Fetch user_notifications records (strictly excluding chat & direct messages)
      try {
        final notifsRes = await supabase
            .from('user_notifications')
            .select(
              'id, user_id, sender_id, title, message, notification_type, link_url, is_read, created_at',
            )
            .eq('user_id', currentUserId)
            .not('notification_type', 'in', '("chat","message","direct_message")')
            .order('created_at', ascending: false)
            .limit(60);

        for (final r in notifsRes) {
          final sId = r['sender_id']?.toString() ?? '';
          final nType = r['notification_type']?.toString().toLowerCase() ?? '';
          if (nType == 'chat' || nType == 'message' || nType == 'direct_message') continue;

          if (sId.isNotEmpty && sId != currentUserId) {
            allSenderIds.add(sId);
            items.add(NotificationItem(
              id: r['id']?.toString() ?? '',
              userId: currentUserId,
              senderId: sId,
              senderUsername: 'user',
              title: r['title'] ?? '',
              message: r['message'] ?? '',
              notificationType: r['notification_type'] ?? 'like',
              linkUrl: r['link_url'],
              isRead: r['is_read'] == true,
              createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
            ));
          }
        }
      } catch (e) {
        debugPrint("user_notifications query notice: $e");
      }

      // 2. Fetch incoming real follows from `user_follows`
      try {
        final followsRes = await supabase
            .from('user_follows')
            .select('id, follower_id, following_id, created_at')
            .eq('following_id', currentUserId)
            .order('created_at', ascending: false)
            .limit(30);

        for (final f in followsRes) {
          final followerId = f['follower_id']?.toString() ?? '';
          if (followerId.isNotEmpty && followerId != currentUserId) {
            allSenderIds.add(followerId);

            // Avoid duplicate if already present in user_notifications
            final alreadyAdded = items.any(
              (it) => it.senderId == followerId && it.notificationType == 'follow',
            );

            if (!alreadyAdded) {
              items.add(NotificationItem(
                id: 'follow_${f['id']}',
                userId: currentUserId,
                senderId: followerId,
                senderUsername: 'user',
                title: "New Follower",
                message: "started following you.",
                notificationType: "follow",
                isRead: true,
                createdAt: DateTime.tryParse(f['created_at']?.toString() ?? '') ?? DateTime.now(),
              ));
            }
          }
        }
      } catch (e) {
        debugPrint("user_follows query notice: $e");
      }

      // 3. Fetch likes on current user's reels
      try {
        final myReels = await supabase
            .from('reels')
            .select('id, title, thumbnail_url')
            .eq('user_id', currentUserId)
            .limit(15);

        if (myReels.isNotEmpty) {
          final reelIds = myReels.map((r) => r['id'].toString()).toList();
          final Map<String, String?> reelThumbs = {
            for (var r in myReels) r['id'].toString(): r['thumbnail_url']?.toString(),
          };

          final reelLikes = await supabase
              .from('reel_likes')
              .select('id, reel_id, user_id, created_at')
              .inFilter('reel_id', reelIds)
              .neq('user_id', currentUserId)
              .order('created_at', ascending: false)
              .limit(20);

          for (final l in reelLikes) {
            final uId = l['user_id']?.toString() ?? '';
            final rId = l['reel_id']?.toString() ?? '';
            if (uId.isNotEmpty) {
              allSenderIds.add(uId);
              final alreadyAdded = items.any(
                (it) => it.senderId == uId && it.linkUrl == rId && it.notificationType == 'reel_like',
              );
              if (!alreadyAdded) {
                items.add(NotificationItem(
                  id: 'reellike_${l['id']}',
                  userId: currentUserId,
                  senderId: uId,
                  senderUsername: 'user',
                  title: "Reel Liked",
                  message: "liked your reel.",
                  notificationType: "reel_like",
                  linkUrl: rId,
                  mediaThumbnail: reelThumbs[rId],
                  isRead: true,
                  createdAt: DateTime.tryParse(l['created_at']?.toString() ?? '') ?? DateTime.now(),
                ));
              }
            }
          }
        }
      } catch (e) {
        debugPrint("reel_likes query notice: $e");
      }

      // 4. Batch fetch author profiles for all senders
      Map<String, Map<String, dynamic>> profilesMap = {};
      if (allSenderIds.isNotEmpty) {
        final profsRes = await supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .inFilter('id', allSenderIds.toList());

        for (final p in profsRes) {
          profilesMap[p['id'].toString()] = p;
        }
      }

      // 5. Batch check who the current user is following
      Set<String> myFollowing = {};
      if (allSenderIds.isNotEmpty) {
        final followCheck = await supabase
            .from('user_follows')
            .select('following_id')
            .eq('follower_id', currentUserId)
            .inFilter('following_id', allSenderIds.toList());

        for (final f in followCheck) {
          final fId = f['following_id']?.toString() ?? '';
          if (fId.isNotEmpty) myFollowing.add(fId);
        }
      }

      // 6. Enrich items with sender profiles & follow state
      final List<NotificationItem> enriched = [];
      for (final item in items) {
        final profile = profilesMap[item.senderId] ?? {};
        final username = profile['username'] ?? 'user';
        final fullName = "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}".trim();
        final avatar = profile['avatar_url'] ?? '';
        final isVerified = profile['is_verified'] == true;
        final isFollowing = myFollowing.contains(item.senderId);

        enriched.add(item.copyWith(
          senderUsername: username,
          senderFullName: fullName,
          senderAvatar: avatar,
          isSenderVerified: isVerified,
          isFollowingSender: isFollowing,
        ));
      }

      // Sort newest first
      enriched.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _notifications = enriched;
          _isLoading = false;
        });
      }

      // Automatically update the database so system knows the user has seen these notifications
      _markAllUnreadAsReadInDatabase();
    } catch (e) {
      debugPrint("Notifications fetch error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Automatically marks all unread notifications as read in the database upon viewing
  Future<void> _markAllUnreadAsReadInDatabase() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;
    try {
      await supabase
          .from('user_notifications')
          .update({'is_read': true})
          .eq('user_id', currentUserId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint("Notice: Updating is_read in database: $e");
    }
  }

  /// Filters items based on selected category pill
  List<NotificationItem> get _filteredNotifications {
    if (_selectedFilter == "All") return _notifications;
    if (_selectedFilter == "Follows") {
      return _notifications.where((n) => n.notificationType == 'follow').toList();
    }
    if (_selectedFilter == "Likes") {
      return _notifications.where((n) => n.notificationType.contains('like')).toList();
    }
    if (_selectedFilter == "Comments") {
      return _notifications
          .where((n) => n.notificationType.contains('comment') || n.notificationType.contains('reply'))
          .toList();
    }
    return _notifications;
  }

  /// Groups notifications chronologically (Today, Yesterday, This Week, Earlier)
  Map<String, List<NotificationItem>> _groupNotifications(List<NotificationItem> list) {
    final Map<String, List<NotificationItem>> groups = {
      "Today": [],
      "Yesterday": [],
      "This Week": [],
      "Earlier": [],
    };

    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final yesterdayMidnight = todayMidnight.subtract(const Duration(days: 1));
    final weekMidnight = todayMidnight.subtract(const Duration(days: 7));

    for (final item in list) {
      if (item.createdAt.isAfter(todayMidnight)) {
        groups["Today"]!.add(item);
      } else if (item.createdAt.isAfter(yesterdayMidnight)) {
        groups["Yesterday"]!.add(item);
      } else if (item.createdAt.isAfter(weekMidnight)) {
        groups["This Week"]!.add(item);
      } else {
        groups["Earlier"]!.add(item);
      }
    }

    // Remove empty groups
    groups.removeWhere((key, value) => value.isEmpty);
    return groups;
  }

  /// Handles 1-tap Follow / Unfollow directly from notification card
  Future<void> _toggleFollowUser(NotificationItem item) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    HapticFeedback.mediumImpact();
    final newFollowState = !item.isFollowingSender;

    // Optimistic UI update
    setState(() {
      _notifications = _notifications.map((n) {
        if (n.senderId == item.senderId) {
          return n.copyWith(isFollowingSender: newFollowState);
        }
        return n;
      }).toList();
    });

    try {
      if (newFollowState) {
        await supabase.from('user_follows').insert({
          'follower_id': currentUserId,
          'following_id': item.senderId,
          'created_at': DateTime.now().toIso8601String(),
        });

        // Notify user of follow back
        unawaited(NotificationService().sendNotificationToUser(
          targetUserId: item.senderId,
          title: "New Follower",
          message: "Followed you back on ZEV",
          notificationType: "follow",
          senderId: currentUserId,
        ));
      } else {
        await supabase
            .from('user_follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', item.senderId);
      }
    } catch (e) {
      debugPrint("Error toggling follow from notification: $e");
      // Revert optimistic update on error
      if (mounted) {
        setState(() {
          _notifications = _notifications.map((n) {
            if (n.senderId == item.senderId) {
              return n.copyWith(isFollowingSender: !newFollowState);
            }
            return n;
          }).toList();
        });
      }
    }
  }

  /// Marks a specific notification as read in Supabase
  Future<void> _markAsRead(NotificationItem item) async {
    if (item.isRead) return;

    setState(() {
      _notifications = _notifications.map((n) {
        if (n.id == item.id) return n.copyWith(isRead: true);
        return n;
      }).toList();
    });

    try {
      if (!item.id.startsWith('follow_') && !item.id.startsWith('reellike_')) {
        await supabase
            .from('user_notifications')
            .update({'is_read': true})
            .eq('id', item.id);
      }
    } catch (_) {}
  }

  /// Marks all notifications as read
  Future<void> _markAllAsRead() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    HapticFeedback.lightImpact();
    setState(() {
      _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    });

    try {
      await supabase
          .from('user_notifications')
          .update({'is_read': true})
          .eq('user_id', currentUserId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "All notifications marked as read",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: ZevColors.deepNavy,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error marking all read: $e");
    }
  }

  /// Deep-links to sender profile, post, or reel
  void _openNotificationTarget(NotificationItem item) async {
    _markAsRead(item);
    HapticFeedback.lightImpact();

    // 1. Follow notification -> Open Profile
    if (item.notificationType == 'follow') {
      ProfileScreen.open(context, userId: item.senderId);
      return;
    }

    // 2. Reel Like or Reel Comment -> Open Reel Player
    if (item.notificationType == 'reel_like' ||
        (item.linkUrl != null && item.title.toLowerCase().contains('reel'))) {
      final reelId = item.linkUrl;
      if (reelId != null && reelId.isNotEmpty) {
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
      }
    }

    // 3. Post Like or Post Comment -> Open Post Detail
    if (item.notificationType == 'like' || item.notificationType == 'comment') {
      final postId = item.linkUrl;
      if (postId != null && postId.isNotEmpty) {
        try {
          final res = await supabase
              .from('discussion_posts')
              .select('id, student_id, title, content, image_url, created_at')
              .eq('id', postId)
              .maybeSingle();

          if (res != null && mounted) {
            final post = FeedPostItem(
              id: res['id'].toString(),
              authorId: res['student_id']?.toString() ?? '',
              authorUsername: item.senderUsername,
              authorFullName: item.senderFullName,
              authorAvatar: item.senderAvatar,
              isVerified: item.isSenderVerified,
              title: res['title'] ?? '',
              content: res['content'] ?? '',
              imageUrl: res['image_url'] ?? '',
              createdAt: DateTime.now(),
            );

            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: const Color(0xFFF1F5F9),
                  appBar: AppBar(
                    backgroundColor: Colors.white,
                    foregroundColor: ZevColors.deepNavy,
                    title: const Text("Post Activity"),
                  ),
                  body: SingleChildScrollView(
                    child: FeedPostCard(
                      post: post,
                      onCommentsUpdated: () {},
                    ),
                  ),
                ),
              ),
            );
            return;
          }
        } catch (_) {}
      }
    }

    // Default fallback: open sender's profile
    if (mounted) {
      ProfileScreen.open(context, userId: item.senderId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;
    final filtered = _filteredNotifications;
    final grouped = _groupNotifications(filtered);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF0F172A),
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Text(
              "Notifications",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.4,
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ZevColors.primaryBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "$unreadCount new",
                  style: const TextStyle(
                    color: ZevColors.deepNavy,
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
                color: ZevColors.primaryBlue,
                size: 22,
              ),
              tooltip: "Mark all as read",
              onPressed: _markAllAsRead,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Category Filter Pills
            _buildCategoryFilterRow(),

            // Notifications List / Groups
            Expanded(
              child: RefreshIndicator(
                color: ZevColors.primaryBlue,
                onRefresh: _fetchActivity,
                child: _isLoading
                    ? _buildLoadingShimmer()
                    : filtered.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
                            itemCount: grouped.keys.length,
                            itemBuilder: (context, index) {
                              final groupTitle = grouped.keys.elementAt(index);
                              final groupItems = grouped[groupTitle]!;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                                    child: Text(
                                      groupTitle,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0F172A),
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: groupItems.length,
                                    separatorBuilder: (context, index) => const SizedBox(height: 7),
                                    itemBuilder: (context, itemIdx) {
                                      final item = groupItems[itemIdx];
                                      return _buildNotificationCard(item);
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

  /// Category Filter Pills (All, Follows, Likes, Comments)
  Widget _buildCategoryFilterRow() {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
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
                color: isSelected ? ZevColors.primaryBlue : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.white,
                  width: 1.2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
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
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? ZevColors.deepNavy : const Color(0xFF475569),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Individual Instagram-style notification item card (user cannot delete)
  Widget _buildNotificationCard(NotificationItem item) {
    return GestureDetector(
      onTap: () => _openNotificationTarget(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: item.isRead ? Colors.white : const Color(0xFFF0FDF4).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: item.isRead
                ? Colors.white
                : ZevColors.primaryBlue.withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
            children: [
              // Avatar with Activity Badge overlay
              GestureDetector(
                onTap: () => ProfileScreen.open(context, userId: item.senderId),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 23,
                      backgroundColor: const Color(0xFFE2E8F0),
                      backgroundImage: item.senderAvatar.isNotEmpty
                          ? CachedNetworkImageProvider(item.senderAvatar)
                          : null,
                      child: item.senderAvatar.isEmpty
                          ? const Icon(Icons.person, color: Color(0xFF94A3B8), size: 22)
                          : null,
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: _buildBadgeForType(item.notificationType),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Notification Text Content
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
                          color: Color(0xFF0F172A),
                          height: 1.35,
                        ),
                        children: [
                          TextSpan(
                            text: "@${item.senderUsername} ",
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          TextSpan(
                            text: "${item.message} ",
                            style: TextStyle(
                              fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w600,
                              color: const Color(0xFF334155),
                            ),
                          ),
                          TextSpan(
                            text: TimeAgo.format(item.createdAt),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Right Action: Follow Button or Media Thumbnail
              _buildRightAction(item),
            ],
          ),
        ),
      );
    }

  /// Badge indicator at the bottom-right corner of the sender avatar
  Widget _buildBadgeForType(String type) {
    IconData icon;
    List<Color> gradientColors;

    switch (type) {
      case 'follow':
        icon = Icons.person_add_rounded;
        gradientColors = [const Color(0xFF00B4D8), const Color(0xFF0077B6)];
        break;
      case 'story_like':
        icon = Icons.favorite_rounded;
        gradientColors = [const Color(0xFFFF9E00), const Color(0xFFFF0054)];
        break;
      case 'reel_like':
        icon = Icons.play_arrow_rounded;
        gradientColors = [const Color(0xFF8338EC), const Color(0xFF3A86FF)];
        break;
      case 'comment':
      case 'reply':
        icon = Icons.chat_bubble_rounded;
        gradientColors = [const Color(0xFF00E5FF), const Color(0xFF0091EA)];
        break;
      case 'like':
      default:
        icon = Icons.favorite_rounded;
        gradientColors = [const Color(0xFFFF4D6D), const Color(0xFFC9184A)];
        break;
    }

    return Container(
      width: 19,
      height: 19,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Icon(icon, color: Colors.white, size: 10),
      ),
    );
  }

  /// Right side of notification: Follow Back button or Media Preview Thumbnail
  Widget _buildRightAction(NotificationItem item) {
    if (item.notificationType == 'follow') {
      final isFollowing = item.isFollowingSender;
      return GestureDetector(
        onTap: () => _toggleFollowUser(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isFollowing ? const Color(0xFFF1F5F9) : ZevColors.primaryBlue,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFollowing ? const Color(0xFFCBD5E1) : Colors.transparent,
              width: 1,
            ),
            boxShadow: isFollowing
                ? []
                : [
                    BoxShadow(
                      color: ZevColors.primaryBlue.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Text(
            isFollowing ? "Following" : "Follow Back",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isFollowing ? const Color(0xFF475569) : ZevColors.deepNavy,
            ),
          ),
        ),
      );
    }

    // Media Thumbnail for Post, Reel, or Story
    if (item.mediaThumbnail != null && item.mediaThumbnail!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: item.mediaThumbnail!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: const Color(0xFFE2E8F0)),
                errorWidget: (context, url, error) => Container(color: const Color(0xFFE2E8F0)),
              ),
              if (item.notificationType == 'reel_like')
                const Positioned(
                  top: 4,
                  right: 4,
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

    // Unread indicator dot if no media thumbnail
    if (!item.isRead) {
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: ZevColors.primaryBlue,
          shape: BoxShape.circle,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildLoadingShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
      itemCount: 8,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) => Container(
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 38,
                color: ZevColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "No Notifications Yet",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "When people follow you, like your posts, reels, or stories, you'll see them here.",
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.35),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchActivity,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text("Refresh Activity"),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: ZevColors.deepNavy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

