import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zev_theme.dart';
import '../models/feed_post_item.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/feed_share_sheet.dart';

/// Flagship Instagram-Grade Single Post Detail Screen for ZEV.
/// Handles Deep Links (https://zevapp.com/post/:id), push notification clicks,
/// and in-app navigation to a standalone post.
class PostDetailScreen extends StatefulWidget {
  final String postId;
  final FeedPostItem? initialPost;

  const PostDetailScreen({
    super.key,
    required this.postId,
    this.initialPost,
  });

  static Future<void> open(
    BuildContext context, {
    required String postId,
    FeedPostItem? initialPost,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          postId: postId,
          initialPost: initialPost,
        ),
      ),
    );
  }

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final supabase = Supabase.instance.client;

  FeedPostItem? _post;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialPost != null) {
      _post = widget.initialPost;
      _isLoading = false;
    }
    _fetchPostDetails();
  }

  Future<void> _fetchPostDetails() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;

      // 1. Fetch raw post from discussion_posts
      final rawPost = await supabase
          .from('discussion_posts')
          .select('id, student_id, title, content, image_url, created_at')
          .eq('id', widget.postId)
          .maybeSingle();

      if (rawPost == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "Post not found or has been removed.";
          });
        }
        return;
      }

      final authorId = rawPost['student_id']?.toString() ?? '';

      // 2. Fetch author profile
      Map<String, dynamic> profile = {};
      if (authorId.isNotEmpty) {
        final profRes = await supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .eq('id', authorId)
            .maybeSingle();
        if (profRes != null) {
          profile = Map<String, dynamic>.from(profRes);
        }
      }

      // 3. Fetch likes count & status
      int likesCount = 0;
      bool isLiked = false;
      try {
        final likesRes = await supabase
            .from('discussion_likes')
            .select('student_id')
            .eq('post_id', widget.postId);
        final list = likesRes as List;
        likesCount = list.length;
        if (currentUserId != null) {
          isLiked = list.any((l) => l['student_id']?.toString() == currentUserId);
        }
      } catch (_) {}

      // 4. Fetch comments count
      int commentsCount = 0;
      try {
        final commRes = await supabase
            .from('discussion_comments')
            .select('id')
            .eq('post_id', widget.postId);
        commentsCount = (commRes as List).length;
      } catch (_) {}

      // 5. Fetch reposts count & status
      int repostsCount = 0;
      bool isReposted = false;
      try {
        final repRes = await supabase
            .from('post_reposts')
            .select('user_id')
            .eq('post_id', widget.postId);
        final list = repRes as List;
        repostsCount = list.length;
        if (currentUserId != null) {
          isReposted = list.any((r) => r['user_id']?.toString() == currentUserId);
        }
      } catch (_) {}

      // 6. Fetch follow status
      bool isFollowing = false;
      if (currentUserId != null && authorId.isNotEmpty && currentUserId != authorId) {
        try {
          final followRes = await supabase
              .from('user_follows')
              .select('id')
              .eq('follower_id', currentUserId)
              .eq('following_id', authorId)
              .maybeSingle();
          if (followRes != null) isFollowing = true;
        } catch (_) {}
      }

      final fn = profile['first_name'] ?? '';
      final ln = profile['last_name'] ?? '';
      final fullName = "$fn $ln".trim();

      final parsedItem = FeedPostItem(
        id: widget.postId,
        authorId: authorId,
        authorUsername: profile['username'] ?? (fullName.isNotEmpty ? fullName : 'user'),
        authorFullName: fullName.isNotEmpty ? fullName : (profile['username'] ?? 'User'),
        authorAvatar: profile['avatar_url'] ?? '',
        isVerified: profile['is_verified'] == true,
        title: rawPost['title'] ?? '',
        content: rawPost['content'] ?? '',
        imageUrl: rawPost['image_url'] ?? '',
        createdAt: DateTime.tryParse(rawPost['created_at']?.toString() ?? '') ?? DateTime.now(),
        likesCount: likesCount,
        isLikedByMe: isLiked,
        commentsCount: commentsCount,
        categoryTag: 'Post',
        repostsCount: repostsCount,
        isRepostedByMe: isReposted,
        isAuthorFollowed: isFollowing,
      );

      if (mounted) {
        setState(() {
          _post = parsedItem;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Could not load post: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZevColors.white,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: ZevColors.deepNavy, size: 20),
          onPressed: () {
            HapticFeedback.lightImpact();
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.of(context).pushReplacementNamed('/');
            }
          },
        ),
        title: const Text(
          "Post",
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_post != null)
            IconButton(
              icon: const Icon(Icons.share_outlined, color: ZevColors.deepNavy, size: 22),
              onPressed: () {
                FeedShareSheet.show(context, post: _post!);
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: ZevColors.primaryBlue,
          strokeWidth: 2.5,
        ),
      );
    }

    if (_errorMessage != null || _post == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: ZevColors.softSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: ZevColors.border),
                ),
                child: const Icon(
                  Icons.link_off_rounded,
                  color: ZevColors.textMuted,
                  size: 34,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Post Unavailable",
                style: TextStyle(
                  color: ZevColors.deepNavy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? "This post may have been deleted or the link is invalid.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ZevColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text("Go Back"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.deepNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: ZevColors.primaryBlue,
      onRefresh: _fetchPostDetails,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 40),
        child: FeedPostCard(
          post: _post!,
          onCommentsUpdated: _fetchPostDetails,
        ),
      ),
    );
  }
}

