import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/content_deletion_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_video_thumbnail.dart';
import '../models/feed_post_item.dart';
import '../widgets/feed_comments_sheet.dart';
import '../widgets/feed_share_sheet.dart';

/// Immersive Facebook-Style Fullscreen Media Viewer.
/// Provides pinch-to-zoom (up to 4x), double-tap zoom/like, full caption display,
/// carousel slide browsing, and live interaction buttons (Like, Comment, Repost, Share).
class FullscreenMediaViewer extends StatefulWidget {
  final FeedPostItem post;
  final int initialIndex;
  final bool isLiked;
  final int likesCount;
  final bool isReposted;
  final int repostsCount;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleRepost;
  final VoidCallback? onPostDeleted;

  const FullscreenMediaViewer({
    super.key,
    required this.post,
    this.initialIndex = 0,
    required this.isLiked,
    required this.likesCount,
    required this.isReposted,
    required this.repostsCount,
    required this.onToggleLike,
    required this.onToggleRepost,
    this.onPostDeleted,
  });

  static void open(
    BuildContext context, {
    required FeedPostItem post,
    int initialIndex = 0,
    required bool isLiked,
    required int likesCount,
    required bool isReposted,
    required int repostsCount,
    required VoidCallback onToggleLike,
    required VoidCallback onToggleRepost,
    VoidCallback? onPostDeleted,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (context, anim1, anim2) => FullscreenMediaViewer(
          post: post,
          initialIndex: initialIndex,
          isLiked: isLiked,
          likesCount: likesCount,
          isReposted: isReposted,
          repostsCount: repostsCount,
          onToggleLike: onToggleLike,
          onToggleRepost: onToggleRepost,
          onPostDeleted: onPostDeleted,
        ),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<FullscreenMediaViewer> createState() => _FullscreenMediaViewerState();
}

class _FullscreenMediaViewerState extends State<FullscreenMediaViewer> {
  final TransformationController _transCtrl = TransformationController();
  late final PageController _pageCtrl;
  late int _currentIndex;
  TapDownDetails? _doubleTapDetails;
  bool _showOverlays = true;
  late bool _liked;
  late int _likes;
  late bool _reposted;
  late int _reposts;

  @override
  void initState() {
    super.initState();
    final total = widget.post.effectiveMediaUrls.length;
    _currentIndex = total > 0 ? widget.initialIndex.clamp(0, total - 1) : 0;
    _pageCtrl = PageController(initialPage: _currentIndex);
    _liked = widget.isLiked;
    _likes = widget.likesCount;
    _reposted = widget.isReposted;
    _reposts = widget.repostsCount;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _transCtrl.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transCtrl.value != Matrix4.identity()) {
      _transCtrl.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      _transCtrl.value = Matrix4.identity()
        // ignore: deprecated_member_use
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        // ignore: deprecated_member_use
        ..scale(2.5);
    }
  }

  void _handleLike() {
    HapticFeedback.mediumImpact();
    setState(() {
      _liked = !_liked;
      _likes = _liked ? _likes + 1 : (_likes > 0 ? _likes - 1 : 0);
    });
    widget.onToggleLike();
  }

  void _handleRepost() {
    HapticFeedback.mediumImpact();
    setState(() {
      _reposted = !_reposted;
      _reposts = _reposted ? _reposts + 1 : (_reposts > 0 ? _reposts - 1 : 0);
    });
    widget.onToggleRepost();
  }

  bool _isVideoSlide(int idx, String url) {
    final items = widget.post.effectiveMediaItems;
    if (idx >= 0 && idx < items.length) {
      if (items[idx].mediaType.toLowerCase() == 'video') return true;
    }
    return ZevVideoThumbnail.isVideoUrl(url);
  }

  Widget _buildMediaContent(String url, {int slideIndex = 0}) {
    if (_isVideoSlide(slideIndex, url)) {
      final items = widget.post.effectiveMediaItems;
      final thumbUrl = slideIndex >= 0 && slideIndex < items.length
          ? items[slideIndex].thumbnailUrl
          : null;
      return _FullscreenVideoSlide(
        videoUrl: url,
        thumbnailUrl: thumbUrl,
        onToggleOverlays: () => setState(() => _showOverlays = !_showOverlays),
      );
    }

    if (url.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        width: double.infinity,
        placeholder: (context, _) => const Center(
          child: CircularProgressIndicator(
            color: ZevColors.primaryBlue,
            strokeWidth: 2.5,
          ),
        ),
        errorWidget: (context, _, _) => const Center(
          child: Icon(
            Icons.broken_image_rounded,
            size: 64,
            color: Colors.white54,
          ),
        ),
      );
    }
    return Image.file(
      File(url),
      fit: BoxFit.contain,
      width: double.infinity,
      errorBuilder: (context, _, _) => const Center(
        child: Icon(
          Icons.broken_image_rounded,
          size: 64,
          color: Colors.white54,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final mediaUrls = post.effectiveMediaUrls;
    final timeStr = TimeAgo.format(post.createdAt);
    final isContentRtl = TextDirectionHelper.isRtl(
      post.content.isNotEmpty ? post.content : post.title,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Interactive Zoomable Media / Carousel
          GestureDetector(
            onTap: () => setState(() => _showOverlays = !_showOverlays),
            onDoubleTapDown: (d) => _doubleTapDetails = d,
            onDoubleTap: _handleDoubleTap,
            child: mediaUrls.isEmpty
                ? const Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      size: 64,
                      color: Colors.white54,
                    ),
                  )
                : mediaUrls.length == 1
                    ? Center(
                        child: _isVideoSlide(0, mediaUrls.first)
                            ? _buildMediaContent(mediaUrls.first, slideIndex: 0)
                            : InteractiveViewer(
                                transformationController: _transCtrl,
                                minScale: 0.8,
                                maxScale: 4.5,
                                child: _buildMediaContent(
                                  mediaUrls.first,
                                  slideIndex: 0,
                                ),
                              ),
                      )
                    : PageView.builder(
                        controller: _pageCtrl,
                        itemCount: mediaUrls.length,
                        onPageChanged: (idx) {
                          _transCtrl.value = Matrix4.identity();
                          if (mounted) {
                            setState(() => _currentIndex = idx);
                          }
                        },
                        itemBuilder: (context, idx) => Center(
                          child: _isVideoSlide(idx, mediaUrls[idx])
                              ? _buildMediaContent(
                                  mediaUrls[idx],
                                  slideIndex: idx,
                                )
                              : InteractiveViewer(
                                  transformationController: _transCtrl,
                                  minScale: 0.8,
                                  maxScale: 4.5,
                                  child: _buildMediaContent(
                                    mediaUrls[idx],
                                    slideIndex: idx,
                                  ),
                                ),
                        ),
                      ),
          ),

          // Slide Indicator Pill for multi-photo posts
          if (_showOverlays && mediaUrls.length > 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '${_currentIndex + 1}/${mediaUrls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),

          // 2. Top Header Bar (Close + Author info)
          if (_showOverlays)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  right: 12,
                  bottom: 12,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    if (post.authorAvatar.isNotEmpty)
                      ZevCachedImage.avatar(
                        imageUrl: post.authorAvatar,
                        size: 36,
                      )
                    else
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white24,
                        child: Icon(
                          Icons.person_rounded,
                          size: 20,
                          color: Colors.white,
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
                                  post.authorUsername,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
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
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.share_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () {
                        FeedShareSheet.show(context, post: post);
                      },
                    ),
                    if (ContentDeletionService.canDeletePost(post))
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFEF4444),
                          size: 23,
                        ),
                        onPressed: () async {
                          await ContentDeletionService.movePostToTrash(
                            context,
                            post: post,
                            onTrashed: () {
                              Navigator.of(context).pop();
                              widget.onPostDeleted?.call();
                            },
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),

          // 3. Bottom Overlays (Caption & Actions)
          if (_showOverlays)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 14,
                  left: 16,
                  right: 16,
                  top: 24,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Caption
                    if (post.title.isNotEmpty || post.content.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                          post.content.isNotEmpty
                              ? post.content
                              : post.title,
                          textDirection: isContentRtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          textAlign: isContentRtl
                              ? TextAlign.right
                              : TextAlign.left,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.4,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    // Actions Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // Like Button
                        _buildAction(
                          icon: _liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: _liked ? Colors.redAccent : Colors.white,
                          label: _likes > 0 ? "$_likes" : "Like",
                          onTap: _handleLike,
                        ),
                        // Comment Button
                        _buildAction(
                          icon: Icons.chat_bubble_outline_rounded,
                          color: Colors.white,
                          label: post.commentsCount > 0
                              ? "${post.commentsCount}"
                              : "Comment",
                          onTap: () {
                            FeedCommentsSheet.show(
                              context,
                              postId: post.id,
                              postAuthorUsername: post.authorUsername,
                              postAuthorId: post.authorId,
                            );
                          },
                        ),
                        // Repost Button
                        _buildAction(
                          icon: Icons.repeat_rounded,
                          color: _reposted
                              ? ZevColors.primaryBlue
                              : Colors.white,
                          label: _reposts > 0 ? "$_reposts" : "Repost",
                          onTap: _handleRepost,
                        ),
                        // Share Button
                        _buildAction(
                          icon: Icons.send_rounded,
                          color: Colors.white,
                          label: "Share",
                          onTap: () {
                            FeedShareSheet.show(context, post: post);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAction({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenVideoSlide extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final VoidCallback onToggleOverlays;

  const _FullscreenVideoSlide({
    required this.videoUrl,
    this.thumbnailUrl,
    required this.onToggleOverlays,
  });

  @override
  State<_FullscreenVideoSlide> createState() => _FullscreenVideoSlideState();
}

class _FullscreenVideoSlideState extends State<_FullscreenVideoSlide> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initPlayer());
  }

  Future<void> _initPlayer() async {
    final url = widget.videoUrl.trim();
    if (url.isEmpty) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    VideoPlayerController? ctrl;
    try {
      ctrl = url.startsWith('http')
          ? VideoPlayerController.networkUrl(
              Uri.parse(url),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            )
          : VideoPlayerController.file(
              File(url),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            );
      _controller = ctrl;
      ctrl.addListener(_tick);
      await ctrl.initialize();
      if (!mounted) {
        ctrl.removeListener(_tick);
        await ctrl.dispose();
        return;
      }
      await ctrl.setLooping(true);
      await ctrl.setVolume(_isMuted ? 0.0 : 1.0);
      await ctrl.play();
      if (mounted) {
        setState(() {
          _initialized = true;
          _hasError = false;
        });
      }
    } catch (_) {
      ctrl?.removeListener(_tick);
      try {
        await ctrl?.dispose();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _controller = null;
          _hasError = true;
        });
      }
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      ctrl.removeListener(_tick);
      try {
        ctrl.pause();
        ctrl.dispose();
      } catch (_) {}
    }
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_initialized) {
      widget.onToggleOverlays();
      return;
    }
    HapticFeedback.lightImpact();
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    setState(() {});
  }

  void _toggleMute() {
    HapticFeedback.selectionClick();
    setState(() => _isMuted = !_isMuted);
    if (_controller != null && _initialized) {
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final showVideo = _initialized && ctrl != null && ctrl.value.isInitialized;
    final durMs = showVideo ? ctrl.value.duration.inMilliseconds : 0;
    final posMs = showVideo ? ctrl.value.position.inMilliseconds : 0;
    final progress = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlayPause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ZevVideoThumbnail(
            videoUrl: widget.videoUrl,
            thumbnailUrl: widget.thumbnailUrl,
            showPlayBadge: false,
            showViews: false,
            fit: BoxFit.contain,
            placeholder: const ColoredBox(color: Colors.black),
          ),
          if (showVideo)
            Center(
              child: AspectRatio(
                aspectRatio: ctrl.value.aspectRatio > 0
                    ? ctrl.value.aspectRatio
                    : 16 / 9,
                child: VideoPlayer(ctrl),
              ),
            ),
          if (!showVideo && !_hasError)
            const Center(
              child: CircularProgressIndicator(
                color: ZevColors.primaryBlue,
                strokeWidth: 2.5,
              ),
            ),
          if (showVideo && !ctrl.value.isPlaying)
            Center(
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
          if (showVideo)
            Positioned(
              right: 16,
              bottom: 138,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    _isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          if (showVideo && durMs > 0)
            Positioned(
              left: 16,
              right: 16,
              bottom: 122,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    ZevColors.primaryBlue,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
