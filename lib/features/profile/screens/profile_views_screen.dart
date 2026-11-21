import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/profile_views_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_skeleton.dart';
import 'profile_screen.dart';

/// TikTok-Grade Profile Views Screen for ZEV.
/// Shows visitors who viewed the user's profile in the past 30 days,
/// with instant follow/following toggles, visit timestamps, and verified badges.
class ProfileViewsScreen extends StatefulWidget {
  const ProfileViewsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileViewsScreen()),
    );
  }

  @override
  State<ProfileViewsScreen> createState() => _ProfileViewsScreenState();
}

class _ProfileViewsScreenState extends State<ProfileViewsScreen> {
  bool _isLoading = true;
  int _viewsCount = 0;
  List<Map<String, dynamic>> _viewers = [];
  final Set<String> _busyFollowIds = {};

  @override
  void initState() {
    super.initState();
    _fetchProfileViews();
  }

  Future<void> _fetchProfileViews() async {
    try {
      final res = await ProfileViewsService.instance.getProfileViews30Days();
      if (!mounted) return;
      setState(() {
        _viewsCount = (res['count'] as int?) ?? 0;
        _viewers = (res['viewers'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[ProfileViewsScreen] fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollowUser(Map<String, dynamic> viewer) async {
    final viewerId = viewer['viewer_id']?.toString() ?? '';
    if (viewerId.isEmpty || _busyFollowIds.contains(viewerId)) return;

    HapticFeedback.lightImpact();
    final currentFollowing = viewer['is_following'] == true;

    // Optimistic toggle
    setState(() {
      _busyFollowIds.add(viewerId);
      viewer['is_following'] = !currentFollowing;
    });

    try {
      final status = await SocialGraphService.instance.toggleFollow(viewerId);
      if (!mounted) return;
      setState(() {
        viewer['is_following'] = (status == FollowToggleStatus.following);
        _busyFollowIds.remove(viewerId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        viewer['is_following'] = currentFollowing;
        _busyFollowIds.remove(viewerId);
      });
    }
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.remove_red_eye_rounded, color: ZevColors.primaryBlue),
            SizedBox(width: 8),
            Text(
              'Profile Views',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: ZevColors.deepNavy,
              ),
            ),
          ],
        ),
        content: const Text(
          '• Only you can see who viewed your profile in the past 30 days.\n\n'
          '• Only people who visited your profile within the last 30 days are displayed.\n\n'
          '• Records are securely encrypted and automatically expire after 30 days.',
          style: TextStyle(
            fontSize: 13.5,
            color: ZevColors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Got it',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: ZevColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile Views',
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w900,
            fontSize: 17,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.info_outline_rounded,
              color: ZevColors.deepNavy,
              size: 22,
            ),
            tooltip: 'Profile views info',
            onPressed: _showInfoDialog,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 680 : double.infinity,
            ),
            child: RefreshIndicator(
              color: ZevColors.primaryBlue,
              onRefresh: _fetchProfileViews,
              child: _isLoading
                  ? _buildLoadingShimmer()
                  : _viewers.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                          itemCount: _viewers.length + 1,
                          separatorBuilder: (_, index) {
                            if (index == 0) return const SizedBox(height: 12);
                            return const SizedBox(height: 8);
                          },
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _buildTopNoticeCard();
                            }
                            final viewer = _viewers[index - 1];
                            return _buildViewerCard(viewer);
                          },
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopNoticeCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: ZevColors.brandGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: ZevColors.secondaryBlue.withValues(alpha: 0.28),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.remove_red_eye_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$_viewsCount views',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Past 30 days',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: ZevColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Only you can see who viewed your profile. Viewers are ordered by latest visit.',
                  style: TextStyle(
                    fontSize: 12,
                    color: ZevColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewerCard(Map<String, dynamic> viewer) {
    final viewerId = viewer['viewer_id']?.toString() ?? '';
    final username = viewer['username']?.toString() ?? 'user';
    final fullName = viewer['full_name']?.toString() ?? '';
    final avatarUrl = viewer['avatar_url']?.toString() ?? '';
    final isVerified = viewer['is_verified'] == true;
    final isFollowing = viewer['is_following'] == true;
    final viewedAtStr = viewer['viewed_at']?.toString() ?? '';
    final viewedAt = DateTime.tryParse(viewedAtStr) ?? DateTime.now();
    final timeStr = TimeAgo.format(viewedAt);
    final isBusy = _busyFollowIds.contains(viewerId);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (viewerId.isNotEmpty) {
            ProfileScreen.open(context, userId: viewerId);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.025),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                ),
                child: ClipOval(
                  child: avatarUrl.isNotEmpty
                      ? ZevCachedImage.avatar(
                          imageUrl: avatarUrl,
                          size: 48,
                        )
                      : Container(
                          color: const Color(0xFFF1F5F9),
                          child: const Icon(
                            Icons.person,
                            color: ZevColors.textMuted,
                            size: 26,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // Names & Time Ago
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            fullName.isNotEmpty ? fullName : '@$username',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: ZevColors.primaryBlue,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (fullName.isNotEmpty) ...[
                          Text(
                            '@$username',
                            style: const TextStyle(
                              fontSize: 12,
                              color: ZevColors.textSecondary,
                            ),
                          ),
                          const Text(
                            ' • ',
                            style: TextStyle(
                              fontSize: 12,
                              color: ZevColors.textMuted,
                            ),
                          ),
                        ],
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: ZevColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Follow / Following Action Button
              SizedBox(
                height: 34,
                child: ElevatedButton(
                  onPressed: isBusy ? null : () => _toggleFollowUser(viewer),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFollowing
                        ? const Color(0xFFF1F5F9)
                        : ZevColors.primaryBlue,
                    foregroundColor: isFollowing
                        ? ZevColors.deepNavy
                        : Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ZevColors.primaryBlue,
                          ),
                        )
                      : Text(
                          isFollowing ? 'Following' : 'Follow',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: isFollowing
                                ? ZevColors.deepNavy
                                : Colors.white,
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
              ),
              child: const Icon(
                Icons.visibility_off_outlined,
                size: 38,
                color: ZevColors.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Profile Views Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'When other people view your profile in the past 30 days, they will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ZevColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Row(
          children: [
            const ZevSkeleton(width: 48, height: 48, shape: BoxShape.circle),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ZevSkeleton(
                    width: 130,
                    height: 14,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(height: 6),
                  ZevSkeleton(
                    width: 80,
                    height: 11,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ZevSkeleton(
              width: 72,
              height: 32,
              borderRadius: BorderRadius.circular(10),
            ),
          ],
        ),
      ),
    );
  }
}
