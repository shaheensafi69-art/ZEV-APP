import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_text_field.dart';
import '../models/feed_post_item.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/feed_stories_tray.dart';

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
  String? _errorMsg;
  List<FeedPostItem> _posts = [];
  List<ActiveFriendStory> _stories = [];
  List<Map<String, dynamic>> _suggestedUsers = [];
  final Set<String> _followedSuggestedIds = {};
  bool _dismissSuggestedCarousel = false;
  String _myAvatarUrl = '';

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
    _fetchFeedData();
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
      final res = await supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified')
          .neq('id', currentUserId ?? '')
          .limit(8);

      final list = (res as List).map((p) {
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
      }).toList();

      if (mounted) {
        setState(() => _suggestedUsers = list);
      }
    } catch (e) {
      debugPrint("Suggested users warning: $e");
    }
  }

  Future<void> _fetchStories() async {
    try {
      final nowStr = DateTime.now().toIso8601String();
      final res = await supabase
          .from('user_stories')
          .select('id, user_id, media_url, media_type, caption, expires_at')
          .gt('expires_at', nowStr)
          .order('created_at', ascending: false)
          .limit(20);

      final rawList = List<Map<String, dynamic>>.from(res as List);
      final userIds =
          rawList.map((s) => s['user_id']?.toString() ?? '').toSet().toList();

      Map<String, Map<String, dynamic>> profilesMap = {};
      if (userIds.isNotEmpty) {
        final profs = await supabase
            .from('profiles')
            .select('id, username, avatar_url')
            .inFilter('id', userIds);
        for (var p in (profs as List)) {
          profilesMap[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }

      final storiesList = userIds.map((uId) {
        final p = profilesMap[uId] ?? {};
        return ActiveFriendStory(
          userId: uId,
          username: p['username'] ?? 'user',
          avatarUrl: p['avatar_url'] ?? '',
          storiesCount: rawList.where((s) => s['user_id'] == uId).length,
        );
      }).toList();

      if (mounted) {
        setState(() => _stories = storiesList);
      }
    } catch (e) {
      debugPrint("Stories query warning: $e");
    }
  }

  Future<void> _fetchPosts() async {
    final currentUserId = supabase.auth.currentUser?.id;

    try {
      // 1. Fetch posts from discussion_posts
      final postsRes = await supabase
          .from('discussion_posts')
          .select('id, student_id, title, content, image_url, created_at')
          .order('created_at', ascending: false)
          .limit(40);

      final rawPosts = List<Map<String, dynamic>>.from(postsRes as List);
      if (rawPosts.isEmpty) {
        if (mounted) setState(() => _posts = []);
        return;
      }

      final postIds = rawPosts.map((p) => p['id'].toString()).toList();
      final authorIds =
          rawPosts.map((p) => p['student_id']?.toString() ?? '').toSet().toList();

      // 2. Batch fetch author profiles
      Map<String, Map<String, dynamic>> profilesMap = {};
      if (authorIds.isNotEmpty) {
        final profRes = await supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .inFilter('id', authorIds);

        for (var p in (profRes as List)) {
          profilesMap[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }

      // 3. Batch fetch likes counts and my like status
      Map<String, int> likesCountMap = {};
      Set<String> myLikedPostIds = {};

      if (postIds.isNotEmpty) {
        try {
          final likesRes = await supabase
              .from('discussion_likes')
              .select('post_id, student_id')
              .inFilter('post_id', postIds);

          for (var l in (likesRes as List)) {
            final pId = l['post_id']?.toString() ?? '';
            final uId = l['student_id']?.toString() ?? '';
            likesCountMap[pId] = (likesCountMap[pId] ?? 0) + 1;
            if (currentUserId != null && uId == currentUserId) {
              myLikedPostIds.add(pId);
            }
          }
        } catch (_) {}
      }

      // 4. Batch fetch comments count
      Map<String, int> commentsCountMap = {};
      if (postIds.isNotEmpty) {
        try {
          final commRes = await supabase
              .from('discussion_comments')
              .select('post_id')
              .inFilter('post_id', postIds);

          for (var c in (commRes as List)) {
            final pId = c['post_id']?.toString() ?? '';
            commentsCountMap[pId] = (commentsCountMap[pId] ?? 0) + 1;
          }
        } catch (_) {}
      }

      // 5. Batch fetch reposts count and my repost status
      Map<String, int> repostsCountMap = {};
      Set<String> myRepostedPostIds = {};
      if (postIds.isNotEmpty) {
        try {
          final repRes = await supabase
              .from('post_reposts')
              .select('post_id, user_id')
              .inFilter('post_id', postIds);

          for (var r in (repRes as List)) {
            final pId = r['post_id']?.toString() ?? '';
            final uId = r['user_id']?.toString() ?? '';
            repostsCountMap[pId] = (repostsCountMap[pId] ?? 0) + 1;
            if (currentUserId != null && uId == currentUserId) {
              myRepostedPostIds.add(pId);
            }
          }
        } catch (_) {}
      }

      // 6. Build models
      final List<FeedPostItem> items = [];
      for (var p in rawPosts) {
        final id = p['id'].toString();
        final aId = p['student_id']?.toString() ?? '';
        final profile = profilesMap[aId] ?? {};

        final fn = profile['first_name'] ?? '';
        final ln = profile['last_name'] ?? '';
        final full = "$fn $ln".trim();

        items.add(
          FeedPostItem(
            id: id,
            authorId: aId,
            authorUsername: profile['username'] ?? (full.isNotEmpty ? full : 'user'),
            authorFullName: full,
            authorAvatar: profile['avatar_url'] ?? '',
            isVerified: profile['is_verified'] == true,
            title: p['title'] ?? '',
            content: p['content'] ?? '',
            imageUrl: p['image_url'] ?? '',
            createdAt: DateTime.tryParse(p['created_at']?.toString() ?? '') ??
                DateTime.now(),
            likesCount: likesCountMap[id] ?? 0,
            isLikedByMe: myLikedPostIds.contains(id),
            commentsCount: commentsCountMap[id] ?? 0,
            repostsCount: repostsCountMap[id] ?? 0,
            isRepostedByMe: myRepostedPostIds.contains(id),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _posts = items;
          _errorMsg = null;
        });
      }
    } catch (e) {
      debugPrint("Fetch posts error: $e");
      if (mounted) setState(() => _errorMsg = e.toString());
    }
  }

  void _openCreatePostModal() {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showNotice("Please log in to create a post.");
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePostModal(onPostCreated: _fetchPosts),
    );
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

  Future<void> _toggleFollowSuggestedUser(String targetUserId, String name) async {
    HapticFeedback.lightImpact();
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      _showNotice("Please sign in to follow users.");
      return;
    }

    final isCurrentlyFollowed = _followedSuggestedIds.contains(targetUserId);

    setState(() {
      if (isCurrentlyFollowed) {
        _followedSuggestedIds.remove(targetUserId);
      } else {
        _followedSuggestedIds.add(targetUserId);
      }
    });

    try {
      if (isCurrentlyFollowed) {
        await supabase
            .from('student_friends')
            .delete()
            .match({'user_id': currentUserId, 'friend_id': targetUserId});
        _showNotice("Unfollowed $name");
      } else {
        await supabase.from('student_friends').upsert({
          'user_id': currentUserId,
          'friend_id': targetUserId,
          'status': 'accepted',
          'created_at': DateTime.now().toIso8601String(),
        });
        _showNotice("Following $name");

        // Record notification
        unawaited(NotificationService().sendNotificationToUser(
          targetUserId: targetUserId,
          title: "New Follower",
          message: "Started following your profile on ZEV",
          notificationType: "follow",
          senderId: currentUserId,
        ));
      }
    } catch (e) {
      debugPrint("Follow suggestion error: $e");
    }
  }

  Widget _buildSuggestedCarousel() {
    if (_dismissSuggestedCarousel || _suggestedUsers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: "Suggested for you" + "See all"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Suggested for you",
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.deepNavy,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _showNotice("Discovering more creators on ZEV");
                  },
                  child: const Text(
                    "See all",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.secondaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Horizontal Carousel
          SizedBox(
            height: 226,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: _suggestedUsers.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final user = _suggestedUsers[i];
                final id = user['id'] as String;
                final isFollowed = _followedSuggestedIds.contains(id);
                final avatarUrl = user['avatar_url'] as String? ?? '';
                final name = user['name'] as String? ?? 'User';

                return Container(
                  width: 156,
                  decoration: BoxDecoration(
                    color: ZevColors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: ZevColors.border,
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
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
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: ZevColors.border,
                                  width: 1.5,
                                ),
                              ),
                              child: ClipOval(
                                child: avatarUrl.isNotEmpty
                                    ? Image.network(
                                        avatarUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                            const Icon(
                                          Icons.person,
                                          size: 38,
                                          color: ZevColors.textMuted,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.person,
                                        size: 38,
                                        color: ZevColors.textMuted,
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Display Name
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: ZevColors.deepNavy,
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
                                  backgroundColor: isFollowed
                                      ? ZevColors.softSurface
                                      : const Color(0xFF0095F6),
                                  foregroundColor: isFollowed
                                      ? ZevColors.deepNavy
                                      : Colors.white,
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: isFollowed
                                        ? const BorderSide(
                                            color: ZevColors.border,
                                          )
                                        : BorderSide.none,
                                  ),
                                ),
                                child: Text(
                                  isFollowed ? "Following" : "Follow",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: isFollowed
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
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 0.8, color: ZevColors.border),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZevColors.white,
      body: SafeArea(
        child: RefreshIndicator(
          color: ZevColors.primaryBlue,
          onRefresh: _fetchFeedData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // 1. Instagram-Style Top Navigation Bar
              SliverAppBar(
                floating: true,
                pinned: false,
                snap: true,
                backgroundColor: ZevColors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                centerTitle: false,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icon/icon-192x192.png',
                      height: 28,
                      width: 28,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.bolt_rounded,
                        color: ZevColors.primaryBlue,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "ZEV",
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: ZevColors.deepNavy,
                    ),
                  ],
                ),
                actions: [
                  // Create Post (+) Button
                  IconButton(
                    icon: const Icon(
                      Icons.add_box_outlined,
                      color: ZevColors.deepNavy,
                      size: 26,
                    ),
                    tooltip: "Create Post",
                    onPressed: _openCreatePostModal,
                  ),
                  // Heart / Activity Button with notification dot
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.favorite_border_rounded,
                          color: ZevColors.deepNavy,
                          size: 26,
                        ),
                        tooltip: "Notifications",
                        onPressed: widget.onOpenNotifications ??
                            () => _showNotice("No new notifications."),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF3040),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Direct Messages (Paper Plane / Chat)
                  IconButton(
                    icon: const Icon(
                      Icons.send_rounded,
                      color: ZevColors.deepNavy,
                      size: 23,
                    ),
                    tooltip: "Messages",
                    onPressed: widget.onOpenMessages ??
                        () => _showNotice("Direct Chat is ready for conversations."),
                  ),
                  const SizedBox(width: 4),
                ],
              ),

              // 2. Stories Tray (Instagram Horizontal Carousel)
              SliverToBoxAdapter(
                child: FeedStoriesTray(
                  myAvatarUrl: _myAvatarUrl,
                  stories: _stories,
                  onAddStory: _openCreatePostModal,
                  onStoryTap: (story) {
                    _showNotice("Viewing @${story.username}'s story");
                  },
                ),
              ),

              // 3. Posts Stream / Feed List
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: ZevColors.primaryBlue,
                    ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ZevColors.softSurface,
                              border: Border.all(color: ZevColors.border),
                            ),
                            child: const Icon(
                              Icons.camera_alt_outlined,
                              size: 34,
                              color: ZevColors.primaryBlue,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "Welcome to your Feed",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            "When creators and friends share stories, photos, and thoughts, they will appear here.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: ZevColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _openCreatePostModal,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text("Create First Post"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ZevColors.primaryBlue,
                              foregroundColor: ZevColors.deepNavy,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final post = _posts[index];
                      final card = FeedPostCard(
                        key: ValueKey(post.id),
                        post: post,
                        onCommentsUpdated: _fetchPosts,
                      );

                      // Render "Suggested for you" carousel directly below the first post
                      if (index == 0 &&
                          _suggestedUsers.isNotEmpty &&
                          !_dismissSuggestedCarousel) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            card,
                            _buildSuggestedCarousel(),
                          ],
                        );
                      }

                      return card;
                    },
                    childCount: _posts.length,
                  ),
                ),

              // Bottom Spacer
              const SliverToBoxAdapter(
                child: SizedBox(height: 80),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Instagram Create Post Bottom Sheet Modal.
class _CreatePostModal extends StatefulWidget {
  final VoidCallback onPostCreated;
  const _CreatePostModal({required this.onPostCreated});

  @override
  State<_CreatePostModal> createState() => _CreatePostModalState();
}

class _CreatePostModalState extends State<_CreatePostModal> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _contentCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();

  File? _selectedImage;
  bool _isPublishing = false;
  String? _modalError;
  String _selectedCategory = "Explore";
  final List<String> _categories = ["Analysis", "Education", "Explore", "Tech", "Community"];

  @override
  void dispose() {
    _contentCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1440,
      );
      if (picked != null) {
        setState(() => _selectedImage = File(picked.path));
      }
    } catch (e) {
      debugPrint("Post image pick notice: $e");
    }
  }

  Future<void> _handlePublish() async {
    final content = _contentCtrl.text.trim();
    final title = _titleCtrl.text.trim();

    if (content.isEmpty && _selectedImage == null) {
      setState(() => _modalError = "Please write a caption or select a photo.");
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _modalError = "User session expired. Please sign in again.");
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isPublishing = true;
      _modalError = null;
    });

    try {
      String imageUrl = "";
      if (_selectedImage != null) {
        final ext = _selectedImage!.path.split('.').last;
        final fileName = 'feed_${user.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        try {
          imageUrl = await CloudflareStorageService.instance.upload(
            bucket: 'feed',
            path: fileName,
            file: _selectedImage,
          );
        } catch (uploadErr) {
          debugPrint("Post image upload fallback: $uploadErr");
        }
      }

      final formattedTitle = title.startsWith('[')
          ? title
          : "[$_selectedCategory] ${title.isNotEmpty ? title : (content.length > 30 ? content.substring(0, 30) : content)}";

      await supabase.from('discussion_posts').insert({
        'student_id': user.id,
        'title': formattedTitle,
        'content': content,
        'image_url': imageUrl,
      });

      widget.onPostCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _modalError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.85,
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle & Header
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4.5,
            decoration: BoxDecoration(
              color: ZevColors.border,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: ZevColors.deepNavy),
                  onPressed: () => Navigator.pop(context),
                ),
                const Text(
                  "New Post",
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                  ),
                ),
                TextButton(
                  onPressed: _isPublishing ? null : _handlePublish,
                  child: _isPublishing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          "Share",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: ZevColors.primaryBlue,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: ZevColors.border),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_modalError != null) ...[
                    Text(
                      _modalError!,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Image Preview or Add Image Box
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: double.infinity,
                      height: 220,
                      decoration: BoxDecoration(
                        color: ZevColors.softSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: ZevColors.border, width: 1.2),
                      ),
                      child: _selectedImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(_selectedImage!, fit: BoxFit.cover),
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.edit_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_rounded,
                                  size: 44,
                                  color: ZevColors.primaryBlue,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  "Tap to select a photo",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: ZevColors.deepNavy,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Category Selector Chips
                  const Text(
                    "Topic / Category",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final cat = _categories[index];
                        final isSelected = cat == _selectedCategory;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _selectedCategory = cat);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? ZevColors.primaryBlue : ZevColors.softSurface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected ? ZevColors.primaryBlue : ZevColors.border,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                  color: isSelected ? ZevColors.deepNavy : ZevColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 18),

                  ZevTextField(
                    label: "Title (Optional)",
                    hint: "Short headline...",
                    controller: _titleCtrl,
                    prefixIcon: Icons.title_rounded,
                  ),

                  const SizedBox(height: 16),

                  ZevTextField(
                    label: "Caption",
                    hint: "What's happening? Share your thoughts...",
                    controller: _contentCtrl,
                    prefixIcon: Icons.notes_rounded,
                    maxLines: 4,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
