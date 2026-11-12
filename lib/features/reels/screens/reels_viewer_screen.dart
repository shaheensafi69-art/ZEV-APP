import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _ReelsViewerScreenState extends State<ReelsViewerScreen>
    with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  late final PageController _pageController;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreReels = true;
  bool _fetchError = false;
  bool _followingOnly = false;
  bool _isOverlayRouteOpen = false;
  bool _isAppForeground = true;

  DateTime? _cursorCreatedAt;
  String? _cursorId;
  int _fetchGeneration = 0;
  static const int _pageSize = 15;
  final Set<String> _loadedReelIds = <String>{};
  List<ReelItem> _reels = [];
  int _activePage = 0;
  bool _isGlobalMuted = false;

  // Native In-Stream Ad Placement Rules (every 4 reels -> 1 ad unit)
  int get _adCount => _reels.length ~/ 4;
  int get _totalPageCount => _reels.length + _adCount;

  bool get _canPlayVideos =>
      widget.isScreenActive && !_isOverlayRouteOpen && _isAppForeground;

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
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _fetchReels();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_isAppForeground && mounted) {
        setState(() => _isAppForeground = false);
      }
      ReelVideoCacheManager().pauseAll();
    } else if (state == AppLifecycleState.resumed) {
      if (!_isAppForeground && mounted) {
        setState(() => _isAppForeground = true);
      }
      _syncPlaybackAndPreload();
    }
  }

  @override
  void didUpdateWidget(ReelsViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isScreenActive && !widget.isScreenActive) {
      ReelVideoCacheManager().pauseAll();
    } else if (!oldWidget.isScreenActive && widget.isScreenActive) {
      _syncPlaybackAndPreload();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  void _syncPlaybackAndPreload() {
    if (!_canPlayVideos || _reels.isEmpty) {
      ReelVideoCacheManager().pauseAll();
      return;
    }

    if (_isAdPage(_activePage)) {
      ReelVideoCacheManager().pauseAll();
      final nextReelIdx = _getReelIndex(_activePage + 1);
      _preloadAroundAd(nextReelIdx);
      return;
    }

    final reelIdx = _getReelIndex(_activePage);
    if (reelIdx >= 0 && reelIdx < _reels.length) {
      final activeReel = _reels[reelIdx];
      FeedAlgorithmService.instance.markReelSeen(activeReel.id);
      ReelVideoCacheManager().pauseAllExcept(activeReel.videoUrl);
      _preloadAdjacentReels(reelIdx);
    } else {
      ReelVideoCacheManager().pauseAll();
    }
  }

  Future<void> _fetchReels({bool loadMore = false}) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (loadMore) {
      if (_isLoadingMore || !_hasMoreReels) return;
      if (mounted) setState(() => _isLoadingMore = true);
    } else if (mounted && _reels.isEmpty) {
      setState(() {
        _isLoading = true;
        _fetchError = false;
      });
    }

    final int generation = loadMore ? _fetchGeneration : ++_fetchGeneration;
    final DateTime? reqCursorCreatedAt = loadMore ? _cursorCreatedAt : null;
    final String? reqCursorId = loadMore ? _cursorId : null;

    try {
      final rawRes = await supabase.rpc(
        'get_reels_page',
        params: {
          'p_cursor_created_at': reqCursorCreatedAt?.toUtc().toIso8601String(),
          'p_cursor_id': reqCursorId,
          'p_limit': _pageSize,
          'p_following_only': _followingOnly,
        },
      );

      if (!mounted || generation != _fetchGeneration) return;

      final rawRows = (rawRes is List)
          ? rawRes.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];

      DateTime? nextCursorCreatedAt = reqCursorCreatedAt;
      String? nextCursorId = reqCursorId;
      if (rawRows.isNotEmpty) {
        final lastRow = rawRows.last;
        nextCursorCreatedAt = DateTime.tryParse(
          lastRow['created_at']?.toString() ?? '',
        );
        nextCursorId = lastRow['id']?.toString();
      }
      final bool hasMore = rawRows.length >= _pageSize && nextCursorId != null;

      if (!loadMore) {
        _loadedReelIds.clear();
      }

      final List<ReelItem> pageItems = [];
      for (final r in rawRows) {
        final id = r['id']?.toString() ?? '';
        if (id.isEmpty || _loadedReelIds.contains(id)) continue;
        _loadedReelIds.add(id);
        pageItems.add(ReelItem.fromRpcMap(r));
      }

      final mixedPage = FeedAlgorithmService.instance.mixReels(
        pageItems,
        currentUserId: currentUserId,
      );

      setState(() {
        if (loadMore) {
          _reels = [..._reels, ...mixedPage];
        } else {
          _reels = mixedPage;
          _activePage = 0;
        }
        _cursorCreatedAt = nextCursorCreatedAt;
        _cursorId = nextCursorId;
        _hasMoreReels = hasMore;
        _fetchError = false;
        _isLoading = false;
        _isLoadingMore = false;
      });

      if (!loadMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_pageController.hasClients &&
              (_pageController.page?.round() ?? 0) != 0) {
            _pageController.jumpToPage(0);
          }
        });
      }

      _syncPlaybackAndPreload();
    } catch (e) {
      debugPrint("Fetch reels exception: $e");
      if (mounted && generation == _fetchGeneration) {
        setState(() {
          if (!loadMore) {
            _reels = [];
            _fetchError = true;
          }
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreReels() => _fetchReels(loadMore: true);

  /// Preloads strictly +1 and -1 so total RAM cache stays <= _maxControllersInRam (3),
  /// preventing cache eviction of the currently playing reel.
  void _preloadAdjacentReels(int currentIndex) {
    if (_reels.isEmpty || !_canPlayVideos) return;
    final urlsToPreload = <String>[];
    if (currentIndex + 1 >= 0 && currentIndex + 1 < _reels.length) {
      final uNext = _reels[currentIndex + 1].videoUrl;
      if (uNext.isNotEmpty) urlsToPreload.add(uNext);
    }
    if (currentIndex - 1 >= 0 && currentIndex - 1 < _reels.length) {
      final uPrev = _reels[currentIndex - 1].videoUrl;
      if (uPrev.isNotEmpty) urlsToPreload.add(uPrev);
    }

    if (urlsToPreload.isNotEmpty) {
      ReelVideoCacheManager().preloadVideos(
        urlsToPreload,
        isMuted: _isGlobalMuted,
      );
    }
  }

  void _preloadAroundAd(int nextReelIdx) {
    if (_reels.isEmpty || !_canPlayVideos) return;
    final urlsToPreload = <String>[];
    if (nextReelIdx >= 0 && nextReelIdx < _reels.length) {
      final uNext = _reels[nextReelIdx].videoUrl;
      if (uNext.isNotEmpty) urlsToPreload.add(uNext);
    }
    if (nextReelIdx - 1 >= 0 && nextReelIdx - 1 < _reels.length) {
      final uPrev = _reels[nextReelIdx - 1].videoUrl;
      if (uPrev.isNotEmpty) urlsToPreload.add(uPrev);
    }
    if (urlsToPreload.isNotEmpty) {
      ReelVideoCacheManager().preloadVideos(
        urlsToPreload,
        isMuted: _isGlobalMuted,
      );
    }
  }

  void _onPageChanged(int index) {
    setState(() => _activePage = index);
    if (_isAdPage(index)) {
      ReelVideoCacheManager().pauseAll();
      final nextReelIdx = _getReelIndex(index + 1);
      _preloadAroundAd(nextReelIdx);
    } else {
      final reelIdx = _getReelIndex(index);
      if (_reels.isNotEmpty && reelIdx >= 0 && reelIdx < _reels.length) {
        final activeReel = _reels[reelIdx];
        if (_canPlayVideos) {
          FeedAlgorithmService.instance.markReelSeen(activeReel.id);
          ReelVideoCacheManager().pauseAllExcept(activeReel.videoUrl);
          _preloadAdjacentReels(reelIdx);
        } else {
          ReelVideoCacheManager().pauseAll();
        }
      }
      if (_hasMoreReels && !_isLoadingMore && reelIdx >= _reels.length - 3) {
        unawaited(_loadMoreReels());
      }
    }
  }

  void _removeReelLocally(String reelId) {
    _loadedReelIds.remove(reelId);
    final oldActivePage = _activePage;

    setState(() {
      _reels.removeWhere((r) => r.id == reelId);
      final maxPage = _totalPageCount > 0 ? _totalPageCount - 1 : 0;
      if (_activePage > maxPage) {
        _activePage = maxPage;
      }
    });

    if (_reels.isEmpty) {
      ReelVideoCacheManager().pauseAll();
      if (_hasMoreReels && !_isLoadingMore) {
        unawaited(_loadMoreReels());
      }
      return;
    }

    if (oldActivePage != _activePage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(_activePage);
      });
    }

    _syncPlaybackAndPreload();

    final currentReelIdx = _isAdPage(_activePage)
        ? _getReelIndex(_activePage + 1)
        : _getReelIndex(_activePage);
    if (_hasMoreReels &&
        !_isLoadingMore &&
        currentReelIdx >= _reels.length - 3) {
      unawaited(_loadMoreReels());
    }
  }

  void _switchFollowingOnly(bool followOnly) {
    if (followOnly == _followingOnly) return;
    HapticFeedback.selectionClick();
    ReelVideoCacheManager().pauseAll();
    setState(() {
      _followingOnly = followOnly;
      _isLoading = true;
      _fetchError = false;
      _reels = [];
      _cursorCreatedAt = null;
      _cursorId = null;
      _hasMoreReels = true;
      _loadedReelIds.clear();
      _activePage = 0;
    });
    _fetchReels();
  }

  void _toggleGlobalMute() {
    setState(() => _isGlobalMuted = !_isGlobalMuted);
  }

  Future<void> _openCreateReel() async {
    HapticFeedback.lightImpact();
    setState(() => _isOverlayRouteOpen = true);
    ReelVideoCacheManager().pauseAll();

    await CreateReelScreen.open(
      context,
      onReelCreated: () {
        if (mounted) {
          _fetchReels();
        }
      },
    );

    if (!mounted) return;
    setState(() => _isOverlayRouteOpen = false);
    _syncPlaybackAndPreload();
  }

  Widget _buildTopHeaderOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              PopupMenuButton<bool>(
                tooltip: 'Switch Reels Feed',
                color: Colors.white,
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: ZevColors.border),
                ),
                initialValue: _followingOnly,
                onSelected: _switchFollowingOnly,
                itemBuilder: (_) => [
                  PopupMenuItem<bool>(
                    value: false,
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: !_followingOnly
                              ? ZevColors.secondaryBlue
                              : ZevColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'For You',
                          style: TextStyle(
                            fontWeight: !_followingOnly
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<bool>(
                    value: true,
                    child: Row(
                      children: [
                        Icon(
                          Icons.people_alt_rounded,
                          size: 18,
                          color: _followingOnly
                              ? ZevColors.secondaryBlue
                              : ZevColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Following',
                          style: TextStyle(
                            fontWeight: _followingOnly
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _followingOnly ? "Following" : "Reels",
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: _openCreateReel,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: ZevColors.primaryBlue,
              ),
            ),
            _buildTopHeaderOverlay(),
          ],
        ),
      );
    }

    if (_reels.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _fetchError
                          ? Icons.wifi_off_rounded
                          : Icons.movie_filter_outlined,
                      size: 56,
                      color: Colors.white54,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _fetchError
                          ? "Couldn't load reels"
                          : _followingOnly
                              ? "No reels from Following yet"
                              : "No reels available",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fetchError
                          ? "Check your connection and try again."
                          : _followingOnly
                              ? "Follow creators to see their reels here, or switch to For You."
                              : "Check back soon for new videos.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        if (_followingOnly)
                          ElevatedButton.icon(
                            onPressed: () => _switchFollowingOnly(false),
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: const Text("Switch to For You"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ZevColors.primaryBlue,
                              foregroundColor: ZevColors.deepNavy,
                            ),
                          ),
                        ElevatedButton.icon(
                          onPressed: _fetchReels,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_fetchError ? "Try Again" : "Refresh"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _followingOnly
                                ? Colors.white.withValues(alpha: 0.16)
                                : ZevColors.primaryBlue,
                            foregroundColor: _followingOnly
                                ? Colors.white
                                : ZevColors.deepNavy,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _buildTopHeaderOverlay(),
          ],
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
              final isPageActive = _canPlayVideos && index == _activePage;

              // Render luxury native ad unit every 4 reels
              if (_isAdPage(index)) {
                return ZevNativeAdReelUnit(
                  key: ValueKey('reel_ad_$index'),
                  isActive: isPageActive,
                  slotKey: 'reel_slot_$index',
                );
              }

              final reelIdx = _getReelIndex(index);
              if (reelIdx < 0 || reelIdx >= _reels.length) {
                return const SizedBox.shrink();
              }
              final reel = _reels[reelIdx];

              return ReelPlayerItem(
                key: ValueKey(reel.id),
                reel: reel,
                isActive: isPageActive,
                isGlobalMuted: _isGlobalMuted,
                onToggleMute: _toggleGlobalMute,
                onHideOrMute: () {
                  FeedAlgorithmService.instance.recordNegativeFeedback(
                    reelId: reel.id,
                    authorId: reel.userId,
                  );
                  _removeReelLocally(reel.id);
                },
                onReelDeleted: () => _removeReelLocally(reel.id),
              );
            },
          ),
          _buildTopHeaderOverlay(),
        ],
      ),
    );
  }
}
