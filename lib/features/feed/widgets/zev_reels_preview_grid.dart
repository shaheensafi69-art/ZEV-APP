import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/widgets/fast_cached_image.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../screens/reels_viewer_screen.dart';

/// TikTok & Instagram Style Reels Grid with Sequential 5-Second Video Previews
class ZevReelsPreviewGrid extends StatefulWidget {
  final List<Map<String, dynamic>> reels;
  final Function(Map<String, dynamic> reel, int index)? onReelTap;
  final int? crossAxisCount;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  const ZevReelsPreviewGrid({
    super.key,
    required this.reels,
    this.onReelTap,
    this.crossAxisCount,
    this.padding = const EdgeInsets.all(8),
    this.physics,
    this.shrinkWrap = false,
  });

  @override
  State<ZevReelsPreviewGrid> createState() => _ZevReelsPreviewGridState();
}

class _ZevReelsPreviewGridState extends State<ZevReelsPreviewGrid> {
  int _activeIndex = 0;
  VideoPlayerController? _controller;
  bool _isVideoInitialized = false;
  String? _currentPlayingUrl;

  Timer? _stepTimer;
  double _progress = 0.0;
  static const int _cycleDurationMs = 5000;
  static const int _tickIntervalMs = 50;

  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    if (widget.reels.isNotEmpty) {
      _startSequentialPlayback();
    }
  }

  @override
  void didUpdateWidget(covariant ZevReelsPreviewGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reels.length != oldWidget.reels.length) {
      if (widget.reels.isEmpty) {
        _stopPlayback();
      } else if (_activeIndex >= widget.reels.length) {
        _activeIndex = 0;
        _startSequentialPlayback();
      }
    }
  }

  @override
  void dispose() {
    _stopPlayback();
    super.dispose();
  }

  void _stopPlayback() {
    _stepTimer?.cancel();
    _stepTimer = null;
    _controller?.dispose();
    _controller = null;
    _isVideoInitialized = false;
    _currentPlayingUrl = null;
  }

  void _startSequentialPlayback() {
    _stepTimer?.cancel();
    _progress = 0.0;

    if (widget.reels.isEmpty) return;

    _initializeVideoForIndex(_activeIndex);

    _stepTimer = Timer.periodic(
      const Duration(milliseconds: _tickIntervalMs),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _progress += (_tickIntervalMs / _cycleDurationMs);
          if (_progress >= 1.0) {
            _progress = 0.0;
            _nextReel();
          }
        });
      },
    );
  }

  void _nextReel() {
    if (widget.reels.isEmpty) return;
    final next = (_activeIndex + 1) % widget.reels.length;
    _switchToReel(next);
  }

  void _switchToReel(int index) {
    if (!mounted || widget.reels.isEmpty) return;
    setState(() {
      _activeIndex = index;
      _progress = 0.0;
    });
    _initializeVideoForIndex(index);
  }

  Future<void> _initializeVideoForIndex(int index) async {
    if (index >= widget.reels.length) return;
    final reel = widget.reels[index];
    final videoUrl = reel['video_url']?.toString() ?? '';

    if (videoUrl.isEmpty) {
      _controller?.dispose();
      _controller = null;
      if (mounted) setState(() => _isVideoInitialized = false);
      return;
    }

    if (_currentPlayingUrl == videoUrl && _controller != null) {
      return;
    }

    final oldController = _controller;
    _controller = null;
    _currentPlayingUrl = videoUrl;
    if (mounted) setState(() => _isVideoInitialized = false);

    await oldController?.dispose();

    try {
      final newController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await newController.initialize();
      await newController.setVolume(0.0); // Muted for silent preview
      await newController.setLooping(true);

      if (mounted && _activeIndex == index && _currentPlayingUrl == videoUrl) {
        _controller = newController;
        await _controller?.play();
        setState(() {
          _isVideoInitialized = true;
        });
      } else {
        await newController.dispose();
      }
    } catch (e) {
      debugPrint("Reel preview init error: $e");
      if (mounted) {
        setState(() => _isVideoInitialized = false);
      }
    }
  }

  String _formatViews(dynamic views) {
    if (views == null) return '0';
    final count = int.tryParse(views.toString()) ?? 0;
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reels.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final columns = widget.crossAxisCount ??
        ResponsiveLayout.gridColumns(
          context,
          mobile: 3,
          tablet: 4,
          desktop: 5,
        );

    return GridView.builder(
      padding: widget.padding,
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.65, // Standard TikTok & IG Reels vertical card
      ),
      itemCount: widget.reels.length,
      itemBuilder: (context, index) {
        final reel = widget.reels[index];
        final isActive = (_activeIndex == index);
        final isHovered = (_hoveredIndex == index);

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            setState(() => _hoveredIndex = index);
            if (!isActive) {
              _switchToReel(index);
            }
          },
          onExit: (_) {
            setState(() => _hoveredIndex = null);
          },
          child: GestureDetector(
            onTap: () {
              if (widget.onReelTap != null) {
                widget.onReelTap!(reel, index);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentReelsScreen(
                      targetReelId: reel['id']?.toString(),
                    ),
                  ),
                );
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: isHovered
                  ? Matrix4.diagonal3Values(1.025, 1.025, 1.0)
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: isActive
                        ? const Color(0xFFFC466B).withValues(alpha: 0.35)
                        : Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: isActive ? 12 : 6,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  color: isActive
                      ? const Color(0xFFFC466B).withValues(alpha: 0.8)
                      : (isHovered
                            ? Colors.white.withValues(alpha: 0.4)
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06))),
                  width: isActive ? 1.8 : 1.0,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Video player layer (Active preview)
                    if (isActive &&
                        _isVideoInitialized &&
                        _controller != null &&
                        _controller!.value.isInitialized)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _controller!.value.size.width,
                          height: _controller!.value.size.height,
                          child: VideoPlayer(_controller!),
                        ),
                      )
                    // Static / Poster Thumbnail layer (TikTok/Instagram style)
                    else
                      _buildThumbnail(reel, isDark),

                    // Ambient gradient overlay for TikTok/IG look
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black38,
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black87,
                          ],
                          stops: [0.0, 0.2, 0.55, 1.0],
                        ),
                      ),
                    ),

                    // Top: 5-Second Progress Bar if active
                    if (isActive)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            LinearProgressIndicator(
                              value: _progress.clamp(0.0, 1.0),
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFFC466B),
                              ),
                              minHeight: 3.5,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFFC466B,
                                      ).withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.play_circle_fill_rounded,
                                          color: Colors.white,
                                          size: 10,
                                        ),
                                        SizedBox(width: 3),
                                        Text(
                                          "PLAYING",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    "${(5 - (_progress * 5)).ceil()}s",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Center Play indicator when not active
                    if (!isActive)
                      Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: isHovered ? 1.0 : 0.45,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white30,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),

                    // Bottom: View Count & Title
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if ((reel['title']?.toString() ?? '').isNotEmpty)
                            Text(
                              reel['title'].toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                                shadows: [
                                  Shadow(
                                    color: Colors.black,
                                    blurRadius: 6,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                _formatViews(
                                  reel['views_count'] ?? reel['views'],
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnail(Map<String, dynamic> reel, bool isDark) {
    final thumbUrl = reel['thumbnail_url']?.toString() ?? '';
    if (thumbUrl.isNotEmpty) {
      return FastCachedImage(
        imageUrl: thumbUrl,
        fit: BoxFit.cover,
        errorWidget: _buildDarkPosterFallback(reel, isDark),
      );
    }
    return _buildDarkPosterFallback(reel, isDark);
  }

  Widget _buildDarkPosterFallback(Map<String, dynamic> reel, bool isDark) {
    final title = reel['title']?.toString() ?? '';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            isDark ? const Color(0xFF1E2230) : const Color(0xFF2D3748),
            isDark ? const Color(0xFF0F111A) : const Color(0xFF1A202C),
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.movie_creation_outlined,
                  color: Colors.white70,
                  size: 24,
                ),
              ),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
