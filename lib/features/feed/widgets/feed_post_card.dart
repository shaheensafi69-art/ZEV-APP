import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/content_deletion_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../profile/screens/profile_screen.dart';
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
  final VoidCallback? onPostDeleted;

  const FeedPostCard({
    super.key,
    required this.post,
    this.onCommentsUpdated,
    this.onPostDeleted,
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
  bool _isFollowLoading = false;
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
    _isFollowing = widget.post.isAuthorFollowed;

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
    if (widget.post.isAuthorFollowed != oldWidget.post.isAuthorFollowed) {
      _isFollowing = widget.post.isAuthorFollowed;
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

        if (widget.post.authorId.isNotEmpty && widget.post.authorId != user.id) {
          unawaited(NotificationService().sendNotificationToUser(
            targetUserId: widget.post.authorId,
            title: "Post Liked",
            message: "liked your post.",
            notificationType: "like",
            linkUrl: widget.post.id,
            senderId: user.id,
          ));
        }
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

  Future<void> _toggleFollow() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showNotice("Please sign in to follow users.");
      return;
    }
    if (_isFollowLoading) return;

    HapticFeedback.lightImpact();

    // Optimistically update follow status so the Follow button is hidden immediately
    setState(() {
      _isFollowing = true;
      _isFollowLoading = true;
    });

    _showNotice("Following @${widget.post.authorUsername}");

    try {
      // 1. Insert into user_follows table
      await supabase.from('user_follows').insert({
        'follower_id': user.id,
        'following_id': widget.post.authorId,
      });

      // 2. Also insert into student_friends table for mutual compatibility
      try {
        await supabase.from('student_friends').upsert({
          'user_id': user.id,
          'friend_id': widget.post.authorId,
          'status': 'accepted',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

      // 3. Dispatch in-app push notification to author
      unawaited(NotificationService().sendNotificationToUser(
        targetUserId: widget.post.authorId,
        title: "New Follower",
        message: "Started following you on ZEV",
        notificationType: "follow",
        senderId: user.id,
      ));
    } catch (e) {
      debugPrint("Follow author notice: $e");
      if (mounted) {
        setState(() => _isFollowing = false);
      }
    } finally {
      if (mounted) {
        setState(() => _isFollowLoading = false);
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
      onPostDeleted: widget.onPostDeleted,
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

    final currentUserId = supabase.auth.currentUser?.id;
    final isMe = currentUserId != null && currentUserId == post.authorId;
    final shouldShowFollowButton = !isMe && !_isFollowing;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 6),
            spreadRadius: -1,
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Post Header: Avatar, Username + Subtitle, Follow Pill, 3-dots
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ProfileScreen.open(context, userId: post.authorId);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF1F5F9),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: post.authorAvatar.isNotEmpty
                        ? ZevCachedImage.avatar(
                            imageUrl: post.authorAvatar,
                            size: 34,
                          )
                        : Container(
                            width: 34,
                            height: 34,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: ZevColors.softSurface,
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              size: 20,
                              color: ZevColors.textMuted,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ProfileScreen.open(context, userId: post.authorId);
                    },
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
                        const SizedBox(height: 2),
                        // Subtitle Pill (Category / Education / AI)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.white,
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 11,
                              color: ZevColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Follow Button: Only shown if NOT me and NOT already following!
                if (shouldShowFollowButton) ...[
                  GestureDetector(
                    onTap: _toggleFollow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0095F6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.8),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0095F6).withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _isFollowLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              "Follow",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Tactile Clay 3-Dots Button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showPostOptions();
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.more_horiz_rounded,
                      color: ZevColors.deepNavy,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Media Box (Smoothly Framed within Clay Card + Tap to Fullscreen)
          if (post.imageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: GestureDetector(
                  onTap: _openFullscreenViewer,
                  onDoubleTap: _triggerDoubleTapLike,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(
                          minHeight: 220,
                          maxHeight: 560,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: post.imageUrl.startsWith('http')
                            ? ZevCachedImage.feedPost(
                                imageUrl: post.imageUrl,
                                fit: BoxFit.contain,
                                width: double.infinity,
                              )
                            : Image.file(
                                File(post.imageUrl),
                                fit: BoxFit.contain,
                                width: double.infinity,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  height: 220,
                                  color: const Color(0xFFF1F5F9),
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
              ),
            ),

          // 3. Tactile Clay Action Metrics Toolbar:
          // [♡ 1,514] [💬 13] [🔁 47] [✈️] ... [🔖]
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      isHighlight: _isLiked,
                      highlightBg: Colors.redAccent.withValues(alpha: 0.10),
                    ),
                    const SizedBox(width: 8),

                    // Comment + Count
                    _buildMetricAction(
                      icon: Icons.chat_bubble_outline_rounded,
                      iconColor: ZevColors.deepNavy,
                      count: widget.post.commentsCount,
                      onTap: _openComments,
                    ),
                    const SizedBox(width: 8),

                    // Repost + Count
                    _buildMetricAction(
                      icon: Icons.repeat_rounded,
                      iconColor: _isReposted
                          ? ZevColors.primaryBlue
                          : ZevColors.deepNavy,
                      count: _repostsCount,
                      onTap: _toggleRepost,
                      isHighlight: _isReposted,
                      highlightBg: ZevColors.primaryBlue.withValues(alpha: 0.12),
                    ),
                    const SizedBox(width: 8),

                    // Share
                    _buildMetricAction(
                      icon: Icons.send_rounded,
                      iconColor: ZevColors.deepNavy,
                      count: null,
                      onTap: _openShareSheet,
                    ),
                  ],
                ),

                // Tactile Clay Bookmark / Save
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isSaved = !_isSaved);
                    _showNotice(_isSaved
                        ? "Saved to collection."
                        : "Removed from collection.");
                  },
                  child: Container(
                    padding: const EdgeInsets.all(7.5),
                    decoration: BoxDecoration(
                      color: _isSaved
                          ? const Color(0xFF00D4FF).withValues(alpha: 0.15)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isSaved
                            ? const Color(0xFF00D4FF).withValues(alpha: 0.5)
                            : Colors.white,
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
                    child: Icon(
                      _isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color:
                          _isSaved ? ZevColors.primaryBlue : ZevColors.deepNavy,
                      size: 20,
                    ),
                  ),
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
    bool isHighlight = false,
    Color? highlightBg,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isHighlight
              ? (highlightBg ?? const Color(0xFFF1F5F9))
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isHighlight
                ? (highlightBg?.withValues(alpha: 0.5) ?? Colors.white)
                : Colors.white,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 6,
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
            Icon(icon, color: iconColor, size: 20),
            if (count != null && count > 0) ...[
              const SizedBox(width: 5),
              Text(
                count > 999
                    ? "${(count / 1000).toStringAsFixed(1)}K"
                    : "$count",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: isHighlight ? iconColor : ZevColors.deepNavy,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showPostOptions() {
    final bool canDelete = ContentDeletionService.canDeletePost(widget.post);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Container(
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 18),
            _buildPostOptionTile(
              icon: Icons.share_outlined,
              title: "Share Post",
              color: ZevColors.deepNavy,
              onTap: () {
                Navigator.pop(bottomSheetContext);
                _openShareSheet();
              },
            ),
            const SizedBox(height: 10),
            _buildPostOptionTile(
              icon: Icons.link_rounded,
              title: "Copy Link",
              color: ZevColors.deepNavy,
              onTap: () {
                Navigator.pop(bottomSheetContext);
                _showNotice("Link copied.");
              },
            ),
            if (canDelete) ...[
              const SizedBox(height: 10),
              _buildPostOptionTile(
                icon: Icons.delete_outline_rounded,
                title: "Delete Post",
                color: const Color(0xFFDC2626),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  await ContentDeletionService.confirmAndDeletePost(
                    context,
                    post: widget.post,
                    onDeleted: widget.onPostDeleted,
                  );
                },
              ),
            ] else ...[
              const SizedBox(height: 10),
              _buildPostOptionTile(
                icon: Icons.flag_outlined,
                title: "Report",
                color: Colors.redAccent,
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  _showNotice("Thank you. Report received for review.");
                },
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPostOptionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: ZevColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
