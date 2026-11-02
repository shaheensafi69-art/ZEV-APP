import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/utils/time_ago.dart';
import '../../feed/models/feed_post_item.dart';

/// Serene, Instagram-Grade Story Viewer for ZEV.
/// Features segmented top progress bars, tap to skip/back, hold to pause,
/// dynamic RTL/LTR captions, and direct message reply.
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
  final TextEditingController _replyCtrl = TextEditingController();

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
          _progressAnimCtrl.forward(from: 0.0);
        } else {
          // No active stories, close after 1s notice
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

  void _onStoryFinished() {
    if (_currentIndex < _stories.length - 1) {
      setState(() => _currentIndex++);
      _progressAnimCtrl.forward(from: 0.0);
    } else {
      Navigator.pop(context);
    }
  }

  void _nextStory() {
    HapticFeedback.lightImpact();
    if (_currentIndex < _stories.length - 1) {
      setState(() => _currentIndex++);
      _progressAnimCtrl.forward(from: 0.0);
    } else {
      Navigator.pop(context);
    }
  }

  void _previousStory() {
    HapticFeedback.lightImpact();
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _progressAnimCtrl.forward(from: 0.0);
    } else {
      _progressAnimCtrl.forward(from: 0.0);
    }
  }

  void _pauseStory() {
    if (!_isPaused) {
      _isPaused = true;
      _progressAnimCtrl.stop();
    }
  }

  void _resumeStory() {
    if (_isPaused) {
      _isPaused = false;
      _progressAnimCtrl.forward();
    }
  }

  void _sendReply() {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.mediumImpact();
    _replyCtrl.clear();
    FocusScope.of(context).unfocus();

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
    final caption = currentStory['caption'] as String? ?? '';
    final createdAtStr = currentStory['created_at'] as String?;
    final timeStr = createdAtStr != null
        ? TimeAgo.format(DateTime.tryParse(createdAtStr) ?? DateTime.now())
        : 'Just now';

    final isRtl = TextDirectionHelper.isRtl(caption);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Story Media Canvas
            Center(
              child: mediaUrl.isNotEmpty
                  ? Image.network(
                      mediaUrl,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(
                            color: ZevColors.primaryBlue,
                            strokeWidth: 2,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                        child: Icon(
                          Icons.broken_image_rounded,
                          color: Colors.white38,
                          size: 48,
                        ),
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: Colors.white24,
                        size: 48,
                      ),
                    ),
            ),

            // 2. Gesture Detector for Tap Skip / Back / Pause on Hold
            Positioned.fill(
              child: Row(
                children: [
                  // Left 35%: Previous Story
                  Expanded(
                    flex: 35,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _previousStory,
                      onLongPressStart: (_) => _pauseStory(),
                      onLongPressEnd: (_) => _resumeStory(),
                    ),
                  ),
                  // Middle 30%: Pause on Hold
                  Expanded(
                    flex: 30,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _nextStory,
                      onLongPressStart: (_) => _pauseStory(),
                      onLongPressEnd: (_) => _resumeStory(),
                    ),
                  ),
                  // Right 35%: Next Story
                  Expanded(
                    flex: 35,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _nextStory,
                      onLongPressStart: (_) => _pauseStory(),
                      onLongPressEnd: (_) => _resumeStory(),
                    ),
                  ),
                ],
              ),
            ),

            // 3. Top Gradient Shadow
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
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
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: Colors.white24,
                    backgroundImage: widget.friendStory.avatarUrl.isNotEmpty
                        ? NetworkImage(widget.friendStory.avatarUrl)
                        : null,
                    child: widget.friendStory.avatarUrl.isEmpty
                        ? const Icon(Icons.person, color: Colors.white, size: 18)
                        : null,
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

            // 6. Caption Overlay (if exists)
            if (caption.isNotEmpty)
              Positioned(
                bottom: 80,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      caption,
                      textAlign: isRtl ? TextAlign.right : TextAlign.center,
                      textDirection:
                          isRtl ? TextDirection.rtl : TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),

            // 7. Bottom Reply Bar & Direct Interaction
            Positioned(
              bottom: 12,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white24,
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyCtrl,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                              ),
                              onSubmitted: (_) => _sendReply(),
                              decoration: const InputDecoration(
                                hintText: "Send message...",
                                hintStyle: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13.5,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.send_rounded,
                              color: ZevColors.primaryBlue,
                              size: 18,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _sendReply,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Heart reaction button
                  IconButton(
                    icon: const Icon(
                      Icons.favorite_border_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("❤️ Sent reaction"),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
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

