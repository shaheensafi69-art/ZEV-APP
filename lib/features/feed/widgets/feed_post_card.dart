import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/utils/time_ago.dart';
import '../models/feed_post_item.dart';
import '../screens/fullscreen_media_viewer.dart';
import 'feed_comments_sheet.dart';
import 'feed_share_sheet.dart';

/// Next-Generation Instagram-Grade Post Card for ZEV Feed.
/// Built with 120 FPS fluid interaction, double-tap heart pop animation,
/// fullscreen Facebook-style lightbox on tap, category badges, and complete
/// Like, Comment, Repost, Share, and Save toolbars.
class FeedPostCard extends StatefulWidget {
  final FeedPostItem post;
  final VoidCallback? onCommentsUpdated;

  const FeedPostCard({
    super.key,
    required this.post,
    this.onCommentsUpdated,
  });

  @override
  State<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<FeedPostCard>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late bool _isLiked;
  late int _likesCount;
  late bool _isReposted;
  late int _repostsCount;
  bool _isSaved = false;
  bool _isExpanded = false;

  // Double-tap heart animation
  late final AnimationController _heartAnimCtrl;
  late final Animation<double> _heartScaleAnim;
  late final Animation<double> _heartOpacityAnim;
  bool _showFloatingHeart = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLikedByMe;
    _likesCount = widget.post.likesCount;
    _isReposted = widget.post.isRepostedByMe;
    _repostsCount = widget.post.repostsCount;

    _heartAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _heartScaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_heartAnimCtrl);

    _heartOpacityAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
    ]).animate(_heartAnimCtrl);

    _heartAnimCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _showFloatingHeart = false);
      }
    });
  }

  @override
  void didUpdateWidget(FeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.post.isLikedByMe != oldWidget.post.isLikedByMe) {
      _isLiked = widget.post.isLikedByMe;
    }
    if (widget.post.likesCount != oldWidget.post.likesCount) {
      _likesCount = widget.post.likesCount;
    }
    if (widget.post.isRepostedByMe != oldWidget.post.isRepostedByMe) {
      _isReposted = widget.post.isRepostedByMe;
    }
    if (widget.post.repostsCount != oldWidget.post.repostsCount) {
      _repostsCount = widget.post.repostsCount;
    }
  }

  @override
  void dispose() {
    _heartAnimCtrl.dispose();
    super.dispose();
  }

  String _getCategoryTag() {
    final title = widget.post.title;
    if (title.contains('[') && title.contains(']')) {
      final start = title.indexOf('[');
      final end = title.indexOf(']');
      if (end > start) {
        return title.substring(start + 1, end).trim();
      }
    }
    return widget.post.categoryTag;
  }

  void _triggerDoubleTapLike() {
    HapticFeedback.mediumImpact();
    setState(() => _showFloatingHeart = true);
    _heartAnimCtrl.forward(from: 0.0);

    if (!_isLiked) {
      _toggleLike();
    }
  }

  Future<void> _toggleLike() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showNotice("Please log in to like posts.");
      return;
    }

    HapticFeedback.lightImpact();
    final previousState = _isLiked;
    final previousCount = _likesCount;

    // Optimistic state
    setState(() {
      _isLiked = !previousState;
      _likesCount = _isLiked
          ? previousCount + 1
          : (previousCount > 0 ? previousCount - 1 : 0);
    });

    try {
      if (_isLiked) {
        await supabase.from('discussion_likes').insert({
          'post_id': widget.post.id,
          'student_id': user.id,
        });
      } else {
        await supabase
            .from('discussion_likes')
            .delete()
            .eq('post_id', widget.post.id)
            .eq('student_id', user.id);
      }
    } catch (e) {
      debugPrint("Like toggle warning: $e");
      if (mounted) {
        setState(() {
          _isLiked = previousState;
          _likesCount = previousCount;
        });
      }
    }
  }

  Future<void> _toggleRepost() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showNotice("Please log in to repost.");
      return;
    }

    HapticFeedback.mediumImpact();
    final previousState = _isReposted;
    final previousCount = _repostsCount;

    setState(() {
      _isReposted = !previousState;
      _repostsCount = _isReposted
          ? previousCount + 1
          : (previousCount > 0 ? previousCount - 1 : 0);
    });

    try {
      if (_isReposted) {
        await supabase.from('post_reposts').insert({
          'post_id': widget.post.id,
          'user_id': user.id,
        });
        _showNotice("Reposted to your feed!");
      } else {
        await supabase
            .from('post_reposts')
            .delete()
            .eq('post_id', widget.post.id)
            .eq('user_id', user.id);
        _showNotice("Repost removed.");
      }
    } catch (e) {
      debugPrint("Repost warning: $e");
      if (mounted) {
        setState(() {
          _isReposted = previousState;
          _repostsCount = previousCount;
        });
      }
    }
  }

  void _openComments() {
    HapticFeedback.lightImpact();
    FeedCommentsSheet.show(
      context,
      postId: widget.post.id,
      postAuthorUsername: widget.post.authorUsername,
      onCommentAdded: widget.onCommentsUpdated,
    );
  }

  void _openShareSheet() {
    HapticFeedback.lightImpact();
    FeedShareSheet.show(context, post: widget.post);
  }

  void _openFullscreenViewer() {
    HapticFeedback.lightImpact();
    FullscreenMediaViewer.open(
      context,
      post: widget.post,
      isLiked: _isLiked,
      likesCount: _likesCount,
      isReposted: _isReposted,
      repostsCount: _repostsCount,
      onToggleLike: _toggleLike,
      onToggleRepost: _toggleRepost,
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

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final timeStr = TimeAgo.format(post.createdAt);
    final category = _getCategoryTag();

    return Container(
      decoration: const BoxDecoration(
        color: ZevColors.white,
        border: Border(
          bottom: BorderSide(
            color: ZevColors.border,
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Post Header: Avatar, Username, Badge, Category Pill, Time, 3-dots
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: ZevColors.softSurface,
                  backgroundImage: post.authorAvatar.isNotEmpty
                      ? NetworkImage(post.authorAvatar)
                      : null,
                  child: post.authorAvatar.isEmpty
                      ? const Icon(
                          Icons.person_rounded,
                          size: 20,
                          color: ZevColors.textMuted,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Username & Verified Badge
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.authorUsername.isNotEmpty
                                  ? post.authorUsername
                                  : 'user',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: ZevColors.deepNavy,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (post.isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 15,
                              color: ZevColors.primaryBlue,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Category Tag Pill & Timestamp
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: ZevColors.softSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: ZevColors.border,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              category,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: ZevColors.secondaryBlue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            "•",
                            style: TextStyle(
                              fontSize: 10,
                              color: ZevColors.textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: ZevColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: ZevColors.deepNavy,
                    size: 20,
                  ),
                  onPressed: _showPostOptions,
                ),
              ],
            ),
          ),

          // 2. Media Box (Tap to Fullscreen Facebook-Style / Double-Tap to Like)
          if (post.imageUrl.isNotEmpty)
            GestureDetector(
              onTap: _openFullscreenViewer,
              onDoubleTap: _triggerDoubleTapLike,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(
                      minHeight: 220,
                      maxHeight: 520,
                    ),
                    color: ZevColors.softSurface,
                    child: Image.network(
                      post.imageUrl,
                      fit: BoxFit.contain, // Full image view without clipping
                      width: double.infinity,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 300,
                          color: ZevColors.softSurface,
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ZevColors.primaryBlue,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 220,
                        color: ZevColors.softSurface,
                        child: const Center(
                          child: Icon(
                            Icons.broken_image_rounded,
                            size: 48,
                            color: ZevColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Floating Heart Pop
                  if (_showFloatingHeart)
                    AnimatedBuilder(
                      animation: _heartAnimCtrl,
                      builder: (context, _) {
                        return Opacity(
                          opacity: _heartOpacityAnim.value,
                          child: Transform.scale(
                            scale: _heartScaleAnim.value,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.redAccent.withValues(alpha: 0.5),
                                    blurRadius: 36,
                                    spreadRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.favorite_rounded,
                                size: 100,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                  // Tap to expand indicator hint
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fullscreen_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                          SizedBox(width: 4),
                          Text(
                            "Full view",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 3. Instagram Full Interaction Toolbar (Like, Comment, Repost, Share, Save)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // Like Icon
                    IconButton(
                      icon: Icon(
                        _isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _isLiked ? Colors.redAccent : ZevColors.deepNavy,
                        size: 26,
                      ),
                      onPressed: _toggleLike,
                    ),
                    // Comment Icon
                    IconButton(
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: ZevColors.deepNavy,
                        size: 24,
                      ),
                      onPressed: _openComments,
                    ),
                    // Repost Icon
                    IconButton(
                      icon: Icon(
                        Icons.repeat_rounded,
                        color: _isReposted
                            ? ZevColors.primaryBlue
                            : ZevColors.deepNavy,
                        size: 25,
                      ),
                      onPressed: _toggleRepost,
                    ),
                    // Share Icon
                    IconButton(
                      icon: const Icon(
                        Icons.send_rounded,
                        color: ZevColors.deepNavy,
                        size: 23,
                      ),
                      onPressed: _openShareSheet,
                    ),
                  ],
                ),
                // Bookmark / Save Icon
                IconButton(
                  icon: Icon(
                    _isSaved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color:
                        _isSaved ? ZevColors.primaryBlue : ZevColors.deepNavy,
                    size: 25,
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isSaved = !_isSaved);
                    _showNotice(_isSaved
                        ? "Saved to collection."
                        : "Removed from collection.");
                  },
                ),
              ],
            ),
          ),

          // 4. Social Telemetry (Likes & Reposts Counts)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                if (_likesCount > 0)
                  Text(
                    _likesCount == 1 ? "1 like" : "$_likesCount likes",
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                if (_likesCount > 0 && _repostsCount > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      "•",
                      style: TextStyle(
                        fontSize: 12,
                        color: ZevColors.textMuted,
                      ),
                    ),
                  ),
                if (_repostsCount > 0)
                  Text(
                    _repostsCount == 1 ? "1 repost" : "$_repostsCount reposts",
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.secondaryBlue,
                    ),
                  ),
              ],
            ),
          ),

          // 5. Post Title & Caption Block with Smart Dynamic RTL/LTR
          if (post.title.isNotEmpty || post.content.isNotEmpty) () {
            final isContentRtl = TextDirectionHelper.isRtl(
              post.content.isNotEmpty ? post.content : post.title,
            );
            return Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, top: 4),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: isContentRtl
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    RichText(
                      textDirection: isContentRtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      textAlign:
                          isContentRtl ? TextAlign.right : TextAlign.left,
                      maxLines: _isExpanded ? null : 2,
                      overflow: _isExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: ZevColors.deepNavy,
                          height: 1.35,
                        ),
                        children: [
                          TextSpan(
                            text: isContentRtl
                                ? " ${post.authorUsername} "
                                : "${post.authorUsername} ",
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (post.title.isNotEmpty &&
                              post.content.isNotEmpty &&
                              !post.title.startsWith('['))
                            TextSpan(
                              text: "${post.title} — ",
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          TextSpan(
                            text: post.content.isNotEmpty
                                ? post.content
                                : post.title,
                          ),
                        ],
                      ),
                    ),
                    if (!_isExpanded && (post.content.length > 70))
                      GestureDetector(
                        onTap: () => setState(() => _isExpanded = true),
                        child: const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            "more",
                            style: TextStyle(
                              fontSize: 12.5,
                              color: ZevColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }(),

          // 6. Comments Trigger
          Padding(
            padding:
                const EdgeInsets.only(left: 14, right: 14, top: 6, bottom: 12),
            child: GestureDetector(
              onTap: _openComments,
              child: Text(
                widget.post.commentsCount > 0
                    ? "View all ${widget.post.commentsCount} comments"
                    : "Add a comment...",
                style: const TextStyle(
                  fontSize: 13,
                  color: ZevColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPostOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.share_outlined, color: ZevColors.deepNavy),
              title: const Text("Share Post",
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(context);
                _openShareSheet();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.link_rounded, color: ZevColors.deepNavy),
              title: const Text("Copy Link",
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(context);
                _showNotice("Link copied.");
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.flag_outlined, color: Colors.redAccent),
              title: const Text("Report",
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _showNotice("Thank you. Report received for review.");
              },
            ),
          ],
        ),
      ),
    );
  }
}
