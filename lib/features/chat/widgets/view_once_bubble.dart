import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/direct_message_model.dart';

/// WhatsApp / Telegram style View-Once Media Message Card for chat bubbles.
class ViewOnceMessageCard extends StatefulWidget {
  final DirectMessageModel message;
  final bool isMine;
  final VoidCallback? onOpened;

  const ViewOnceMessageCard({
    super.key,
    required this.message,
    required this.isMine,
    this.onOpened,
  });

  @override
  State<ViewOnceMessageCard> createState() => _ViewOnceMessageCardState();
}

class _ViewOnceMessageCardState extends State<ViewOnceMessageCard> {
  bool _hasOpened = false;

  bool get _isOpened =>
      _hasOpened ||
      widget.message.isRead ||
      widget.message.localSendState == 'opened';

  bool get _isVideo =>
      widget.message.messageType == 'video' ||
      (widget.message.mimeType ?? '').contains('video');

  @override
  Widget build(BuildContext context) {
    if (_isOpened) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isMine
              ? Colors.white.withValues(alpha: 0.15)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isMine
                ? Colors.white.withValues(alpha: 0.25)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.looks_one_rounded,
              size: 19,
              color: widget.isMine
                  ? Colors.white.withValues(alpha: 0.65)
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Text(
              'Opened',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                color: widget.isMine
                    ? Colors.white.withValues(alpha: 0.75)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () async {
        final url = widget.message.attachmentUrl;
        if (url == null || url.isEmpty) return;

        HapticFeedback.mediumImpact();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ViewOnceMediaViewer(
              mediaUrl: url,
              isVideo: _isVideo,
            ),
          ),
        );

        if (mounted) {
          setState(() => _hasOpened = true);
          widget.onOpened?.call();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isMine
              ? Colors.white.withValues(alpha: 0.22)
              : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isMine
                ? Colors.white.withValues(alpha: 0.5)
                : const Color(0xFF38BDF8).withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isMine
                  ? Colors.black.withValues(alpha: 0.08)
                  : const Color(0xFF0284C7).withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF06B6D4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  '1',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isVideo ? 'View-Once Video' : 'View-Once Photo',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: widget.isMine ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to view • Disappears after view',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: widget.isMine
                        ? Colors.white.withValues(alpha: 0.8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Fullscreen View-Once Viewer with a countdown timer that closes and vanishes after viewing.
class ViewOnceMediaViewer extends StatefulWidget {
  final String mediaUrl;
  final bool isVideo;

  const ViewOnceMediaViewer({
    super.key,
    required this.mediaUrl,
    required this.isVideo,
  });

  @override
  State<ViewOnceMediaViewer> createState() => _ViewOnceMediaViewerState();
}

class _ViewOnceMediaViewerState extends State<ViewOnceMediaViewer> {
  VideoPlayerController? _videoCtrl;
  Timer? _countdownTimer;
  int _secondsLeft = 12;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    if (widget.isVideo) {
      _initVideo();
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        Navigator.of(context).pop();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _initVideo() async {
    final uri = Uri.tryParse(widget.mediaUrl);
    if (uri == null) return;
    try {
      final c = VideoPlayerController.networkUrl(uri);
      _videoCtrl = c;
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.play();
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      debugPrint('[ViewOnceMediaViewer] video error: $e');
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _videoCtrl?.pause();
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // Media Viewer
              Center(
                child: widget.isVideo
                    ? (_initialized && _videoCtrl != null
                        ? AspectRatio(
                            aspectRatio: _videoCtrl!.value.aspectRatio,
                            child: VideoPlayer(_videoCtrl!),
                          )
                        : const CircularProgressIndicator(
                            color: Color(0xFF38BDF8),
                          ))
                    : InteractiveViewer(
                        maxScale: 3.5,
                        child: CachedNetworkImage(
                          imageUrl: widget.mediaUrl,
                          fit: BoxFit.contain,
                          placeholder: (_, _) => const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                          errorWidget: (_, _, _) => const Icon(
                            Icons.broken_image_rounded,
                            color: Colors.white54,
                            size: 48,
                          ),
                        ),
                      ),
              ),

              // Top Bar with Countdown and Privacy Notice
              Positioned(
                top: 10,
                left: 14,
                right: 14,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFF0284C7), Color(0xFF06B6D4)],
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$_secondsLeft',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'View-Once Media',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48), // Balance close button
                  ],
                ),
              ),

              // Bottom Vanishing Notice
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.lock_rounded,
                          color: Color(0xFF38BDF8),
                          size: 14,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Disappears completely when you exit',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
