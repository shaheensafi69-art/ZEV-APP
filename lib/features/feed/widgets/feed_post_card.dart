import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/content_deletion_service.dart';
import '../../../core/services/feed_algorithm_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/rich_text_helper.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_video_thumbnail.dart';
import '../../profile/screens/profile_screen.dart';
import '../models/feed_post_item.dart';
import '../screens/fullscreen_media_viewer.dart';
import 'feed_comments_sheet.dart';
import 'feed_share_sheet.dart';

/// Light Clearmorphic Post Card for ZEV Feed.
class FeedPostCard extends StatefulWidget {
  final FeedPostItem post;
  final VoidCallback? onCommentsUpdated;
  final VoidCallback? onPostDeleted;
  final ValueChanged<FeedPostItem>? onPostUpdated;
  final VoidCallback? onHideOrMute;

  const FeedPostCard({
    super.key,
    required this.post,
    this.onCommentsUpdated,
    this.onPostDeleted,
    this.onPostUpdated,
    this.onHideOrMute,
  });

  @override
  State<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<FeedPostCard>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late FeedPostItem _post;
  late bool _isLiked;
  late int _likesCount;
  late int _commentsCount;
  late bool _isReposted;
  late int _repostsCount;
  bool _isFollowing = false;
  bool _followRequested = false;
  bool _isFollowLoading = false;
  bool _isSaved = false;
  bool _isExpanded = false;
  late final PageController _mediaPageCtrl;
  int _currentSlide = 0;
  final Set<int> _inlinePlayingSlides = {};

  // Double-tap heart animation
  late final AnimationController _heartAnimCtrl;
  late final Animation<double> _heartScaleAnim;
  late final Animation<double> _heartOpacityAnim;
  bool _showFloatingHeart = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _mediaPageCtrl = PageController();
    _isLiked = _post.isLikedByMe;
    _likesCount = _post.likesCount;
    _commentsCount = _post.commentsCount;
    _isReposted = _post.isRepostedByMe;
    _repostsCount = _post.repostsCount;
    _isSaved = _post.isBookmarkedByMe;
    _isFollowing = _post.isAuthorFollowed;
    FeedAlgorithmService.instance.markSeen(_post.id);

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
    if (widget.post != oldWidget.post) {
      _post = widget.post;
      final mediaLen = _post.effectiveMediaUrls.length;
      if (mediaLen <= 1) {
        _currentSlide = 0;
      } else if (_currentSlide >= mediaLen) {
        _currentSlide = mediaLen - 1;
      }
      if (_mediaPageCtrl.hasClients && mediaLen > 0) {
        final page = _currentSlide.clamp(0, mediaLen - 1);
        if ((_mediaPageCtrl.page?.round() ?? 0) != page) {
          _mediaPageCtrl.jumpToPage(page);
        }
      }
    }
    if (widget.post.isLikedByMe != oldWidget.post.isLikedByMe) {
      _isLiked = widget.post.isLikedByMe;
    }
    if (widget.post.likesCount != oldWidget.post.likesCount) {
      _likesCount = widget.post.likesCount;
    }
    if (widget.post.commentsCount != oldWidget.post.commentsCount) {
      _commentsCount = widget.post.commentsCount;
    }
    if (widget.post.isRepostedByMe != oldWidget.post.isRepostedByMe) {
      _isReposted = widget.post.isRepostedByMe;
    }
    if (widget.post.repostsCount != oldWidget.post.repostsCount) {
      _repostsCount = widget.post.repostsCount;
    }
    if (widget.post.isBookmarkedByMe != oldWidget.post.isBookmarkedByMe) {
      _isSaved = widget.post.isBookmarkedByMe;
    }
    if (widget.post.isAuthorFollowed != oldWidget.post.isAuthorFollowed) {
      _isFollowing = widget.post.isAuthorFollowed;
    }
  }

  @override
  void dispose() {
    _mediaPageCtrl.dispose();
    _heartAnimCtrl.dispose();
    super.dispose();
  }

  String _getCategorySubtitle() {
    final title = _post.title;
    if (title.contains('[') && title.contains(']')) {
      final start = title.indexOf('[');
      final end = title.indexOf(']');
      if (end > start) {
        return title.substring(start + 1, end).trim();
      }
    }
    return _post.categoryTag;
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
          'post_id': _post.id,
          'student_id': user.id,
        });
        FeedAlgorithmService.instance.recordPositiveInteraction(
          authorId: _post.authorId,
          category: _getCategorySubtitle(),
          text: '${_post.title} ${_post.content}',
          weight: 4.5,
        );
        if (_post.authorId != user.id) {
          unawaited(
            NotificationService().dispatchPushNotification(
              recipientUserId: _post.authorId,
              title: 'New Like',
              body: 'liked your post on ZEV.',
              notificationType: 'like',
              deepLink: '/post/${_post.id}',
            ),
          );
        }
      } else {
        await supabase
            .from('discussion_likes')
            .delete()
            .eq('post_id', _post.id)
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
          'post_id': _post.id,
          'user_id': user.id,
        });
        FeedAlgorithmService.instance.recordPositiveInteraction(
          authorId: _post.authorId,
          category: _getCategorySubtitle(),
          text: '${_post.title} ${_post.content}',
          weight: 5.5,
        );
        _showNotice("Reposted to your profile!");
      } else {
        await supabase
            .from('post_reposts')
            .delete()
            .eq('post_id', _post.id)
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

  Future<void> _toggleBookmark() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showNotice("Please sign in to save posts.");
      return;
    }

    HapticFeedback.lightImpact();
    final previousState = _isSaved;
    setState(() => _isSaved = !previousState);

    try {
      if (_isSaved) {
        await supabase.from('discussion_bookmarks').insert({
          'post_id': _post.id,
          'user_id': user.id,
        });
        FeedAlgorithmService.instance.recordPositiveInteraction(
          authorId: _post.authorId,
          category: _getCategorySubtitle(),
          text: '${_post.title} ${_post.content}',
          weight: 6.0,
        );
        _showNotice("Saved to your bookmarks.");
      } else {
        await supabase
            .from('discussion_bookmarks')
            .delete()
            .eq('post_id', _post.id)
            .eq('user_id', user.id);
        _showNotice("Removed from bookmarks.");
      }
    } catch (e) {
      debugPrint("Bookmark toggle warning: $e");
      if (mounted) {
        setState(() => _isSaved = previousState);
        _showNotice("Could not update bookmark.");
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
    setState(() => _isFollowLoading = true);

    final status = await SocialGraphService.instance.toggleFollow(_post.authorId);

    if (!mounted) return;
    setState(() {
      _isFollowLoading = false;
      switch (status) {
        case FollowToggleStatus.following:
          _isFollowing = true;
          _followRequested = false;
          _showNotice("Following @${_post.authorUsername}");
          break;
        case FollowToggleStatus.requested:
          _isFollowing = false;
          _followRequested = true;
          _showNotice("Follow request sent to @${_post.authorUsername}");
          break;
        case FollowToggleStatus.unfollowed:
        case FollowToggleStatus.cancelled:
          _isFollowing = false;
          _followRequested = false;
          break;
        case FollowToggleStatus.blocked:
          _showNotice("You cannot follow this account.");
          break;
        case FollowToggleStatus.error:
          _showNotice("Could not update follow status.");
          break;
      }
    });
  }

  void _openComments() {
    HapticFeedback.lightImpact();
    FeedCommentsSheet.show(
      context,
      postId: _post.id,
      postAuthorUsername: _post.authorUsername,
      postAuthorId: _post.authorId,
      onCommentAdded: () {
        FeedAlgorithmService.instance.recordPositiveInteraction(
          authorId: _post.authorId,
          category: _getCategorySubtitle(),
          text: '${_post.title} ${_post.content}',
          weight: 5.0,
        );
        if (mounted) {
          setState(() => _commentsCount += 1);
        }
        widget.onCommentsUpdated?.call();
      },
      onCommentDeleted: () {
        if (mounted) {
          setState(() {
            _commentsCount = _commentsCount > 0 ? _commentsCount - 1 : 0;
          });
        }
        widget.onCommentsUpdated?.call();
      },
    );
  }

  void _openShareSheet() {
    HapticFeedback.lightImpact();
    FeedShareSheet.show(context, post: _post);
  }

  void _openFullscreenViewer() {
    HapticFeedback.lightImpact();
    FullscreenMediaViewer.open(
      context,
      post: _post,
      initialIndex: _currentSlide,
      isLiked: _isLiked,
      likesCount: _likesCount,
      isReposted: _isReposted,
      repostsCount: _repostsCount,
      onToggleLike: _toggleLike,
      onToggleRepost: _toggleRepost,
      onPostDeleted: widget.onPostDeleted,
    );
  }

  void _showPeopleOnPostSheet() {
    if (_post.collaborators.isEmpty && _post.taggedUsers.isEmpty) return;
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.68,
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'People in this post',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (_post.collaborators.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          'COLLABORATORS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: ZevColors.textMuted,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      ..._post.collaborators.map(
                        (u) => _buildPersonTagTile(
                          sheetCtx,
                          user: u,
                          badgeText: 'Collaborator',
                          badgeColor: ZevColors.secondaryBlue,
                        ),
                      ),
                    ],
                    if (_post.taggedUsers.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.only(
                          top: _post.collaborators.isNotEmpty ? 10 : 0,
                          bottom: 6,
                        ),
                        child: const Text(
                          'TAGGED PEOPLE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: ZevColors.textMuted,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      ..._post.taggedUsers.map(
                        (u) => _buildPersonTagTile(
                          sheetCtx,
                          user: u,
                          badgeText: 'Tagged',
                          badgeColor: ZevColors.primaryBlue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPersonTagTile(
    BuildContext sheetCtx, {
    required FeedPostUserTag user,
    required String badgeText,
    required Color badgeColor,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(sheetCtx);
        if (user.id.isNotEmpty) {
          ProfileScreen.open(context, userId: user.id);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            user.avatarUrl.isNotEmpty
                ? ZevCachedImage.avatar(imageUrl: user.avatarUrl, size: 38)
                : const CircleAvatar(
                    radius: 19,
                    backgroundColor: ZevColors.softSurface,
                    child: Icon(
                      Icons.person_rounded,
                      size: 20,
                      color: ZevColors.textMuted,
                    ),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                      if (user.isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: ZevColors.primaryBlue,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '@${user.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: ZevColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: badgeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleMediaSlide(
    String mediaUrl, {
    FeedPostMediaItem? mediaItem,
    int slideIndex = 0,
  }) {
    final isVideo =
        mediaItem?.mediaType.toLowerCase() == 'video' ||
        ZevVideoThumbnail.isVideoUrl(mediaUrl);

    if (isVideo) {
      final isInlinePlaying = _inlinePlayingSlides.contains(slideIndex);
      return Container(
        width: double.infinity,
        height: 360,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ZevVideoThumbnail(
              videoUrl: mediaUrl,
              thumbnailUrl: mediaItem?.thumbnailUrl,
              durationSeconds: mediaItem?.durationSeconds,
              autoPlay: isInlinePlaying,
              initialMuted: false,
              showMuteToggle: true,
              showPlayBadge: true,
              showCenterPlayButton: false,
              showViews: false,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(20),
            ),
            if (!isInlinePlaying)
              Center(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _inlinePlayingSlides.add(slideIndex));
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.deepNavy.withValues(alpha: 0.2),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: ZevColors.deepNavy,
                      size: 34,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 10,
              left: 10,
              child: GestureDetector(
                onTap: _openFullscreenViewer,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.open_in_full_rounded,
                        size: 13,
                        color: ZevColors.deepNavy,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(
        minHeight: 220,
        maxHeight: 560,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: mediaUrl.startsWith('http')
          ? ZevCachedImage.feedPost(
              imageUrl: mediaUrl,
              fit: BoxFit.contain,
              width: double.infinity,
            )
          : Image.file(
              File(mediaUrl),
              fit: BoxFit.contain,
              width: double.infinity,
              errorBuilder: (context, error, stackTrace) => Container(
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
    final post = _post;
    final timeStr = TimeAgo.format(post.createdAt);
    final subtitle = _getCategorySubtitle();
    final mediaItems = post.effectiveMediaItems;
    final mediaUrls = post.effectiveMediaUrls;

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
                            if (post.collaborators.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Flexible(
                                child: GestureDetector(
                                  onTap: _showPeopleOnPostSheet,
                                  child: Text(
                                    post.collaborators.length == 1
                                        ? '• with @${post.collaborators.first.username}'
                                        : '• with @${post.collaborators.first.username} +${post.collaborators.length - 1}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: ZevColors.secondaryBlue,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Subtitle Pill + Optional Location
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 1.5,
                              ),
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
                            if (post.location.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 12,
                                    color: ZevColors.textMuted,
                                  ),
                                  const SizedBox(width: 2),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 130,
                                    ),
                                    child: Text(
                                      post.location,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: ZevColors.textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Follow / Requested Button
                if (shouldShowFollowButton) ...[
                  GestureDetector(
                    onTap: _toggleFollow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _followRequested
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF0095F6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.8),
                          width: 1.2,
                        ),
                        boxShadow: _followRequested
                            ? null
                            : [
                                BoxShadow(
                                  color: const Color(0xFF0095F6)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: _isFollowLoading
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: _followRequested
                                    ? ZevColors.deepNavy
                                    : Colors.white,
                              ),
                            )
                          : Text(
                              _followRequested ? "Requested" : "Follow",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: _followRequested
                                    ? ZevColors.deepNavy
                                    : Colors.white,
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

          // 2. Media Box (Single or Multi-Slide Carousel + Tap to Fullscreen)
          if (mediaUrls.isNotEmpty)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                          if (mediaUrls.length == 1)
                            _buildSingleMediaSlide(
                              mediaUrls.first,
                              mediaItem:
                                  mediaItems.isNotEmpty ? mediaItems.first : null,
                              slideIndex: 0,
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              height: 360,
                              child: Container(
                                color: const Color(0xFFF8FAFC),
                                child: PageView.builder(
                                  controller: _mediaPageCtrl,
                                  itemCount: mediaUrls.length,
                                  onPageChanged: (idx) {
                                    if (mounted) {
                                      setState(() {
                                        _inlinePlayingSlides.clear();
                                        _currentSlide = idx;
                                      });
                                    }
                                  },
                                  itemBuilder: (context, idx) {
                                    final item = idx < mediaItems.length
                                        ? mediaItems[idx]
                                        : null;
                                    return _buildSingleMediaSlide(
                                      mediaUrls[idx],
                                      mediaItem: item,
                                      slideIndex: idx,
                                    );
                                  },
                                ),
                              ),
                            ),

                          if (mediaUrls.length > 1)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0F172A)
                                          .withValues(alpha: 0.10),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '${_currentSlide + 1}/${mediaUrls.length}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: ZevColors.deepNavy,
                                  ),
                                ),
                              ),
                            ),

                          if (post.taggedUsers.isNotEmpty)
                            Positioned(
                              bottom: 10,
                              left: 10,
                              child: GestureDetector(
                                onTap: _showPeopleOnPostSheet,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF0F172A)
                                            .withValues(alpha: 0.12),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.person_pin_rounded,
                                        size: 14,
                                        color: ZevColors.secondaryBlue,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${post.taggedUsers.length} Tagged',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: ZevColors.deepNavy,
                                        ),
                                      ),
                                    ],
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
                                            color: Colors.redAccent
                                                .withValues(alpha: 0.5),
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
                if (mediaUrls.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(mediaUrls.length, (idx) {
                        final active = idx == _currentSlide;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          width: active ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: active
                                ? ZevColors.secondaryBlue
                                : const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),

          if (mediaUrls.isEmpty && post.taggedUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: GestureDetector(
                onTap: _showPeopleOnPostSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_pin_rounded,
                        size: 14,
                        color: ZevColors.secondaryBlue,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${post.taggedUsers.length} Tagged',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: ZevColors.deepNavy,
                        ),
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
                      count: _commentsCount,
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
                  onTap: _toggleBookmark,
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
                    ZevRichText(
                      text: post.content.isNotEmpty
                          ? post.content
                          : post.title,
                      textDirection: isContentRtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      textAlign:
                          isContentRtl ? TextAlign.right : TextAlign.left,
                      maxLines: _isExpanded ? null : 2,
                      overflow: _isExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: ZevColors.deepNavy,
                        height: 1.35,
                      ),
                      prefixSpans: [
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
                      ],
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

          // 5. Timestamp & Edited Badge
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 14, top: 4),
            child: Row(
              children: [
                Text(
                  post.editedAt != null ? "$timeStr • Edited" : timeStr,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: ZevColors.textMuted,
                    fontWeight: FontWeight.w500,
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
    final bool canDelete = ContentDeletionService.canDeletePost(_post);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
                Clipboard.setData(
                  ClipboardData(text: "https://www.zevapp.com/post/${_post.id}"),
                );
                _showNotice("Post link copied to clipboard.");
              },
            ),
            if (canDelete) ...[
              const SizedBox(height: 10),
              _buildPostOptionTile(
                icon: Icons.edit_outlined,
                title: "Edit Post",
                color: ZevColors.deepNavy,
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  final updated = await ContentDeletionService.showEditPostDialog(
                    context,
                    post: _post,
                  );
                  if (updated != null && mounted) {
                    setState(() => _post = updated);
                    widget.onPostUpdated?.call(updated);
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildPostOptionTile(
                icon: Icons.archive_outlined,
                title: "Move to Archive",
                color: ZevColors.deepNavy,
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  await ContentDeletionService.setPostArchived(
                    context,
                    post: _post,
                    archived: true,
                    onUpdated: widget.onPostDeleted,
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildPostOptionTile(
                icon: Icons.delete_outline_rounded,
                title: "Move to Trash",
                color: const Color(0xFFDC2626),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  await ContentDeletionService.movePostToTrash(
                    context,
                    post: _post,
                    onTrashed: widget.onPostDeleted,
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildPostOptionTile(
                icon: Icons.delete_forever_outlined,
                title: "Delete Permanently",
                color: const Color(0xFFDC2626),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  await ContentDeletionService.confirmAndDeletePost(
                    context,
                    post: _post,
                    onDeleted: widget.onPostDeleted,
                  );
                },
              ),
            ] else ...[
              const SizedBox(height: 10),
              _buildPostOptionTile(
                icon: Icons.visibility_off_outlined,
                title: "Not Interested",
                color: ZevColors.deepNavy,
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  final ok = await SocialGraphService.instance.hideContent(
                    targetId: _post.id,
                    targetType: 'post',
                  );
                  if (ok) {
                    FeedAlgorithmService.instance.recordNegativeFeedback(
                      postId: _post.id,
                      authorId: _post.authorId,
                    );
                    _showNotice("We'll show fewer posts like this.");
                    widget.onHideOrMute?.call();
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildPostOptionTile(
                icon: Icons.volume_off_outlined,
                title: "Mute @${_post.authorUsername}",
                color: ZevColors.deepNavy,
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  final ok = await SocialGraphService.instance.muteUser(
                    _post.authorId,
                  );
                  if (ok) {
                    FeedAlgorithmService.instance.recordNegativeFeedback(
                      authorId: _post.authorId,
                      suppressAuthor: true,
                    );
                    _showNotice("Muted @${_post.authorUsername}.");
                    widget.onHideOrMute?.call();
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildPostOptionTile(
                icon: Icons.block_rounded,
                title: "Block @${_post.authorUsername}",
                color: const Color(0xFFDC2626),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  final ok = await SocialGraphService.instance.blockUser(
                    _post.authorId,
                  );
                  if (ok) {
                    FeedAlgorithmService.instance.recordNegativeFeedback(
                      authorId: _post.authorId,
                      suppressAuthor: true,
                    );
                    _showNotice("Blocked @${_post.authorUsername}.");
                    widget.onHideOrMute?.call();
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildPostOptionTile(
                icon: Icons.flag_outlined,
                title: "Report Post",
                color: const Color(0xFFDC2626),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  SocialGraphService.instance.showReportSheet(
                    context,
                    targetType: 'post',
                    targetId: _post.id,
                    reportedUserId: _post.authorId,
                    targetLabel: 'Post',
                  );
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
