import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../feed/models/feed_post_item.dart';

/// Serene, Instagram-Grade Story Viewer for ZEV.
/// Features:
/// - 5-second timer for photos and text stories
/// - Exact video duration timer for video stories
/// - Instant press-and-hold freeze / pause (both video and progress timer)
/// - Segmented top progress bars, tap to skip/back, and direct message replies.
class StoryViewerScreen extends StatefulWidget {
  final ActiveFriendStory friendStory;

  const StoryViewerScreen({super.key, required this.friendStory});

  static Future<void> open(
    BuildContext context, {
    required ActiveFriendStory friendStory,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            StoryViewerScreen(friendStory: friendStory),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _stories = [];
  bool _isLoading = true;
  int _currentIndex = 0;

  late final AnimationController _progressAnimCtrl;
  bool _isPaused = false;
  DateTime? _pointerDownTime;
  final TextEditingController _replyCtrl = TextEditingController();

  VideoPlayerController? _videoPlayerCtrl;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();

    _progressAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _progressAnimCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onStoryFinished();
      }
    });

    _fetchUserStories();
  }

  @override
  void dispose() {
    _progressAnimCtrl.dispose();
    _videoPlayerCtrl?.dispose();
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchUserStories() async {
    try {
      final nowStr = DateTime.now().toIso8601String();
      final res = await supabase
          .from('user_stories')
          .select('id, media_url, media_type, caption, created_at, expires_at')
          .eq('user_id', widget.friendStory.userId)
          .gt('expires_at', nowStr)
          .order('created_at', ascending: true);

      final list = List<Map<String, dynamic>>.from(res as List);
      if (mounted) {
        setState(() {
          _stories = list;
          _isLoading = false;
        });

        if (list.isNotEmpty) {
          _setupCurrentStory();
        } else {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) Navigator.pop(context);
          });
        }
      }
    } catch (e) {
      debugPrint("Fetch stories error: $e");
      if (mounted) Navigator.pop(context);
    }
  }

  void _setupCurrentStory() {
    if (_stories.isEmpty) return;

    _videoPlayerCtrl?.pause();
    _videoPlayerCtrl?.dispose();
    _videoPlayerCtrl = null;
    _isVideoInitialized = false;

    final currentStory = _stories[_currentIndex];
    final mediaUrl = currentStory['media_url'] as String? ?? '';
    final mediaType = currentStory['media_type'] as String? ?? 'image';

    final isVideo = mediaType == 'video' ||
        mediaUrl.toLowerCase().contains('.mp4') ||
        mediaUrl.toLowerCase().contains('.mov') ||
        mediaUrl.toLowerCase().contains('.webm');

    if (isVideo && mediaUrl.isNotEmpty) {
      _progressAnimCtrl.stop();
      _videoPlayerCtrl = VideoPlayerController.networkUrl(Uri.parse(mediaUrl))
        ..initialize().then((_) {
          if (!mounted) return;
          final videoDuration = _videoPlayerCtrl!.value.duration;
          setState(() {
            _isVideoInitialized = true;
            _progressAnimCtrl.duration = videoDuration > Duration.zero
                ? videoDuration
                : const Duration(seconds: 5);
          });
          if (!_isPaused) {
            _videoPlayerCtrl!.play();
            _progressAnimCtrl.forward(from: 0.0);
          }
        }).catchError((err) {
          debugPrint("Story video playback error: $err");
          if (!mounted) return;
          _progressAnimCtrl.duration = const Duration(seconds: 5);
          _progressAnimCtrl.forward(from: 0.0);
        });
    } else {
      // Photo or text story: exact 5-second timer
      _progressAnimCtrl.duration = const Duration(seconds: 5);
      _progressAnimCtrl.forward(from: 0.0);
    }
  }

  void _onStoryFinished() {
    if (_currentIndex < _stories.length - 1) {
      setState(() => _currentIndex++);
      _setupCurrentStory();
    } else {
      Navigator.pop(context);
    }
  }

  void _nextStory() {
    HapticFeedback.lightImpact();
    if (_currentIndex < _stories.length - 1) {
      setState(() => _currentIndex++);
      _setupCurrentStory();
    } else {
      Navigator.pop(context);
    }
  }

  void _previousStory() {
    HapticFeedback.lightImpact();
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _setupCurrentStory();
    } else {
      _setupCurrentStory();
    }
  }

  void _pauseStory() {
    if (!_isPaused) {
      _isPaused = true;
      _progressAnimCtrl.stop();
      _videoPlayerCtrl?.pause();
    }
  }

  void _resumeStory() {
    if (_isPaused) {
      _isPaused = false;
      _progressAnimCtrl.forward();
      _videoPlayerCtrl?.play();
    }
  }

  void _sendReply() {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.mediumImpact();
    _replyCtrl.clear();
    FocusScope.of(context).unfocus();

    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId != null && currentUserId != widget.friendStory.userId) {
      unawaited(NotificationService().sendNotificationToUser(
        targetUserId: widget.friendStory.userId,
        title: "Story Reply",
        message: "replied to your story: \"$text\"",
        notificationType: "comment",
        senderId: currentUserId,
      ));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Reply sent to @${widget.friendStory.username}"),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: ZevColors.primaryBlue,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_stories.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            "No active stories",
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      );
    }

    final currentStory = _stories[_currentIndex];
    final mediaUrl = currentStory['media_url'] as String? ?? '';
    final mediaType = currentStory['media_type'] as String? ?? 'image';
    final caption = currentStory['caption'] as String? ?? '';
    final createdAtStr = currentStory['created_at'] as String?;
    final timeStr = createdAtStr != null
        ? TimeAgo.format(DateTime.tryParse(createdAtStr) ?? DateTime.now())
        : 'Just now';

    final isVideo = mediaType == 'video' ||
        mediaUrl.toLowerCase().contains('.mp4') ||
        mediaUrl.toLowerCase().contains('.mov') ||
        mediaUrl.toLowerCase().contains('.webm');

    final isRtl = TextDirectionHelper.isRtl(caption);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Story Media Canvas (Image or Video)
            Center(
              child: isVideo
                  ? (_isVideoInitialized && _videoPlayerCtrl != null
                      ? SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: _videoPlayerCtrl!.value.size.width,
                              height: _videoPlayerCtrl!.value.size.height,
                              child: VideoPlayer(_videoPlayerCtrl!),
                            ),
                          ),
                        )
                      : const Center(
                          child: CircularProgressIndicator(
                            color: ZevColors.primaryBlue,
                            strokeWidth: 2,
                          ),
                        ))
                  : (mediaUrl.isNotEmpty
                      ? ZevCachedImage(
                          imageUrl: mediaUrl,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                        )
                      : const Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: Colors.white24,
                            size: 48,
                          ),
                        )),
            ),

            // 2. Gesture Detector with Instant Hold-to-Pause
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  _pointerDownTime = DateTime.now();
                  _pauseStory();
                },
                onPointerUp: (e) {
                  final downTime = _pointerDownTime;
                  _resumeStory();
                  if (downTime != null) {
                    final elapsed =
                        DateTime.now().difference(downTime).inMilliseconds;
                    if (elapsed < 250) {
                      final screenWidth = MediaQuery.of(context).size.width;
                      if (e.position.dx < screenWidth * 0.3) {
                        _previousStory();
                      } else {
                        _nextStory();
                      }
                    }
                  }
                },
                onPointerCancel: (_) => _resumeStory(),
                child: const SizedBox.expand(),
              ),
            ),

            // 3. Top Gradient Shadow
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),

            // 4. Segmented Progress Bars at Top
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(_stories.length, (index) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 2.5,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: index < _currentIndex
                            ? Container(color: Colors.white)
                            : index == _currentIndex
                                ? AnimatedBuilder(
                                    animation: _progressAnimCtrl,
                                    builder: (context, _) {
                                      return LinearProgressIndicator(
                                        value: _progressAnimCtrl.value,
                                        backgroundColor: Colors.white30,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      );
                                    },
                                  )
                                : Container(color: Colors.white30),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // 5. Header: Author Avatar, Username, Time Ago, Close
            Positioned(
              top: 22,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  widget.friendStory.avatarUrl.isNotEmpty
                      ? ZevCachedImage.avatar(
                          imageUrl: widget.friendStory.avatarUrl,
                          size: 34,
                        )
                      : const CircleAvatar(
                          radius: 17,
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.person, color: Colors.white, size: 18),
                        ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.friendStory.username,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 26),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 6. Caption Overlay
            if (caption.isNotEmpty)
              Positioned(
                bottom: 84,
                left: 20,
                right: 20,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      caption,
                      textAlign: isRtl ? TextAlign.right : TextAlign.left,
                      textDirection:
                          isRtl ? TextDirection.rtl : TextDirection.ltr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),

            // 7. Bottom Reply Bar
            Positioned(
              bottom: 14,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white30, width: 1.0),
                      ),
                      child: TextField(
                        controller: _replyCtrl,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        onTap: _pauseStory,
                        onSubmitted: (_) {
                          _resumeStory();
                          _sendReply();
                        },
                        decoration: InputDecoration(
                          hintText: "Reply to @${widget.friendStory.username}...",
                          hintStyle: const TextStyle(
                              color: Colors.white60, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _sendReply,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
