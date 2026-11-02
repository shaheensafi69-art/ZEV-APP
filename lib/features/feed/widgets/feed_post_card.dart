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

/// Serene, Instagram-Grade Post Card for ZEV Feed.
/// Modeled directly from the official Instagram app:
/// - Crisp typography with serene breathing room
/// - Subtitle topic under author username (e.g. "AI content", "Analysis")
/// - Integrated "Follow" pill button in post header
/// - Single-line action metrics: [♡ 1,514] [💬 13] [🔁 47] [✈️ 1,692] ... [🔖]
/// - Full adaptive media canvas without cropping + Facebook fullscreen lightbox on tap
/// - "October 22 • See translation" subtle metadata
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
  bool _isFollowing = false;
  bool _isSaved = false;
  bool _isExpanded = false;
  bool _showTranslation = false;

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
        tween: Tween<double>(begin: 0.0, end: 1.35)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.35, end: 1.0)
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

  String _getCategorySubtitle() {
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
        _showNotice("Reposted to your profile!");
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

  void _toggleFollow() {
    HapticFeedback.lightImpact();
    setState(() => _isFollowing = !_isFollowing);
    _showNotice(_isFollowing
        ? "Following @${widget.post.authorUsername}"
        : "Unfollowed @${widget.post.authorUsername}");
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
    final subtitle = _getCategorySubtitle();

    return Container(
      decoration: const BoxDecoration(
        color: ZevColors.white,
        border: Border(
          bottom: BorderSide(
            color: ZevColors.border,
            width: 0.6,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Post Header: Avatar, Username + Subtitle, Follow Pill, 3-dots
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
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
                      const SizedBox(height: 1),
                      // Subtitle (AI content / Education / Analysis)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: ZevColors.textMuted,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Follow Button (Exact Instagram Style)
                GestureDetector(
                  onTap: _toggleFollow,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _isFollowing
                          ? ZevColors.white
                          : ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ZevColors.border,
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      _isFollowing ? "Following" : "Follow",
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _isFollowing
                            ? ZevColors.textMuted
                            : ZevColors.deepNavy,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 4),

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

          // 2. Media Box (Full Display without cut-off + Tap to Fullscreen)
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
                      maxHeight: 580,
                    ),
                    color: ZevColors.softSurface,
                    child: Image.network(
                      post.imageUrl,
                      fit: BoxFit.contain, // Full un-cropped display
                      width: double.infinity,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 320,
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
                ],
              ),
            ),

          // 3. Instagram Exact Single-Line Action Metrics Toolbar:
          // [♡ 1,514] [💬 13] [🔁 47] [✈️] ... [🔖]
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // Like + Count
                    _buildMetricAction(
                      icon: _isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      iconColor:
                          _isLiked ? Colors.redAccent : ZevColors.deepNavy,
                      count: _likesCount,
                      onTap: _toggleLike,
                    ),
                    const SizedBox(width: 16),

                    // Comment + Count
                    _buildMetricAction(
                      icon: Icons.chat_bubble_outline_rounded,
                      iconColor: ZevColors.deepNavy,
                      count: widget.post.commentsCount,
                      onTap: _openComments,
                    ),
                    const SizedBox(width: 16),

                    // Repost + Count
                    _buildMetricAction(
                      icon: Icons.repeat_rounded,
                      iconColor: _isReposted
                          ? ZevColors.primaryBlue
                          : ZevColors.deepNavy,
                      count: _repostsCount,
                      onTap: _toggleRepost,
                    ),
                    const SizedBox(width: 16),

                    // Share
                    _buildMetricAction(
                      icon: Icons.send_rounded,
                      iconColor: ZevColors.deepNavy,
                      count: null,
                      onTap: _openShareSheet,
                    ),
                  ],
                ),

                // Bookmark / Save
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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

          // 4. Post Title & Caption Block with Smart Dynamic RTL/LTR
          if (post.title.isNotEmpty || post.content.isNotEmpty) () {
            final isContentRtl = TextDirectionHelper.isRtl(
              post.content.isNotEmpty ? post.content : post.title,
            );
            return Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, top: 2),
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

          // 5. Date & See Translation (Exact Instagram Style)
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 14, top: 4),
            child: Row(
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: ZevColors.textMuted,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  "•",
                  style: TextStyle(fontSize: 10, color: ZevColors.textMuted),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _showTranslation = !_showTranslation);
                  },
                  child: Text(
                    _showTranslation ? "See original" : "See translation",
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildMetricAction({
    required IconData icon,
    required Color iconColor,
    required int? count,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 24),
          if (count != null && count > 0) ...[
            const SizedBox(width: 5),
            Text(
              count > 999
                  ? "${(count / 1000).toStringAsFixed(1)}K"
                  : "$count",
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ZevColors.deepNavy,
                letterSpacing: -0.2,
              ),
            ),
          ],
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
