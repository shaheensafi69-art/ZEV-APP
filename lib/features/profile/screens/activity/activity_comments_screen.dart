import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/zev_theme.dart';
import '../../../feed/screens/post_detail_screen.dart';
import '../../../reels/models/reel_item.dart';
import '../../../reels/services/reel_video_cache_manager.dart';
import '../../../reels/widgets/reel_comments_sheet.dart';
import '../../../reels/widgets/reel_player_item.dart';

/// Instagram-Grade Comments Activity Screen for ZEV.
/// Displays all comments posted by the user across posts and reels with quick navigation and deletion.
class ActivityCommentsScreen extends StatefulWidget {
  const ActivityCommentsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ActivityCommentsScreen(),
      ),
    );
  }

  @override
  State<ActivityCommentsScreen> createState() => _ActivityCommentsScreenState();
}

class _ActivityCommentsScreenState extends State<ActivityCommentsScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _comments = [];

  @override
  void initState() {
    super.initState();
    _fetchUserComments();
  }

  Future<void> _fetchUserComments() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final results = await Future.wait([
        supabase
            .from('discussion_comments')
            .select('id, post_id, comment_text, created_at, likes_count')
            .eq('student_id', userId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .limit(60),
        supabase
            .from('reel_comments')
            .select('id, reel_id, comment_text, created_at, likes_count')
            .eq('user_id', userId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .limit(60),
      ]);

      final List<Map<String, dynamic>> list = [];
      for (final row in (results[0] as List)) {
        list.add({
          'id': row['id'].toString(),
          'type': 'post',
          'target_id': row['post_id']?.toString() ?? '',
          'content': (row['comment_text'] ?? '').toString(),
          'likes_count': (row['likes_count'] as int?) ?? 0,
          'created_at': (row['created_at'] ?? '').toString(),
        });
      }

      for (final row in (results[1] as List)) {
        list.add({
          'id': row['id'].toString(),
          'type': 'reel',
          'target_id': row['reel_id']?.toString() ?? '',
          'content': (row['comment_text'] ?? '').toString(),
          'likes_count': (row['likes_count'] as int?) ?? 0,
          'created_at': (row['created_at'] ?? '').toString(),
        });
      }

      list.sort((a, b) {
        final tA = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime(2000);
        final tB = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime(2000);
        return tB.compareTo(tA);
      });

      if (mounted) {
        setState(() {
          _comments = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch user comments error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openReelFromComment(String reelId) async {
    final userId = supabase.auth.currentUser?.id;
    try {
      final row = await supabase
          .from('reels')
          .select(
            'id, user_id, title, description, category, duration_seconds, '
            'thumbnail_url, video_url, views_count, likes_count, comments_count, created_at',
          )
          .eq('id', reelId)
          .isFilter('deleted_at', null)
          .maybeSingle();

      if (!mounted) return;
      if (row == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This reel is no longer available.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final authorId = (row['user_id'] ?? '').toString();
      final prof = authorId.isNotEmpty
          ? await supabase
              .from('profiles')
              .select('id, username, first_name, last_name, avatar_url, is_verified')
              .eq('id', authorId)
              .maybeSingle()
          : null;

      bool isLiked = false;
      bool isSaved = false;
      bool isFollowed = false;
      if (userId != null) {
        final checks = await Future.wait([
          supabase
              .from('reel_likes')
              .select('id')
              .eq('reel_id', reelId)
              .eq('user_id', userId)
              .maybeSingle(),
          supabase
              .from('reel_bookmarks')
              .select('id')
              .eq('reel_id', reelId)
              .eq('user_id', userId)
              .maybeSingle(),
          if (authorId.isNotEmpty && authorId != userId)
            supabase
                .from('follows')
                .select('id')
                .eq('follower_id', userId)
                .eq('following_id', authorId)
                .eq('status', 'accepted')
                .maybeSingle(),
        ]);
        isLiked = checks[0] != null;
        isSaved = checks[1] != null;
        isFollowed = checks.length > 2 && checks[2] != null;
      }

      final fn = (prof?['first_name'] ?? '').toString().trim();
      final ln = (prof?['last_name'] ?? '').toString().trim();
      final fullName = '$fn $ln'.trim();
      final username = (prof?['username'] ?? 'creator').toString();

      final reel = ReelItem(
        id: row['id'].toString(),
        userId: authorId,
        authorUsername: username,
        authorFullName: fullName.isNotEmpty ? fullName : username,
        authorAvatar: (prof?['avatar_url'] ?? '').toString(),
        isVerified: prof?['is_verified'] == true,
        videoUrl: (row['video_url'] ?? '').toString(),
        thumbnailUrl: row['thumbnail_url']?.toString(),
        title: (row['title'] ?? '').toString(),
        description: (row['description'] ?? '').toString(),
        category: (row['category'] ?? 'Explore').toString(),
        durationSeconds: (row['duration_seconds'] as int?) ?? 30,
        viewsCount: (row['views_count'] as int?) ?? 0,
        likesCount: (row['likes_count'] as int?) ?? 0,
        isLikedByMe: isLiked,
        commentsCount: (row['comments_count'] as int?) ?? 0,
        isBookmarkedByMe: isSaved,
        isAuthorFollowed: isFollowed,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _SingleCommentReelScreen(
            reel: reel,
            onRefreshNeeded: _fetchUserComments,
          ),
        ),
      );
      ReelVideoCacheManager().pauseAll();
      await _fetchUserComments();
    } catch (e) {
      debugPrint('Open reel from comment error: $e');
    }
  }

  Future<void> _deleteOwnComment(Map<String, dynamic> item) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZevColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Comment?',
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'This will remove your comment from the thread.',
          style: TextStyle(color: ZevColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: ZevColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final id = item['id'].toString();
    final isReel = item['type'] == 'reel';
    try {
      if (isReel) {
        await supabase
            .from('reel_comments')
            .delete()
            .eq('id', id)
            .eq('user_id', userId);
      } else {
        await supabase
            .from('discussion_comments')
            .delete()
            .eq('id', id)
            .eq('student_id', userId);
      }
      if (!mounted) return;
      setState(() {
        _comments.removeWhere((c) => c['id'].toString() == id);
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('Delete comment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete comment.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatTimestamp(String ts) {
    final dt = DateTime.tryParse(ts);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dt.year}/${dt.month}/${dt.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
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
              'Comments',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '${_comments.length} comments shared',
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
        child: _isLoading
            ? _buildShimmerList()
            : _comments.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    color: ZevColors.primaryBlue,
                    onRefresh: _fetchUserComments,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
                      itemCount: _comments.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _buildCommentCard(_comments[index]),
                    ),
                  ),
      ),
    );
  }

  Widget _buildCommentCard(Map<String, dynamic> item) {
    final isReel = item['type'] == 'reel';
    final content = (item['content'] ?? '').toString();
    final targetId = (item['target_id'] ?? '').toString();
    final likesCount = (item['likes_count'] as int?) ?? 0;
    final timeStr = _formatTimestamp((item['created_at'] ?? '').toString());

    return Container(
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ZevColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.lightImpact();
            if (!isReel && targetId.isNotEmpty) {
              PostDetailScreen.open(context, postId: targetId).then((_) {
                if (mounted) _fetchUserComments();
              });
            } else if (isReel && targetId.isNotEmpty) {
              _openReelFromComment(targetId);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ZevColors.primaryBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isReel
                        ? Icons.play_arrow_rounded
                        : Icons.chat_bubble_rounded,
                    color: ZevColors.secondaryBlue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isReel ? 'Comment on Reel' : 'Comment on Post',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: ZevColors.textSecondary,
                            ),
                          ),
                          Row(
                            children: [
                              if (likesCount > 0) ...[
                                const Icon(
                                  Icons.favorite_rounded,
                                  size: 12,
                                  color: Color(0xFFFF2D55),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$likesCount  •  ',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: ZevColors.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              Text(
                                timeStr,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: ZevColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        content,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: ZevColors.deepNavy,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: ZevColors.textMuted,
                  ),
                  tooltip: 'Delete comment',
                  onPressed: () => _deleteOwnComment(item),
                ),
              ],
            ),
          ),
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
                Icons.chat_bubble_outline_rounded,
                size: 34,
                color: ZevColors.secondaryBlue,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Comments Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'When you comment on posts and reels across ZEV, they will appear here.',
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

  Widget _buildShimmerList() {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      itemCount: 6,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) => Container(
        height: 76,
        decoration: BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ZevColors.border),
        ),
      ),
    );
  }
}

class _SingleCommentReelScreen extends StatefulWidget {
  final ReelItem reel;
  final VoidCallback onRefreshNeeded;

  const _SingleCommentReelScreen({
    required this.reel,
    required this.onRefreshNeeded,
  });

  @override
  State<_SingleCommentReelScreen> createState() =>
      _SingleCommentReelScreenState();
}

class _SingleCommentReelScreenState extends State<_SingleCommentReelScreen> {
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ReelCommentsSheet.show(
          context,
          reelId: widget.reel.id,
          reelAuthorUsername: widget.reel.authorUsername,
          reelAuthorId: widget.reel.userId,
          onCommentDeleted: widget.onRefreshNeeded,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ReelPlayerItem(
            reel: widget.reel,
            isActive: true,
            isGlobalMuted: _isMuted,
            onToggleMute: () => setState(() => _isMuted = !_isMuted),
            onReelDeleted: () {
              if (mounted) Navigator.pop(context);
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
