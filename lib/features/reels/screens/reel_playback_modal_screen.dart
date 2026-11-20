import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/reel_item.dart';
import '../services/reel_video_cache_manager.dart';
import '../widgets/reel_player_item.dart';

/// Full-Screen Modal Reel Player for ZEV.
/// Used when tapping suggested reels in feed, bookmarks, hashtag feeds, or profile grids.
/// Hosts vertical snapping PageView, hardware-accelerated caching, sound control,
/// and smooth back navigation to feed.
class ReelPlaybackModalScreen extends StatefulWidget {
  final List<ReelItem> reels;
  final int initialIndex;

  const ReelPlaybackModalScreen({
    super.key,
    required this.reels,
    required this.initialIndex,
  });

  static Future<void> open(
    BuildContext context, {
    required List<ReelItem> reels,
    required int initialIndex,
  }) {
    HapticFeedback.selectionClick();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReelPlaybackModalScreen(
          reels: reels,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  State<ReelPlaybackModalScreen> createState() =>
      _ReelPlaybackModalScreenState();
}

class _ReelPlaybackModalScreenState extends State<ReelPlaybackModalScreen> {
  late final PageController _pageController;
  late final List<ReelItem> _reels;
  int _activeIndex = 0;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _reels = List.of(widget.reels);
    _activeIndex = widget.initialIndex.clamp(
      0,
      _reels.isEmpty ? 0 : _reels.length - 1,
    );
    _pageController = PageController(initialPage: _activeIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _reels.isNotEmpty && _activeIndex < _reels.length) {
        ReelVideoCacheManager().pauseAllExcept(_reels[_activeIndex].videoUrl);
      }
    });
  }

  @override
  void dispose() {
    ReelVideoCacheManager().pauseAll();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_reels.isEmpty)
            const Center(
              child: Text(
                'Reel no longer available',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            )
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _reels.length,
              onPageChanged: (idx) {
                setState(() => _activeIndex = idx);
                ReelVideoCacheManager().pauseAllExcept(_reels[idx].videoUrl);
              },
              itemBuilder: (context, index) {
                final reel = _reels[index];
                return ReelPlayerItem(
                  reel: reel,
                  isActive: index == _activeIndex,
                  isGlobalMuted: _isMuted,
                  onToggleMute: () => setState(() => _isMuted = !_isMuted),
                  onReelDeleted: () {
                    setState(() {
                      _reels.removeWhere((r) => r.id == reel.id);
                    });
                    if (_reels.isEmpty && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  onHideOrMute: () {
                    setState(() {
                      _reels.removeWhere((r) => r.id == reel.id);
                    });
                    if (_reels.isEmpty && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                );
              },
            ),

          // Top Header Overlay with Back Button & "Reels" label
          Positioned(
            top: topPadding + 6,
            left: 12,
            right: 12,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 17,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.8,
                    ),
                  ),
                  child: const Text(
                    'Reels',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
