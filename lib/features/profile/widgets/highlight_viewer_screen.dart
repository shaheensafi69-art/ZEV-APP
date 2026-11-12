import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../models/story_highlight_model.dart';
import 'video_cover_thumbnail.dart';

/// Fullscreen, Instagram-Grade Story Highlight Viewer for ZEV.
/// Plays highlight stories (images, videos, and text notes) with segmented progress,
/// tap forward/backward, press-and-hold to freeze/pause, and highlight management.
class HighlightViewerScreen extends StatefulWidget {
  final StoryHighlight highlight;
  final bool isOwner;
  final VoidCallback? onDelete;

  const HighlightViewerScreen({
    super.key,
    required this.highlight,
    this.isOwner = false,
    this.onDelete,
  });

  static Future<void> open(
    BuildContext context, {
    required StoryHighlight highlight,
    bool isOwner = false,
    VoidCallback? onDelete,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            HighlightViewerScreen(
          highlight: highlight,
          isOwner: isOwner,
          onDelete: onDelete,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<HighlightViewerScreen> createState() => _HighlightViewerScreenState();
}

class _HighlightViewerScreenState extends State<HighlightViewerScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late final AnimationController _progressAnimCtrl;
  bool _isPaused = false;
  DateTime? _pointerDownTime;

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
        _onItemFinished();
      }
    });

    _setupCurrentItem();
  }

  @override
  void dispose() {
    _progressAnimCtrl.dispose();
    _videoPlayerCtrl?.dispose();
    super.dispose();
  }

  void _setupCurrentItem() {
    if (widget.highlight.items.isEmpty) return;

    _videoPlayerCtrl?.pause();
    _videoPlayerCtrl?.dispose();
    _videoPlayerCtrl = null;
    _isVideoInitialized = false;

    final item = widget.highlight.items[_currentIndex];

    if (item.mediaType == 'video' && item.mediaUrl.isNotEmpty) {
      _progressAnimCtrl.stop();
      _videoPlayerCtrl = VideoPlayerController.networkUrl(Uri.parse(item.mediaUrl))
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {
            _isVideoInitialized = true;
            final dur = _videoPlayerCtrl!.value.duration;
            _progressAnimCtrl.duration =
                dur > Duration.zero ? dur : const Duration(seconds: 6);
          });
          _videoPlayerCtrl!.play();
          _progressAnimCtrl.forward(from: 0.0);
        }).catchError((err) {
          debugPrint("Highlight video load error: $err");
          _progressAnimCtrl.duration = const Duration(seconds: 4);
          _progressAnimCtrl.forward(from: 0.0);
        });
    } else {
      _progressAnimCtrl.duration = const Duration(seconds: 5);
      _progressAnimCtrl.forward(from: 0.0);
    }
  }

  void _onItemFinished() {
    if (_currentIndex < widget.highlight.items.length - 1) {
      setState(() => _currentIndex++);
      _setupCurrentItem();
    } else {
      Navigator.pop(context);
    }
  }

  void _nextItem() {
    HapticFeedback.selectionClick();
    if (_currentIndex < widget.highlight.items.length - 1) {
      setState(() => _currentIndex++);
      _setupCurrentItem();
    } else {
      Navigator.pop(context);
    }
  }

  void _previousItem() {
    HapticFeedback.selectionClick();
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _setupCurrentItem();
    } else {
      _progressAnimCtrl.forward(from: 0.0);
    }
  }

  void _pause() {
    if (_isPaused) return;
    setState(() => _isPaused = true);
    _progressAnimCtrl.stop();
    _videoPlayerCtrl?.pause();
  }

  void _resume() {
    if (!_isPaused) return;
    setState(() => _isPaused = false);
    _progressAnimCtrl.forward();
    _videoPlayerCtrl?.play();
  }

  void _showOptionsMenu() {
    _pause();
    showModalBottomSheet(
      context: context,
      backgroundColor: ZevColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: ZevColors.deepNavy),
                title: const Text(
                  "Copy Highlight Link",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final link =
                      'https://zevapp.com/u/${widget.highlight.userId}?highlight=${widget.highlight.id}';
                  await Clipboard.setData(ClipboardData(text: link));
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  _resume();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text("Highlight link copied to clipboard"),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded, color: ZevColors.secondaryBlue),
                title: const Text("Share Highlight",
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () async {
                  final link =
                      'https://zevapp.com/u/${widget.highlight.userId}?highlight=${widget.highlight.id}';
                  Navigator.pop(ctx);
                  await Share.share(
                    'Check out "${widget.highlight.title}" on ZEV:\n$link',
                  );
                  if (mounted) _resume();
                },
              ),
              if (widget.isOwner) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent),
                  title: const Text(
                    "Delete Highlight",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context); // close viewer
                    widget.onDelete?.call();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    ).then((_) => _resume());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.highlight.items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Highlight has no items",
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final item = widget.highlight.items[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Content Media (Image, Video, or Text)
            _buildItemContent(item),

            // 2. Touch Navigation Gestures (Instant Hold Pause & Tap Skip)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  _pointerDownTime = DateTime.now();
                  _pause();
                },
                onPointerUp: (e) {
                  final downTime = _pointerDownTime;
                  _resume();
                  if (downTime != null) {
                    final elapsed =
                        DateTime.now().difference(downTime).inMilliseconds;
                    if (elapsed < 250) {
                      final screenWidth = MediaQuery.of(context).size.width;
                      if (e.position.dx < screenWidth * 0.35) {
                        _previousItem();
                      } else {
                        _nextItem();
                      }
                    }
                  }
                },
                onPointerCancel: (_) => _resume(),
                child: const SizedBox.expand(),
              ),
            ),

            // 3. Top Gradient Shade
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 110,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // 4. Segmented Progress Bar (Top)
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(widget.highlight.items.length, (index) {
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
                                : Container(color: Colors.white24),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // 5. Header: Cover Thumbnail + Highlight Title + 3-dots + Close
            Positioned(
              top: 18,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: ClipOval(
                      child: widget.highlight.coverUrl.isNotEmpty
                          ? (widget.highlight.coverUrl.toLowerCase().contains('.mp4') ||
                                  widget.highlight.coverUrl.toLowerCase().contains('.mov') ||
                                  widget.highlight.coverUrl.toLowerCase().contains('.webm')
                              ? VideoCoverThumbnail(videoUrl: widget.highlight.coverUrl)
                              : ZevCachedImage.avatar(
                                  imageUrl: widget.highlight.coverUrl,
                                  size: 32,
                                ))
                          : const Icon(Icons.star, color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.highlight.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "${_currentIndex + 1} of ${widget.highlight.items.length}",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded,
                        color: Colors.white, size: 22),
                    onPressed: _showOptionsMenu,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 26),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 6. Caption at bottom if present
            if (item.caption.isNotEmpty && item.mediaType != 'text')
              Positioned(
                bottom: 24,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    item.caption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemContent(StoryHighlightItem item) {
    if (item.mediaType == 'text') {
      final gradientColors = (item.bgGradientColors ?? [0xFF00D4FF, 0xFF536DFE])
          .map((c) => Color(c))
          .toList();

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        alignment: Alignment.center,
        child: Text(
          item.caption,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
            height: 1.4,
          ),
        ),
      );
    }

    if (item.mediaType == 'video') {
      if (_isVideoInitialized && _videoPlayerCtrl != null) {
        return Center(
          child: AspectRatio(
            aspectRatio: _videoPlayerCtrl!.value.aspectRatio,
            child: VideoPlayer(_videoPlayerCtrl!),
          ),
        );
      }
      return const Center(
        child: CircularProgressIndicator(
          color: ZevColors.primaryBlue,
          strokeWidth: 2,
        ),
      );
    }

    // Default: Image
    final isRealUrl = item.mediaUrl.startsWith('http');
    return Center(
      child: isRealUrl
          ? ZevCachedImage(
              imageUrl: item.mediaUrl,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            )
          : const Center(
              child: Icon(Icons.image, color: Colors.white24, size: 48),
            ),
    );
  }
}

