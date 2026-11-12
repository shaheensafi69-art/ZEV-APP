import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/feed_algorithm_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/services/zev_ads_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_native_ad_card.dart';
import '../../../core/widgets/zev_skeleton.dart';
import '../../../core/widgets/zev_video_thumbnail.dart';
import '../../discover/screens/discover_screen.dart';
import '../../discover/screens/hashtag_feed_screen.dart';
import '../../feed/models/feed_post_item.dart';
import '../../feed/widgets/feed_post_card.dart';
import '../../feed/widgets/feed_share_sheet.dart';
import '../../profile/screens/profile_screen.dart';
import '../../reels/models/reel_item.dart';
import '../../reels/widgets/reel_player_item.dart';

/// Unified Explore Item representation combining Posts and Reels for ZEV Explore.
class ExploreGridItem {
  final String id;
  final String rawId;
  final String type; // 'post' | 'reel'
  final String mediaUrl;
  final String? thumbnailUrl;
  final String title;
  final String? description;
  final String? category;
  final String authorId;
  final String authorUsername;
  final String authorFullName;
  final String authorAvatar;
  final bool isVerified;
  final int viewsCount;
  final int likesCount;
  final FeedPostItem? post;
  final ReelItem? reel;

  const ExploreGridItem({
    required this.id,
    required this.rawId,
    required this.type,
    required this.mediaUrl,
    this.thumbnailUrl,
    required this.title,
    this.description,
    this.category,
    required this.authorId,
    required this.authorUsername,
    this.authorFullName = '',
    required this.authorAvatar,
    this.isVerified = false,
    this.viewsCount = 0,
    this.likesCount = 0,
    this.post,
    this.reel,
  });

  bool get isReel => type == 'reel';
}

/// Lightweight video grid tile powered by [ZevVideoThumbnail].
class ExploreVideoTile extends StatelessWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final bool autoPlay;
  final int? viewsCount;

  const ExploreVideoTile({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.autoPlay = false,
    this.viewsCount,
  });

  @override
  Widget build(BuildContext context) {
    return ZevVideoThumbnail(
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      autoPlay: autoPlay,
      viewsCount: viewsCount,
      fit: BoxFit.cover,
    );
  }
}

/// Flagship Light Clearmorphic Explore & Unified Search Screen for ZEV.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _gridScrollCtrl = ScrollController();

  static const int _pageSize = 36;
  List<ExploreGridItem> _items = [];
  final Set<String> _loadedIds = <String>{};
  int _offset = 0;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _feedGeneration = 0;
  String _selectedCategory = "For You";

  // Discovery / Recent Searches & Hashtags state
  bool _isSearchFocused = false;
  List<Map<String, dynamic>> _recentSearches = [];
  List<Map<String, dynamic>> _trendingHashtags = [];
  bool _isDiscoveryPanelLoading = false;

  // Live Unified Search state
  bool _isSearching = false;
  int _searchTab = 0; // 0: Accounts, 1: Reels, 2: Posts, 3: #Tags
  bool _isSearchLoading = false;
  int _searchGeneration = 0;
  List<Map<String, dynamic>> _searchedAccounts = [];
  List<ReelItem> _searchedReels = [];
  List<FeedPostItem> _searchedPosts = [];
  List<Map<String, dynamic>> _searchedHashtags = [];
  final Set<String> _busyAccountIds = <String>{};
  Timer? _debounceTimer;

  final List<String> _categories = [
    "For You",
    "Trending",
    "Reels",
    "Posts",
    "Technology",
    "Design & Art",
    "Photography",
    "Fitness",
    "Travel",
    "Music",
    "Quotes",
  ];

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_handleSearchFocusChanged);
    _gridScrollCtrl.addListener(_handleGridScroll);
    _fetchExploreFeed(refresh: true);
    _loadDiscoveryPanelData();
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_handleSearchFocusChanged);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _gridScrollCtrl.removeListener(_handleGridScroll);
    _gridScrollCtrl.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _handleSearchFocusChanged() {
    if (!mounted) return;
    setState(() {
      _isSearchFocused = _searchFocus.hasFocus;
    });
    if (_searchFocus.hasFocus && _searchCtrl.text.trim().isEmpty) {
      _loadDiscoveryPanelData();
    }
  }

  void _handleGridScroll() {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    if (_gridScrollCtrl.position.pixels >=
        _gridScrollCtrl.position.maxScrollExtent - 500) {
      _fetchExploreFeed(refresh: false);
    }
  }

  Future<void> _loadDiscoveryPanelData() async {
    if (mounted) {
      setState(() => _isDiscoveryPanelLoading = true);
    }
    try {
      final isAuthed = supabase.auth.currentUser != null;
      final futures = <Future<dynamic>>[
        supabase.rpc('get_trending_hashtags', params: {'p_limit': 12}),
        if (isAuthed)
          supabase.rpc('get_recent_searches', params: {'p_limit': 15}),
      ];
      final res = await Future.wait<dynamic>(futures);

      final tagsRaw = res[0] is List
          ? List<Map<String, dynamic>>.from(
              (res[0] as List).map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : <Map<String, dynamic>>[];

      final recentRaw = (isAuthed && res.length > 1 && res[1] is List)
          ? List<Map<String, dynamic>>.from(
              (res[1] as List).map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : <Map<String, dynamic>>[];

      if (mounted) {
        setState(() {
          _trendingHashtags = tagsRaw;
          _recentSearches = recentRaw;
          _isDiscoveryPanelLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Explore discovery panel warning: $e");
      if (mounted) {
        setState(() => _isDiscoveryPanelLoading = false);
      }
    }
  }

  Future<void> _fetchExploreFeed({bool refresh = true}) async {
    if (refresh) {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _isLoadingMore = false;
          _offset = 0;
          _hasMore = true;
          _loadedIds.clear();
        });
      }
    } else {
      if (_isLoadingMore || !_hasMore) return;
      if (mounted) {
        setState(() => _isLoadingMore = true);
      }
    }

    final int generation = refresh ? ++_feedGeneration : _feedGeneration;
    final int reqOffset = refresh ? 0 : _offset;

    try {
      final rawRes = await supabase.rpc(
        'get_explore_grid_page',
        params: {
          'p_category': _selectedCategory,
          'p_offset': reqOffset,
          'p_limit': _pageSize,
        },
      );

      if (generation != _feedGeneration) return;

      final rows = rawRes is List
          ? List<Map<String, dynamic>>.from(
              rawRes.map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : <Map<String, dynamic>>[];

      final List<ExploreGridItem> pageItems = [];
      for (final row in rows) {
        final itemId = row['item_id']?.toString() ?? '';
        final rawId = row['raw_id']?.toString() ?? '';
        if (itemId.isEmpty || rawId.isEmpty || _loadedIds.contains(itemId)) {
          continue;
        }
        _loadedIds.add(itemId);

        final itemType = row['item_type']?.toString() ?? 'post';
        final fn = (row['author_first_name'] ?? '').toString();
        final ln = (row['author_last_name'] ?? '').toString();
        final fullName = '$fn $ln'.trim();
        final username = (row['author_username'] ?? '').toString();
        final authorId = row['author_id']?.toString() ?? '';
        final avatarUrl = (row['author_avatar_url'] ?? '').toString();
        final isVerified = row['author_is_verified'] == true;
        final mediaUrl = (row['media_url'] ?? '').toString();
        final thumbUrl = row['thumbnail_url']?.toString();
        final title = (row['title'] ?? '').toString();
        final description = (row['description'] ?? '').toString();
        final category = (row['category'] ?? 'Explore').toString();
        final viewsCount = (row['views_count'] as num?)?.toInt() ?? 0;
        final likesCount = (row['likes_count'] as num?)?.toInt() ?? 0;
        final commentsCount = (row['comments_count'] as num?)?.toInt() ?? 0;
        final repostsCount = (row['reposts_count'] as num?)?.toInt() ?? 0;
        final createdAt =
            DateTime.tryParse(row['created_at']?.toString() ?? '') ??
            DateTime.now();

        ReelItem? reelItem;
        FeedPostItem? postItem;

        if (itemType == 'reel') {
          reelItem = ReelItem(
            id: rawId,
            userId: authorId,
            authorUsername: username.isNotEmpty ? username : 'creator',
            authorFullName: fullName,
            authorAvatar: avatarUrl,
            isVerified: isVerified,
            videoUrl: mediaUrl,
            thumbnailUrl: thumbUrl,
            title: title,
            description: description,
            category: category,
            viewsCount: viewsCount,
            likesCount: likesCount,
            isLikedByMe: row['is_liked_by_me'] == true,
            commentsCount: commentsCount,
            isBookmarkedByMe: row['is_bookmarked_by_me'] == true,
            isAuthorFollowed: row['is_author_followed'] == true,
            createdAt: createdAt,
          );
        } else {
          postItem = FeedPostItem(
            id: rawId,
            authorId: authorId,
            authorUsername: username.isNotEmpty
                ? username
                : (fullName.isNotEmpty ? fullName : 'user'),
            authorFullName: fullName,
            authorAvatar: avatarUrl,
            isVerified: isVerified,
            title: title,
            content: description,
            imageUrl: mediaUrl,
            createdAt: createdAt,
            likesCount: likesCount,
            isLikedByMe: row['is_liked_by_me'] == true,
            commentsCount: commentsCount,
            repostsCount: repostsCount,
            isRepostedByMe: row['is_reposted_by_me'] == true,
            isBookmarkedByMe: row['is_bookmarked_by_me'] == true,
            isAuthorFollowed: row['is_author_followed'] == true,
          );
        }

        pageItems.add(
          ExploreGridItem(
            id: itemId,
            rawId: rawId,
            type: itemType,
            mediaUrl: mediaUrl,
            thumbnailUrl: thumbUrl,
            title: title,
            description: description,
            category: category,
            authorId: authorId,
            authorUsername: username.isNotEmpty ? username : 'user',
            authorFullName: fullName,
            authorAvatar: avatarUrl,
            isVerified: isVerified,
            viewsCount: viewsCount,
            likesCount: likesCount,
            reel: reelItem,
            post: postItem,
          ),
        );
      }

      if (mounted && generation == _feedGeneration) {
        setState(() {
          if (refresh) {
            _items = pageItems;
          } else {
            _items = [..._items, ...pageItems];
          }
          _offset = reqOffset + rows.length;
          _hasMore = rows.length >= _pageSize;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint("Explore feed fetch error: $e");
      if (mounted && generation == _feedGeneration) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _saveSearchHistory(
    String query, {
    String searchType = 'all',
    String? targetId,
  }) async {
    if (supabase.auth.currentUser == null || query.trim().isEmpty) return;
    try {
      await supabase.rpc(
        'save_search_history',
        params: {
          'p_query': query.trim(),
          'p_search_type': searchType,
          'p_target_id': targetId,
        },
      );
      _loadDiscoveryPanelData();
    } catch (_) {}
  }

  Future<void> _clearSearchHistory({String? id}) async {
    if (supabase.auth.currentUser == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (id == null) {
        _recentSearches = [];
      } else {
        _recentSearches.removeWhere((r) => r['id']?.toString() == id);
      }
    });
    try {
      await supabase.rpc(
        'clear_search_history',
        params: {'p_id': id},
      );
    } catch (_) {}
  }

  void _onSearchQueryChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchedAccounts = [];
        _searchedReels = [];
        _searchedPosts = [];
        _searchedHashtags = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isSearchLoading = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 280), () {
      _executeSearch(query.trim());
    });
  }

  Future<void> _executeSearch(String query) async {
    final int gen = ++_searchGeneration;
    try {
      final raw = await supabase.rpc(
        'search_unified_content',
        params: {'p_query': query, 'p_limit': 25},
      );

      if (gen != _searchGeneration) return;

      final Map<String, dynamic> data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      final accountsRaw = data['accounts'] is List
          ? List<Map<String, dynamic>>.from(
              (data['accounts'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            )
          : <Map<String, dynamic>>[];

      final reelsRaw = data['reels'] is List
          ? (data['reels'] as List)
                .map((e) => ReelItem.fromRpcMap(Map<String, dynamic>.from(e as Map)))
                .toList()
          : <ReelItem>[];

      final postsRaw = data['posts'] is List
          ? (data['posts'] as List)
                .map((e) => FeedPostItem.fromRpcMap(Map<String, dynamic>.from(e as Map)))
                .toList()
          : <FeedPostItem>[];

      final tagsRaw = data['hashtags'] is List
          ? List<Map<String, dynamic>>.from(
              (data['hashtags'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            )
          : <Map<String, dynamic>>[];

      if (mounted && gen == _searchGeneration) {
        setState(() {
          _searchedAccounts = accountsRaw;
          _searchedReels = reelsRaw;
          _searchedPosts = postsRaw;
          _searchedHashtags = tagsRaw;
          _isSearchLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Execute unified search error: $e");
      if (mounted && gen == _searchGeneration) {
        setState(() => _isSearchLoading = false);
      }
    }
  }

  Future<void> _toggleSearchAccountFollow(int index) async {
    final user = _searchedAccounts[index];
    final targetId = user['id']?.toString() ?? '';
    if (targetId.isEmpty || _busyAccountIds.contains(targetId)) return;

    HapticFeedback.lightImpact();
    setState(() => _busyAccountIds.add(targetId));

    final status = await SocialGraphService.instance.toggleFollow(targetId);

    if (!mounted) return;
    setState(() {
      _busyAccountIds.remove(targetId);
      final updated = Map<String, dynamic>.from(_searchedAccounts[index]);
      switch (status) {
        case FollowToggleStatus.following:
          updated['is_following'] = true;
          updated['is_requested'] = false;
          break;
        case FollowToggleStatus.requested:
          updated['is_following'] = false;
          updated['is_requested'] = true;
          break;
        case FollowToggleStatus.unfollowed:
        case FollowToggleStatus.cancelled:
          updated['is_following'] = false;
          updated['is_requested'] = false;
          break;
        case FollowToggleStatus.blocked:
        case FollowToggleStatus.error:
          break;
      }
      _searchedAccounts[index] = updated;
    });
  }

  void _openDetail(ExploreGridItem item) {
    HapticFeedback.lightImpact();
    if (item.isReel && item.reel != null) {
      FeedAlgorithmService.instance.markReelSeen(item.reel!.id);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(
                item.title.isNotEmpty ? item.title : "Reel",
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              elevation: 0,
            ),
            body: ReelPlayerItem(
              reel: item.reel!,
              isActive: true,
              isGlobalMuted: false,
              onToggleMute: () {},
              onHideOrMute: () {
                if (Navigator.canPop(context)) Navigator.of(context).pop();
                setState(() {
                  _items.removeWhere((i) => i.id == item.id);
                });
              },
              onReelDeleted: () {
                if (Navigator.canPop(context)) Navigator.of(context).pop();
                _fetchExploreFeed(refresh: true);
              },
            ),
          ),
        ),
      );
    } else if (item.post != null) {
      FeedAlgorithmService.instance.markSeen(item.post!.id);
      if (supabase.auth.currentUser != null) {
        unawaited(
          Future<void>.microtask(() async {
            try {
              await supabase.rpc(
                'record_post_view',
                params: {'p_post_id': item.post!.id},
              );
            } catch (_) {}
          }),
        );
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: const Color(0xFFF1F5F9),
            appBar: AppBar(
              backgroundColor: Colors.white,
              foregroundColor: ZevColors.deepNavy,
              title: const Text(
                "Explore Post",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              elevation: 0.5,
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 40),
              child: FeedPostCard(
                post: item.post!,
                onCommentsUpdated: () => _fetchExploreFeed(refresh: true),
                onHideOrMute: () {
                  if (Navigator.canPop(context)) Navigator.of(context).pop();
                  setState(() {
                    _items.removeWhere((i) => i.id == item.id);
                  });
                },
                onPostDeleted: () {
                  if (Navigator.canPop(context)) Navigator.of(context).pop();
                  _fetchExploreFeed(refresh: true);
                },
              ),
            ),
          ),
        ),
      );
    }
  }

  /// Long-Press Quick Peek Dialog with real Share & Not Interested wiring
  void _showQuickPreview(ExploreGridItem item) {
    HapticFeedback.heavyImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Preview",
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Author Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(dialogCtx);
                          ProfileScreen.open(context, userId: item.authorId);
                        },
                        child: Row(
                          children: [
                            item.authorAvatar.isNotEmpty
                                ? ZevCachedImage.avatar(
                                    imageUrl: item.authorAvatar,
                                    size: 36,
                                  )
                                : Container(
                                    width: 36,
                                    height: 36,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE2E8F0),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.person,
                                      color: Color(0xFF94A3B8),
                                      size: 18,
                                    ),
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
                                          "@${item.authorUsername}",
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: ZevColors.deepNavy,
                                          ),
                                        ),
                                      ),
                                      if (item.isVerified) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.verified_rounded,
                                          size: 14,
                                          color: ZevColors.primaryBlue,
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (item.authorFullName.isNotEmpty)
                                    Text(
                                      item.authorFullName,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: ZevColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Media Content (Reels + Video Posts use ZevVideoThumbnail live preview)
                    AspectRatio(
                      aspectRatio:
                          (item.isReel || ZevVideoThumbnail.isVideoUrl(item.mediaUrl))
                              ? 9 / 14
                              : 1.0,
                      child: (item.isReel ||
                              ZevVideoThumbnail.isVideoUrl(item.mediaUrl))
                          ? ZevVideoThumbnail(
                              videoUrl: item.mediaUrl,
                              thumbnailUrl: item.thumbnailUrl,
                              autoPlay: true,
                              initialMuted: false,
                              showMuteToggle: true,
                              showPlayBadge: false,
                              showViews: false,
                            )
                          : CachedNetworkImage(
                              imageUrl: item.mediaUrl,
                              fit: BoxFit.cover,
                            ),
                    ),

                    // Quick Action Buttons
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      color: ZevColors.softSurface,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          IconButton(
                            tooltip: "View & Interact",
                            icon: const Icon(
                              Icons.favorite_border_rounded,
                              size: 24,
                            ),
                            color: ZevColors.deepNavy,
                            onPressed: () {
                              Navigator.pop(dialogCtx);
                              _openDetail(item);
                            },
                          ),
                          IconButton(
                            tooltip: "Share",
                            icon: const Icon(Icons.share_outlined, size: 22),
                            color: ZevColors.deepNavy,
                            onPressed: () {
                              Navigator.pop(dialogCtx);
                              HapticFeedback.lightImpact();
                              final shareTarget = item.post ??
                                  FeedPostItem(
                                    id: item.reel?.id ?? item.rawId,
                                    authorId: item.authorId,
                                    authorUsername: item.authorUsername,
                                    authorFullName: item.authorFullName,
                                    authorAvatar: item.authorAvatar,
                                    isVerified: item.isVerified,
                                    title: item.title,
                                    content: item.description ?? '',
                                    imageUrl: item.thumbnailUrl ?? '',
                                    createdAt:
                                        item.reel?.createdAt ?? DateTime.now(),
                                  );
                              FeedShareSheet.show(
                                context,
                                post: shareTarget,
                                isReel: item.isReel,
                              );
                            },
                          ),
                          IconButton(
                            tooltip: "Not Interested",
                            icon: const Icon(
                              Icons.visibility_off_outlined,
                              size: 22,
                            ),
                            color: ZevColors.textSecondary,
                            onPressed: () async {
                              Navigator.pop(dialogCtx);
                              final ok = await SocialGraphService.instance
                                  .hideContent(
                                targetId: item.rawId,
                                targetType: item.type,
                              );
                              if (!mounted) return;
                              if (ok) {
                                FeedAlgorithmService.instance
                                    .recordNegativeFeedback(
                                  postId: item.isReel ? null : item.rawId,
                                  reelId: item.isReel ? item.rawId : null,
                                  authorId: item.authorId,
                                );
                                setState(() {
                                  _items.removeWhere((i) => i.id == item.id);
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "We'll show fewer items like this.",
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                          IconButton(
                            tooltip: "Open",
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 22,
                            ),
                            color: ZevColors.primaryBlue,
                            onPressed: () {
                              Navigator.pop(dialogCtx);
                              _openDetail(item);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showDiscoveryPanel =
        _isSearchFocused && _searchCtrl.text.trim().isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildSearchBar(),

            if (_isSearching)
              Expanded(child: _buildSearchResultsView())
            else if (showDiscoveryPanel)
              Expanded(child: _buildSearchDiscoveryPanel())
            else ...[
              _buildCategoryChips(),
              Expanded(
                child: RefreshIndicator(
                  color: ZevColors.primaryBlue,
                  onRefresh: () {
                    ZevAdsService.instance.clearSlotCache();
                    return _fetchExploreFeed(refresh: true);
                  },
                  child: _isLoading
                      ? _buildGridShimmer()
                      : _items.isEmpty
                          ? _buildEmptyState()
                          : _buildExploreGrid(_items),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final showCancel = _isSearchFocused || _isSearching;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: (_isSearchFocused || _isSearching)
                      ? ZevColors.primaryBlue.withValues(alpha: 0.65)
                      : Colors.white,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                  const BoxShadow(
                    color: Colors.white,
                    blurRadius: 6,
                    offset: Offset(0, -1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(
                      Icons.search_rounded,
                      color: Color(0xFF64748B),
                      size: 22,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      onChanged: _onSearchQueryChanged,
                      onSubmitted: (val) {
                        final q = val.trim();
                        if (q.isNotEmpty) {
                          _saveSearchHistory(
                            q,
                            searchType: q.startsWith('#') ? 'hashtag' : 'all',
                          );
                          _executeSearch(q);
                        }
                      },
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: ZevColors.deepNavy,
                      ),
                      decoration: const InputDecoration(
                        hintText: "Search accounts, reels, #tags...",
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: ZevColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchQueryChanged("");
                      },
                    ),
                ],
              ),
            ),
          ),
          if (showCancel) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _searchFocus.unfocus();
                _searchCtrl.clear();
                _onSearchQueryChanged("");
                setState(() => _isSearchFocused = false);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: ZevColors.border),
                ),
                child: const Text(
                  "Cancel",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.deepNavy,
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                DiscoverScreen.open(context);
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: ZevColors.deepNavy,
                  size: 21,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchDiscoveryPanel() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      children: [
        // Discover People Banner
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            DiscoverScreen.open(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [ZevColors.primaryBlue, ZevColors.secondaryBlue],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.people_alt_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Discover Creators & Friends",
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Browse verified creators, rising voices, and new accounts.",
                        style: TextStyle(
                          fontSize: 12,
                          color: ZevColors.textSecondary,
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
        const SizedBox(height: 18),

        // Trending Hashtags
        if (_trendingHashtags.isNotEmpty) ...[
          const Text(
            "Trending Hashtags",
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: ZevColors.deepNavy,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _trendingHashtags.map((tagRow) {
              final tag = (tagRow['tag'] ?? '').toString();
              final total = (tagRow['total_count'] as num?)?.toInt() ?? 0;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _saveSearchHistory('#$tag', searchType: 'hashtag');
                  HashtagFeedScreen.open(context, tag: tag);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ZevColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "#$tag",
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.secondaryBlue,
                        ),
                      ),
                      if (total > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          _formatCount(total),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: ZevColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Recent Searches
        Row(
          children: [
            const Text(
              "Recent Searches",
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: ZevColors.deepNavy,
              ),
            ),
            const Spacer(),
            if (_recentSearches.isNotEmpty)
              GestureDetector(
                onTap: () => _clearSearchHistory(),
                child: const Text(
                  "Clear All",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.secondaryBlue,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_isDiscoveryPanelLoading && _recentSearches.isEmpty)
          const Column(
            children: [
              ZevSkeleton(width: double.infinity, height: 50),
              SizedBox(height: 8),
              ZevSkeleton(width: double.infinity, height: 50),
            ],
          )
        else if (_recentSearches.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ZevColors.border),
            ),
            child: const Text(
              "Your recent searches for accounts, hashtags, and topics will appear here.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ZevColors.textSecondary,
              ),
            ),
          )
        else
          ..._recentSearches.map((entry) {
            final id = entry['id']?.toString() ?? '';
            final query = entry['query']?.toString() ?? '';
            final type = entry['search_type']?.toString() ?? 'all';
            final targetId = entry['target_id']?.toString();

            final IconData icon;
            if (type == 'hashtag' || query.startsWith('#')) {
              icon = Icons.tag_rounded;
            } else if (type == 'account' || query.startsWith('@')) {
              icon = Icons.person_outline_rounded;
            } else {
              icon = Icons.history_rounded;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ZevColors.border),
              ),
              child: ListTile(
                dense: true,
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (type == 'account' &&
                      targetId != null &&
                      targetId.isNotEmpty) {
                    _saveSearchHistory(
                      query,
                      searchType: 'account',
                      targetId: targetId,
                    );
                    ProfileScreen.open(context, userId: targetId);
                  } else if (type == 'hashtag' || query.startsWith('#')) {
                    final cleanTag = query.replaceFirst(RegExp(r'^#+'), '');
                    _saveSearchHistory('#$cleanTag', searchType: 'hashtag');
                    HashtagFeedScreen.open(context, tag: cleanTag);
                  } else {
                    _searchCtrl.text = query;
                    _searchCtrl.selection = TextSelection.fromPosition(
                      TextPosition(offset: query.length),
                    );
                    _onSearchQueryChanged(query);
                  }
                },
                leading: Icon(icon, size: 20, color: ZevColors.secondaryBlue),
                title: Text(
                  query,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.deepNavy,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: ZevColors.textMuted,
                  ),
                  onPressed: () => _clearSearchHistory(id: id),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == _selectedCategory;

          return GestureDetector(
            onTap: () {
              if (cat == _selectedCategory) return;
              HapticFeedback.selectionClick();
              setState(() => _selectedCategory = cat);
              _fetchExploreFeed(refresh: true);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? ZevColors.primaryBlue : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.white,
                  width: 1.2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Center(
                child: Text(
                  cat,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? ZevColors.deepNavy
                        : const Color(0xFF475569),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildExploreGrid(List<ExploreGridItem> displayItems) {
    const int chunkSize = 12; // 4 full 3-column rows before each Explore ad unit
    final List<Widget> slivers = [];

    for (int start = 0, chunkIdx = 0;
        start < displayItems.length;
        start += chunkSize, chunkIdx++) {
      final int end = (start + chunkSize).clamp(0, displayItems.length);
      final chunk = displayItems.sublist(start, end);

      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            14,
            chunkIdx == 0 ? 8 : 4,
            14,
            4,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.82,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, idx) => _buildExploreGridTile(chunk[idx]),
              childCount: chunk.length,
            ),
          ),
        ),
      );

      if (end < displayItems.length || displayItems.length >= chunkSize) {
        slivers.add(
          SliverToBoxAdapter(
            child: ZevNativeAdCard(
              key: ValueKey('explore_ad_$chunkIdx'),
              placement: 'explore',
              slotKey: 'explore_slot_$chunkIdx',
              interest: _selectedCategory == 'All' ? null : _selectedCategory,
            ),
          ),
        );
      }
    }

    if (_isLoadingMore) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.82,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  ZevSkeleton(borderRadius: BorderRadius.circular(16)),
              childCount: 3,
            ),
          ),
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 110)));

    return CustomScrollView(
      controller: _gridScrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: slivers,
    );
  }

  Widget _buildExploreGridTile(ExploreGridItem item) {
    return GestureDetector(
      onTap: () => _openDetail(item),
      onLongPress: () => _showQuickPreview(item),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.9),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.isReel || ZevVideoThumbnail.isVideoUrl(item.mediaUrl))
                ZevVideoThumbnail(
                  videoUrl: item.mediaUrl,
                  thumbnailUrl: item.thumbnailUrl,
                  viewsCount: item.viewsCount,
                  showPlayBadge: false,
                  showViews: false,
                  borderRadius: BorderRadius.circular(16),
                )
              else if (item.mediaUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: item.mediaUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 400,
                  memCacheHeight: 400,
                  placeholder: (context, url) => _buildFallbackTile(item),
                  errorWidget: (context, url, error) =>
                      _buildFallbackTile(item),
                )
              else
                _buildFallbackTile(item),

              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),

              if (item.isReel)
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        if (item.viewsCount > 0) ...[
                          const SizedBox(width: 3),
                          Text(
                            _formatCount(item.viewsCount),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              Positioned(
                left: 8,
                right: 8,
                bottom: 7,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        "@${item.authorUsername}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 4),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.isVerified) ...[
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.verified_rounded,
                        size: 11,
                        color: ZevColors.primaryBlue,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return "${(count / 1000000).toStringAsFixed(1)}M";
    } else if (count >= 1000) {
      return "${(count / 1000).toStringAsFixed(1)}K";
    }
    return count.toString();
  }

  Widget _buildFallbackTile(ExploreGridItem item) {
    return Container(
      color: const Color(0xFFE2E8F0),
      padding: const EdgeInsets.all(10),
      child: Center(
        child: Icon(
          item.isReel ? Icons.movie_filter_rounded : Icons.photo_rounded,
          color: const Color(0xFF94A3B8),
          size: 32,
        ),
      ),
    );
  }

  Widget _buildSearchResultsView() {
    if (_isSearchLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: List.generate(
            5,
            (_) => const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: ZevSkeleton(width: double.infinity, height: 68),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildSearchFilterTab(0, "Accounts (${_searchedAccounts.length})"),
              const SizedBox(width: 6),
              _buildSearchFilterTab(1, "Reels (${_searchedReels.length})"),
              const SizedBox(width: 6),
              _buildSearchFilterTab(2, "Posts (${_searchedPosts.length})"),
              const SizedBox(width: 6),
              _buildSearchFilterTab(3, "#Tags (${_searchedHashtags.length})"),
            ],
          ),
        ),

        Expanded(
          child: _searchTab == 0
              ? _buildAccountsSearchResults()
              : _searchTab == 1
                  ? _buildReelsSearchResults()
                  : _searchTab == 2
                      ? _buildPostsSearchResults()
                      : _buildHashtagsSearchResults(),
        ),
      ],
    );
  }

  Widget _buildSearchFilterTab(int index, String label) {
    final isSelected = _searchTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _searchTab = index);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? ZevColors.primaryBlue : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.transparent : Colors.white,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: ZevColors.primaryBlue.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? ZevColors.deepNavy : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountsSearchResults() {
    if (_searchedAccounts.isEmpty) {
      return const Center(
        child: Text(
          "No accounts found",
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
      itemCount: _searchedAccounts.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = _searchedAccounts[index];
        final userId = user['id']?.toString() ?? '';
        final username = (user['username'] ?? 'user').toString();
        final fullName =
            "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}".trim();
        final avatarUrl = (user['avatar_url'] ?? '').toString();
        final isFollowing = user['is_following'] == true;
        final isRequested = user['is_requested'] == true;
        final isBusy = _busyAccountIds.contains(userId);

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _saveSearchHistory(
              '@$username',
              searchType: 'account',
              targetId: userId,
            );
            ProfileScreen.open(context, userId: userId);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                avatarUrl.isNotEmpty
                    ? ZevCachedImage.avatar(imageUrl: avatarUrl, size: 46)
                    : Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE2E8F0),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Color(0xFF94A3B8),
                          size: 24,
                        ),
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              "@$username",
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: ZevColors.deepNavy,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (user['is_verified'] == true) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 15,
                              color: ZevColors.primaryBlue,
                            ),
                          ],
                          if (user['is_private'] == true) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.lock_outline_rounded,
                              size: 13,
                              color: ZevColors.textMuted,
                            ),
                          ],
                        ],
                      ),
                      if (fullName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: isBusy ? null : () => _toggleSearchAccountFollow(index),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (isFollowing || isRequested)
                        ? ZevColors.softSurface
                        : ZevColors.primaryBlue,
                    foregroundColor: ZevColors.deepNavy,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: const Size(76, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: (isFollowing || isRequested)
                            ? ZevColors.border
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: isBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          isFollowing
                              ? "Following"
                              : isRequested
                                  ? "Requested"
                                  : "Follow",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReelsSearchResults() {
    if (_searchedReels.isEmpty) {
      return const Center(
        child: Text(
          "No reels found",
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 110),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.7,
      ),
      itemCount: _searchedReels.length,
      itemBuilder: (context, index) {
        final reel = _searchedReels[index];
        return GestureDetector(
          onTap: () {
            _saveSearchHistory(_searchCtrl.text.trim(), searchType: 'reel');
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    title: Text(reel.title.isNotEmpty ? reel.title : 'Reel'),
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
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white,
              border: Border.all(color: ZevColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ZevVideoThumbnail(
                    videoUrl: reel.videoUrl,
                    thumbnailUrl: reel.thumbnailUrl,
                    viewsCount: reel.viewsCount,
                    showPlayBadge: false,
                    showViews: false,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 6,
                    left: 6,
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
                            fontWeight: FontWeight.w700,
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
      },
    );
  }

  Widget _buildPostsSearchResults() {
    if (_searchedPosts.isEmpty) {
      return const Center(
        child: Text(
          "No posts found",
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 110),
      itemCount: _searchedPosts.length,
      itemBuilder: (context, index) {
        final post = _searchedPosts[index];
        return FeedPostCard(
          post: post,
          onCommentsUpdated: () {},
          onPostDeleted: () {
            setState(() {
              _searchedPosts.removeWhere((p) => p.id == post.id);
            });
          },
        );
      },
    );
  }

  Widget _buildHashtagsSearchResults() {
    if (_searchedHashtags.isEmpty) {
      return const Center(
        child: Text(
          "No hashtags found",
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
      itemCount: _searchedHashtags.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _searchedHashtags[index];
        final tag = (item['tag'] ?? '').toString();
        final postsCnt = (item['posts_count'] as num?)?.toInt() ?? 0;
        final reelsCnt = (item['reels_count'] as num?)?.toInt() ?? 0;
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _saveSearchHistory('#$tag', searchType: 'hashtag');
            HashtagFeedScreen.open(context, tag: tag);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: ZevColors.primaryBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.tag_rounded,
                      color: ZevColors.secondaryBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "#$tag",
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "$postsCnt posts  •  $reelsCnt reels",
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
      },
    );
  }

  Widget _buildGridShimmer() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.82,
      ),
      itemCount: 15,
      itemBuilder: (context, index) => ZevSkeleton(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isCategoryFiltered = _selectedCategory != "For You";

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                isCategoryFiltered
                    ? Icons.category_outlined
                    : Icons.explore_outlined,
                size: 34,
                color: ZevColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isCategoryFiltered
                  ? "No items in '$_selectedCategory'"
                  : "Explore ZEV",
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              isCategoryFiltered
                  ? "Be the first to share content in this topic!"
                  : "Discover trending reels, posts, and creators.",
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                if (isCategoryFiltered) {
                  setState(() => _selectedCategory = "For You");
                  _fetchExploreFeed(refresh: true);
                } else {
                  _fetchExploreFeed(refresh: true);
                }
              },
              icon: Icon(
                isCategoryFiltered
                    ? Icons.arrow_back_rounded
                    : Icons.refresh_rounded,
                size: 18,
              ),
              label: Text(
                isCategoryFiltered ? "Show All Posts" : "Refresh Feed",
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: ZevColors.deepNavy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
