import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/feed_algorithm_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/comments_thread_sheet.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_native_ad_reel_unit.dart';
import '../../profile/screens/profile_screen.dart';
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
  int _previousPage = 0;
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
    setState(() {
      _previousPage = _activePage;
      _activePage = index;
    });
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

  void _handleAdPageUnavailable(int adPageIndex) {
    if (!mounted || !_pageController.hasClients || _activePage != adPageIndex) {
      return;
    }
    final bool movingForward = adPageIndex >= _previousPage;
    int target = movingForward ? adPageIndex + 1 : adPageIndex - 1;
    if (target < 0) target = 0;
    if (target >= _totalPageCount) target = adPageIndex - 1;
    if (target >= 0 && target < _totalPageCount && target != adPageIndex) {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
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

    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

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

              Widget child;
              final isAd = _isAdPage(index);
              ReelItem? activeReel;

              // Render luxury native ad unit every 4 reels
              if (isAd) {
                child = ZevNativeAdReelUnit(
                  key: ValueKey('reel_ad_$index'),
                  isActive: isPageActive,
                  slotKey: 'reel_slot_$index',
                  onAdUnavailable: () => _handleAdPageUnavailable(index),
                );
              } else {
                final reelIdx = _getReelIndex(index);
                if (reelIdx < 0 || reelIdx >= _reels.length) {
                  return const SizedBox.shrink();
                }
                final reel = _reels[reelIdx];
                activeReel = reel;

                child = ReelPlayerItem(
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
              }

              if (isDesktop) {
                final screenWidth = MediaQuery.sizeOf(context).width;
                final screenHeight = MediaQuery.sizeOf(context).height;
                final cardHeight = math.min(screenHeight - 32.0, 840.0);
                final double sidebarWidth = (screenWidth < 1140) ? 340.0 : 400.0;

                return Center(
                  child: Container(
                    height: cardHeight,
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left 9:16 Video Player Card
                        Container(
                          width: 440,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.1),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: child,
                        ),
                        const SizedBox(width: 16),
                        // Right Interactive Comments & Info Card
                        SizedBox(
                          width: sidebarWidth,
                          child: isAd || activeReel == null
                              ? _buildDesktopAdSidebar()
                              : DesktopReelSidebar(
                                  key: ValueKey('sidebar_${activeReel.id}'),
                                  reel: activeReel,
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return child;
            },
          ),
          _buildTopHeaderOverlay(),
          if (isDesktop)
            Positioned(
              right: 28,
              top: 0,
              bottom: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Previous Reel',
                      icon: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      onPressed: () {
                        if (_pageController.hasClients && _activePage > 0) {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    IconButton(
                      tooltip: 'Next Reel',
                      icon: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      onPressed: () {
                        if (_pageController.hasClients &&
                            _activePage < _totalPageCount - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopAdSidebar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141721),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ZevColors.primaryBlue.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              size: 44,
              color: ZevColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sponsored Content',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Discover featured promotions and services curated for the ZEV community.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class DesktopReelSidebar extends StatefulWidget {
  final ReelItem reel;

  const DesktopReelSidebar({
    super.key,
    required this.reel,
  });

  @override
  State<DesktopReelSidebar> createState() => _DesktopReelSidebarState();
}

class _DesktopReelSidebarState extends State<DesktopReelSidebar> {
  final _supabase = Supabase.instance.client;
  bool _isFollowing = false;
  bool _followRequested = false;
  bool _isFollowLoading = false;
  bool _isCaptionExpanded = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.reel.isAuthorFollowed;
  }

  @override
  void didUpdateWidget(DesktopReelSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reel.id != widget.reel.id) {
      _isFollowing = widget.reel.isAuthorFollowed;
      _followRequested = false;
      _isFollowLoading = false;
      _isCaptionExpanded = false;
    }
  }

  Future<void> _toggleFollow() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to follow creators.')),
      );
      return;
    }
    if (_isFollowLoading) return;

    HapticFeedback.lightImpact();
    setState(() => _isFollowLoading = true);

    final status = await SocialGraphService.instance.toggleFollow(
      widget.reel.userId,
    );
    if (!mounted) return;
    setState(() {
      _isFollowLoading = false;
      switch (status) {
        case FollowToggleStatus.following:
          _isFollowing = true;
          _followRequested = false;
          break;
        case FollowToggleStatus.requested:
          _isFollowing = false;
          _followRequested = true;
          break;
        case FollowToggleStatus.unfollowed:
        case FollowToggleStatus.cancelled:
        case FollowToggleStatus.blocked:
        case FollowToggleStatus.error:
          _isFollowing = false;
          _followRequested = false;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final isMe = currentUserId != null && currentUserId == widget.reel.userId;
    final captionText = widget.reel.description.isNotEmpty
        ? widget.reel.description
        : widget.reel.title;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141721),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Author Header + Follow Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => ProfileScreen.open(
                        context,
                        userId: widget.reel.userId,
                      ),
                      child: widget.reel.authorAvatar.isNotEmpty
                          ? ZevCachedImage.avatar(
                              imageUrl: widget.reel.authorAvatar,
                              size: 40,
                            )
                          : Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF22283A),
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                size: 22,
                                color: Colors.white70,
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => ProfileScreen.open(
                          context,
                          userId: widget.reel.userId,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '@${widget.reel.authorUsername}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.reel.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.verified_rounded,
                                    color: ZevColors.primaryBlue,
                                    size: 14,
                                  ),
                                ],
                              ],
                            ),
                            if (widget.reel.authorFullName.isNotEmpty)
                              Text(
                                widget.reel.authorFullName,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (!isMe) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _isFollowLoading ? null : _toggleFollow,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _isFollowing
                                ? Colors.white.withValues(alpha: 0.12)
                                : ZevColors.primaryBlue,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _isFollowing
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.transparent,
                            ),
                          ),
                          child: _isFollowLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isFollowing
                                      ? 'Following'
                                      : _followRequested
                                          ? 'Requested'
                                          : 'Follow',
                                  style: TextStyle(
                                    color: _isFollowing
                                        ? Colors.white
                                        : ZevColors.deepNavy,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
                // Caption / Description
                if (captionText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => setState(
                      () => _isCaptionExpanded = !_isCaptionExpanded,
                    ),
                    child: Text(
                      captionText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.35,
                      ),
                      maxLines: _isCaptionExpanded ? 8 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                // Music info
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.music_note_rounded,
                      size: 13,
                      color: ZevColors.secondaryBlue,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Original audio • @${widget.reel.authorUsername}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          // 2. Interactive Real-Time Comments Section
          Expanded(
            child: CommentsThreadSheet(
              targetType: 'reel',
              targetId: widget.reel.id,
              targetAuthorUsername: widget.reel.authorUsername,
              targetAuthorId: widget.reel.userId,
              isEmbedded: true,
              isDarkTheme: true,
              customBorderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
