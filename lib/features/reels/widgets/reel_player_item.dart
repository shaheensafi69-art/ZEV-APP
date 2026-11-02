import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../feed/models/feed_post_item.dart';
import '../../feed/widgets/feed_share_sheet.dart';
import '../models/reel_item.dart';
import 'reel_comments_sheet.dart';

/// Next-Generation Instagram/TikTok Caliber Reel Player Item.
/// Engineered with 120 FPS buttery-smooth playback, interactive touch-scrubber,
/// press-and-hold 1.5x fast-forward, double-tap floating heart pop, and full telemetry.
class ReelPlayerItem extends StatefulWidget {
  final ReelItem reel;
  final bool isActive;
  final bool isGlobalMuted;
  final VoidCallback onToggleMute;

  const ReelPlayerItem({
    super.key,
    required this.reel,
    required this.isActive,
    required this.isGlobalMuted,
    required this.onToggleMute,
  });

  @override
  State<ReelPlayerItem> createState() => _ReelPlayerItemState();
}

class _ReelPlayerItemState extends State<ReelPlayerItem>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isLiked = false;
  int _likesCount = 0;
  bool _isSaved = false;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  bool _isCaptionExpanded = false;

  // Single-tap play/pause animation overlay
  bool _showPlayPauseBadge = false;
  bool _badgeIsPlay = false;
  Timer? _badgeTimer;

  // Double-tap heart animation
  late final AnimationController _heartAnimCtrl;
  late final Animation<double> _heartScaleAnim;
  late final Animation<double> _heartOpacityAnim;
  bool _showFloatingHeart = false;

  // Rotating vinyl record animation
  late final AnimationController _vinylAnimCtrl;

  // Fast forward (1.5x speed on hold)
  bool _isFastForwarding = false;
  Timer? _holdSpeedTimer;

  // Interactive scrubber (seek bar)
  bool _isScrubbing = false;
  double _scrubRatio = 0.0;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.reel.isLikedByMe;
    _likesCount = widget.reel.likesCount;
    _isSaved = widget.reel.isBookmarkedByMe;
    _isFollowing = widget.reel.isAuthorFollowed;

    // Heart pop animation
    _heartAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _heartScaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.4, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_heartAnimCtrl);

    _heartOpacityAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 30,
      ),
    ]).animate(_heartAnimCtrl);

    _heartAnimCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _showFloatingHeart = false);
      }
    });

    // Vinyl record rotation
    _vinylAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final uri = Uri.parse(widget.reel.videoUrl);
      _controller = VideoPlayerController.networkUrl(uri);
      await _controller!.initialize();
      _controller!.setLooping(true);
      _controller!.setVolume(widget.isGlobalMuted ? 0.0 : 1.0);

      _controller!.addListener(_onVideoControllerTick);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _totalDuration = _controller!.value.duration;
        });

        if (widget.isActive) {
          _controller!.play();
        }
      }
    } catch (e) {
      debugPrint("Reel video initialization notice: $e");
    }
  }

  void _onVideoControllerTick() {
    if (_controller == null || !mounted || _isScrubbing) return;
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
    if (pos != _currentPosition) {
      setState(() {
        _currentPosition = pos;
        _totalDuration = dur;
      });
    }
  }

  @override
  void didUpdateWidget(ReelPlayerItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller?.play();
        _vinylAnimCtrl.repeat();
      } else {
        _controller?.pause();
        _vinylAnimCtrl.stop();
      }
    }

    if (widget.isGlobalMuted != oldWidget.isGlobalMuted) {
      _controller?.setVolume(widget.isGlobalMuted ? 0.0 : 1.0);
    }
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    _holdSpeedTimer?.cancel();
    _controller?.removeListener(_onVideoControllerTick);
    _controller?.dispose();
    _heartAnimCtrl.dispose();
    _vinylAnimCtrl.dispose();
    super.dispose();
  }

  // Single Tap to Play/Pause
  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    HapticFeedback.lightImpact();

    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _badgeIsPlay = false;
        _vinylAnimCtrl.stop();
      } else {
        _controller!.play();
        _badgeIsPlay = true;
        _vinylAnimCtrl.repeat();
      }
      _showPlayPauseBadge = true;
    });

    _badgeTimer?.cancel();
    _badgeTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showPlayPauseBadge = false);
    });
  }

  // Double Tap to Like
  void _triggerDoubleTapLike() {
    HapticFeedback.mediumImpact();
    setState(() => _showFloatingHeart = true);
    _heartAnimCtrl.forward(from: 0.0);

    if (!_isLiked) {
      _toggleLike();
    }
  }

  // Like in Supabase
  Future<void> _toggleLike() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showNotice("Please sign in to like reels.");
      return;
    }

    HapticFeedback.lightImpact();
    final prevLiked = _isLiked;
    final prevCount = _likesCount;

    setState(() {
      _isLiked = !prevLiked;
      _likesCount = _isLiked ? prevCount + 1 : (prevCount > 0 ? prevCount - 1 : 0);
    });

    try {
      if (_isLiked) {
        await supabase.from('reel_likes').upsert({
          'reel_id': widget.reel.id,
          'user_id': user.id,
        });

        // Send notification to author
        unawaited(NotificationService().sendNotificationToUser(
          targetUserId: widget.reel.userId,
          title: "Reel Liked",
          message: "Liked your reel: ${widget.reel.title}",
          notificationType: "like",
          senderId: user.id,
        ));
      } else {
        await supabase.from('reel_likes').delete().match({
          'reel_id': widget.reel.id,
          'user_id': user.id,
        });
      }
    } catch (e) {
      debugPrint("Like reel error: $e");
      if (mounted) {
        setState(() {
          _isLiked = prevLiked;
          _likesCount = prevCount;
        });
      }
    }
  }

  // Bookmark in Supabase
  Future<void> _toggleBookmark() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showNotice("Please sign in to save reels.");
      return;
    }

    HapticFeedback.lightImpact();
    final prevSaved = _isSaved;
    setState(() => _isSaved = !prevSaved);
    _showNotice(_isSaved ? "Saved to collection" : "Removed from collection");

    try {
      if (_isSaved) {
        await supabase.from('reel_bookmarks').upsert({
          'reel_id': widget.reel.id,
          'user_id': user.id,
        });
      } else {
        await supabase.from('reel_bookmarks').delete().match({
          'reel_id': widget.reel.id,
          'user_id': user.id,
        });
      }
    } catch (e) {
      debugPrint("Bookmark reel error: $e");
      if (mounted) setState(() => _isSaved = prevSaved);
    }
  }

  // Follow author in database
  Future<void> _toggleFollow() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showNotice("Please sign in to follow creators.");
      return;
    }
    if (_isFollowLoading) return;

    HapticFeedback.lightImpact();
    setState(() {
      _isFollowing = true;
      _isFollowLoading = true;
    });
    _showNotice("Following @${widget.reel.authorUsername}");

    try {
      await supabase.from('user_follows').insert({
        'follower_id': user.id,
        'following_id': widget.reel.userId,
      });

      try {
        await supabase.from('student_friends').upsert({
          'user_id': user.id,
          'friend_id': widget.reel.userId,
          'status': 'accepted',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

      unawaited(NotificationService().sendNotificationToUser(
        targetUserId: widget.reel.userId,
        title: "New Follower",
        message: "Started following you on ZEV",
        notificationType: "follow",
        senderId: user.id,
      ));
    } catch (e) {
      debugPrint("Follow reel creator error: $e");
      if (mounted) setState(() => _isFollowing = false);
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  // 1.5x Speed Up on Hold
  void _startFastForward() {
    if (_controller == null || !_isInitialized || _isFastForwarding) return;
    HapticFeedback.selectionClick();
    _controller!.setPlaybackSpeed(1.5);
    setState(() => _isFastForwarding = true);
  }

  void _stopFastForward() {
    _holdSpeedTimer?.cancel();
    if (_controller == null || !_isInitialized || !_isFastForwarding) return;
    HapticFeedback.selectionClick();
    _controller!.setPlaybackSpeed(1.0);
    setState(() => _isFastForwarding = false);
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

  void _openComments() {
    HapticFeedback.lightImpact();
    ReelCommentsSheet.show(
      context,
      reelId: widget.reel.id,
      reelAuthorUsername: widget.reel.authorUsername,
    );
  }

  void _openShareSheet() {
    HapticFeedback.lightImpact();
    // Build temporary FeedPostItem for FeedShareSheet compatibility
    final postItem = FeedPostItem(
      id: widget.reel.id,
      authorId: widget.reel.userId,
      authorUsername: widget.reel.authorUsername,
      authorFullName: widget.reel.authorFullName,
      authorAvatar: widget.reel.authorAvatar,
      isVerified: widget.reel.isVerified,
      title: widget.reel.title,
      content: widget.reel.description,
      imageUrl: widget.reel.thumbnailUrl ?? '',
      createdAt: widget.reel.createdAt,
      likesCount: _likesCount,
      isLikedByMe: _isLiked,
      commentsCount: widget.reel.commentsCount,
    );
    FeedShareSheet.show(context, post: postItem);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id;
    final isMe = currentUserId != null && currentUserId == widget.reel.userId;
    final shouldShowFollowButton = !isMe && !_isFollowing;
    final isRtl = TextDirectionHelper.isRtl(
      widget.reel.description.isNotEmpty
          ? widget.reel.description
          : widget.reel.title,
    );

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Fullscreen Video Player with Long-Press 1.5x Gesture
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayPause,
            onDoubleTap: _triggerDoubleTapLike,
            onLongPressStart: (_) {
              _holdSpeedTimer?.cancel();
              _holdSpeedTimer = Timer(const Duration(milliseconds: 300), () {
                _startFastForward();
              });
            },
            onLongPressEnd: (_) => _stopFastForward(),
            child: Center(
              child: _controller != null && _isInitialized
                  ? FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: _controller!.value.size.width > 0
                            ? _controller!.value.size.width
                            : 1080,
                        height: _controller!.value.size.height > 0
                            ? _controller!.value.size.height
                            : 1920,
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: ZevColors.primaryBlue,
                      ),
                    ),
            ),
          ),

          // 2. Cinematic Gradient Overlays (Top & Bottom for text readability)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                    stops: const [0.0, 0.2, 0.55, 1.0],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),

          // 3. Fast-Forward 1.5x Floating Badge (Shown when finger is held)
          if (_isFastForwarding)
            Positioned(
              top: 54,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: ZevColors.primaryBlue.withValues(alpha: 0.8),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ZevColors.primaryBlue.withValues(alpha: 0.4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fast_forward_rounded,
                        color: ZevColors.primaryBlue,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        "1.5X SPEED",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 4. Center Play / Pause Pop Badge
          if (_showPlayPauseBadge)
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _badgeIsPlay ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),

          // 5. Double-Tap Floating Heart Bloom
          if (_showFloatingHeart)
            Center(
              child: AnimatedBuilder(
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
                              color: Colors.redAccent.withValues(alpha: 0.55),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          size: 110,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // 6. Top Bar Header: "Reels" + Mute/Unmute sound button
          Positioned(
            top: 48,
            left: 18,
            right: 18,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Text(
                      "Reels",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
                // Sound Toggle Button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onToggleMute();
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      widget.isGlobalMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 7. Right-Side Action Column: Avatar + Like + Comment + Share + Save + Spinning Disc
          Positioned(
            right: 14,
            bottom: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Author Avatar with '+' follow badge if not followed
                GestureDetector(
                  onTap: shouldShowFollowButton ? _toggleFollow : null,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2.0,
                          ),
                        ),
                        child: ClipOval(
                          child: widget.reel.authorAvatar.isNotEmpty
                              ? Image.network(
                                  widget.reel.authorAvatar,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                    Icons.person_rounded,
                                    size: 26,
                                    color: Colors.white70,
                                  ),
                                )
                              : const Icon(
                                  Icons.person_rounded,
                                  size: 26,
                                  color: Colors.white70,
                                ),
                        ),
                      ),
                      if (shouldShowFollowButton)
                        Positioned(
                          bottom: -6,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: ZevColors.primaryBlue,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.add_rounded,
                                color: ZevColors.deepNavy,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Like Button
                _buildActionColumnItem(
                  icon: _isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  iconColor: _isLiked ? const Color(0xFFFF3040) : Colors.white,
                  count: _likesCount,
                  onTap: _toggleLike,
                ),
                const SizedBox(height: 18),

                // Comment Button
                _buildActionColumnItem(
                  icon: Icons.chat_bubble_rounded,
                  iconColor: Colors.white,
                  count: widget.reel.commentsCount,
                  onTap: _openComments,
                ),
                const SizedBox(height: 18),

                // Share Button (Opens Light Share Sheet)
                _buildActionColumnItem(
                  icon: Icons.send_rounded,
                  iconColor: Colors.white,
                  count: null,
                  label: "Share",
                  onTap: _openShareSheet,
                ),
                const SizedBox(height: 18),

                // Save / Bookmark Button
                GestureDetector(
                  onTap: _toggleBookmark,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: _isSaved ? ZevColors.primaryBlue : Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Rotating Vinyl Music Record
                RotationTransition(
                  turns: _vinylAnimCtrl,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1E222B),
                      border: Border.all(
                        color: Colors.white24,
                        width: 2,
                      ),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: ClipOval(
                      child: widget.reel.authorAvatar.isNotEmpty
                          ? Image.network(
                              widget.reel.authorAvatar,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                Icons.music_note_rounded,
                                color: ZevColors.primaryBlue,
                                size: 16,
                              ),
                            )
                          : const Icon(
                              Icons.music_note_rounded,
                              color: ZevColors.primaryBlue,
                              size: 16,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 8. Bottom-Left Information Overlay: Author, Follow, Caption, Audio
          Positioned(
            left: 16,
            right: 80,
            bottom: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Author row with Follow button
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        "@${widget.reel.authorUsername}",
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.reel.isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified_rounded,
                        size: 15,
                        color: ZevColors.primaryBlue,
                      ),
                    ],
                    if (shouldShowFollowButton) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _toggleFollow,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 1.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: _isFollowLoading
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Follow",
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Title & Caption with Smart RTL/LTR
                if (widget.reel.description.isNotEmpty ||
                    widget.reel.title.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(
                      () => _isCaptionExpanded = !_isCaptionExpanded,
                    ),
                    child: Text(
                      widget.reel.description.isNotEmpty
                          ? widget.reel.description
                          : widget.reel.title,
                      textDirection:
                          isRtl ? TextDirection.rtl : TextDirection.ltr,
                      maxLines: _isCaptionExpanded ? 8 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        height: 1.35,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),

                // Audio ticker
                Row(
                  children: [
                    const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white70,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Original audio • ${widget.reel.authorUsername}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
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
          ),

          // 9. Floating Scrubber Tooltip & Interactive Scrubber Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live timestamp bubble when scrubbing
                if (_isScrubbing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        "${_formatDuration(Duration(milliseconds: (_scrubRatio * _totalDuration.inMilliseconds).round()))} / ${_formatDuration(_totalDuration)}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),

                // Touch-Reactive Scrubber
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    setState(() {
                      _isScrubbing = true;
                      _scrubRatio = (details.localPosition.dx /
                              MediaQuery.of(context).size.width)
                          .clamp(0.0, 1.0);
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _scrubRatio = (details.localPosition.dx /
                              MediaQuery.of(context).size.width)
                          .clamp(0.0, 1.0);
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_controller != null && _isInitialized) {
                      final targetMs =
                          (_scrubRatio * _totalDuration.inMilliseconds).round();
                      _controller!.seekTo(Duration(milliseconds: targetMs));
                    }
                    setState(() => _isScrubbing = false);
                  },
                  child: Container(
                    height: _isScrubbing ? 20 : 6,
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        height: _isScrubbing ? 5 : 2,
                        width: double.infinity,
                        color: Colors.white.withValues(alpha: 0.25),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _isScrubbing
                              ? _scrubRatio
                              : (_totalDuration.inMilliseconds > 0
                                  ? (_currentPosition.inMilliseconds /
                                          _totalDuration.inMilliseconds)
                                      .clamp(0.0, 1.0)
                                  : 0.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: ZevColors.primaryBlue,
                              boxShadow: _isScrubbing
                                  ? [
                                      BoxShadow(
                                        color: ZevColors.primaryBlue
                                            .withValues(alpha: 0.8),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionColumnItem({
    required IconData icon,
    required Color iconColor,
    required int? count,
    String? label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 30),
          const SizedBox(height: 4),
          Text(
            label ??
                (count != null
                    ? (count > 999
                        ? "${(count / 1000).toStringAsFixed(1)}K"
                        : "$count")
                    : ""),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
