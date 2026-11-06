import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/feed_algorithm_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_native_ad_reel_unit.dart';
import '../models/reel_item.dart';
import '../services/reel_video_cache_manager.dart';
import '../widgets/reel_player_item.dart';
import 'create_reel_screen.dart';

/// Flagship Full-Screen Reels Viewer Screen for ZEV.
/// Hosts vertical snapping PageView, pre-caching, auto-play management,
/// and live Supabase synchronization.
class ReelsViewerScreen extends StatefulWidget {
  final bool isScreenActive;
  const ReelsViewerScreen({super.key, this.isScreenActive = true});

  @override
  State<ReelsViewerScreen> createState() => _ReelsViewerScreenState();
}

class _ReelsViewerScreenState extends State<ReelsViewerScreen> {
  final supabase = Supabase.instance.client;
  late final PageController _pageController;

  bool _isLoading = true;
  List<ReelItem> _reels = [];
  int _activePage = 0;
  bool _isGlobalMuted = false;

  // Native In-Stream Ad Placement Rules (every 4 reels -> 1 ad unit)
  int get _adCount => _reels.length ~/ 4;
  int get _totalPageCount => _reels.length + _adCount;

  bool _isAdPage(int index) {
    if (_reels.isEmpty) return false;
    return (index + 1) % 5 == 0;
  }

  int _getReelIndex(int index) {
    return index - ((index + 1) ~/ 5);
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _fetchReels();
  }

  @override
  void didUpdateWidget(ReelsViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isScreenActive && !widget.isScreenActive) {
      ReelVideoCacheManager().pauseAll();
    } else if (!oldWidget.isScreenActive && widget.isScreenActive) {
      if (_reels.isNotEmpty && !_isAdPage(_activePage)) {
        final reelIdx = _getReelIndex(_activePage);
        if (reelIdx < _reels.length) {
          ReelVideoCacheManager().pauseAllExcept(_reels[reelIdx].videoUrl);
        }
      } else {
        ReelVideoCacheManager().pauseAll();
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchReels() async {
    final currentUserId = supabase.auth.currentUser?.id;

    try {
      // 1. Fetch candidate pool of published reels
      final res = await supabase
          .from('reels')
          .select(
            'id, user_id, title, description, video_url, thumbnail_url, category, duration_seconds, views_count, likes_count, comments_count, created_at',
          )
          .eq('is_published', true)
          .order('created_at', ascending: false)
          .limit(50);

      final rawList = List<Map<String, dynamic>>.from(res as List);
      if (rawList.isEmpty) {
        if (mounted) {
          setState(() {
            _reels = [];
            _isLoading = false;
          });
        }
        return;
      }

      final reelIds = rawList.map((r) => r['id'].toString()).toList();
      final authorIds =
          rawList.map((r) => r['user_id']?.toString() ?? '').toSet().toList();

      // 2. Batch fetch author profiles
      Map<String, Map<String, dynamic>> profilesMap = {};
      if (authorIds.isNotEmpty) {
        final profRes = await supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .inFilter('id', authorIds);

        for (var p in (profRes as List)) {
          profilesMap[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }

      // 3. Batch fetch likes for current user
      Set<String> myLikedReelIds = {};
      if (currentUserId != null && reelIds.isNotEmpty) {
        try {
          final likesRes = await supabase
              .from('reel_likes')
              .select('reel_id')
              .eq('user_id', currentUserId)
              .inFilter('reel_id', reelIds);

          for (var l in (likesRes as List)) {
            final rId = l['reel_id']?.toString() ?? '';
            if (rId.isNotEmpty) myLikedReelIds.add(rId);
          }
        } catch (_) {}
      }

      // 4. Batch fetch bookmarks for current user
      Set<String> myBookmarkedReelIds = {};
      if (currentUserId != null && reelIds.isNotEmpty) {
        try {
          final marksRes = await supabase
              .from('reel_bookmarks')
              .select('reel_id')
              .eq('user_id', currentUserId)
              .inFilter('reel_id', reelIds);

          for (var m in (marksRes as List)) {
            final rId = m['reel_id']?.toString() ?? '';
            if (rId.isNotEmpty) myBookmarkedReelIds.add(rId);
          }
        } catch (_) {}
      }

      // 5. Batch fetch following status for authors
      Set<String> myFollowedAuthorIds = {};
      if (currentUserId != null && authorIds.isNotEmpty) {
        try {
          final followRes = await supabase
              .from('user_follows')
              .select('following_id')
              .eq('follower_id', currentUserId)
              .inFilter('following_id', authorIds);

          for (var f in (followRes as List)) {
            final fId = f['following_id']?.toString() ?? '';
            if (fId.isNotEmpty) myFollowedAuthorIds.add(fId);
          }
        } catch (_) {}
      }

      // 6. Build models
      final List<ReelItem> items = [];
      for (var r in rawList) {
        final id = r['id'].toString();
        final aId = r['user_id']?.toString() ?? '';
        final profile = profilesMap[aId] ?? {};
        final fn = profile['first_name'] ?? '';
        final ln = profile['last_name'] ?? '';
        final full = "$fn $ln".trim();

        items.add(
          ReelItem(
            id: id,
            userId: aId,
            authorUsername: profile['username'] ?? (full.isNotEmpty ? full : 'creator'),
            authorFullName: full,
            authorAvatar: profile['avatar_url'] ?? '',
            isVerified: profile['is_verified'] == true,
            videoUrl: r['video_url'] ?? '',
            thumbnailUrl: r['thumbnail_url'],
            title: r['title'] ?? '',
            description: r['description'] ?? '',
            category: r['category'] ?? 'Explore',
            durationSeconds: r['duration_seconds'] ?? 30,
            viewsCount: r['views_count'] ?? 0,
            likesCount: r['likes_count'] ?? 0,
            isLikedByMe: myLikedReelIds.contains(id),
            commentsCount: r['comments_count'] ?? 0,
            isBookmarkedByMe: myBookmarkedReelIds.contains(id),
            isAuthorFollowed: myFollowedAuthorIds.contains(aId),
            createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
                DateTime.now(),
          ),
        );
      }

      // 7. Apply Instagram-grade Algorithmic Reels Mix
      final mixedReels = FeedAlgorithmService.instance.mixReels(
        items,
        currentUserId: currentUserId,
      );

      if (mounted) {
        setState(() {
          _reels = mixedReels;
          _isLoading = false;
        });
        _preloadAdjacentReels(0);
      }
    } catch (e) {
      debugPrint("Fetch reels exception: $e");
      if (mounted) {
        setState(() {
          _reels = [];
          _isLoading = false;
        });
      }
    }
  }

  void _preloadAdjacentReels(int currentIndex) {
    if (_reels.isEmpty) return;
    final urlsToPreload = <String>[];
    // Next 2 reels
    if (currentIndex + 1 < _reels.length) {
      final u1 = _reels[currentIndex + 1].videoUrl;
      if (u1.isNotEmpty) urlsToPreload.add(u1);
    }
    if (currentIndex + 2 < _reels.length) {
      final u2 = _reels[currentIndex + 2].videoUrl;
      if (u2.isNotEmpty) urlsToPreload.add(u2);
    }
    // Previous reel for smooth backward scroll
    if (currentIndex - 1 >= 0) {
      final uPrev = _reels[currentIndex - 1].videoUrl;
      if (uPrev.isNotEmpty) urlsToPreload.add(uPrev);
    }

    if (urlsToPreload.isNotEmpty) {
      ReelVideoCacheManager().preloadVideos(urlsToPreload, isMuted: _isGlobalMuted);
    }
  }

  void _onPageChanged(int index) {
    setState(() => _activePage = index);
    if (_isAdPage(index)) {
      // Pause all reel audio/video while viewing the native in-stream ad
      ReelVideoCacheManager().pauseAll();
      final nextReelIdx = _getReelIndex(index + 1);
      _preloadAdjacentReels(nextReelIdx);
    } else {
      final reelIdx = _getReelIndex(index);
      if (_reels.isNotEmpty && reelIdx < _reels.length) {
        ReelVideoCacheManager().pauseAllExcept(_reels[reelIdx].videoUrl);
      }
      _preloadAdjacentReels(reelIdx);
    }
  }

  void _toggleGlobalMute() {
    setState(() => _isGlobalMuted = !_isGlobalMuted);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: ZevColors.primaryBlue,
          ),
        ),
      );
    }

    if (_reels.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.movie_filter_outlined,
                size: 56,
                color: Colors.white54,
              ),
              const SizedBox(height: 16),
              const Text(
                "No reels available",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Check back soon for new videos.",
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchReels,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Refresh"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.primaryBlue,
                  foregroundColor: ZevColors.deepNavy,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            physics: const BouncingScrollPhysics(),
            itemCount: _totalPageCount,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final isPageActive = widget.isScreenActive && index == _activePage;

              // Render luxury native ad unit every 4 reels
              if (_isAdPage(index)) {
                return ZevNativeAdReelUnit(
                  key: ValueKey('reel_ad_$index'),
                  isActive: isPageActive,
                );
              }

              final reelIdx = _getReelIndex(index);
              if (reelIdx >= _reels.length) return const SizedBox.shrink();
              final reel = _reels[reelIdx];

              return ReelPlayerItem(
                key: ValueKey(reel.id),
                reel: reel,
                isActive: isPageActive,
                isGlobalMuted: _isGlobalMuted,
                onToggleMute: _toggleGlobalMute,
              );
            },
          ),

          // Next-Gen Claymorphic Top Reels Header Overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Reels",
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => CreateReelScreen.open(
                        context,
                        onReelCreated: _fetchReels,
                      ),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
