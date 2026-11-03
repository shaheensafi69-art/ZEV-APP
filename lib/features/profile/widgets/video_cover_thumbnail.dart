import 'package:flutter/material.dart';
import '../../../core/widgets/zev_video_thumbnail.dart';

/// Lightweight widget to render the first frame of a video URL
/// inside circular highlight covers, preventing generic star icons.
class VideoCoverThumbnail extends StatelessWidget {
  final String videoUrl;

  const VideoCoverThumbnail({super.key, required this.videoUrl});

  @override
  Widget build(BuildContext context) {
    return ZevVideoThumbnail(
      videoUrl: videoUrl,
      showPlayBadge: false,
      showViews: false,
      fit: BoxFit.cover,
    );
  }
}

