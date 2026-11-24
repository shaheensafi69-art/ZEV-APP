import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'chat_modals.dart';

/// Telegram-style circular Video Note Bubble Player for chat messages.
/// Auto-loops, supports tap-to-unmute, and renders a sleek progress ring around the perimeter.
class VideoNoteBubblePlayer extends StatefulWidget {
  final String videoUrl;
  final String? localFilePath;
  final bool isMine;

  const VideoNoteBubblePlayer({
    super.key,
    required this.videoUrl,
    this.localFilePath,
    required this.isMine,
  });

  @override
  State<VideoNoteBubblePlayer> createState() => _VideoNoteBubblePlayerState();
}

class _VideoNoteBubblePlayerState extends State<VideoNoteBubblePlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _isMuted = true;
  double _progress = 0.0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    VideoPlayerController? c;
    try {
      if (widget.localFilePath != null &&
          widget.localFilePath!.isNotEmpty &&
          File(widget.localFilePath!).existsSync()) {
        c = VideoPlayerController.file(File(widget.localFilePath!));
      } else {
        final uri = Uri.tryParse(widget.videoUrl);
        if (uri == null) {
          if (mounted) setState(() => _hasError = true);
          return;
        }
        c = VideoPlayerController.networkUrl(uri);
      }

      _controller = c;
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setLooping(true);
      await c.setVolume(0.0);
      await c.play();
      c.addListener(_onVideoTick);
      if (mounted) {
        setState(() {
          _initialized = true;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('[VideoNoteBubblePlayer] init error: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _onVideoTick() {
    final c = _controller;
    if (c != null && c.value.isInitialized && c.value.duration.inMilliseconds > 0) {
      final p = c.value.position.inMilliseconds / c.value.duration.inMilliseconds;
      if (mounted) {
        setState(() => _progress = p.clamp(0.0, 1.0));
      }
    }
  }

  void _toggleAudio() {
    final c = _controller;
    if (c == null || !_initialized) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isMuted = !_isMuted;
      c.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _openFullScreen() {
    if (widget.videoUrl.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FullScreenVideoViewer(videoUrl: widget.videoUrl),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoTick);
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double size = 200.0;

    return GestureDetector(
      onTap: _toggleAudio,
      onDoubleTap: _openFullScreen,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ambient outer soft glow
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.isMine
                        ? const Color(0xFF0284C7).withValues(alpha: 0.28)
                        : Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),

            // Circular progress ring painter
            SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _VideoNoteProgressPainter(
                  progress: _progress,
                  isMine: widget.isMine,
                ),
              ),
            ),

            // Video circular content
            Padding(
              padding: const EdgeInsets.all(5.0),
              child: ClipOval(
                child: Container(
                  width: size - 10,
                  height: size - 10,
                  color: const Color(0xFF0F172A),
                  child: _initialized && _controller != null
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _controller!.value.size.width > 0
                                ? _controller!.value.size.width
                                : size,
                            height: _controller!.value.size.height > 0
                                ? _controller!.value.size.height
                                : size,
                            child: VideoPlayer(_controller!),
                          ),
                        )
                      : _hasError
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: Colors.white70,
                                    size: 28,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Unavailable',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                ),
              ),
            ),

            // Audio mute/unmute indicator badge
            Positioned(
              bottom: 12,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _initialized ? 0.92 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isMuted ? 'Tap for sound' : 'Sound ON',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Telegram-style camera icon pill at top right
            Positioned(
              top: 10,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  color: Colors.white,
                  size: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoNoteProgressPainter extends CustomPainter {
  final double progress;
  final bool isMine;

  _VideoNoteProgressPainter({
    required this.progress,
    required this.isMine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 4) / 2;

    // Track
    final trackPaint = Paint()
      ..color = (isMine ? Colors.white : const Color(0xFF0284C7))
          .withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(center, radius, trackPaint);

    // Active Progress Arc
    final activePaint = Paint()
      ..shader = LinearGradient(
        colors: isMine
            ? [const Color(0xFF38BDF8), Colors.white]
            : [const Color(0xFF0284C7), const Color(0xFF06B6D4)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;

    const startAngle = -3.141592653589793 / 2; // -90 deg (top)
    final sweepAngle = 2 * 3.141592653589793 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoNoteProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isMine != isMine;
  }
}
