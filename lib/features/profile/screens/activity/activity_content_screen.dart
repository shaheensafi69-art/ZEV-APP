import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/zev_cached_image.dart';
import '../../../feed/screens/post_detail_screen.dart';

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

  Future<void> _fetchMyContent() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch user's posts
      final postsRes = await supabase
          .from('discussion_posts')
          .select('id, image_url, video_url, content, created_at, likes_count, comments_count')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final pList = (postsRes as List).map((p) {
        return {
          'id': p['id'].toString(),
          'type': 'post',
          'image_url': (p['image_url'] ?? '').toString(),
          'caption': p['content'] ?? '',
          'likes_count': p['likes_count'] ?? 0,
          'comments_count': p['comments_count'] ?? 0,
          'created_at': p['created_at'] ?? '',
        };
      }).toList();

      // 2. Fetch user's reels
      final reelsRes = await supabase
          .from('reels')
          .select('id, thumbnail_url, video_url, caption, created_at, likes_count, views_count')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final rList = (reelsRes as List).map((r) {
        return {
          'id': r['id'].toString(),
          'type': 'reel',
          'image_url': (r['thumbnail_url'] ?? '').toString(),
          'caption': r['caption'] ?? '',
          'likes_count': r['likes_count'] ?? 0,
          'views_count': r['views_count'] ?? 0,
          'created_at': r['created_at'] ?? '',
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
      debugPrint("Fetch my content error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeList = _tabCtrl.index == 0 ? _posts : _reels;
    final isReels = _tabCtrl.index == 1;

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
              "Shared Content",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            Text(
              "${_posts.length} posts • ${_reels.length} reels",
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
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
                    _buildTabPill(
                        index: 0, label: "Posts & Photos", count: _posts.length),
                    _buildTabPill(
                        index: 1, label: "Reels", count: _reels.length),
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
                          itemCount: activeList.length,
                          itemBuilder: (context, index) {
                            final item = activeList[index];
                            return _buildGridItem(item, isReels);
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

  Widget _buildGridItem(Map<String, dynamic> item, bool isReel) {
    final imageUrl = item['image_url'] as String;
    final postId = item['id'] as String;
    final likesCount = item['likes_count'] as int;
    final viewsCount = item['views_count'] ?? 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (!isReel) {
          PostDetailScreen.open(context, postId: postId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Opening reel in viewer..."),
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
                  isReel ? Icons.play_arrow_rounded : Icons.photo_rounded,
                  color: const Color(0xFF94A3B8),
                  size: 30,
                ),
              ),

            // Top gradient overlay
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 28,
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

            // Top indicator icon
            Positioned(
              top: 6,
              right: 6,
              child: Icon(
                isReel ? Icons.play_arrow_rounded : Icons.grid_on_rounded,
                color: Colors.white,
                size: 15,
              ),
            ),

            // Bottom metric pill
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
                      isReel ? Icons.visibility_rounded : Icons.favorite_rounded,
                      color: Colors.white,
                      size: 11,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isReel ? "$viewsCount" : "$likesCount",
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
              child: Icon(
                isReel ? Icons.video_library_outlined : Icons.grid_on_rounded,
                size: 34,
                color: const Color(0xFF0284C7),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isReel ? "No Reels Published" : "No Posts Published",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isReel
                  ? "Reels you create and share will be listed here with performance statistics."
                  : "Photos and thoughts you share will be archived here for quick review.",
              textAlign: TextAlign.center,
              style: const TextStyle(
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
      itemCount: 9,
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

