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
import '../../../core/widgets/zev_native_ad_story_unit.dart';
import '../../feed/models/feed_post_item.dart';

/// Serene, Instagram-Grade Story Viewer for ZEV.
/// Features:
/// - 5-second timer for photos, text stories, and sponsored story ads
/// - Exact video duration timer for video stories
/// - Instant press-and-hold freeze / pause (both video and progress timer)
/// - Segmented top progress bars, tap to skip/back, and direct message replies
/// - Native AdMob Sponsored Story Ads seamlessly integrated in-stream
class StoryViewerScreen extends StatefulWidget {
  final ActiveFriendStory friendStory;
  final List<ActiveFriendStory>? allFriendStories;
  final int initialFriendIndex;

  const StoryViewerScreen({
    super.key,
    required this.friendStory,
    this.allFriendStories,
    this.initialFriendIndex = 0,
  });

  static Future<void> open(
    BuildContext context, {
    required ActiveFriendStory friendStory,
    List<ActiveFriendStory>? allFriendStories,
    int initialFriendIndex = 0,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            StoryViewerScreen(
              friendStory: friendStory,
              allFriendStories: allFriendStories,
              initialFriendIndex: initialFriendIndex,
            ),
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

  late int _currentFriendIndex;
  late ActiveFriendStory _currentFriendStory;

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
    _currentFriendIndex = widget.initialFriendIndex;
    _currentFriendStory = widget.friendStory;

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
          .eq('user_id', _currentFriendStory.userId)
          .gt('expires_at', nowStr)
          .order('created_at', ascending: true);

      final list = List<Map<String, dynamic>>.from(res as List);
      if (mounted) {
        // Native Ad Insertion Rules (In-Stream Story Monetization):
        // 1) If user has 3 or more stories, insert a sponsored ad story at index 2 (after 2nd story)
        if (list.length >= 3) {
          list.insert(2, {
            'id': 'ad_story_${_currentFriendStory.userId}',
            'is_ad': true,
            'media_type': 'ad',
            'caption': '',
          });
        }
        // 2) Or if viewing across multiple friends and this friend has <= 2 stories,
        // every 2nd friend transition appends an ad story seamlessly
        else if (widget.allFriendStories != null &&
            widget.allFriendStories!.length > 1 &&
            _currentFriendIndex % 2 == 1 &&
            list.isNotEmpty) {
          list.add({
            'id': 'ad_between_${_currentFriendStory.userId}',
            'is_ad': true,
            'media_type': 'ad',
            'caption': '',
          });
        }

        setState(() {
          _stories = list;
          _isLoading = false;
        });

        if (list.isNotEmpty) {
          _setupCurrentStory();
        } else {
          _advanceToNextFriendOrClose();
        }
      }
    } catch (e) {
      debugPrint("Fetch stories error: $e");
      if (mounted) _advanceToNextFriendOrClose();
    }
  }

  void _setupCurrentStory() {
    if (_stories.isEmpty) return;

    _videoPlayerCtrl?.pause();
    _videoPlayerCtrl?.dispose();
    _videoPlayerCtrl = null;
    _isVideoInitialized = false;

    final currentStory = _stories[_currentIndex];
    final isAd = currentStory['is_ad'] == true;

    if (isAd) {
      // Sponsored Story: exact 5-second viewing duration
      _progressAnimCtrl.duration = const Duration(seconds: 5);
      _progressAnimCtrl.forward(from: 0.0);
      return;
    }

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
      _advanceToNextFriendOrClose();
    }
  }

  void _nextStory() {
    HapticFeedback.lightImpact();
    if (_currentIndex < _stories.length - 1) {
      setState(() => _currentIndex++);
      _setupCurrentStory();
    } else {
      _advanceToNextFriendOrClose();
    }
  }

  void _previousStory() {
    HapticFeedback.lightImpact();
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _setupCurrentStory();
    } else {
      _retreatToPreviousFriendOrRestart();
    }
  }

  void _advanceToNextFriendOrClose() {
    if (widget.allFriendStories != null &&
        _currentFriendIndex < widget.allFriendStories!.length - 1) {
      setState(() {
        _currentFriendIndex++;
        _currentFriendStory = widget.allFriendStories![_currentFriendIndex];
        _currentIndex = 0;
        _isLoading = true;
      });
      _fetchUserStories();
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  void _retreatToPreviousFriendOrRestart() {
    if (widget.allFriendStories != null && _currentFriendIndex > 0) {
      setState(() {
        _currentFriendIndex--;
        _currentFriendStory = widget.allFriendStories![_currentFriendIndex];
        _currentIndex = 0;
        _isLoading = true;
      });
      _fetchUserStories();
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
    if (currentUserId != null && currentUserId != _currentFriendStory.userId) {
      unawaited(NotificationService().sendNotificationToUser(
        targetUserId: _currentFriendStory.userId,
        title: "Story Reply",
        message: "replied to your story: \"$text\"",
        notificationType: "comment",
        senderId: currentUserId,
      ));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Reply sent to @${_currentFriendStory.username}"),
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
    final isAd = currentStory['is_ad'] == true;
    final mediaUrl = currentStory['media_url'] as String? ?? '';
    final mediaType = currentStory['media_type'] as String? ?? 'image';
    final caption = currentStory['caption'] as String? ?? '';
    final createdAtStr = currentStory['created_at'] as String?;
    final timeStr = createdAtStr != null
        ? TimeAgo.format(DateTime.tryParse(createdAtStr) ?? DateTime.now())
        : 'Just now';

    final isVideo = !isAd &&
        (mediaType == 'video' ||
            mediaUrl.toLowerCase().contains('.mp4') ||
            mediaUrl.toLowerCase().contains('.mov') ||
            mediaUrl.toLowerCase().contains('.webm'));

    final isRtl = TextDirectionHelper.isRtl(caption);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Story Media Canvas (Image, Video, or Native Ad Unit)
            Center(
              child: isAd
                  ? ZevNativeAdStoryUnit(
                      onAdFailed: () {
                        if (mounted) _nextStory();
                      },
                    )
                  : (isVideo
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
                            ))),
            ),

            // 2. Gesture Detector with Instant Hold-to-Pause & Tap-to-Skip
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
                  final isItemAd = _stories[index]['is_ad'] == true;
                  final activeColor = isItemAd ? const Color(0xFF00D4FF) : Colors.white;

                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 2.5,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: index < _currentIndex
                            ? Container(color: activeColor)
                            : index == _currentIndex
                                ? AnimatedBuilder(
                                    animation: _progressAnimCtrl,
                                    builder: (context, _) {
                                      return LinearProgressIndicator(
                                        value: _progressAnimCtrl.value,
                                        backgroundColor: Colors.white30,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          activeColor,
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

            // 5. Header: Author Avatar / Sponsored Badge, Username, Close
            Positioned(
              top: 22,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  if (isAd)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00D4FF), Color(0xFF0072FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.campaign_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                    )
                  else if (_currentFriendStory.avatarUrl.isNotEmpty)
                    ZevCachedImage.avatar(
                      imageUrl: _currentFriendStory.avatarUrl,
                      size: 34,
                    )
                  else
                    const CircleAvatar(
                      radius: 17,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.person, color: Colors.white, size: 18),
                    ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isAd ? "Sponsored" : _currentFriendStory.username,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          if (isAd) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: Color(0xFF00D4FF),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isAd ? "Advertisement" : timeStr,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                          if (isAd) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00D4FF).withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                "AD",
                                style: TextStyle(
                                  color: Color(0xFF00D4FF),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ],
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
            if (!isAd && caption.isNotEmpty)
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

            // 7. Bottom Area: Direct Reply Bar OR Sponsored Story CTA
            Positioned(
              bottom: 14,
              left: 14,
              right: 14,
              child: isAd
                  ? GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _nextStory();
                      },
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00D4FF), Color(0xFF0072FF)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                              blurRadius: 14,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                "Learn More & Continue",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 13),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Row(
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
                                hintText: "Reply to @${_currentFriendStory.username}...",
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

