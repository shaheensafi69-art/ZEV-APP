import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/utils/time_ago.dart';
import '../models/feed_post_item.dart';
import '../widgets/feed_comments_sheet.dart';
import '../widgets/feed_share_sheet.dart';

/// Immersive Facebook-Style Fullscreen Media Viewer.
/// Provides pinch-to-zoom (up to 4x), double-tap zoom/like, full caption display,
/// and live interaction buttons (Like, Comment, Repost, Share).
class FullscreenMediaViewer extends StatefulWidget {
  final FeedPostItem post;
  final bool isLiked;
  final int likesCount;
  final bool isReposted;
  final int repostsCount;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleRepost;

  const FullscreenMediaViewer({
    super.key,
    required this.post,
    required this.isLiked,
    required this.likesCount,
    required this.isReposted,
    required this.repostsCount,
    required this.onToggleLike,
    required this.onToggleRepost,
  });

  static void open(
    BuildContext context, {
    required FeedPostItem post,
    required bool isLiked,
    required int likesCount,
    required bool isReposted,
    required int repostsCount,
    required VoidCallback onToggleLike,
    required VoidCallback onToggleRepost,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (context, anim1, anim2) => FullscreenMediaViewer(
          post: post,
          isLiked: isLiked,
          likesCount: likesCount,
          isReposted: isReposted,
          repostsCount: repostsCount,
          onToggleLike: onToggleLike,
          onToggleRepost: onToggleRepost,
        ),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<FullscreenMediaViewer> createState() => _FullscreenMediaViewerState();
}

class _FullscreenMediaViewerState extends State<FullscreenMediaViewer> {
  final TransformationController _transCtrl = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _showOverlays = true;
  late bool _liked;
  late int _likes;
  late bool _reposted;
  late int _reposts;

  @override
  void initState() {
    super.initState();
    _liked = widget.isLiked;
    _likes = widget.likesCount;
    _reposted = widget.isReposted;
    _reposts = widget.repostsCount;
  }

  @override
  void dispose() {
    _transCtrl.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transCtrl.value != Matrix4.identity()) {
      _transCtrl.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      _transCtrl.value = Matrix4.identity()
        // ignore: deprecated_member_use
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        // ignore: deprecated_member_use
        ..scale(2.5);
    }
  }

  void _handleLike() {
    HapticFeedback.mediumImpact();
    setState(() {
      _liked = !_liked;
      _likes = _liked ? _likes + 1 : (_likes > 0 ? _likes - 1 : 0);
    });
    widget.onToggleLike();
  }

  void _handleRepost() {
    HapticFeedback.mediumImpact();
    setState(() {
      _reposted = !_reposted;
      _reposts = _reposted ? _reposts + 1 : (_reposts > 0 ? _reposts - 1 : 0);
    });
    widget.onToggleRepost();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final timeStr = TimeAgo.format(post.createdAt);
    final isContentRtl = TextDirectionHelper.isRtl(
      post.content.isNotEmpty ? post.content : post.title,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Interactive Zoomable Image
          GestureDetector(
            onTap: () => setState(() => _showOverlays = !_showOverlays),
            onDoubleTapDown: (d) => _doubleTapDetails = d,
            onDoubleTap: _handleDoubleTap,
            child: Center(
              child: InteractiveViewer(
                transformationController: _transCtrl,
                minScale: 0.8,
                maxScale: 4.5,
                child: CachedNetworkImage(
                  imageUrl: post.imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(
                      color: ZevColors.primaryBlue,
                      strokeWidth: 2.5,
                    ),
                  ),
                  errorWidget: (context, url, error) => const Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      size: 64,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 2. Top Header Bar (Close + Author info)
          if (_showOverlays)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  right: 12,
                  bottom: 12,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white24,
                      backgroundImage: post.authorAvatar.isNotEmpty
                          ? NetworkImage(post.authorAvatar)
                          : null,
                      child: post.authorAvatar.isEmpty
                          ? const Icon(
                              Icons.person_rounded,
                              size: 20,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  post.authorUsername,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (post.isVerified) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 15,
                                  color: ZevColors.primaryBlue,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.share_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () {
                        FeedShareSheet.show(context, post: post);
                      },
                    ),
                  ],
                ),
              ),
            ),

          // 3. Bottom Overlays (Caption & Actions)
          if (_showOverlays)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 14,
                  left: 16,
                  right: 16,
                  top: 24,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Caption
                    if (post.title.isNotEmpty || post.content.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                          post.content.isNotEmpty
                              ? post.content
                              : post.title,
                          textDirection: isContentRtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          textAlign: isContentRtl
                              ? TextAlign.right
                              : TextAlign.left,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.4,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    // Actions Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // Like Button
                        _buildAction(
                          icon: _liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: _liked ? Colors.redAccent : Colors.white,
                          label: _likes > 0 ? "$_likes" : "Like",
                          onTap: _handleLike,
                        ),
                        // Comment Button
                        _buildAction(
                          icon: Icons.chat_bubble_outline_rounded,
                          color: Colors.white,
                          label: post.commentsCount > 0
                              ? "${post.commentsCount}"
                              : "Comment",
                          onTap: () {
                            FeedCommentsSheet.show(
                              context,
                              postId: post.id,
                              postAuthorUsername: post.authorUsername,
                            );
                          },
                        ),
                        // Repost Button
                        _buildAction(
                          icon: Icons.repeat_rounded,
                          color: _reposted
                              ? ZevColors.primaryBlue
                              : Colors.white,
                          label: _reposts > 0 ? "$_reposts" : "Repost",
                          onTap: _handleRepost,
                        ),
                        // Share Button
                        _buildAction(
                          icon: Icons.send_rounded,
                          color: Colors.white,
                          label: "Share",
                          onTap: () {
                            FeedShareSheet.show(context, post: post);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAction({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
