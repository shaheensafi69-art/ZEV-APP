import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/badge_counter_service.dart';
import '../../../core/services/feed_algorithm_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/services/zev_ads_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_native_ad_card.dart';
import '../../../core/widgets/zev_skeleton.dart';
import '../models/feed_post_item.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/feed_stories_tray.dart';
import '../../stories/screens/create_story_screen.dart';
import '../../stories/screens/story_viewer_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../discover/screens/discover_screen.dart';
import '../../live/screens/live_rooms_screen.dart';
import 'create_post_screen.dart';

/// Next-Generation Instagram-Grade Home Feed Screen for ZEV.
/// Engineered with buttery-smooth 120 FPS sliver rendering, live Stories carousel,
/// real-time like/comment telemetry, and official brand palette (#00D4FF / #080D1A).
class FeedViewerScreen extends StatefulWidget {
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenNotifications;

  const FeedViewerScreen({
    super.key,
    this.onOpenMessages,
    this.onOpenNotifications,
  });

  @override
  State<FeedViewerScreen> createState() => _FeedViewerScreenState();
}

class _FeedViewerScreenState extends State<FeedViewerScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  bool _followingOnly = false;
  DateTime? _cursorCreatedAt;
  String? _cursorId;
  int _fetchGeneration = 0;
  static const int _pageSize = 20;
  final Set<String> _loadedPostIds = <String>{};
  String? _errorMsg;
  List<FeedPostItem> _posts = [];
  ActiveFriendStory? _myActiveStory;
  List<ActiveFriendStory> _stories = [];
  List<Map<String, dynamic>> _suggestedUsers = [];
  final Set<String> _followedSuggestedIds = {};
  final Set<String> _requestedSuggestedIds = {};
  bool _dismissSuggestedCarousel = false;
  String _myAvatarUrl = '';

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
    _fetchFeedData();
    BadgeCounterService.instance.startListening();
  }

  Future<void> _loadMyProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() => _myAvatarUrl = res['avatar_url'] ?? '');
      }
    } catch (_) {}
  }

  Future<void> _fetchFeedData() async {
    try {
      await Future.wait([
        _fetchStories(),
        _fetchPosts(),
        _fetchSuggestedUsers(),
      ]);
    } catch (e) {
      debugPrint("Feed data fetch warning: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSuggestedUsers() async {
    final currentUserId = supabase.auth.currentUser?.id;
    try {
      final results = await Future.wait<dynamic>([
        SocialGraphService.instance.fetchSafetyFilters(),
        supabase
            .from('profiles')
            .select(
              'id, username, first_name, last_name, avatar_url, is_verified',
            )
            .neq('id', currentUserId ?? '')
            .limit(20),
        if (currentUserId != null)
          supabase
              .from('user_follows')
              .select('following_id')
              .eq('follower_id', currentUserId),
      ]);

      final filters = results[0] as UserSafetyFilters;
      final res = results[1] as List;
      final alreadyFollowing = <String>{};
      if (results.length > 2) {
        for (final f in (results[2] as List)) {
          final fid = f['following_id']?.toString() ?? '';
          if (fid.isNotEmpty) alreadyFollowing.add(fid);
        }
      }

      final list = res
          .where((p) {
            final id = p['id']?.toString() ?? '';
            return id.isNotEmpty &&
                !filters.blockedUserIds.contains(id) &&
                !alreadyFollowing.contains(id);
          })
          .take(8)
          .map((p) {
            final fn = p['first_name'] ?? '';
            final ln = p['last_name'] ?? '';
            final full = "$fn $ln".trim();
            return {
              'id': p['id'].toString(),
              'username': p['username'] ?? (full.isNotEmpty ? full : 'user'),
              'name': full.isNotEmpty ? full : (p['username'] ?? 'User'),
              'avatar_url': p['avatar_url'] ?? '',
              'is_verified': p['is_verified'] == true,
            };
          })
          .toList();

      if (mounted) {
        setState(() => _suggestedUsers = list);
      }
    } catch (e) {
      debugPrint("Suggested users warning: $e");
    }
  }

  Future<void> _fetchStories() async {
    final currentUserId = supabase.auth.currentUser?.id;
    try {
      final results = await Future.wait<dynamic>([
        SocialGraphService.instance.fetchSafetyFilters(),
        supabase.rpc('get_story_feed_trays'),
      ]);

      final filters = results[0] as UserSafetyFilters;
      final rawRows = (results[1] is List)
          ? List<Map<String, dynamic>>.from(
              (results[1] as List).map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : <Map<String, dynamic>>[];

      ActiveFriendStory? myStory;
      final List<ActiveFriendStory> friendStories = [];

      for (final row in rawRows) {
        final uId = row['user_id']?.toString() ?? '';
        if (uId.isEmpty) continue;
        final isMe = currentUserId != null && uId == currentUserId;
        if (!isMe && filters.storyExcludedUserIds.contains(uId)) continue;

        final item = ActiveFriendStory(
          userId: uId,
          username: (row['username']?.toString() ?? '').isNotEmpty
              ? row['username'].toString()
              : 'user',
          avatarUrl: row['avatar_url']?.toString() ?? '',
          storiesCount: (row['stories_count'] as num?)?.toInt() ?? 1,
          isMe: isMe,
          hasUnseen: row['has_unseen'] == true,
          hasCloseFriendStory: row['has_close_friend_story'] == true,
        );

        if (isMe) {
          myStory = item;
        } else {
          friendStories.add(item);
        }
      }

      if (mounted) {
        setState(() {
          _myActiveStory = myStory;
          _stories = friendStories;
        });
      }
    } catch (e) {
      debugPrint("Stories query warning: $e");
    }
  }

  Future<void> _fetchPosts({bool loadMore = false}) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (loadMore) {
      if (_isLoadingMore || !_hasMorePosts) return;
      if (mounted) setState(() => _isLoadingMore = true);
    }

    final int generation = loadMore ? _fetchGeneration : ++_fetchGeneration;
    final DateTime? reqCursorCreatedAt = loadMore ? _cursorCreatedAt : null;
    final String? reqCursorId = loadMore ? _cursorId : null;

    try {
      final rawRes = await supabase.rpc(
        'get_feed_posts_page',
        params: {
          'p_cursor_created_at': reqCursorCreatedAt?.toUtc().toIso8601String(),
          'p_cursor_id': reqCursorId,
          'p_limit': _pageSize,
          'p_following_only': _followingOnly,
        },
      );

      if (generation != _fetchGeneration) return;

      final rawRows = (rawRes is List)
          ? rawRes.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];

      DateTime? nextCursorCreatedAt = reqCursorCreatedAt;
      String? nextCursorId = reqCursorId;
      if (rawRows.isNotEmpty) {
        final lastRow = rawRows.last;
        nextCursorCreatedAt = DateTime.tryParse(
          lastRow['created_at']?.toString() ?? '',
        );
        nextCursorId = lastRow['id']?.toString();
      }
      final bool hasMore = rawRows.length >= _pageSize && nextCursorId != null;

      if (!loadMore) {
        _loadedPostIds.clear();
      }

      final List<FeedPostItem> pageItems = [];
      for (final p in rawRows) {
        final id = p['id']?.toString() ?? '';
        if (id.isEmpty || _loadedPostIds.contains(id)) continue;
        _loadedPostIds.add(id);
        pageItems.add(FeedPostItem.fromRpcMap(p));
      }

      final mixedPage = FeedAlgorithmService.instance.mixPosts(
        pageItems,
        currentUserId: currentUserId,
      );

      if (mounted && generation == _fetchGeneration) {
        setState(() {
          if (loadMore) {
            _posts = [..._posts, ...mixedPage];
          } else {
            _posts = mixedPage;
          }
          _cursorCreatedAt = nextCursorCreatedAt;
          _cursorId = nextCursorId;
          _hasMorePosts = hasMore;
          _isLoadingMore = false;
          _errorMsg = null;
        });
      }
    } catch (e) {
      debugPrint("Fetch posts error: $e");
      if (mounted && generation == _fetchGeneration) {
        setState(() {
          _isLoadingMore = false;
          if (!loadMore) {
            _errorMsg = e.toString();
          }
        });
      }
    }
  }

  Future<void> _loadMorePosts() => _fetchPosts(loadMore: true);

  void _openCreatePostModal() {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showNotice("Please log in to create a post.");
      return;
    }

    CreatePostScreen.open(context, onPostCreated: _fetchPosts);
  }

  void _openCreateStoryModal() {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showNotice("Please log in to create a story.");
      return;
    }

    CreateStoryScreen.open(context, onStoryCreated: _fetchFeedData);
  }

  void _showNotice(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleFollowSuggestedUser(
    String targetUserId,
    String name,
  ) async {
    HapticFeedback.lightImpact();
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      _showNotice("Please sign in to follow users.");
      return;
    }

    final status = await SocialGraphService.instance.toggleFollow(targetUserId);
    if (!mounted) return;
    setState(() {
      switch (status) {
        case FollowToggleStatus.following:
          _followedSuggestedIds.add(targetUserId);
          _requestedSuggestedIds.remove(targetUserId);
          _showNotice("Following $name");
          break;
        case FollowToggleStatus.requested:
          _followedSuggestedIds.remove(targetUserId);
          _requestedSuggestedIds.add(targetUserId);
          _showNotice("Follow request sent to $name");
          break;
        case FollowToggleStatus.unfollowed:
        case FollowToggleStatus.cancelled:
          _followedSuggestedIds.remove(targetUserId);
          _requestedSuggestedIds.remove(targetUserId);
          _showNotice("Unfollowed $name");
          break;
        case FollowToggleStatus.blocked:
          _showNotice("Cannot follow this account.");
          break;
        case FollowToggleStatus.error:
          _showNotice("Could not update follow status.");
          break;
      }
    });
  }

  Widget _buildSuggestedCarousel() {
    if (_dismissSuggestedCarousel || _suggestedUsers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: "Suggested for you" + "See all"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Suggested for you",
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                    letterSpacing: -0.2,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    DiscoverScreen.open(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      "See all",
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ZevColors.secondaryBlue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Horizontal Carousel
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _suggestedUsers.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final user = _suggestedUsers[i];
                final id = user['id'] as String;
                final isFollowed = _followedSuggestedIds.contains(id);
                final isRequested = _requestedSuggestedIds.contains(id);
                final avatarUrl = user['avatar_url'] as String? ?? '';
                final name = user['name'] as String? ?? 'User';

                return Container(
                  width: 154,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Dismiss '✕' button
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _suggestedUsers.removeAt(i);
                              if (_suggestedUsers.isEmpty) {
                                _dismissSuggestedCarousel = true;
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.transparent,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: ZevColors.textMuted,
                            ),
                          ),
                        ),
                      ),

                      // Card body
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Circular Avatar
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ProfileScreen.open(context, userId: id);
                              },
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: avatarUrl.isNotEmpty
                                    ? ZevCachedImage.avatar(
                                        imageUrl: avatarUrl,
                                        size: 64,
                                      )
                                    : const Icon(
                                        Icons.person,
                                        size: 34,
                                        color: ZevColors.textMuted,
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Display Name
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ProfileScreen.open(context, userId: id);
                              },
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: ZevColors.deepNavy,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),

                            // Subtitle
                            const Text(
                              "Suggested for you",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: ZevColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Blue Follow / Following Button
                            SizedBox(
                              width: double.infinity,
                              height: 32,
                              child: ElevatedButton(
                                onPressed: () =>
                                    _toggleFollowSuggestedUser(id, name),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: (isFollowed || isRequested)
                                      ? const Color(0xFFE2E8F0)
                                      : const Color(0xFF0095F6),
                                  foregroundColor: (isFollowed || isRequested)
                                      ? ZevColors.deepNavy
                                      : Colors.white,
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: (isFollowed || isRequested)
                                        ? BorderSide.none
                                        : const BorderSide(
                                            color: Colors.white,
                                            width: 1.0,
                                          ),
                                  ),
                                ),
                                child: Text(
                                  isFollowed
                                      ? "Following"
                                      : isRequested
                                          ? "Requested"
                                          : "Follow",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: (isFollowed || isRequested)
                                        ? ZevColors.deepNavy
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClayAppbarButton({
    required Widget child,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 38,
        height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            const BoxShadow(
              color: Colors.white,
              blurRadius: 4,
              offset: Offset(0, -1),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: RefreshIndicator(
          color: ZevColors.primaryBlue,
          onRefresh: () {
            ZevAdsService.instance.clearSlotCache();
            return _fetchFeedData();
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (!_isLoading &&
                  !_isLoadingMore &&
                  _hasMorePosts &&
                  notification.metrics.pixels >=
                      notification.metrics.maxScrollExtent - 600) {
                _loadMorePosts();
              }
              return false;
            },
            child: CustomScrollView(
              // ignore: deprecated_member_use
              cacheExtent: 1200.0,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
              // 1. Next-Gen Claymorphic Top Navigation Bar
              SliverAppBar(
                floating: true,
                pinned: false,
                snap: true,
                backgroundColor: const Color(0xFFF1F5F9),
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                centerTitle: false,
                title: PopupMenuButton<bool>(
                  tooltip: 'Switch Feed Mode',
                  color: Colors.white,
                  elevation: 10,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: ZevColors.border),
                  ),
                  initialValue: _followingOnly,
                  onSelected: (followOnly) {
                    if (followOnly == _followingOnly) return;
                    HapticFeedback.selectionClick();
                    setState(() {
                      _followingOnly = followOnly;
                      _isLoading = true;
                      _posts = [];
                      _cursorCreatedAt = null;
                      _cursorId = null;
                      _hasMorePosts = true;
                      _loadedPostIds.clear();
                    });
                    _fetchPosts().whenComplete(() {
                      if (mounted) setState(() => _isLoading = false);
                    });
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem<bool>(
                      value: false,
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                            color: !_followingOnly
                                ? ZevColors.secondaryBlue
                                : ZevColors.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'For You',
                            style: TextStyle(
                              fontWeight: !_followingOnly
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          if (!_followingOnly) ...[
                            const Spacer(),
                            const Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: ZevColors.secondaryBlue,
                            ),
                          ],
                        ],
                      ),
                    ),
                    PopupMenuItem<bool>(
                      value: true,
                      child: Row(
                        children: [
                          Icon(
                            Icons.people_alt_rounded,
                            size: 18,
                            color: _followingOnly
                                ? ZevColors.secondaryBlue
                                : ZevColors.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Following',
                            style: TextStyle(
                              fontWeight: _followingOnly
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          if (_followingOnly) ...[
                            const Spacer(),
                            const Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: ZevColors.secondaryBlue,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A)
                                  .withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/icon/icon-192x192.png',
                          height: 24,
                          width: 24,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.bolt_rounded,
                            color: ZevColors.primaryBlue,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "ZEV",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.deepNavy,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (_followingOnly) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: ZevColors.border),
                          ),
                          child: const Text(
                            'Following',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: ZevColors.secondaryBlue,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: ZevColors.deepNavy,
                      ),
                    ],
                  ),
                ),
                actions: [
                  // Interactive ZEV Live Chat & Presence Rooms Pill
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      LiveRoomsScreen.open(context);
                    },
                    child: Container(
                      height: 36,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 10,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A)
                                .withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                          const BoxShadow(
                            color: Colors.white,
                            blurRadius: 4,
                            offset: Offset(0, -1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: ZevColors.errorRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Live',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Create Post (+) Button
                  _buildClayAppbarButton(
                    tooltip: "Create Post",
                    onTap: _openCreatePostModal,
                    child: const Icon(
                      Icons.add_rounded,
                      color: ZevColors.deepNavy,
                      size: 24,
                    ),
                  ),

                  // Heart / Activity Button with live synced numeric badge
                  ValueListenableBuilder<int>(
                    valueListenable:
                        BadgeCounterService.instance.unreadNotificationsCount,
                    builder: (context, count, _) {
                      final hasUnread = count > 0;
                      final badgeText = count > 99 ? '99+' : '$count';
                      return Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          _buildClayAppbarButton(
                            tooltip: "Notifications",
                            onTap: () async {
                              HapticFeedback.lightImpact();
                              BadgeCounterService.instance
                                  .markNotificationsReadOptimistic();
                              if (widget.onOpenNotifications != null) {
                                widget.onOpenNotifications!();
                              } else {
                                await NotificationsScreen.open(context);
                                BadgeCounterService.instance.refreshCounts();
                              }
                            },
                            child: const Icon(
                              Icons.favorite_border_rounded,
                              color: ZevColors.deepNavy,
                              size: 21,
                            ),
                          ),
                          if (hasUnread)
                            Positioned(
                              top: 2,
                              right: 0,
                              child: IgnorePointer(
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF3040),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      badgeText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  // Direct Messages (Paper Plane / Chat) with live unread badge
                  ValueListenableBuilder<int>(
                    valueListenable:
                        BadgeCounterService.instance.unreadMessagesCount,
                    builder: (context, count, _) {
                      final hasUnread = count > 0;
                      final badgeText = count > 99 ? '99+' : '$count';
                      return Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          _buildClayAppbarButton(
                            tooltip: "Messages",
                            onTap: () async {
                              if (widget.onOpenMessages != null) {
                                widget.onOpenMessages!();
                              } else {
                                await ChatListScreen.open(context);
                                BadgeCounterService.instance.refreshCounts();
                              }
                            },
                            child: const Icon(
                              Icons.send_rounded,
                              color: ZevColors.deepNavy,
                              size: 19,
                            ),
                          ),
                          if (hasUnread)
                            Positioned(
                              top: 2,
                              right: 0,
                              child: IgnorePointer(
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF3040),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      badgeText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),

              // 2. Stories Tray (Claymorphic Horizontal Carousel)
              SliverToBoxAdapter(
                child: FeedStoriesTray(
                  myAvatarUrl: _myAvatarUrl,
                  myActiveStory: _myActiveStory,
                  stories: _stories,
                  onAddStory: _openCreateStoryModal,
                  onStoryTap: (story) async {
                    final allStories = <ActiveFriendStory>[
                      ?_myActiveStory,
                      ..._stories,
                    ];
                    final idx = allStories.indexWhere(
                      (s) => s.userId == story.userId,
                    );
                    await StoryViewerScreen.open(
                      context,
                      friendStory: story,
                      allFriendStories: allStories,
                      initialFriendIndex: idx < 0 ? 0 : idx,
                    );
                    if (mounted) {
                      _fetchStories();
                    }
                  },
                ),
              ),

              // 3. Posts Stream / Feed List
              if (_isLoading)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, _) => const ZevFeedCardSkeleton(),
                    childCount: 3,
                  ),
                )
              else if (_errorMsg != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            size: 48,
                            color: ZevColors.textMuted,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            "Couldn't load feed",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _errorMsg!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: ZevColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton(
                            onPressed: _fetchFeedData,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ZevColors.primaryBlue,
                              foregroundColor: ZevColors.deepNavy,
                            ),
                            child: const Text("Retry"),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_posts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.95),
                            width: 1.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                            const BoxShadow(
                              color: Colors.white,
                              blurRadius: 10,
                              offset: Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFF1F5F9),
                                border: Border.all(color: Colors.white, width: 2.0),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt_outlined,
                                size: 36,
                                color: ZevColors.primaryBlue,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _followingOnly
                                  ? "No posts from Following yet"
                                  : "Welcome to your Feed",
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: ZevColors.deepNavy,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _followingOnly
                                  ? "Follow creators you like or switch back to For You to explore the community."
                                  : "When creators and friends share stories, photos, and thoughts, they will appear here.",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: ZevColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 22),
                            GestureDetector(
                              onTap: _followingOnly
                                  ? () {
                                      setState(() {
                                        _followingOnly = false;
                                        _isLoading = true;
                                        _posts = [];
                                        _cursorCreatedAt = null;
                                        _cursorId = null;
                                        _hasMorePosts = true;
                                        _loadedPostIds.clear();
                                      });
                                      _fetchPosts().whenComplete(() {
                                        if (mounted) {
                                          setState(() => _isLoading = false);
                                        }
                                      });
                                    }
                                  : _openCreatePostModal,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _followingOnly
                                          ? Icons.auto_awesome_rounded
                                          : Icons.add_rounded,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _followingOnly
                                          ? "Switch to For You"
                                          : "Create First Post",
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final post = _posts[index];
                      final card = RepaintBoundary(
                        child: FeedPostCard(
                          key: ValueKey(post.id),
                          post: post,
                          onCommentsUpdated: _fetchPosts,
                          onPostUpdated: (updated) {
                            setState(() {
                              final idx = _posts.indexWhere((p) => p.id == updated.id);
                              if (idx != -1) _posts[idx] = updated;
                            });
                          },
                          onHideOrMute: () {
                            FeedAlgorithmService.instance.recordNegativeFeedback(
                              postId: post.id,
                              authorId: post.authorId,
                            );
                            setState(() {
                              _posts.removeWhere((p) => p.id == post.id);
                            });
                            _fetchPosts();
                          },
                          onPostDeleted: () {
                            setState(() {
                              _posts.removeWhere((p) => p.id == post.id);
                            });
                          },
                        ),
                      );

                      // Display a native in-stream ad card every 3 posts (posts 0, 1, 2 -> Ad below 2, etc.)
                      final showNativeAd = (index + 1) % 3 == 0;

                      // Render "Suggested for you" carousel directly below the first post
                      if (index == 0 &&
                          _suggestedUsers.isNotEmpty &&
                          !_dismissSuggestedCarousel) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            card,
                            _buildSuggestedCarousel(),
                            if (showNativeAd)
                              ZevNativeAdCard(
                                key: ValueKey('feed_ad_${post.id}'),
                                placement: 'feed',
                                slotKey: 'feed_${post.id}',
                              ),
                          ],
                        );
                      }

                      if (showNativeAd) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            card,
                            ZevNativeAdCard(
                              key: ValueKey('feed_ad_${post.id}'),
                              placement: 'feed',
                              slotKey: 'feed_${post.id}',
                            ),
                          ],
                        );
                      }

                      return card;
                    },
                    childCount: _posts.length,
                    addAutomaticKeepAlives: true,
                    addRepaintBoundaries: true,
                  ),
                ),

              if (_isLoadingMore)
                const SliverToBoxAdapter(
                  child: ZevFeedCardSkeleton(),
                ),

              // Bottom Spacer to comfortably clear the floating navigation dock
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    ),
  );
  }
}
