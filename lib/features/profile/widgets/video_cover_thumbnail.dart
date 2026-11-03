import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/zev_theme.dart';

/// Lightweight widget to render the first frame of a video URL
/// inside circular highlight covers, preventing generic star icons.
class VideoCoverThumbnail extends StatefulWidget {
  final String videoUrl;

  const VideoCoverThumbnail({super.key, required this.videoUrl});

  @override
  State<VideoCoverThumbnail> createState() => _VideoCoverThumbnailState();
}

class _VideoCoverThumbnailState extends State<VideoCoverThumbnail> {
  VideoPlayerController? _controller;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _initThumbnail();
  }

  Future<void> _initThumbnail() async {
    if (widget.videoUrl.isEmpty) return;
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller!.initialize();
      await _controller!.pause();
      if (mounted) {
        setState(() => _isLoaded = true);
      }
    } catch (_) {
      // If network video preview fails, dispose cleanly
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoaded && _controller != null) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width > 0
                ? _controller!.value.size.width
                : 100,
            height: _controller!.value.size.height > 0
                ? _controller!.value.size.height
                : 100,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF0F172A),
      child: const Center(
        child: Icon(
          Icons.play_circle_fill_rounded,
          color: ZevColors.primaryBlue,
          size: 26,
        ),
      ),
    );
  }
}

