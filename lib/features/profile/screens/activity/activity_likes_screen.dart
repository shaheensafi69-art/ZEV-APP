import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/zev_cached_image.dart';
import '../../../feed/screens/post_detail_screen.dart';

/// Instagram-Grade Liked Media Activity Screen for ZEV.
/// Displays all posts and reels liked by the user with interactive tabs,
/// 3-column claymorphic media grid, sort options, and direct post opening.
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

  Future<void> _fetchLikedMedia() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch liked discussion posts
      final postLikesRes = await supabase
          .from('discussion_likes')
          .select('post_id, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(60);

      final postIds = (postLikesRes as List)
          .map((r) => r['post_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      List<Map<String, dynamic>> postsList = [];
      if (postIds.isNotEmpty) {
        final postsRes = await supabase
            .from('discussion_posts')
            .select('id, image_url, video_url, content, created_at, likes_count')
            .inFilter('id', postIds);

        postsList = (postsRes as List).map((p) {
          final imageUrl = (p['image_url'] ?? '').toString();
          return {
            'id': p['id'].toString(),
            'type': 'post',
            'image_url': imageUrl,
            'caption': p['content'] ?? '',
            'likes_count': p['likes_count'] ?? 0,
            'created_at': p['created_at'] ?? '',
          };
        }).toList();
      }

      // 2. Fetch liked reels
      final reelLikesRes = await supabase
          .from('reel_likes')
          .select('reel_id, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(60);

      final reelIds = (reelLikesRes as List)
          .map((r) => r['reel_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      List<Map<String, dynamic>> reelsList = [];
      if (reelIds.isNotEmpty) {
        final reelsRes = await supabase
            .from('reels')
            .select('id, thumbnail_url, video_url, caption, created_at, likes_count')
            .inFilter('id', reelIds);

        reelsList = (reelsRes as List).map((r) {
          final thumb = (r['thumbnail_url'] ?? '').toString();
          return {
            'id': r['id'].toString(),
            'type': 'reel',
            'image_url': thumb,
            'caption': r['caption'] ?? '',
            'likes_count': r['likes_count'] ?? 0,
            'created_at': r['created_at'] ?? '',
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
      debugPrint("Fetch liked media error: $e");
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
      final tA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(2000);
      final tB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(2000);
      return _newestFirst ? tB.compareTo(tA) : tA.compareTo(tB);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final items = _getItemsForActiveTab();
    final totalCount = _likedPosts.length + _likedReels.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF0F172A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            const Text(
              "Likes",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            Text(
              "$totalCount items liked",
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _newestFirst ? Icons.sort_rounded : Icons.swap_vert_rounded,
              color: const Color(0xFF0284C7),
              size: 22,
            ),
            tooltip: _newestFirst ? "Sort: Oldest first" : "Sort: Newest first",
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
            // Segmented Tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    _buildTabPill(index: 0, label: "All", count: totalCount),
                    _buildTabPill(
                        index: 1, label: "Posts", count: _likedPosts.length),
                    _buildTabPill(
                        index: 2, label: "Reels", count: _likedReels.length),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Content Grid
            Expanded(
              child: _isLoading
                  ? _buildShimmerGrid()
                  : items.isEmpty
                      ? _buildEmptyState()
                      : GridView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _buildMediaTile(item);
                          },
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
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
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
                  color: isSelected
                      ? const Color(0xFF0F172A)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                "($count)",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? const Color(0xFF0284C7)
                      : const Color(0xFF94A3B8),
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
    final imageUrl = item['image_url'] as String;
    final postId = item['id'] as String;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (!isReel) {
          PostDetailScreen.open(context, postId: postId);
        } else {
          // Open notification or preview
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Playing liked reel in player..."),
              duration: Duration(seconds: 1),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.95),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              ZevCachedImage.grid(
                imageUrl: imageUrl,
                borderRadius: BorderRadius.circular(16),
              )
            else
              Container(
                color: const Color(0xFFE2E8F0),
                child: Icon(
                  isReel ? Icons.play_arrow_rounded : Icons.image_rounded,
                  color: const Color(0xFF94A3B8),
                  size: 30,
                ),
              ),

            // Top gradient overlay for contrast
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // Media Badge (Reel icon or Post icon)
            Positioned(
              top: 6,
              right: 6,
              child: Icon(
                isReel ? Icons.play_arrow_rounded : Icons.photo_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),

            // Liked Heart Badge (Bottom Left)
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFFFF2D55),
                      size: 12,
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
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.05),
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
              "No Liked Media Yet",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Posts and reels you like will show up here so you can revisit them anytime.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF64748B),
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
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }
}

