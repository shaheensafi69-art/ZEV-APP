import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_video_thumbnail.dart';
import '../../ads/screens/ads_manager_screen.dart';
import '../../feed/screens/drafts_scheduled_screen.dart';
import '../../feed/screens/post_detail_screen.dart';
import '../../reels/models/reel_item.dart';
import '../../reels/widgets/reel_player_item.dart';
import 'zev_blue_verification_screen.dart';

/// Light Clearmorphic Creator Insights & Professional Dashboard for ZEV.
/// Backed live by PostgreSQL `get_creator_insights(p_days)`.
class CreatorInsightsScreen extends StatefulWidget {
  final Map<String, dynamic>? userProfile;

  const CreatorInsightsScreen({
    super.key,
    this.userProfile,
  });

  static Future<void> open(
    BuildContext context, {
    Map<String, dynamic>? userProfile,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatorInsightsScreen(userProfile: userProfile),
      ),
    );
  }

  @override
  State<CreatorInsightsScreen> createState() => _CreatorInsightsScreenState();
}

class _CreatorInsightsScreenState extends State<CreatorInsightsScreen> {
  final _supabase = Supabase.instance.client;

  int _selectedDays = 30;
  bool _isLoading = true;
  String? _errorMsg;
  Map<String, dynamic>? _insights;
  Map<String, dynamic>? _myProfile;
  int? _selectedSeriesIndex;

  @override
  void initState() {
    super.initState();
    _myProfile = widget.userProfile != null
        ? Map<String, dynamic>.from(widget.userProfile!)
        : null;
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
      });
    }

    try {
      final uid = _supabase.auth.currentUser?.id;
      final futures = <Future<dynamic>>[
        _supabase.rpc('get_creator_insights', params: {'p_days': _selectedDays}),
        if (_myProfile == null && uid != null)
          _supabase.from('profiles').select().eq('id', uid).maybeSingle(),
      ];

      final results = await Future.wait<dynamic>(futures);
      final raw = results[0];
      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      if (results.length > 1 && results[1] is Map) {
        _myProfile = Map<String, dynamic>.from(results[1] as Map);
      }

      final series = (map['daily_series'] is List)
          ? (map['daily_series'] as List)
          : const [];

      if (!mounted) return;
      setState(() {
        _insights = map;
        _selectedSeriesIndex = series.isNotEmpty ? series.length - 1 : null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Load creator insights error: $e');
      if (!mounted) return;
      setState(() {
        _errorMsg = 'Could not load insights: $e';
        _isLoading = false;
      });
    }
  }

  String _compact(num v) {
    final n = v.toInt();
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  int _intVal(dynamic v) => (v as num?)?.toInt() ?? 0;
  double _doubleVal(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

  void _openVerificationCenter() async {
    Map<String, dynamic> profileMap = _myProfile ?? {};
    if (profileMap.isEmpty) {
      final uid = _supabase.auth.currentUser?.id;
      if (uid != null) {
        try {
          final res = await _supabase
              .from('profiles')
              .select()
              .eq('id', uid)
              .maybeSingle();
          if (res != null) {
            profileMap = Map<String, dynamic>.from(res);
            _myProfile = profileMap;
          }
        } catch (_) {}
      }
    }
    if (!mounted) return;
    await ZevBlueVerificationScreen.open(context, userProfile: profileMap);
    _loadInsights();
  }

  void _openReelPreview(Map<String, dynamic> raw) {
    final uid = _supabase.auth.currentUser?.id ?? '';
    final prof = _myProfile ?? const <String, dynamic>{};
    final fn = (prof['first_name'] ?? '').toString().trim();
    final ln = (prof['last_name'] ?? '').toString().trim();
    final full = '$fn $ln'.trim();
    final uname = (prof['username'] ?? 'creator').toString();

    final reel = ReelItem(
      id: raw['id']?.toString() ?? '',
      userId: uid,
      authorUsername: uname,
      authorFullName: full.isNotEmpty ? full : '@$uname',
      authorAvatar: (prof['avatar_url'] ?? '').toString(),
      isVerified: prof['is_verified'] == true,
      videoUrl: (raw['video_url'] ?? '').toString(),
      thumbnailUrl: raw['thumbnail_url']?.toString(),
      title: (raw['title'] ?? '').toString(),
      category: (raw['category'] ?? 'Explore').toString(),
      viewsCount: _intVal(raw['views_count']),
      likesCount: _intVal(raw['likes_count']),
      commentsCount: _intVal(raw['comments_count']),
      createdAt:
          DateTime.tryParse(raw['created_at']?.toString() ?? '') ??
              DateTime.now(),
    );

    bool muted = false;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (ctx, setPlayerState) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: const BackButton(color: Colors.white),
            ),
            body: ReelPlayerItem(
              reel: reel,
              isActive: true,
              isGlobalMuted: muted,
              onToggleMute: () => setPlayerState(() => muted = !muted),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          children: [
            Text(
              'Creator Insights',
              style: TextStyle(
                color: ZevColors.deepNavy,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Performance, audience & monetization',
              style: TextStyle(
                color: ZevColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: ZevColors.primaryBlue,
        onRefresh: _loadInsights,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
          children: [
            _buildRangeSelector(),
            const SizedBox(height: 14),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(
                  child: CircularProgressIndicator(
                    color: ZevColors.primaryBlue,
                  ),
                ),
              )
            else if (_errorMsg != null)
              _buildErrorCard()
            else
              _buildInsightsBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeSelector() {
    return _buildClayCard(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [7, 30, 90].map((days) {
          final selected = _selectedDays == days;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_selectedDays == days) return;
                HapticFeedback.selectionClick();
                setState(() => _selectedDays = days);
                _loadInsights();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  gradient: selected ? ZevColors.brandGradient : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color:
                                ZevColors.primaryBlue.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'Last ${days}d',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : ZevColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildErrorCard() {
    return _buildClayCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(
            Icons.analytics_outlined,
            size: 42,
            color: ZevColors.errorRed,
          ),
          const SizedBox(height: 12),
          const Text(
            'Unable to Load Analytics',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ZevColors.deepNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _errorMsg ?? 'Please try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: ZevColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadInsights,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ZevColors.secondaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsBody() {
    final overview = Map<String, dynamic>.from(
      (_insights?['overview'] as Map?) ?? const {},
    );
    final series = (_insights?['daily_series'] is List)
        ? (_insights!['daily_series'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final topPosts = (_insights?['top_posts'] is List)
        ? (_insights!['top_posts'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final topReels = (_insights?['top_reels'] is List)
        ? (_insights!['top_reels'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final monetization = Map<String, dynamic>.from(
      (_insights?['monetization'] as Map?) ?? const {},
    );

    final totalViews = _intVal(overview['total_views']);
    final periodViews = _intVal(overview['period_views']);
    final followers = _intVal(overview['followers_count']);
    final followersGained = _intVal(overview['followers_gained']);
    final engagementRate = _doubleVal(overview['engagement_rate']);
    final totalEngagements = _intVal(overview['total_engagements']);
    final totalPosts = _intVal(overview['total_posts']);
    final totalReels = _intVal(overview['total_reels']);
    final draftsCount = _intVal(overview['drafts_count']);
    final scheduledCount = _intVal(overview['scheduled_count']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. KPI Grid
        Row(
          children: [
            Expanded(
              child: _buildKpiTile(
                title: 'Total Views',
                value: _compact(totalViews),
                delta: '+${_compact(periodViews)} in ${_selectedDays}d',
                icon: Icons.visibility_rounded,
                accent: ZevColors.secondaryBlue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildKpiTile(
                title: 'Engagement Rate',
                value: '${engagementRate.toStringAsFixed(1)}%',
                delta: '${_compact(totalEngagements)} interactions',
                icon: Icons.bolt_rounded,
                accent: const Color(0xFF0EA5E9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildKpiTile(
                title: 'Audience',
                value: _compact(followers),
                delta: '+$followersGained in ${_selectedDays}d',
                icon: Icons.group_rounded,
                accent: const Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildKpiTile(
                title: 'Published',
                value: '${totalPosts + totalReels}',
                delta: '$totalPosts posts • $totalReels reels',
                icon: Icons.auto_awesome_mosaic_rounded,
                accent: ZevColors.successGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 2. Engagement Breakdown Strip
        _buildClayCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniMetric(
                Icons.favorite_rounded,
                const Color(0xFFEF4444),
                _compact(_intVal(overview['total_likes'])),
                'Likes',
              ),
              _buildMiniMetric(
                Icons.chat_bubble_rounded,
                ZevColors.secondaryBlue,
                _compact(_intVal(overview['total_comments'])),
                'Comments',
              ),
              _buildMiniMetric(
                Icons.repeat_rounded,
                const Color(0xFF10B981),
                _compact(_intVal(overview['total_reposts'])),
                'Reposts',
              ),
              _buildMiniMetric(
                Icons.bookmark_rounded,
                const Color(0xFF6366F1),
                _compact(_intVal(overview['total_bookmarks'])),
                'Saved',
              ),
              _buildMiniMetric(
                Icons.send_rounded,
                const Color(0xFFF59E0B),
                _compact(_intVal(overview['total_shares'])),
                'Shares',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Daily Series Interactive Bar Chart
        _buildDailyChartCard(series),
        const SizedBox(height: 14),

        // 4. Drafts & Scheduled Quick Card
        _buildDraftsQueueCard(draftsCount, scheduledCount),
        const SizedBox(height: 14),

        // 5. Top Performing Posts
        _buildSectionTitle('TOP PERFORMING POSTS'),
        if (topPosts.isEmpty)
          _buildEmptySubcard('Publish posts to track top performing content.')
        else
          ...topPosts.map(_buildTopPostRow),
        const SizedBox(height: 14),

        // 6. Top Performing Reels
        _buildSectionTitle('TOP PERFORMING REELS'),
        if (topReels.isEmpty)
          _buildEmptySubcard('Upload reels to view watch and like analytics.')
        else
          ...topReels.map(_buildTopReelRow),
        const SizedBox(height: 14),

        // 7. Monetization, Verification & Ads Summary
        _buildSectionTitle('MONETIZATION & GROWTH'),
        _buildMonetizationCard(monetization),
      ],
    );
  }

  Widget _buildKpiTile({
    required String title,
    required String value,
    required String delta,
    required IconData icon,
    required Color accent,
  }) {
    return _buildClayCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            delta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(
    IconData icon,
    Color color,
    String value,
    String label,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: ZevColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyChartCard(List<Map<String, dynamic>> series) {
    if (series.isEmpty) {
      return _buildEmptySubcard('Daily traffic chart will populate as views arrive.');
    }

    // Show up to the most recent 14 days on screen for crisp tap targets
    final visible =
        series.length > 14 ? series.sublist(series.length - 14) : series;
    final selectedIdx = (_selectedSeriesIndex != null &&
            _selectedSeriesIndex! >= 0 &&
            _selectedSeriesIndex! < visible.length)
        ? _selectedSeriesIndex!
        : visible.length - 1;
    final selectedDay = visible[selectedIdx];
    final maxViews = visible.fold<int>(
      1,
      (prev, item) => math.max(prev, _intVal(item['views'])),
    );

    return _buildClayCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Daily Reach Trend',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: ZevColors.primaryBlue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${selectedDay['date'] ?? selectedDay['label']}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.secondaryBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_intVal(selectedDay['views'])} views '
            '(${_intVal(selectedDay['post_views'])} posts • '
            '${_intVal(selectedDay['reel_views'])} reels) • '
            '+${_intVal(selectedDay['followers_gained'])} followers',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ZevColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(visible.length, (i) {
                final item = visible[i];
                final views = _intVal(item['views']);
                final ratio =
                    maxViews <= 0 ? 0.08 : (views / maxViews).clamp(0.08, 1.0);
                final isSelected = i == selectedIdx;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedSeriesIndex = i);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            height: 92 * ratio,
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? ZevColors.brandGradient
                                  : LinearGradient(
                                      colors: [
                                        ZevColors.primaryBlue
                                            .withValues(alpha: 0.42),
                                        ZevColors.secondaryBlue
                                            .withValues(alpha: 0.35),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            (item['label'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? ZevColors.deepNavy
                                  : ZevColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftsQueueCard(int draftsCount, int scheduledCount) {
    return GestureDetector(
      onTap: () async {
        await DraftsScheduledScreen.open(context);
        _loadInsights();
      },
      child: _buildClayCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ZevColors.secondaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.schedule_send_rounded,
                color: ZevColors.secondaryBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Drafts & Scheduled Posts',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$draftsCount drafts • $scheduledCount scheduled in queue',
                    style: const TextStyle(
                      fontSize: 12,
                      color: ZevColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: ZevColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPostRow(Map<String, dynamic> post) {
    final postId = post['id']?.toString() ?? '';
    final imageUrl = (post['image_url'] ?? '').toString();
    final content = (post['content'] ?? '').toString();
    final title = (post['title'] ?? '').toString();
    final displayText =
        content.isNotEmpty ? content : (title.isNotEmpty ? title : 'ZEV Post');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: postId.isEmpty
            ? null
            : () => PostDetailScreen.open(context, postId: postId),
        child: _buildClayCard(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: imageUrl.isNotEmpty
                      ? ZevCachedImage.grid(imageUrl: imageUrl)
                      : Container(
                          color: ZevColors.softSurface,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.article_rounded,
                            color: ZevColors.secondaryBlue,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_compact(_intVal(post['views_count']))} views • '
                      '${_compact(_intVal(post['likes_count']))} likes • '
                      '${_compact(_intVal(post['comments_count']))} comments',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: ZevColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: ZevColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopReelRow(Map<String, dynamic> reel) {
    final thumbUrl = (reel['thumbnail_url'] ?? '').toString();
    final videoUrl = (reel['video_url'] ?? '').toString();
    final title = (reel['title'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: videoUrl.isEmpty ? null : () => _openReelPreview(reel),
        child: _buildClayCard(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 54,
                  height: 68,
                  child: ZevVideoThumbnail(
                    videoUrl: videoUrl,
                    thumbnailUrl: thumbUrl.isNotEmpty ? thumbUrl : null,
                    showPlayBadge: true,
                    showViews: false,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isNotEmpty ? title : 'ZEV Reel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_compact(_intVal(reel['views_count']))} views • '
                      '${_compact(_intVal(reel['likes_count']))} likes • '
                      '${_compact(_intVal(reel['shares_count']))} shares',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: ZevColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.play_circle_outline_rounded,
                color: ZevColors.secondaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonetizationCard(Map<String, dynamic> m) {
    final isVerified = m['is_verified'] == true;
    final referrals = _intVal(m['referral_count']);
    final lifetimeEligible = m['lifetime_blue_eligible'] == true;
    final sub = m['subscription'] is Map
        ? Map<String, dynamic>.from(m['subscription'] as Map)
        : null;
    final ads = m['ads'] is Map
        ? Map<String, dynamic>.from(m['ads'] as Map)
        : const <String, dynamic>{};

    final planType = (sub?['plan_type'] ?? '').toString();
    final subActive = sub?['is_active'] == true;
    final referralProgress = (referrals / 100.0).clamp(0.0, 1.0);

    final adBalance = _doubleVal(ads['balance']);
    final adImpressions = _intVal(ads['total_impressions']);
    final adClicks = _intVal(ads['total_clicks']);
    final adCampaigns = _intVal(ads['campaigns_count']);

    return Column(
      children: [
        GestureDetector(
          onTap: _openVerificationCenter,
          child: _buildClayCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        gradient: ZevColors.brandGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isVerified
                                ? 'ZEV Blue Active'
                                : (lifetimeEligible
                                    ? 'Eligible for Free Lifetime Blue'
                                    : 'ZEV Blue Verification'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subActive && planType.isNotEmpty
                                ? 'Plan: ${planType.toUpperCase()} • $referrals/100 referrals'
                                : '$referrals / 100 verified referrals toward Free Lifetime Blue',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: ZevColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: ZevColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: referralProgress,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      ZevColors.secondaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => AdsManagerScreen.open(context),
          child: _buildClayCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: Color(0xFF0284C7),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ZEV Ads Manager',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$adCampaigns campaigns • ${_compact(adImpressions)} impressions • '
                        '${_compact(adClicks)} clicks • \$${adBalance.toStringAsFixed(2)} balance',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: ZevColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: ZevColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptySubcard(String text) {
    return _buildClayCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12.5,
          color: ZevColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF94A3B8),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildClayCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: child,
    );
  }
}
