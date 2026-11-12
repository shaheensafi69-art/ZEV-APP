import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/zev_theme.dart';
import '../../../../core/widgets/zev_cached_image.dart';
import '../../../../core/widgets/zev_video_thumbnail.dart';
import '../../../feed/screens/post_detail_screen.dart';
import '../../../reels/models/reel_item.dart';
import '../../../reels/services/reel_video_cache_manager.dart';
import '../../../reels/widgets/reel_player_item.dart';

/// Instagram-Grade Liked Media Activity Screen for ZEV.
/// Displays all posts and reels liked by the user with interactive tabs,
/// 3-column Light Clearmorphic media grid, sort options, and direct post/reel playback.
class ActivityLikesScreen extends StatefulWidget {
  const ActivityLikesScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ActivityLikesScreen(),
      ),
    );
  }

  @override
  State<ActivityLikesScreen> createState() => _ActivityLikesScreenState();
}

class _ActivityLikesScreenState extends State<ActivityLikesScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TabController _tabCtrl;

  bool _isLoading = true;
  List<Map<String, dynamic>> _likedPosts = [];
  List<Map<String, dynamic>> _likedReels = [];
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _fetchLikedMedia();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  bool _isVideoMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v');
  }

  Future<void> _fetchLikedMedia() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch liked discussion posts (`discussion_likes.student_id`)
      final postLikesRes = await supabase
          .from('discussion_likes')
          .select('post_id, created_at')
          .eq('student_id', userId)
          .order('created_at', ascending: false)
          .limit(60);

      final postLikedAt = <String, String>{};
      final postIds = <String>[];
      for (final row in (postLikesRes as List)) {
        final pid = row['post_id']?.toString() ?? '';
        if (pid.isNotEmpty) {
          postIds.add(pid);
          postLikedAt[pid] = row['created_at']?.toString() ?? '';
        }
      }

      List<Map<String, dynamic>> postsList = [];
      if (postIds.isNotEmpty) {
        final postsRes = await supabase
            .from('discussion_posts')
            .select(
              'id, image_url, title, content, created_at, likes_count',
            )
            .inFilter('id', postIds)
            .isFilter('deleted_at', null);

        postsList = (postsRes as List).map((p) {
          final id = p['id'].toString();
          final imageUrl = (p['image_url'] ?? '').toString();
          final title = (p['title'] ?? '').toString();
          final content = (p['content'] ?? '').toString();
          return {
            'id': id,
            'type': 'post',
            'image_url': imageUrl,
            'is_video': _isVideoMediaUrl(imageUrl),
            'caption': content.isNotEmpty ? content : title,
            'likes_count': p['likes_count'] ?? 0,
            'created_at': postLikedAt[id] ?? (p['created_at'] ?? ''),
          };
        }).toList();
      }

      // 2. Fetch liked reels (`reel_likes.user_id`)
      final reelLikesRes = await supabase
          .from('reel_likes')
          .select('reel_id, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(60);

      final reelLikedAt = <String, String>{};
      final reelIds = <String>[];
      for (final row in (reelLikesRes as List)) {
        final rid = row['reel_id']?.toString() ?? '';
        if (rid.isNotEmpty) {
          reelIds.add(rid);
          reelLikedAt[rid] = row['created_at']?.toString() ?? '';
        }
      }

      List<Map<String, dynamic>> reelsList = [];
      if (reelIds.isNotEmpty) {
        final reelsRes = await supabase
            .from('reels')
            .select(
              'id, user_id, title, description, category, duration_seconds, '
              'thumbnail_url, video_url, views_count, likes_count, comments_count, created_at',
            )
            .inFilter('id', reelIds)
            .isFilter('deleted_at', null);

        final rawReels = List<Map<String, dynamic>>.from(reelsRes as List);
        final authorIds = rawReels
            .map((r) => r['user_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

        final profilesMap = <String, Map<String, dynamic>>{};
        if (authorIds.isNotEmpty) {
          final profRes = await supabase
              .from('profiles')
              .select('id, username, first_name, last_name, avatar_url, is_verified')
              .inFilter('id', authorIds);
          for (final p in (profRes as List)) {
            final m = Map<String, dynamic>.from(p as Map);
            profilesMap[m['id'].toString()] = m;
          }
        }

        final bookmarkedIds = <String>{};
        try {
          final bmRes = await supabase
              .from('reel_bookmarks')
              .select('reel_id')
              .eq('user_id', userId)
              .inFilter('reel_id', reelIds);
          for (final b in (bmRes as List)) {
            final bid = b['reel_id']?.toString() ?? '';
            if (bid.isNotEmpty) bookmarkedIds.add(bid);
          }
        } catch (_) {}

        final followedAuthorIds = <String>{};
        if (authorIds.isNotEmpty) {
          try {
            final fRes = await supabase
                .from('follows')
                .select('following_id')
                .eq('follower_id', userId)
                .eq('status', 'accepted')
                .inFilter('following_id', authorIds);
            for (final f in (fRes as List)) {
              final fid = f['following_id']?.toString() ?? '';
              if (fid.isNotEmpty) followedAuthorIds.add(fid);
            }
          } catch (_) {}
        }

        reelsList = rawReels.map((r) {
          final id = r['id'].toString();
          final authorId = (r['user_id'] ?? '').toString();
          final prof = profilesMap[authorId] ?? const <String, dynamic>{};
          final fn = (prof['first_name'] ?? '').toString().trim();
          final ln = (prof['last_name'] ?? '').toString().trim();
          final fullName = '$fn $ln'.trim();
          final username = (prof['username'] ?? 'creator').toString();

          final reelItem = ReelItem(
            id: id,
            userId: authorId,
            authorUsername: username,
            authorFullName: fullName.isNotEmpty ? fullName : username,
            authorAvatar: (prof['avatar_url'] ?? '').toString(),
            isVerified: prof['is_verified'] == true,
            videoUrl: (r['video_url'] ?? '').toString(),
            thumbnailUrl: r['thumbnail_url']?.toString(),
            title: (r['title'] ?? '').toString(),
            description: (r['description'] ?? '').toString(),
            category: (r['category'] ?? 'Explore').toString(),
            durationSeconds: (r['duration_seconds'] as int?) ?? 30,
            viewsCount: (r['views_count'] as int?) ?? 0,
            likesCount: (r['likes_count'] as int?) ?? 0,
            isLikedByMe: true,
            commentsCount: (r['comments_count'] as int?) ?? 0,
            isBookmarkedByMe: bookmarkedIds.contains(id),
            isAuthorFollowed: followedAuthorIds.contains(authorId),
            createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
                DateTime.now(),
          );

          return {
            'id': id,
            'type': 'reel',
            'image_url': reelItem.thumbnailUrl ?? '',
            'video_url': reelItem.videoUrl,
            'caption': reelItem.title.isNotEmpty
                ? reelItem.title
                : reelItem.description,
            'likes_count': reelItem.likesCount,
            'created_at': reelLikedAt[id] ?? (r['created_at'] ?? ''),
            'reel_item': reelItem,
          };
        }).toList();
      }

      if (mounted) {
        setState(() {
          _likedPosts = postsList;
          _likedReels = reelsList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch liked media error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _getItemsForActiveTab() {
    List<Map<String, dynamic>> list;
    if (_tabCtrl.index == 0) {
      list = [..._likedPosts, ..._likedReels];
    } else if (_tabCtrl.index == 1) {
      list = List.from(_likedPosts);
    } else {
      list = List.from(_likedReels);
    }

    list.sort((a, b) {
      final tA = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime(2000);
      final tB = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime(2000);
      return _newestFirst ? tB.compareTo(tA) : tA.compareTo(tB);
    });

    return list;
  }

  Future<void> _openReelPlayer(ReelItem tappedReel) async {
    final orderedReels = _getItemsForActiveTab()
        .where((e) => e['reel_item'] is ReelItem)
        .map((e) => e['reel_item'] as ReelItem)
        .toList();
    if (orderedReels.isEmpty) orderedReels.add(tappedReel);

    final startIndex = orderedReels.indexWhere((r) => r.id == tappedReel.id);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ActivityReelPlaybackScreen(
          reels: orderedReels,
          initialIndex: startIndex >= 0 ? startIndex : 0,
        ),
      ),
    );
    ReelVideoCacheManager().pauseAll();
    await _fetchLikedMedia();
  }

  @override
  Widget build(BuildContext context) {
    final items = _getItemsForActiveTab();
    final totalCount = _likedPosts.length + _likedReels.length;

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            const Text(
              'Likes',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '$totalCount items liked',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: ZevColors.textMuted,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _newestFirst ? Icons.sort_rounded : Icons.swap_vert_rounded,
              color: ZevColors.secondaryBlue,
              size: 22,
            ),
            tooltip: _newestFirst ? 'Sort: Oldest first' : 'Sort: Newest first',
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _newestFirst = !_newestFirst);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: ZevColors.border,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    _buildTabPill(index: 0, label: 'All', count: totalCount),
                    _buildTabPill(
                      index: 1,
                      label: 'Posts',
                      count: _likedPosts.length,
                    ),
                    _buildTabPill(
                      index: 2,
                      label: 'Reels',
                      count: _likedReels.length,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _isLoading
                  ? _buildShimmerGrid()
                  : items.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          color: ZevColors.primaryBlue,
                          onRefresh: _fetchLikedMedia,
                          child: GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 0.85,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) =>
                                _buildMediaTile(items[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPill({
    required int index,
    required String label,
    required int count,
  }) {
    final isSelected = _tabCtrl.index == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _tabCtrl.animateTo(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? ZevColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: ZevColors.deepNavy.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color:
                      isSelected ? ZevColors.deepNavy : ZevColors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? ZevColors.secondaryBlue
                      : ZevColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaTile(Map<String, dynamic> item) {
    final isReel = item['type'] == 'reel';
    final imageUrl = (item['image_url'] ?? '').toString();
    final videoUrl = (item['video_url'] ?? '').toString();
    final isVideoPost = item['is_video'] == true;
    final caption = (item['caption'] ?? '').toString();
    final itemId = item['id'].toString();

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (!isReel) {
          PostDetailScreen.open(context, postId: itemId).then((_) {
            if (mounted) _fetchLikedMedia();
          });
        } else {
          final reelItem = item['reel_item'] as ReelItem?;
          if (reelItem != null) {
            _openReelPlayer(reelItem);
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZevColors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: ZevColors.deepNavy.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isReel)
              ZevVideoThumbnail(
                videoUrl: videoUrl,
                thumbnailUrl: imageUrl.isNotEmpty ? imageUrl : null,
                showPlayBadge: false,
                showViews: false,
                borderRadius: BorderRadius.circular(16),
              )
            else if (isVideoPost && imageUrl.isNotEmpty)
              ZevVideoThumbnail(
                videoUrl: imageUrl,
                showPlayBadge: false,
                showViews: false,
                borderRadius: BorderRadius.circular(16),
              )
            else if (imageUrl.isNotEmpty)
              ZevCachedImage.grid(
                imageUrl: imageUrl,
                borderRadius: BorderRadius.circular(16),
              )
            else
              Container(
                color: ZevColors.softSurface,
                padding: const EdgeInsets.all(10),
                alignment: Alignment.center,
                child: Text(
                  caption.isNotEmpty ? caption : 'ZEV Post',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ZevColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.38),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Icon(
                (isReel || isVideoPost)
                    ? Icons.play_arrow_rounded
                    : (imageUrl.isNotEmpty
                        ? Icons.photo_rounded
                        : Icons.notes_rounded),
                color: Colors.white,
                size: 16,
              ),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFFF2D55),
                  size: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: ZevColors.white,
                shape: BoxShape.circle,
                border: Border.all(color: ZevColors.border, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: ZevColors.deepNavy.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.favorite_border_rounded,
                size: 34,
                color: Color(0xFFFF2D55),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Liked Media Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Posts and reels you like will show up here so you can revisit them anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: ZevColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: 12,
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: ZevColors.border,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _ActivityReelPlaybackScreen extends StatefulWidget {
  final List<ReelItem> reels;
  final int initialIndex;

  const _ActivityReelPlaybackScreen({
    required this.reels,
    required this.initialIndex,
  });

  @override
  State<_ActivityReelPlaybackScreen> createState() =>
      _ActivityReelPlaybackScreenState();
}

class _ActivityReelPlaybackScreenState
    extends State<_ActivityReelPlaybackScreen> {
  late final PageController _pageController;
  late final List<ReelItem> _reels;
  int _activeIndex = 0;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _reels = List.of(widget.reels);
    _activeIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_reels.isEmpty)
            const Center(
              child: Text(
                'Reel no longer available',
                style: TextStyle(color: Colors.white),
              ),
            )
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _reels.length,
              onPageChanged: (idx) {
                setState(() => _activeIndex = idx);
                ReelVideoCacheManager().pauseAllExcept(_reels[idx].videoUrl);
              },
              itemBuilder: (context, index) {
                final reel = _reels[index];
                return ReelPlayerItem(
                  reel: reel,
                  isActive: index == _activeIndex,
                  isGlobalMuted: _isMuted,
                  onToggleMute: () => setState(() => _isMuted = !_isMuted),
                  onReelDeleted: () {
                    setState(() {
                      _reels.removeWhere((r) => r.id == reel.id);
                    });
                    if (_reels.isEmpty && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                );
              },
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 14,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ZevColors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  border: Border.all(color: ZevColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.deepNavy.withValues(alpha: 0.14),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: ZevColors.deepNavy,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
