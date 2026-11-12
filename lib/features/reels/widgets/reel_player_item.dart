import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/content_deletion_service.dart';
import '../../../core/services/feed_algorithm_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/rich_text_helper.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_video_thumbnail.dart';
import '../../feed/models/feed_post_item.dart';
import '../../feed/widgets/feed_share_sheet.dart';
import '../../profile/screens/profile_screen.dart';
import '../models/reel_item.dart';
import '../services/reel_video_cache_manager.dart';
import 'reel_comments_sheet.dart';

/// Next-Generation Instagram/TikTok Caliber Reel Player Item.
/// Engineered with smooth playback, interactive touch-scrubber,
/// press-and-hold 1.5x fast-forward, double-tap floating heart pop, and telemetry.
class ReelPlayerItem extends StatefulWidget {
  final ReelItem reel;
  final bool isActive;
  final bool isGlobalMuted;
  final VoidCallback onToggleMute;
  final VoidCallback? onReelDeleted;
  final VoidCallback? onHideOrMute;

  const ReelPlayerItem({
    super.key,
    required this.reel,
    required this.isActive,
    required this.isGlobalMuted,
    required this.onToggleMute,
    this.onReelDeleted,
    this.onHideOrMute,
  });

  @override
  State<ReelPlayerItem> createState() => _ReelPlayerItemState();
}

class _ReelPlayerItemState extends State<ReelPlayerItem>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isInitializingVideo = false;
  bool _videoLoadError = false;
  int _initEpoch = 0;
  bool _isRoutePaused = false;

  bool _hasRecordedView = false;
  bool _isLiked = false;
  int _likesCount = 0;
  int _commentsCount = 0;
  bool _isSaved = false;
  bool _isFollowing = false;
  bool _followRequested = false;
  bool _isFollowLoading = false;
  bool _isCaptionExpanded = false;

  // Double-tap heart animation
  late final AnimationController _heartAnimCtrl;
  late final Animation<double> _heartScaleAnim;
  late final Animation<double> _heartOpacityAnim;
  bool _showFloatingHeart = false;

  // Rotating vinyl record animation
  late final AnimationController _vinylAnimCtrl;

  // Fast forward (1.5x speed on hold)
  bool _isFastForwarding = false;

  // Interactive scrubber (seek bar) + floating frame preview
  bool _isScrubbing = false;
  double _scrubRatio = 0.0;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  Uint8List? _scrubPreviewBytes;
  int _lastScrubSampleMs = -1000;
  Timer? _scrubSampleDebounce;
  bool _hasRenderedFirstFrame = false;

  bool get _hasLiveController {
    final ctrl = _controller;
    if (ctrl == null) return false;
    if (!ReelVideoCacheManager().isCachedInRam(widget.reel.videoUrl)) {
      return false;
    }
    try {
      return ctrl.value.isInitialized;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncStateFromReel();

    // Heart pop animation
    _heartAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _heartScaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.4,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.4,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_heartAnimCtrl);

    _heartOpacityAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 40),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_heartAnimCtrl);

    _heartAnimCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showFloatingHeart = false);
      }
    });

    // Vinyl record rotation (starts repeating only while actively playing)
    _vinylAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _initializeVideo();
  }

  void _syncStateFromReel() {
    _isLiked = widget.reel.isLikedByMe;
    _likesCount = widget.reel.likesCount;
    _commentsCount = widget.reel.commentsCount;
    _isSaved = widget.reel.isBookmarkedByMe;
    _isFollowing = widget.reel.isAuthorFollowed;
    _followRequested = false;
    _isFollowLoading = false;
    _hasRecordedView = false;
    _isCaptionExpanded = false;
    _showFloatingHeart = false;
    _isFastForwarding = false;
    _isScrubbing = false;
    _scrubRatio = 0.0;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _scrubPreviewBytes = null;
    _lastScrubSampleMs = -1000;
    _scrubSampleDebounce?.cancel();
    _hasRenderedFirstFrame = false;
    _videoLoadError = false;
  }

  void _detachController({bool pauseIfLive = false}) {
    final ctrl = _controller;
    if (ctrl != null) {
      try {
        ctrl.removeListener(_onVideoControllerTick);
        if (pauseIfLive && ctrl.value.isInitialized && ctrl.value.isPlaying) {
          ctrl.pause();
        }
      } catch (_) {
        // Controller may already be evicted and disposed by ReelVideoCacheManager
      }
    }
    _controller = null;
    _isInitialized = false;
    _hasRenderedFirstFrame = false;
  }

  Future<void> _initializeVideo() async {
    final videoUrl = widget.reel.videoUrl;
    if (videoUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isInitializingVideo = false;
          _isInitialized = false;
          _videoLoadError = true;
        });
      }
      return;
    }

    final int epoch = ++_initEpoch;
    _isInitializingVideo = true;
    if (mounted && _videoLoadError) {
      setState(() => _videoLoadError = false);
    }

    try {
      final ctrl = await ReelVideoCacheManager().getOrCreateController(
        videoUrl,
        isMuted: widget.isGlobalMuted,
      );
      if (!mounted || epoch != _initEpoch || videoUrl != widget.reel.videoUrl) {
        return;
      }

      if (ctrl.value.hasError || !ctrl.value.isInitialized) {
        throw StateError('Video controller failed to initialize');
      }

      _detachController();
      _controller = ctrl;
      ctrl.addListener(_onVideoControllerTick);

      setState(() {
        _isInitializingVideo = false;
        _isInitialized = true;
        _videoLoadError = false;
        _totalDuration = ctrl.value.duration;
        _currentPosition = ctrl.value.position;
      });

      if (widget.isActive && !_isRoutePaused) {
        await ctrl.setVolume(widget.isGlobalMuted ? 0.0 : 1.0);
        await ctrl.setPlaybackSpeed(1.0);
        await ctrl.play();
        if (mounted && epoch == _initEpoch) {
          _vinylAnimCtrl.repeat();
          _recordViewOnce();
        }
      } else {
        if (ctrl.value.isPlaying) {
          await ctrl.pause();
        }
        _vinylAnimCtrl.stop();
      }
    } catch (e) {
      debugPrint("Reel video initialization notice: $e");
      if (mounted && epoch == _initEpoch) {
        setState(() {
          _isInitializingVideo = false;
          _isInitialized = false;
          _videoLoadError = true;
        });
        _vinylAnimCtrl.stop();
      }
    }
  }

  Future<void> _recordViewOnce() async {
    if (_hasRecordedView) return;
    if (widget.reel.id.isEmpty || widget.reel.id == 'preview_reel') return;
    _hasRecordedView = true;
    try {
      await supabase.rpc(
        'record_reel_view',
        params: {'p_reel_id': widget.reel.id},
      );
    } catch (_) {}
  }

  void _onVideoControllerTick() {
    if (!mounted) return;

    if (!_hasLiveController) {
      _vinylAnimCtrl.stop();
      setState(() {
        _controller = null;
        _isInitialized = false;
        _isFastForwarding = false;
      });
      if (widget.isActive && !_isInitializingVideo && !_isRoutePaused) {
        unawaited(_initializeVideo());
      }
      return;
    }

    final val = _controller!.value;
    if (val.hasError) {
      _vinylAnimCtrl.stop();
      setState(() {
        _isInitialized = false;
        _videoLoadError = true;
        _isFastForwarding = false;
      });
      return;
    }

    if (val.isPlaying && widget.isActive && !_isRoutePaused) {
      if (!_vinylAnimCtrl.isAnimating) {
        _vinylAnimCtrl.repeat();
      }
    } else if (_vinylAnimCtrl.isAnimating) {
      _vinylAnimCtrl.stop();
    }

    final frameReady = val.isInitialized &&
        (val.position > Duration.zero || val.isPlaying);
    if (frameReady && !_hasRenderedFirstFrame) {
      setState(() => _hasRenderedFirstFrame = true);
    }

    if (_isScrubbing) return;
    final pos = val.position;
    final dur = val.duration;
    if (pos != _currentPosition || dur != _totalDuration) {
      setState(() {
        _currentPosition = pos;
        _totalDuration = dur;
      });
    }
  }

  @override
  void didUpdateWidget(ReelPlayerItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.reel.id != oldWidget.reel.id ||
        widget.reel.videoUrl != oldWidget.reel.videoUrl) {
      _initEpoch++;
      _isInitializingVideo = false;
      _detachController(pauseIfLive: true);
      _vinylAnimCtrl.stop();
      setState(_syncStateFromReel);
      unawaited(_initializeVideo());
      return;
    }

    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        if (_hasLiveController && _isInitialized && !_isRoutePaused) {
          try {
            _controller!.setVolume(widget.isGlobalMuted ? 0.0 : 1.0);
            _controller!.setPlaybackSpeed(1.0);
            _controller!.play();
            _vinylAnimCtrl.repeat();
            _recordViewOnce();
            setState(() {});
          } catch (_) {
            _detachController();
            unawaited(_initializeVideo());
          }
        } else if (!_isInitializingVideo && !_isRoutePaused) {
          _detachController();
          unawaited(_initializeVideo());
        }
      } else {
        if (_isFastForwarding || _isScrubbing) {
          setState(() {
            _isFastForwarding = false;
            _isScrubbing = false;
          });
        }
        if (_hasLiveController) {
          try {
            _controller!.setPlaybackSpeed(1.0);
            _controller!.pause();
          } catch (_) {}
        }
        _vinylAnimCtrl.stop();
      }
    }

    if (widget.isGlobalMuted != oldWidget.isGlobalMuted && _hasLiveController) {
      try {
        _controller!.setVolume(widget.isGlobalMuted ? 0.0 : 1.0);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _initEpoch++;
    _scrubSampleDebounce?.cancel();
    _detachController(pauseIfLive: true);
    _heartAnimCtrl.dispose();
    _vinylAnimCtrl.dispose();
    super.dispose();
  }

  void _requestScrubPreviewFrame(int rawMs) {
    final bucketMs = ((rawMs / 500).round() * 500).clamp(
      0,
      _totalDuration.inMilliseconds > 0 ? _totalDuration.inMilliseconds : rawMs,
    );
    if ((bucketMs - _lastScrubSampleMs).abs() < 400 &&
        _scrubPreviewBytes != null) {
      return;
    }
    _scrubSampleDebounce?.cancel();
    _scrubSampleDebounce = Timer(const Duration(milliseconds: 90), () async {
      final url = widget.reel.videoUrl;
      if (!mounted || !_isScrubbing || url.isEmpty) return;
      _lastScrubSampleMs = bucketMs;
      final bytes = await ZevVideoThumbnail.extractThumbnailBytes(
        url,
        position: Duration(milliseconds: bucketMs),
        maxHeight: 240,
        quality: 68,
      );
      if (mounted && _isScrubbing && widget.reel.videoUrl == url && bytes != null) {
        setState(() => _scrubPreviewBytes = bytes);
      }
    });
  }

  // Single Tap to Play/Pause
  void _togglePlayPause() {
    if (_videoLoadError) {
      HapticFeedback.lightImpact();
      unawaited(_initializeVideo());
      return;
    }

    if (!_hasLiveController || !_isInitialized) {
      if (!_isInitializingVideo) {
        unawaited(_initializeVideo());
      }
      return;
    }

    HapticFeedback.lightImpact();
    try {
      setState(() {
        if (_controller!.value.isPlaying) {
          _controller!.pause();
          _vinylAnimCtrl.stop();
        } else {
          _controller!.play();
          _vinylAnimCtrl.repeat();
          _recordViewOnce();
        }
      });
    } catch (_) {
      _detachController();
      unawaited(_initializeVideo());
    }
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
      _likesCount = _isLiked
          ? prevCount + 1
          : (prevCount > 0 ? prevCount - 1 : 0);
    });

    try {
      if (_isLiked) {
        await supabase.from('reel_likes').upsert({
          'reel_id': widget.reel.id,
          'user_id': user.id,
        }, onConflict: 'reel_id,user_id');

        FeedAlgorithmService.instance.recordPositiveInteraction(
          authorId: widget.reel.userId,
          category: widget.reel.category,
          text: '${widget.reel.title} ${widget.reel.description}',
          weight: 4.5,
        );

        if (widget.reel.userId != user.id) {
          unawaited(
            NotificationService().dispatchPushNotification(
              recipientUserId: widget.reel.userId,
              title: 'New Reel Like',
              body: 'liked your reel on ZEV.',
              notificationType: 'reel_like',
              deepLink: '/reel/${widget.reel.id}',
            ),
          );
        }
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

    try {
      if (_isSaved) {
        await supabase.from('reel_bookmarks').upsert({
          'reel_id': widget.reel.id,
          'user_id': user.id,
        }, onConflict: 'reel_id,user_id');

        FeedAlgorithmService.instance.recordPositiveInteraction(
          authorId: widget.reel.userId,
          category: widget.reel.category,
          text: '${widget.reel.title} ${widget.reel.description}',
          weight: 3.5,
        );

        if (!mounted) return;
        _showNotice("Saved to bookmarks");
      } else {
        await supabase.from('reel_bookmarks').delete().match({
          'reel_id': widget.reel.id,
          'user_id': user.id,
        });
        if (!mounted) return;
        _showNotice("Removed from bookmarks");
      }
    } catch (e) {
      debugPrint("Bookmark reel error: $e");
      if (mounted) {
        setState(() => _isSaved = prevSaved);
        _showNotice("Could not update bookmark.");
      }
    }
  }

  // Follow author in database via SocialGraphService
  Future<void> _toggleFollow() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showNotice("Please sign in to follow creators.");
      return;
    }
    if (_isFollowLoading) return;

    HapticFeedback.lightImpact();
    setState(() => _isFollowLoading = true);

    final status = await SocialGraphService.instance.toggleFollow(
      widget.reel.userId,
    );
    if (!mounted) return;
    setState(() {
      _isFollowLoading = false;
      switch (status) {
        case FollowToggleStatus.following:
          _isFollowing = true;
          _followRequested = false;
          _showNotice("Following @${widget.reel.authorUsername}");
          break;
        case FollowToggleStatus.requested:
          _isFollowing = false;
          _followRequested = true;
          _showNotice("Follow request sent to @${widget.reel.authorUsername}");
          break;
        case FollowToggleStatus.unfollowed:
        case FollowToggleStatus.cancelled:
          _isFollowing = false;
          _followRequested = false;
          break;
        case FollowToggleStatus.blocked:
          _showNotice("Cannot follow this account.");
          break;
        case FollowToggleStatus.error:
          _showNotice("Could not update follow status.");
          break;
      }
    });
  }

  Future<void> _openAuthorProfile() async {
    if (widget.reel.userId.isEmpty || widget.reel.userId == 'preview_user') {
      return;
    }
    HapticFeedback.lightImpact();
    final bool wasPlaying = _hasLiveController && _controller!.value.isPlaying;
    _isRoutePaused = true;
    if (_hasLiveController && wasPlaying) {
      try {
        _controller!.pause();
      } catch (_) {}
    }
    _vinylAnimCtrl.stop();

    await ProfileScreen.open(context, userId: widget.reel.userId);
    if (!mounted) return;

    _isRoutePaused = false;
    if (widget.isActive && wasPlaying) {
      if (_hasLiveController) {
        try {
          _controller!.setVolume(widget.isGlobalMuted ? 0.0 : 1.0);
          _controller!.play();
          _vinylAnimCtrl.repeat();
        } catch (_) {
          _detachController();
          unawaited(_initializeVideo());
        }
      } else if (!_isInitializingVideo) {
        unawaited(_initializeVideo());
      }
    }
  }

  // 1.5x Speed Up on Hold
  void _startFastForward() {
    if (!widget.isActive ||
        !_hasLiveController ||
        !_isInitialized ||
        _isFastForwarding) {
      return;
    }
    HapticFeedback.selectionClick();
    try {
      _controller!.setPlaybackSpeed(1.5);
      setState(() => _isFastForwarding = true);
    } catch (_) {}
  }

  void _stopFastForward() {
    if (!_isFastForwarding) return;
    HapticFeedback.selectionClick();
    if (_hasLiveController) {
      try {
        _controller!.setPlaybackSpeed(1.0);
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _isFastForwarding = false);
    }
  }

  void _showNotice(String msg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
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
      reelAuthorId: widget.reel.userId,
      onCommentAdded: () {
        if (mounted) setState(() => _commentsCount += 1);
      },
      onCommentDeleted: () {
        if (mounted) {
          setState(() {
            _commentsCount = _commentsCount > 0 ? _commentsCount - 1 : 0;
          });
        }
      },
    );
  }

  void _openShareSheet() {
    HapticFeedback.lightImpact();
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
      commentsCount: _commentsCount,
    );
    FeedShareSheet.show(context, post: postItem, isReel: true);
  }

  void _showReelOptions() {
    HapticFeedback.lightImpact();
    final bool canDelete = ContentDeletionService.canDeleteReel(widget.reel);

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
            Container(
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 18),
            _buildReelOptionTile(
              icon: Icons.share_outlined,
              title: "Share Reel",
              color: ZevColors.deepNavy,
              onTap: () {
                Navigator.pop(bottomSheetContext);
                if (mounted) _openShareSheet();
              },
            ),
            const SizedBox(height: 10),
            _buildReelOptionTile(
              icon: Icons.link_rounded,
              title: "Copy Link",
              color: ZevColors.deepNavy,
              onTap: () {
                Navigator.pop(bottomSheetContext);
                Clipboard.setData(
                  ClipboardData(
                    text: "https://www.zevapp.com/reel/${widget.reel.id}",
                  ),
                );
                if (mounted) _showNotice("Reel link copied to clipboard.");
              },
            ),
            if (canDelete) ...[
              const SizedBox(height: 10),
              _buildReelOptionTile(
                icon: Icons.delete_outline_rounded,
                title: "Move to Trash",
                color: const Color(0xFFDC2626),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  if (!mounted) return;
                  await ContentDeletionService.moveReelToTrash(
                    context,
                    reel: widget.reel,
                    onTrashed: widget.onReelDeleted,
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildReelOptionTile(
                icon: Icons.delete_forever_outlined,
                title: "Delete Permanently",
                color: const Color(0xFFDC2626),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  if (!mounted) return;
                  await ContentDeletionService.confirmAndDeleteReel(
                    context,
                    reel: widget.reel,
                    onDeleted: widget.onReelDeleted,
                  );
                },
              ),
            ] else ...[
              const SizedBox(height: 10),
              _buildReelOptionTile(
                icon: Icons.visibility_off_outlined,
                title: "Not Interested",
                color: ZevColors.deepNavy,
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  final ok = await SocialGraphService.instance.hideContent(
                    targetId: widget.reel.id,
                    targetType: 'reel',
                  );
                  if (!mounted) return;
                  if (ok) {
                    _showNotice("We'll show fewer reels like this.");
                    widget.onHideOrMute?.call();
                  } else {
                    _showNotice("Could not update preference.");
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildReelOptionTile(
                icon: Icons.volume_off_outlined,
                title: "Mute @${widget.reel.authorUsername}",
                color: ZevColors.deepNavy,
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  final ok = await SocialGraphService.instance.muteUser(
                    widget.reel.userId,
                  );
                  if (!mounted) return;
                  if (ok) {
                    _showNotice("Muted @${widget.reel.authorUsername}.");
                    widget.onHideOrMute?.call();
                  } else {
                    _showNotice("Could not mute user.");
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildReelOptionTile(
                icon: Icons.block_rounded,
                title: "Block @${widget.reel.authorUsername}",
                color: const Color(0xFFDC2626),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  final ok = await SocialGraphService.instance.blockUser(
                    widget.reel.userId,
                  );
                  if (!mounted) return;
                  if (ok) {
                    _showNotice("Blocked @${widget.reel.authorUsername}.");
                    widget.onHideOrMute?.call();
                  } else {
                    _showNotice("Could not block user.");
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildReelOptionTile(
                icon: Icons.flag_outlined,
                title: "Report Reel",
                color: const Color(0xFFDC2626),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  if (!mounted) return;
                  SocialGraphService.instance.showReportSheet(
                    context,
                    targetType: 'reel',
                    targetId: widget.reel.id,
                    reportedUserId: widget.reel.userId,
                    targetLabel: 'Reel',
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

  Widget _buildReelOptionTile({
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
            const Icon(
              Icons.chevron_right_rounded,
              color: ZevColors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Widget _buildLoadingOrErrorStage({bool showSpinner = true}) {
    final hasThumb = ZevVideoThumbnail.isValidImageThumbUrl(widget.reel.thumbnailUrl);

    return Stack(
      fit: StackFit.expand,
      children: [
        ZevVideoThumbnail(
          videoUrl: widget.reel.videoUrl,
          thumbnailUrl: widget.reel.thumbnailUrl,
          showPlayBadge: false,
          showViews: false,
          fit: BoxFit.cover,
          placeholder: const ColoredBox(color: Color(0xFF0B1120)),
        ),
        if (_videoLoadError)
          Container(
            color: Colors.black.withValues(alpha: hasThumb ? 0.55 : 0.85),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_off_outlined,
                    color: Colors.white70,
                    size: 46,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Unable to play video",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _initializeVideo,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text("Retry"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZevColors.primaryBlue,
                      foregroundColor: ZevColors.deepNavy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (showSpinner)
          Positioned(
            bottom: 108,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 0.8,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: ZevColors.primaryBlue,
                      ),
                    ),
                    SizedBox(width: 7),
                    Text(
                      "Loading video...",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.height < 720 || screenSize.width < 380;
    final currentUserId = supabase.auth.currentUser?.id;
    final isMe = currentUserId != null && currentUserId == widget.reel.userId;
    final shouldShowFollowButton = !isMe && !_isFollowing;
    final isRtl = TextDirectionHelper.isRtl(
      widget.reel.description.isNotEmpty
          ? widget.reel.description
          : widget.reel.title,
    );

    final bool canRenderVideo = _isInitialized && _hasLiveController;
    final bool showPauseOverlay =
        canRenderVideo && !_controller!.value.isPlaying;
    final double overlayBottom = isCompact ? 104 : 110;

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
            onLongPressStart: (_) => _startFastForward(),
            onLongPressEnd: (_) => _stopFastForward(),
            onLongPressCancel: _stopFastForward,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!canRenderVideo || !_hasRenderedFirstFrame)
                  _buildLoadingOrErrorStage(showSpinner: !canRenderVideo),
                if (canRenderVideo)
                  AnimatedOpacity(
                    opacity: _hasRenderedFirstFrame ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: Center(
                      child: FittedBox(
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
                      ),
                    ),
                  ),
              ],
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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

          // 4. Center Pause Badge with Mute/Unmute Toggle directly above it
          if (showPauseOverlay)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onToggleMute();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.15),
                            blurRadius: 6,
                            offset: const Offset(0, -1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isGlobalMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.isGlobalMuted ? "Muted" : "Sound On",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.50),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 46,
                      ),
                    ),
                  ),
                ],
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

          // 6. Right-Side Action Column: Avatar + Like + Comment + Share + Save + Spinning Disc
          Positioned(
            right: isCompact ? 8 : 10,
            bottom: overlayBottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: _openAuthorProfile,
                      child: Container(
                        width: isCompact ? 36 : 40,
                        height: isCompact ? 36 : 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.9),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: widget.reel.authorAvatar.isNotEmpty
                            ? ZevCachedImage.avatar(
                                imageUrl: widget.reel.authorAvatar,
                                size: isCompact ? 36 : 40,
                              )
                            : Icon(
                                Icons.person_rounded,
                                size: isCompact ? 20 : 22,
                                color: Colors.white70,
                              ),
                      ),
                    ),
                    if (shouldShowFollowButton && !_followRequested)
                      Positioned(
                        bottom: -4,
                        child: GestureDetector(
                          onTap: _toggleFollow,
                          child: Container(
                            width: isCompact ? 16 : 18,
                            height: isCompact ? 16 : 18,
                            decoration: BoxDecoration(
                              color: ZevColors.primaryBlue,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1.5),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                Icons.add_rounded,
                                color: ZevColors.deepNavy,
                                size: isCompact ? 11 : 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: isCompact ? 10 : 13),

                _buildActionColumnItem(
                  icon: _isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  iconColor: _isLiked ? const Color(0xFFFF3040) : Colors.white,
                  count: _likesCount,
                  onTap: _toggleLike,
                  iconSize: isCompact ? 24 : 26,
                  isCompact: isCompact,
                ),
                SizedBox(height: isCompact ? 8 : 11),

                _buildActionColumnItem(
                  icon: Icons.chat_bubble_rounded,
                  iconColor: Colors.white,
                  count: _commentsCount,
                  onTap: _openComments,
                  iconSize: isCompact ? 24 : 26,
                  isCompact: isCompact,
                ),
                SizedBox(height: isCompact ? 8 : 11),

                _buildActionColumnItem(
                  icon: Icons.send_rounded,
                  iconColor: Colors.white,
                  count: null,
                  label: "Share",
                  onTap: _openShareSheet,
                  iconSize: isCompact ? 23 : 25,
                  isCompact: isCompact,
                ),
                SizedBox(height: isCompact ? 8 : 11),

                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _toggleBookmark();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: isCompact ? 2 : 3),
                    child: Icon(
                      _isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: _isSaved ? ZevColors.primaryBlue : Colors.white,
                      size: isCompact ? 24 : 26,
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 6,
                          offset: Offset(0, 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: isCompact ? 8 : 11),

                _buildActionColumnItem(
                  icon: Icons.more_horiz_rounded,
                  iconColor: Colors.white,
                  count: null,
                  onTap: _showReelOptions,
                  iconSize: isCompact ? 24 : 26,
                  isCompact: isCompact,
                ),
                SizedBox(height: isCompact ? 8 : 11),

                RotationTransition(
                  turns: _vinylAnimCtrl,
                  child: Container(
                    width: isCompact ? 28 : 32,
                    height: isCompact ? 28 : 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1E222B),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 6,
                          offset: Offset(0, 1.5),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(isCompact ? 3 : 4),
                    child: widget.reel.authorAvatar.isNotEmpty
                        ? ZevCachedImage.avatar(
                            imageUrl: widget.reel.authorAvatar,
                            size: isCompact ? 22 : 26,
                          )
                        : Icon(
                            Icons.music_note_rounded,
                            color: ZevColors.primaryBlue,
                            size: isCompact ? 12 : 14,
                          ),
                  ),
                ),
              ],
            ),
          ),

          // 7. Bottom-Left Information Overlay: Author, Follow, Caption, Audio
          Positioned(
            left: 12,
            right: isCompact ? 56 : 64,
            bottom: overlayBottom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: _openAuthorProfile,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                "@${widget.reel.authorUsername}",
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black87,
                                      blurRadius: 8,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.reel.isVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.verified_rounded,
                                size: 16,
                                color: ZevColors.primaryBlue,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (shouldShowFollowButton) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _toggleFollow,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 1.2,
                            ),
                            borderRadius: BorderRadius.circular(8),
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
                              : Text(
                                  _isFollowing
                                      ? "Following"
                                      : _followRequested
                                          ? "Requested"
                                          : "Follow",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Title & Caption with Smart RTL/LTR & expansion
                if (widget.reel.description.isNotEmpty ||
                    widget.reel.title.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(
                      () => _isCaptionExpanded = !_isCaptionExpanded,
                    ),
                    child: ZevRichText(
                      text: widget.reel.description.isNotEmpty
                          ? widget.reel.description
                          : widget.reel.title,
                      textDirection: isRtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      maxLines: _isCaptionExpanded ? 8 : 2,
                      overflow: TextOverflow.ellipsis,
                      mentionColor: ZevColors.primaryBlue,
                      hashtagColor: ZevColors.primaryBlue,
                      linkColor: ZevColors.primaryBlue,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Colors.white,
                        height: 1.35,
                        shadows: [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white,
                      size: 15,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Original audio • ${widget.reel.authorUsername}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 4),
                          ],
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

          // 8. Floating Scrubber Frame Preview & Interactive Scrubber Bar (Above floating dock)
          Positioned(
            left: 0,
            right: 0,
            bottom: 94,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth > 0
                    ? constraints.maxWidth
                    : screenSize.width;
                const double previewWidth = 82.0;
                const double previewHeight = 132.0;
                final double targetLeft = (_scrubRatio * width - previewWidth / 2)
                    .clamp(12.0, (width - previewWidth - 12.0).clamp(12.0, width));
                final int previewMs =
                    (_scrubRatio * _totalDuration.inMilliseconds)
                        .clamp(0, _totalDuration.inMilliseconds)
                        .round();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isScrubbing && _totalDuration.inMilliseconds > 0)
                      Padding(
                        padding: EdgeInsets.only(left: targetLeft, bottom: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: previewWidth,
                              height: previewHeight,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (_scrubPreviewBytes != null)
                                      Image.memory(
                                        _scrubPreviewBytes!,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      )
                                    else
                                      ZevVideoThumbnail(
                                        videoUrl: widget.reel.videoUrl,
                                        thumbnailUrl: widget.reel.thumbnailUrl,
                                        showPlayBadge: false,
                                        showViews: false,
                                        fit: BoxFit.cover,
                                      ),
                                    Positioned(
                                      left: 4,
                                      right: 4,
                                      bottom: 5,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.72),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _formatDuration(
                                            Duration(milliseconds: previewMs),
                                          ),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.78),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: ZevColors.primaryBlue.withValues(alpha: 0.55),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                "${_formatDuration(Duration(milliseconds: previewMs))} / ${_formatDuration(_totalDuration)}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (details) {
                        if (width > 0 && _totalDuration.inMilliseconds > 0) {
                          final ratio = (details.localPosition.dx / width)
                              .clamp(0.0, 1.0);
                          setState(() {
                            _isScrubbing = true;
                            _scrubRatio = ratio;
                          });
                          _requestScrubPreviewFrame(
                            (ratio * _totalDuration.inMilliseconds).round(),
                          );
                        }
                      },
                      onHorizontalDragUpdate: (details) {
                        if (width > 0 && _totalDuration.inMilliseconds > 0) {
                          final ratio = (details.localPosition.dx / width)
                              .clamp(0.0, 1.0);
                          setState(() {
                            _scrubRatio = ratio;
                          });
                          _requestScrubPreviewFrame(
                            (ratio * _totalDuration.inMilliseconds).round(),
                          );
                        }
                      },
                      onHorizontalDragCancel: () {
                        _scrubSampleDebounce?.cancel();
                        if (_isScrubbing && mounted) {
                          setState(() => _isScrubbing = false);
                        }
                      },
                      onHorizontalDragEnd: (_) {
                        _scrubSampleDebounce?.cancel();
                        Duration? seekTarget;
                        if (_hasLiveController &&
                            _isInitialized &&
                            _totalDuration.inMilliseconds > 0) {
                          final targetMs =
                              (_scrubRatio * _totalDuration.inMilliseconds)
                                  .clamp(0, _totalDuration.inMilliseconds)
                                  .round();
                          seekTarget = Duration(milliseconds: targetMs);
                          try {
                            unawaited(_controller!.seekTo(seekTarget));
                          } catch (_) {}
                        }
                        if (mounted) {
                          setState(() {
                            if (seekTarget != null) {
                              _currentPosition = seekTarget;
                            }
                            _isScrubbing = false;
                          });
                        }
                      },
                      child: Container(
                        height: _isScrubbing ? 20 : 8,
                        color: Colors.transparent,
                        child: Center(
                          child: Container(
                            height: _isScrubbing ? 5 : 2.5,
                            width: double.infinity,
                            color: Colors.white.withValues(alpha: 0.25),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: _isScrubbing
                                  ? _scrubRatio.clamp(0.0, 1.0)
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
                );
              },
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
    double iconSize = 25.0,
    bool isCompact = false,
  }) {
    final displayText =
        label ??
        (count != null
            ? (count > 999 ? "${(count / 1000).toStringAsFixed(1)}K" : "$count")
            : "");

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: isCompact ? 2 : 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: iconColor,
              size: iconSize,
              shadows: const [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 6,
                  offset: Offset(0, 1.5),
                ),
              ],
            ),
            if (displayText.isNotEmpty) ...[
              SizedBox(height: isCompact ? 2 : 3),
              Text(
                displayText,
                style: TextStyle(
                  fontSize: isCompact ? 10.5 : 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                  shadows: const [
                    Shadow(
                      color: Colors.black87,
                      blurRadius: 5,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
