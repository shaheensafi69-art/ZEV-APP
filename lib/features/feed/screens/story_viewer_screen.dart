import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class StoryItemData {
  final String id;
  final String userId;
  final String mediaUrl;
  final String mediaType;
  final String? caption;
  final String createdAt;
  final String expiresAt;

  StoryItemData({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.mediaType,
    this.caption,
    required this.createdAt,
    required this.expiresAt,
  });
}

class StoryViewerScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userAvatar;

  const StoryViewerScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userAvatar,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  List<StoryItemData> stories = [];
  int currentIndex = 0;
  int viewersCount = 0;

  Timer? _timer;
  double _progress = 0.0;
  bool _isMediaLoaded = false;
  Duration _currentStoryDuration = const Duration(seconds: 5);

  VideoPlayerController? _videoController;
  bool _isLongPressing = false;

  bool isLiked = false;
  bool isLiking = false;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();

  static const Color primaryPink = Color(0xFFFC466B);

  @override
  void initState() {
    super.initState();
    _fetchUserActiveStories();
    _replyFocusNode.addListener(() {
      if (_replyFocusNode.hasFocus) {
        _onLongPressStart();
      } else {
        _onLongPressEnd();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _videoController?.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchUserActiveStories() async {
    try {
      final nowStr = DateTime.now().toIso8601String();

      // Fetch active stories (< 24 hours) from Supabase
      final res = await supabase
          .from("user_stories")
          .select("*")
          .eq("user_id", widget.userId)
          .gt("expires_at", nowStr)
          .order("created_at", ascending: true);

      List<StoryItemData> loaded = [];
      for (var s in (res as List)) {
        loaded.add(
          StoryItemData(
            id: s['id'].toString(),
            userId: s['user_id'].toString(),
            mediaUrl: s['media_url'] ?? '',
            mediaType: s['media_type'] ?? 'image',
            caption: s['caption'],
            createdAt: s['created_at'] ?? '',
            expiresAt: s['expires_at'] ?? '',
          ),
        );
      }

      if (loaded.isEmpty) {
        // Demo story for testing
        loaded.add(
          StoryItemData(
            id: "story-demo-1",
            userId: widget.userId,
            mediaUrl:
                "https://images.unsplash.com/photo-1516321318423-f06f85e504b3?w=800&q=80",
            mediaType: "image",
            caption:
                "Excited to explore the latest updates on ZEV! 🚀",
            createdAt: DateTime.now().toIso8601String(),
            expiresAt: DateTime.now()
                .add(const Duration(hours: 20))
                .toIso8601String(),
          ),
        );
      }

      if (mounted) {
        setState(() {
          stories = loaded;
          isLoading = false;
        });
        _loadStoryMedia();
      }
    } catch (e) {
      debugPrint("Error fetching active user stories: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _recordStoryView() async {
    if (stories.isEmpty) return;
    final currentStory = stories[currentIndex];
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (currentStory.id.startsWith('story-demo')) {
      if (mounted) {
        setState(() => viewersCount = 1);
      }
      return;
    }

    try {
      // Record story view in Supabase
      await supabase.from("story_views").upsert({
        'story_id': currentStory.id,
        'viewer_id': user.id,
        'viewed_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint("Error recording story view upsert: $e");
    }

    try {
      // Count story viewers
      final viewsRes = await supabase
          .from("story_views")
          .select("id")
          .eq("story_id", currentStory.id);

      if (mounted) {
        setState(() => viewersCount = viewsRes.length);
      }
    } catch (_) {}
  }

  Future<void> _checkIfStoryLiked() async {
    if (stories.isEmpty) return;
    final currentStory = stories[currentIndex];
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (currentStory.id.startsWith('story-demo')) {
      setState(() => isLiked = false);
      return;
    }

    try {
      final res = await supabase
          .from("story_likes")
          .select("id")
          .eq("story_id", currentStory.id)
          .eq("user_id", user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          isLiked = res != null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => isLiked = false);
    }
  }

  Future<void> _toggleStoryLike() async {
    if (stories.isEmpty || isLiking) return;
    final currentStory = stories[currentIndex];
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (currentStory.id.startsWith('story-demo')) {
      setState(() {
        isLiked = !isLiked;
      });
      return;
    }

    setState(() => isLiking = true);

    try {
      if (isLiked) {
        await supabase
            .from("story_likes")
            .delete()
            .eq("story_id", currentStory.id)
            .eq("user_id", user.id);

        setState(() {
          isLiked = false;
          isLiking = false;
        });
      } else {
        await supabase.from("story_likes").insert({
          'story_id': currentStory.id,
          'user_id': user.id,
        });

        if (currentStory.userId != user.id) {
          try {
            final senderProfile = await supabase
                .from("profiles")
                .select("first_name, last_name")
                .eq("id", user.id)
                .maybeSingle();

            final String senderName = (senderProfile != null)
                ? "${senderProfile['first_name'] ?? 'Someone'} ${senderProfile['last_name'] ?? ''}".trim()
                : 'Someone';

            await supabase.from("user_notifications").insert({
              'user_id': currentStory.userId,
              'sender_id': user.id,
              'title': "Liked your Story ❤️",
              'message': "$senderName liked your story.",
              'notification_type': "story_like",
              'link_url': "/story/${currentStory.id}",
              'is_read': false,
            });
          } catch (_) {}
        }

        setState(() {
          isLiked = true;
          isLiking = false;
        });
      }
    } catch (e) {
      debugPrint("Error toggling story like: $e");
      setState(() => isLiking = false);
    }
  }

  Future<void> _sendStoryReply(String replyText) async {
    if (replyText.trim().isEmpty || stories.isEmpty) return;
    final currentStory = stories[currentIndex];
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final String text = "💬 Reply to story: $replyText";

    try {
      await supabase.from("direct_messages").insert({
        'sender_id': user.id,
        'receiver_id': currentStory.userId,
        'message_text': text,
        'is_delivered': true,
      });

      try {
        await supabase.from("user_notifications").insert({
          'user_id': currentStory.userId,
          'sender_id': user.id,
          'title': "💬 Reply to Story",
          'message': replyText,
          'notification_type': "direct_message",
          'link_url': "/chat/${user.id}",
          'is_read': false,
        });
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Your reply was sent successfully! ✉️"),
            backgroundColor: primaryPink,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error sending story reply: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error sending reply: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _loadStoryMedia() async {
    _timer?.cancel();
    _videoController?.dispose();
    _videoController = null;

    setState(() {
      _progress = 0.0;
      _isMediaLoaded = false;
      viewersCount = 0;
    });

    if (stories.isEmpty) return;
    final currentStory = stories[currentIndex];

    _recordStoryView();
    _checkIfStoryLiked();

    if (currentStory.mediaType == 'video') {
      try {
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(currentStory.mediaUrl),
        );
        _videoController = controller;
        await controller.initialize();
        if (mounted && _videoController == controller) {
          controller.play();
          _onMediaLoaded(controller.value.duration);
        }
      } catch (e) {
        debugPrint("Error initializing story video: $e");
        // Fallback to 5 seconds if video loading fails
        _onMediaLoaded(const Duration(seconds: 5));
      }
    } else {
      // Image will call _onMediaLoaded internally in its loadingBuilder/frameBuilder
    }
  }

  void _onMediaLoaded(Duration duration) {
    if (_isMediaLoaded) return;
    setState(() {
      _isMediaLoaded = true;
    });
    if (!_isLongPressing) {
      _startStoryTimer(duration);
    }
  }

  void _startStoryTimer(Duration duration) {
    _timer?.cancel();
    _currentStoryDuration = duration;

    if (_progress >= 1.0) {
      _progress = 0.0;
    }

    final interval = const Duration(milliseconds: 50);
    final totalDurationMs = duration.inMilliseconds.toDouble();

    _timer = Timer.periodic(interval, (t) {
      if (!mounted || _isLongPressing || !_isMediaLoaded) return;
      setState(() {
        _progress += 50 / totalDurationMs;
        if (_progress >= 1.0) {
          _progress = 1.0;
          _timer?.cancel();
          _nextStory();
        }
      });
    });
  }

  void _onLongPressStart() {
    setState(() {
      _isLongPressing = true;
    });
    _timer?.cancel();
    _videoController?.pause();
  }

  void _onLongPressEnd() {
    setState(() {
      _isLongPressing = false;
    });
    _videoController?.play();
    if (_isMediaLoaded) {
      _startStoryTimer(_currentStoryDuration);
    }
  }

  void _nextStory() {
    if (currentIndex < stories.length - 1) {
      setState(() {
        currentIndex++;
      });
      _loadStoryMedia();
    } else {
      Navigator.pop(context);
    }
  }

  void _previousStory() {
    if (currentIndex > 0) {
      setState(() {
        currentIndex--;
      });
      _loadStoryMedia();
    } else {
      _loadStoryMedia();
    }
  }

  String _calculateRemainingHours(String expiresAtStr) {
    try {
      final exp = DateTime.parse(expiresAtStr);
      final diff = exp.difference(DateTime.now());
      if (diff.inHours > 0) {
        return "${diff.inHours}h left";
      }
      return "${diff.inMinutes}m left";
    } catch (_) {
      return "24h story";
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: primaryPink)),
      );
    }

    final currentStory = stories[currentIndex];
    final isMyStory = supabase.auth.currentUser?.id == widget.userId;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width * 0.3) {
            _previousStory();
          } else {
            _nextStory();
          }
        },
        onLongPressStart: (_) => _onLongPressStart(),
        onLongPressEnd: (_) => _onLongPressEnd(),
        child: Stack(
          children: [
            // Story image or video
            Positioned.fill(
              child: currentStory.mediaType == 'video'
                  ? (_videoController != null &&
                            _videoController!.value.isInitialized
                        ? FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: _videoController!.value.size.width,
                              height: _videoController!.value.size.height,
                              child: VideoPlayer(_videoController!),
                            ),
                          )
                        : const Center(
                            child: CircularProgressIndicator(
                              color: primaryPink,
                            ),
                          ))
                  : Image.network(
                      currentStory.mediaUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          // Image fully loaded!
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _onMediaLoaded(const Duration(seconds: 5));
                          });
                          return child;
                        }
                        return const Center(
                          child: CircularProgressIndicator(color: primaryPink),
                        );
                      },
                      errorBuilder: (_, _, _) {
                        // If image fails, trigger load to not get stuck
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _onMediaLoaded(const Duration(seconds: 5));
                        });
                        return const Center(
                          child: Icon(
                            Icons.broken_image_rounded,
                            color: Colors.white54,
                            size: 60,
                          ),
                        );
                      },
                    ),
            ),

            // Dark gradient for text readability
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),

            // Top progress bars
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(stories.length, (index) {
                  double value = 0.0;
                  if (index < currentIndex) {
                    value = 1.0;
                  } else if (index == currentIndex) {
                    value = _progress;
                  } else {
                    value = 0.0;
                  }

                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: value,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // User profile and remaining time
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: widget.userAvatar.isNotEmpty
                        ? NetworkImage(widget.userAvatar)
                        : null,
                    backgroundColor: primaryPink,
                    child: widget.userAvatar.isEmpty
                        ? Text(
                            widget.userName.isNotEmpty
                                ? widget.userName[0]
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        _calculateRemainingHours(currentStory.expiresAt),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Story caption
            if (currentStory.caption != null &&
                currentStory.caption!.isNotEmpty)
              Positioned(
                bottom: isMyStory ? 80 : 100,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    currentStory.caption!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            // Viewer tray (for user's own story)
            if (isMyStory)
              Positioned(
                bottom:
                    56, // Raised from 24 to 56 to clear system navigation bar
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment
                      .start, // Aligned to the left (daste chap)
                  children: [
                    const Icon(
                      Icons.visibility_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "$viewersCount Views",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

            // Reply and like bar (for other stories)
            if (!isMyStory)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            Expanded(
                              child: TextField(
                                controller: _replyController,
                                focusNode: _replyFocusNode,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: const InputDecoration(
                                  hintText: "Send reply...",
                                  hintStyle: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                textInputAction: TextInputAction.send,
                                onSubmitted: (val) {
                                  _sendStoryReply(val);
                                  _replyController.clear();
                                  _replyFocusNode.unfocus();
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              onPressed: () {
                                _sendStoryReply(_replyController.text);
                                _replyController.clear();
                                _replyFocusNode.unfocus();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _toggleStoryLike,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isLiked
                              ? primaryPink
                              : Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isLiked
                                ? primaryPink
                                : Colors.white.withOpacity(0.25),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: Colors.white,
                          size: 20,
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
