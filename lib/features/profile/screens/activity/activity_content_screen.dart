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

/// Instagram-Grade Shared Content Activity Screen for ZEV.
/// Displays all published posts and reels with view counts, likes, and direct navigation.
class ActivityContentScreen extends StatefulWidget {
  final int initialTabIndex; // 0 = Posts, 1 = Reels

  const ActivityContentScreen({super.key, this.initialTabIndex = 0});

  static Future<void> open(BuildContext context, {int initialTabIndex = 0}) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityContentScreen(initialTabIndex: initialTabIndex),
      ),
    );
  }

  @override
  State<ActivityContentScreen> createState() => _ActivityContentScreenState();
}

class _ActivityContentScreenState extends State<ActivityContentScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TabController _tabCtrl;

  bool _isLoading = true;
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _reels = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _fetchMyContent();
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

  Future<void> _fetchMyContent() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      // 1. Fetch user's published posts (`student_id`, not archived, scheduled, or soft-deleted)
      final results = await Future.wait([
        supabase
            .from('discussion_posts')
            .select(
              'id, title, image_url, content, created_at, likes_count, comments_count',
            )
            .eq('student_id', userId)
            .isFilter('deleted_at', null)
            .eq('is_draft', false)
            .or('scheduled_at.is.null,scheduled_at.lte.$nowIso')
            .order('created_at', ascending: false),
        supabase
            .from('reels')
            .select(
              'id, user_id, title, description, category, duration_seconds, '
              'thumbnail_url, video_url, created_at, likes_count, comments_count, views_count',
            )
            .eq('user_id', userId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false),
        supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .eq('id', userId)
            .maybeSingle(),
      ]);

      final postsRes = results[0] as List;
      final reelsRes = results[1] as List;
      final myProfile = results[2] as Map<String, dynamic>?;

      final fn = (myProfile?['first_name'] ?? '').toString().trim();
      final ln = (myProfile?['last_name'] ?? '').toString().trim();
      final fullName = '$fn $ln'.trim();
      final username = (myProfile?['username'] ?? 'me').toString();
      final avatarUrl = (myProfile?['avatar_url'] ?? '').toString();
      final isVerified = myProfile?['is_verified'] == true;

      final pList = postsRes.map((p) {
        final imageUrl = (p['image_url'] ?? '').toString();
        final title = (p['title'] ?? '').toString();
        final content = (p['content'] ?? '').toString();
        return {
          'id': p['id'].toString(),
          'type': 'post',
          'image_url': imageUrl,
          'is_video': _isVideoMediaUrl(imageUrl),
          'caption': content.isNotEmpty ? content : title,
          'likes_count': p['likes_count'] ?? 0,
          'comments_count': p['comments_count'] ?? 0,
          'created_at': p['created_at'] ?? '',
        };
      }).toList();

      final reelIds = reelsRes.map((r) => r['id'].toString()).toList();
      final likedReelIds = <String>{};
      final savedReelIds = <String>{};
      if (reelIds.isNotEmpty) {
        try {
          final likeBm = await Future.wait([
            supabase
                .from('reel_likes')
                .select('reel_id')
                .eq('user_id', userId)
                .inFilter('reel_id', reelIds),
            supabase
                .from('reel_bookmarks')
                .select('reel_id')
                .eq('user_id', userId)
                .inFilter('reel_id', reelIds),
          ]);
          for (final row in (likeBm[0] as List)) {
            final rid = row['reel_id']?.toString() ?? '';
            if (rid.isNotEmpty) likedReelIds.add(rid);
          }
          for (final row in (likeBm[1] as List)) {
            final rid = row['reel_id']?.toString() ?? '';
            if (rid.isNotEmpty) savedReelIds.add(rid);
          }
        } catch (_) {}
      }

      final rList = reelsRes.map((r) {
        final id = r['id'].toString();
        final reelItem = ReelItem(
          id: id,
          userId: userId,
          authorUsername: username,
          authorFullName: fullName.isNotEmpty ? fullName : username,
          authorAvatar: avatarUrl,
          isVerified: isVerified,
          videoUrl: (r['video_url'] ?? '').toString(),
          thumbnailUrl: r['thumbnail_url']?.toString(),
          title: (r['title'] ?? '').toString(),
          description: (r['description'] ?? '').toString(),
          category: (r['category'] ?? 'Explore').toString(),
          durationSeconds: (r['duration_seconds'] as int?) ?? 30,
          viewsCount: (r['views_count'] as int?) ?? 0,
          likesCount: (r['likes_count'] as int?) ?? 0,
          isLikedByMe: likedReelIds.contains(id),
          commentsCount: (r['comments_count'] as int?) ?? 0,
          isBookmarkedByMe: savedReelIds.contains(id),
          isAuthorFollowed: false,
          createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
              DateTime.now(),
        );

        return {
          'id': id,
          'type': 'reel',
          'image_url': reelItem.thumbnailUrl ?? '',
          'video_url': reelItem.videoUrl,
          'caption':
              reelItem.title.isNotEmpty ? reelItem.title : reelItem.description,
          'likes_count': reelItem.likesCount,
          'views_count': reelItem.viewsCount,
          'created_at': r['created_at'] ?? '',
          'reel_item': reelItem,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _posts = pList;
          _reels = rList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch my content error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openReelPlayer(ReelItem tappedReel) async {
    final allReels = _reels
        .where((e) => e['reel_item'] is ReelItem)
        .map((e) => e['reel_item'] as ReelItem)
        .toList();
    if (allReels.isEmpty) allReels.add(tappedReel);

    final startIndex = allReels.indexWhere((r) => r.id == tappedReel.id);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ContentReelPlayerScreen(
          reels: allReels,
          initialIndex: startIndex >= 0 ? startIndex : 0,
        ),
      ),
    );
    ReelVideoCacheManager().pauseAll();
    await _fetchMyContent();
  }

  @override
  Widget build(BuildContext context) {
    final activeList = _tabCtrl.index == 0 ? _posts : _reels;
    final isReels = _tabCtrl.index == 1;

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
              'Shared Content',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '${_posts.length} posts • ${_reels.length} reels',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: ZevColors.textMuted,
              ),
            ),
          ],
        ),
        centerTitle: true,
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
                    _buildTabPill(
                      index: 0,
                      label: 'Posts & Photos',
                      count: _posts.length,
                    ),
                    _buildTabPill(
                      index: 1,
                      label: 'Reels',
                      count: _reels.length,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _isLoading
                  ? _buildShimmerGrid()
                  : activeList.isEmpty
                      ? _buildEmptyState(isReels)
                      : RefreshIndicator(
                          color: ZevColors.primaryBlue,
                          onRefresh: _fetchMyContent,
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
                            itemCount: activeList.length,
                            itemBuilder: (context, index) =>
                                _buildGridItem(activeList[index], isReels),
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

  Widget _buildGridItem(Map<String, dynamic> item, bool isReel) {
    final imageUrl = (item['image_url'] ?? '').toString();
    final videoUrl = (item['video_url'] ?? '').toString();
    final isVideoPost = item['is_video'] == true;
    final caption = (item['caption'] ?? '').toString();
    final postId = item['id'].toString();
    final likesCount = (item['likes_count'] as int?) ?? 0;
    final viewsCount = (item['views_count'] as int?) ?? 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (!isReel) {
          PostDetailScreen.open(context, postId: postId).then((_) {
            if (mounted) _fetchMyContent();
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
                  caption.isNotEmpty ? caption : 'Text Post',
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
                height: 28,
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
                    : Icons.grid_on_rounded,
                color: Colors.white,
                size: 15,
              ),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isReel
                          ? Icons.visibility_rounded
                          : Icons.favorite_rounded,
                      color: Colors.white,
                      size: 11,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isReel ? '$viewsCount' : '$likesCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
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
    );
  }

  Widget _buildEmptyState(bool isReel) {
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
              child: Icon(
                isReel
                    ? Icons.video_library_outlined
                    : Icons.grid_on_rounded,
                size: 34,
                color: ZevColors.secondaryBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isReel ? 'No Reels Published' : 'No Posts Published',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isReel
                  ? 'Reels you create and share will be listed here with performance statistics.'
                  : 'Photos and thoughts you share will appear here for quick review.',
              textAlign: TextAlign.center,
              style: const TextStyle(
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
      itemCount: 9,
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: ZevColors.border,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _ContentReelPlayerScreen extends StatefulWidget {
  final List<ReelItem> reels;
  final int initialIndex;

  const _ContentReelPlayerScreen({
    required this.reels,
    required this.initialIndex,
  });

  @override
  State<_ContentReelPlayerScreen> createState() =>
      _ContentReelPlayerScreenState();
}

class _ContentReelPlayerScreenState extends State<_ContentReelPlayerScreen> {
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
                'Reel removed',
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
