import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/admob_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/services/zev_ads_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_native_ad_story_unit.dart';
import '../../live/screens/live_room_screen.dart';
import '../models/feed_post_item.dart';

/// Active Live Broadcast Room metadata for FeedStoriesTray
class _TrayLiveRoom {
  final Map<String, dynamic> stream;
  final Map<String, dynamic> hostProfile;
  final String hostUsername;
  final String hostAvatarUrl;
  final int viewerCount;

  _TrayLiveRoom({
    required this.stream,
    required this.hostProfile,
    required this.hostUsername,
    required this.hostAvatarUrl,
    required this.viewerCount,
  });
}

/// Next-Generation Unified Stories & Discovery Tray for ZEV.
/// Seamlessly integrates:
/// 1. "Your Story" (with instant story create/view action)
/// 2. Active Live Broadcasts (Real-time pulsating red glow & "LIVE" badge)
/// 3. ZEV Promoted / Advertised Stories (Targeted sponsored campaigns with "Ad" badge)
/// 4. Google AdMob Native Sponsor Slot (Mobile partner sponsorship)
/// 5. Friend Stories (Electric Cyan, Emerald close-friends, and muted rings)
class FeedStoriesTray extends StatefulWidget {
  final String myAvatarUrl;
  final ActiveFriendStory? myActiveStory;
  final List<ActiveFriendStory> stories;
  final VoidCallback? onAddStory;
  final ValueChanged<ActiveFriendStory>? onStoryTap;

  const FeedStoriesTray({
    super.key,
    required this.myAvatarUrl,
    this.myActiveStory,
    required this.stories,
    this.onAddStory,
    this.onStoryTap,
  });

  @override
  State<FeedStoriesTray> createState() => _FeedStoriesTrayState();
}

class _FeedStoriesTrayState extends State<FeedStoriesTray>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  List<_TrayLiveRoom> _liveRooms = [];
  ZevSponsoredAd? _sponsoredAd;
  RealtimeChannel? _liveChannel;
  Timer? _liveDebounceTimer;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    unawaited(_loadLiveRooms());
    unawaited(_loadSponsoredAd());
    _subscribeLiveStreams();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _liveDebounceTimer?.cancel();
    final channel = _liveChannel;
    _liveChannel = null;
    if (channel != null) {
      unawaited(channel.unsubscribe());
    }
    super.dispose();
  }

  void _subscribeLiveStreams() {
    try {
      _liveChannel = _supabase
          .channel('feed_stories_tray_live_updates')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'live_streams',
            callback: (_) {
              _liveDebounceTimer?.cancel();
              _liveDebounceTimer = Timer(
                const Duration(milliseconds: 400),
                () => unawaited(_loadLiveRooms()),
              );
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[FeedStoriesTray] live subscribe notice: $e');
    }
  }

  Future<void> _loadLiveRooms() async {
    try {
      final safety = await SocialGraphService.instance.fetchSafetyFilters();
      final res = await _supabase
          .from('live_streams')
          .select()
          .eq('status', 'live')
          .order('started_at', ascending: false)
          .limit(8);

      final rawRooms = (res as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((r) {
            final hostId = r['host_id']?.toString() ?? '';
            return hostId.isNotEmpty && !safety.blockedUserIds.contains(hostId);
          })
          .toList();

      final hostIds = rawRooms
          .map((r) => r['host_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (hostIds.isEmpty) {
        if (mounted) setState(() => _liveRooms = []);
        return;
      }

      final profRes = await _supabase
          .from('profiles')
          .select(
            'id, username, first_name, last_name, avatar_url, is_verified, is_banned, account_status',
          )
          .inFilter('id', hostIds);

      final profilesMap = <String, Map<String, dynamic>>{};
      for (final item in (profRes as List).whereType<Map>()) {
        final m = Map<String, dynamic>.from(item);
        final id = m['id']?.toString() ?? '';
        final isBanned = m['is_banned'] == true;
        final accountStatus = (m['account_status'] ?? 'active').toString();
        if (id.isNotEmpty && !isBanned && accountStatus == 'active') {
          profilesMap[id] = m;
        }
      }

      final List<_TrayLiveRoom> list = [];
      for (final room in rawRooms) {
        final hostId = room['host_id']?.toString() ?? '';
        final prof = profilesMap[hostId];
        if (prof != null) {
          list.add(_TrayLiveRoom(
            stream: room,
            hostProfile: prof,
            hostUsername: (prof['username'] ?? 'Live').toString(),
            hostAvatarUrl: (prof['avatar_url'] ?? '').toString(),
            viewerCount: (room['viewer_count'] as num?)?.toInt() ?? 1,
          ));
        }
      }

      if (mounted) {
        setState(() => _liveRooms = list);
      }
    } catch (e) {
      debugPrint('[FeedStoriesTray] loadLiveRooms notice: $e');
    }
  }

  Future<void> _loadSponsoredAd() async {
    try {
      final ad = await ZevAdsService.instance.fetchEligibleAd(
        placement: 'story',
        slotKey: 'feed_stories_tray',
      );
      if (mounted) {
        setState(() => _sponsoredAd = ad);
        if (ad != null) {
          unawaited(
            ZevAdsService.instance.recordImpressionOnce(
              slotKey: 'feed_stories_tray',
              ad: ad,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[FeedStoriesTray] loadSponsoredAd notice: $e');
    }
  }

  bool get _hasAdMobSlot =>
      !kIsWeb && AdmobService.instance.isInitialized && _sponsoredAd == null;

  @override
  Widget build(BuildContext context) {
    // Total count:
    // 1 (My Story) + Live Rooms + Sponsored Ad (0 or 1) + AdMob Slot (0 or 1) + Friend Stories
    final liveCount = _liveRooms.length;
    final adCount = _sponsoredAd != null ? 1 : (_hasAdMobSlot ? 1 : 0);
    final totalCount = 1 + liveCount + adCount + widget.stories.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      height: 114,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: totalCount,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          // 0: My Story
          if (index == 0) {
            return _buildMyStoryItem(context);
          }

          // 1 .. liveCount: Live broadcast rooms
          if (index <= liveCount) {
            final liveRoom = _liveRooms[index - 1];
            return _buildLiveRoomItem(context, liveRoom);
          }

          final afterLiveIndex = index - 1 - liveCount;

          // Next: Sponsored Ad or AdMob slot
          if (adCount > 0 && afterLiveIndex == 0) {
            if (_sponsoredAd != null) {
              return _buildSponsoredStoryItem(context, _sponsoredAd!);
            } else if (_hasAdMobSlot) {
              return _buildAdMobStoryItem(context);
            }
          }

          // Remaining: Friend stories
          final friendIndex = afterLiveIndex - adCount;
          if (friendIndex >= 0 && friendIndex < widget.stories.length) {
            final story = widget.stories[friendIndex];
            return _buildFriendStoryItem(context, story);
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  // 1. My Story bubble
  Widget _buildMyStoryItem(BuildContext context) {
    final activeStory = widget.myActiveStory;
    final hasActive = activeStory != null && activeStory.storiesCount > 0;

    void handleAddStory() {
      HapticFeedback.lightImpact();
      if (widget.onAddStory != null) {
        widget.onAddStory!();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Create Story will open camera/media picker.",
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    Widget avatarInner = Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF1F5F9),
        border: Border.all(
          color: Colors.white,
          width: 2.0,
        ),
        boxShadow: hasActive
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
                const BoxShadow(
                  color: Colors.white,
                  blurRadius: 6,
                  offset: Offset(0, -2),
                ),
              ],
      ),
      child: widget.myAvatarUrl.isNotEmpty
          ? ZevCachedImage.avatar(
              imageUrl: widget.myAvatarUrl,
              size: 60,
            )
          : const Center(
              child: Icon(
                Icons.person_rounded,
                size: 32,
                color: ZevColors.textMuted,
              ),
            ),
    );

    if (hasActive) {
      final isCloseFriend = activeStory.hasCloseFriendStory;
      final isUnseen = activeStory.hasUnseen;
      avatarInner = Container(
        width: 60,
        height: 60,
        padding: EdgeInsets.all(isUnseen ? 2.4 : 1.8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isUnseen
              ? LinearGradient(
                  colors: isCloseFriend
                      ? const [Color(0xFF10B981), Color(0xFF00D4FF)]
                      : const [
                          Color(0xFF00D4FF),
                          Color(0xFF536DFE),
                          Color(0xFFA60F93),
                        ],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                )
              : null,
          color: isUnseen ? null : const Color(0xFFCBD5E1),
        ),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(1.5),
          child: avatarInner,
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (hasActive && widget.onStoryTap != null) {
          widget.onStoryTap!(activeStory);
        } else {
          handleAddStory();
        }
      },
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                avatarInner,
                Positioned(
                  bottom: -1,
                  right: -1,
                  child: GestureDetector(
                    onTap: handleAddStory,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00D4FF), Color(0xFF0095F6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.45),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.add,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Your story",
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: hasActive ? FontWeight.w800 : FontWeight.w700,
                color: hasActive ? ZevColors.deepNavy : ZevColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // 2. Active Live Room bubble with pulsing red gradient and "LIVE" pill
  Widget _buildLiveRoomItem(BuildContext context, _TrayLiveRoom room) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        LiveRoomScreen.open(
          context,
          stream: room.stream,
          hostProfile: room.hostProfile,
        );
      },
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 60,
                      height: 60,
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFF0055),
                            Color(0xFFFF3366),
                            Color(0xFFFF6600),
                          ],
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF0055)
                                .withValues(alpha: 0.35 * _pulseAnimation.value),
                            blurRadius: 10 * _pulseAnimation.value,
                            spreadRadius: 1.5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        padding: const EdgeInsets.all(1.5),
                        child: room.hostAvatarUrl.isNotEmpty
                            ? ZevCachedImage.avatar(
                                imageUrl: room.hostAvatarUrl,
                                size: 58,
                              )
                            : const Center(
                                child: Icon(
                                  Icons.sensors_rounded,
                                  size: 28,
                                  color: Color(0xFFFF0055),
                                ),
                              ),
                      ),
                    );
                  },
                ),
                Positioned(
                  bottom: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE11D48), Color(0xFFDC2626)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1.6),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE11D48).withValues(alpha: 0.5),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sensors_rounded,
                          size: 9,
                          color: Colors.white,
                        ),
                        SizedBox(width: 2),
                        Text(
                          "LIVE",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              room.hostUsername,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE11D48),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // 3. ZEV Internal Sponsored Campaign Story bubble
  Widget _buildSponsoredStoryItem(BuildContext context, ZevSponsoredAd ad) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        unawaited(
          ZevAdsService.instance.openAdDestination(
            context: context,
            slotKey: 'feed_stories_tray',
            ad: ad,
          ),
        );
      },
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF00D4FF),
                        Color(0xFF6366F1),
                        Color(0xFFF59E0B),
                      ],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: ad.mediaUrl.isNotEmpty
                        ? ZevCachedImage.avatar(
                            imageUrl: ad.mediaUrl,
                            size: 58,
                          )
                        : const Center(
                            child: Icon(
                              Icons.campaign_rounded,
                              size: 28,
                              color: ZevColors.primaryBlue,
                            ),
                          ),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF00D4FF)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1.6),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Text(
                      "Ad",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              ad.businessName.isNotEmpty ? ad.businessName : "Sponsored",
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: ZevColors.primaryBlue,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // 4. Google AdMob Native Partner Sponsor bubble
  Widget _buildAdMobStoryItem(BuildContext context) {
    return GestureDetector(
      onTap: () => _openAdMobStoryModal(context),
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF4285F4),
                        Color(0xFF34A853),
                        Color(0xFFFBBC05),
                        Color(0xFFEA4335),
                      ],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4285F4).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: const Center(
                      child: Icon(
                        Icons.star_rounded,
                        size: 28,
                        color: Color(0xFF4285F4),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1.6),
                    ),
                    child: const Text(
                      "AdMob",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              "Sponsored",
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4285F4),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _openAdMobStoryModal(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Sponsored',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Featured Partner',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const SizedBox(
              height: 340,
              child: ZevNativeAdStoryUnit(
                slotKey: 'stories_tray_partner_sheet',
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 5. Standard Friend Story bubble
  Widget _buildFriendStoryItem(BuildContext context, ActiveFriendStory story) {
    final bool isUnseen = story.hasUnseen;
    final bool isCloseFriend = story.hasCloseFriendStory;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (widget.onStoryTap != null) {
          widget.onStoryTap!(story);
        }
      },
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  padding: EdgeInsets.all(isUnseen ? 2.5 : 1.8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isUnseen
                        ? LinearGradient(
                            colors: isCloseFriend
                                ? const [Color(0xFF10B981), Color(0xFF00D4FF)]
                                : const [
                                    Color(0xFFFBAA47),
                                    Color(0xFFD91A46),
                                    Color(0xFFA60F93),
                                  ],
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                          )
                        : null,
                    color: isUnseen ? null : const Color(0xFFCBD5E1),
                    boxShadow: isUnseen
                        ? [
                            BoxShadow(
                              color: (isCloseFriend
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFD91A46))
                                  .withValues(alpha: 0.24),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: story.avatarUrl.isNotEmpty
                        ? ZevCachedImage.avatar(
                            imageUrl: story.avatarUrl,
                            size: 58,
                          )
                        : const Center(
                            child: Icon(
                              Icons.person_rounded,
                              size: 30,
                              color: ZevColors.textMuted,
                            ),
                          ),
                  ),
                ),
                if (isCloseFriend)
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.8),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.star_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              story.username,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isUnseen ? FontWeight.w700 : FontWeight.w600,
                color: isUnseen ? ZevColors.deepNavy : ZevColors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
