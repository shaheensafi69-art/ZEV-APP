import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_skeleton.dart';
import '../../../core/widgets/zev_video_thumbnail.dart';
import '../../feed/models/feed_post_item.dart';
import '../../feed/widgets/feed_post_card.dart';
import '../../reels/models/reel_item.dart';
import '../../reels/widgets/reel_player_item.dart';

/// Light Clearmorphic Hashtag Discovery Feed Screen for ZEV.
/// Backed by PostgreSQL `get_hashtag_content(p_tag, p_limit)` with live tabs
/// for All, Reels, and Posts.
class HashtagFeedScreen extends StatefulWidget {
  final String tag;

  const HashtagFeedScreen({super.key, required this.tag});

  static Future<void> open(
    BuildContext context, {
    required String tag,
  }) async {
    final clean = tag.trim().replaceFirst(RegExp(r'^#+'), '');
    if (clean.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HashtagFeedScreen(tag: clean)),
    );
  }

  @override
  State<HashtagFeedScreen> createState() => _HashtagFeedScreenState();
}

class _HashtagFeedScreenState extends State<HashtagFeedScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMsg;
  int _selectedTab = 0; // 0: All, 1: Reels, 2: Posts

  String _resolvedTag = '';
  int _postsCount = 0;
  int _reelsCount = 0;
  List<FeedPostItem> _posts = [];
  List<ReelItem> _reels = [];

  String get _cleanTag => widget.tag.trim().replaceFirst(RegExp(r'^#+'), '');

  @override
  void initState() {
    super.initState();
    _resolvedTag = _cleanTag;
    _fetchHashtagContent();
  }

  Future<void> _fetchHashtagContent() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
      });
    }

    try {
      final raw = await _supabase.rpc(
        'get_hashtag_content',
        params: {'p_tag': _cleanTag, 'p_limit': 40},
      );

      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      final postsRaw = (map['posts'] is List)
          ? (map['posts'] as List)
              .whereType<Map>()
              .map((m) => FeedPostItem.fromRpcMap(Map<String, dynamic>.from(m)))
              .where((p) => p.id.isNotEmpty)
              .toList()
          : <FeedPostItem>[];

      final reelsRaw = (map['reels'] is List)
          ? (map['reels'] as List)
              .whereType<Map>()
              .map((m) => ReelItem.fromRpcMap(Map<String, dynamic>.from(m)))
              .where((r) => r.id.isNotEmpty)
              .toList()
          : <ReelItem>[];

      if (!mounted) return;
      setState(() {
        _resolvedTag = (map['tag']?.toString().isNotEmpty == true)
            ? map['tag'].toString()
            : _cleanTag;
        _postsCount = (map['posts_count'] as num?)?.toInt() ?? postsRaw.length;
        _reelsCount = (map['reels_count'] as num?)?.toInt() ?? reelsRaw.length;
        _posts = postsRaw;
        _reels = reelsRaw;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Hashtag feed fetch error: $e');
      if (!mounted) return;
      setState(() {
        _errorMsg = 'Could not load #$_cleanTag content.';
        _isLoading = false;
      });
    }
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return '$count';
  }

  void _openReelPlayer(ReelItem reel) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              reel.title.isNotEmpty ? reel.title : '#$_resolvedTag Reel',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          body: ReelPlayerItem(
            reel: reel,
            isActive: true,
            isGlobalMuted: false,
            onToggleMute: () {},
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
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '#$_resolvedTag',
          style: const TextStyle(
            color: ZevColors.deepNavy,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(
              Icons.refresh_rounded,
              color: ZevColors.deepNavy,
              size: 21,
            ),
            onPressed: _fetchHashtagContent,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: ZevColors.primaryBlue,
        onRefresh: _fetchHashtagContent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _buildHeaderCard()),
            SliverToBoxAdapter(child: _buildFilterTabs()),
            if (_isLoading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, _) => const ZevFeedCardSkeleton(),
                  childCount: 3,
                ),
              )
            else if (_errorMsg != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildErrorState(),
              )
            else if (_posts.isEmpty && _reels.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(
                  'No posts or reels for #$_resolvedTag yet.',
                ),
              )
            else if (_selectedTab == 1)
              ..._buildReelsOnlySlivers()
            else if (_selectedTab == 2)
              ..._buildPostsOnlySlivers()
            else
              ..._buildAllSlivers(),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final total = _postsCount + _reelsCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ZevColors.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.045),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: ZevColors.brandGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: ZevColors.primaryBlue.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                '#',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#$_resolvedTag',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatCount(total)} total  •  ${_formatCount(_postsCount)} posts  •  ${_formatCount(_reelsCount)} reels',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final labels = [
      'All (${_posts.length + _reels.length})',
      'Reels (${_reels.length})',
      'Posts (${_posts.length})',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = _selectedTab == i;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedTab = i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? ZevColors.primaryBlue : ZevColors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: active ? ZevColors.primaryBlue : ZevColors.border,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: ZevColors.primaryBlue.withValues(
                                alpha: 0.28,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: active
                            ? ZevColors.deepNavy
                            : ZevColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  List<Widget> _buildAllSlivers() {
    final slivers = <Widget>[];
    if (_reels.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Featured Reels',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                  ),
                ),
              ),
              SizedBox(
                height: 185,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _reels.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, idx) => SizedBox(
                    width: 118,
                    child: _buildReelTile(_reels[idx]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    }

    if (_posts.isNotEmpty) {
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, idx) => _buildPostCard(_posts[idx]),
            childCount: _posts.length,
          ),
        ),
      );
    }
    return slivers;
  }

  List<Widget> _buildReelsOnlySlivers() {
    if (_reels.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyState('No reels with #$_resolvedTag yet.'),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.7,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, idx) => _buildReelTile(_reels[idx]),
            childCount: _reels.length,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildPostsOnlySlivers() {
    if (_posts.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyState('No posts with #$_resolvedTag yet.'),
        ),
      ];
    }

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, idx) => _buildPostCard(_posts[idx]),
          childCount: _posts.length,
        ),
      ),
    ];
  }

  Widget _buildReelTile(ReelItem reel) {
    return GestureDetector(
      onTap: () => _openReelPlayer(reel),
      child: Container(
        decoration: BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZevColors.border, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: ZevColors.deepNavy.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ZevVideoThumbnail(
                videoUrl: reel.videoUrl,
                thumbnailUrl: reel.thumbnailUrl,
                viewsCount: reel.viewsCount,
                showPlayBadge: true,
                showViews: false,
                borderRadius: BorderRadius.circular(15),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Row(
                  children: [
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _formatCount(reel.viewsCount),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostCard(FeedPostItem post) {
    return FeedPostCard(
      key: ValueKey(post.id),
      post: post,
      onCommentsUpdated: _fetchHashtagContent,
      onPostUpdated: (updated) {
        setState(() {
          final idx = _posts.indexWhere((p) => p.id == updated.id);
          if (idx != -1) _posts[idx] = updated;
        });
      },
      onHideOrMute: () {
        setState(() {
          _posts.removeWhere((p) => p.id == post.id);
        });
      },
      onPostDeleted: () {
        setState(() {
          _posts.removeWhere((p) => p.id == post.id);
        });
      },
    );
  }

  Widget _buildEmptyState(String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: ZevColors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: ZevColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.tag_rounded,
                size: 40,
                color: ZevColors.primaryBlue,
              ),
              const SizedBox(height: 12),
              Text(
                '#$_resolvedTag',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: ZevColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: ZevColors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: ZevColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: ZevColors.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                _errorMsg ?? 'Could not load hashtag feed.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: ZevColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _fetchHashtagContent,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
