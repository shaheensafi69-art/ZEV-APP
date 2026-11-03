import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/theme/zev_theme.dart';
import '../../feed/models/feed_post_item.dart';
import '../../feed/widgets/feed_post_card.dart';
import '../../profile/screens/profile_screen.dart';
import '../../reels/models/reel_item.dart';
import '../../reels/widgets/reel_player_item.dart';

/// Unified Explore Item representation combining Posts and Reels for Instagram-style Explore.
class ExploreGridItem {
  final String id;
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

/// Lightweight, auto-disposed inline video tile for Instagram-grade Explore previews.
class ExploreVideoTile extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final bool autoPlay;

  const ExploreVideoTile({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.autoPlay = true,
  });

  @override
  State<ExploreVideoTile> createState() => _ExploreVideoTileState();
}

class _ExploreVideoTileState extends State<ExploreVideoTile> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay && widget.videoUrl.isNotEmpty) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      await controller.setVolume(0.0);
      await controller.setLooping(true);
      await controller.play();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("ExploreVideoTile initialization error: $e");
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasError && _isInitialized && _controller != null && _controller!.value.isInitialized) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    }

    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.thumbnailUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF0F172A),
      child: const Center(
        child: Icon(
          Icons.play_circle_fill_rounded,
          color: Colors.white24,
          size: 32,
        ),
      ),
    );
  }
}

/// Flagship Instagram-Caliber Explore & Search Screen for ZEV.
/// Features:
/// - Real-time video player previews in the grid
/// - High-fidelity photo cards via cached network images
/// - Active multi-category taxonomy detection engine
/// - Multi-entity live search (Accounts, Reels, Posts)
/// - Instagram-style Long-press quick preview modal
/// - 100% Claymorphic aesthetics
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();

  List<ExploreGridItem> _items = [];
  bool _isLoading = true;
  String _selectedCategory = "For You";

  // Search state
  bool _isSearching = false;
  int _searchTab = 0; // 0: Accounts, 1: Reels, 2: Posts
  bool _isSearchLoading = false;
  List<Map<String, dynamic>> _searchedAccounts = [];
  List<ReelItem> _searchedReels = [];
  List<FeedPostItem> _searchedPosts = [];
  Timer? _debounceTimer;

  final List<String> _categories = [
    "For You",
    "Reels",
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
    _fetchExploreFeed();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Intelligently filters explore items based on the active taxonomy category
  List<ExploreGridItem> get _filteredItems {
    if (_selectedCategory == "For You") {
      return _items;
    }
    if (_selectedCategory == "Reels") {
      return _items.where((item) => item.isReel).toList();
    }

    return _items.where((item) => _matchesCategory(item, _selectedCategory)).toList();
  }

  /// Comprehensive keyword & tag classification engine for explore topics
  bool _matchesCategory(ExploreGridItem item, String category) {
    final targetCat = category.toLowerCase();
    final itemCat = (item.category ?? "").toLowerCase();

    if (itemCat.isNotEmpty && (itemCat.contains(targetCat) || targetCat.contains(itemCat))) {
      return true;
    }

    final combinedText = "${item.title} ${item.description ?? ''} ${(item.post?.content) ?? ''} ${(item.post?.categoryTag) ?? ''}".toLowerCase();

    switch (category) {
      case "Technology":
        return combinedText.contains("tech") ||
            combinedText.contains("code") ||
            combinedText.contains("software") ||
            combinedText.contains("ai") ||
            combinedText.contains("app") ||
            combinedText.contains("dev") ||
            combinedText.contains("program") ||
            combinedText.contains("flutter") ||
            combinedText.contains("python") ||
            combinedText.contains("computer") ||
            combinedText.contains("robot") ||
            combinedText.contains("web");

      case "Design & Art":
        return combinedText.contains("design") ||
            combinedText.contains("art") ||
            combinedText.contains("draw") ||
            combinedText.contains("ui") ||
            combinedText.contains("ux") ||
            combinedText.contains("creative") ||
            combinedText.contains("paint") ||
            combinedText.contains("color") ||
            combinedText.contains("sketch") ||
            combinedText.contains("illustration");

      case "Photography":
        return combinedText.contains("photo") ||
            combinedText.contains("camera") ||
            combinedText.contains("shot") ||
            combinedText.contains("lens") ||
            combinedText.contains("pic") ||
            combinedText.contains("portrait") ||
            combinedText.contains("landscape") ||
            combinedText.contains("nature") ||
            combinedText.contains("capture");

      case "Fitness":
        return combinedText.contains("fit") ||
            combinedText.contains("gym") ||
            combinedText.contains("workout") ||
            combinedText.contains("exercise") ||
            combinedText.contains("health") ||
            combinedText.contains("body") ||
            combinedText.contains("muscle") ||
            combinedText.contains("train") ||
            combinedText.contains("run") ||
            combinedText.contains("sport");

      case "Travel":
        return combinedText.contains("travel") ||
            combinedText.contains("trip") ||
            combinedText.contains("tour") ||
            combinedText.contains("vacation") ||
            combinedText.contains("place") ||
            combinedText.contains("city") ||
            combinedText.contains("country") ||
            combinedText.contains("hotel") ||
            combinedText.contains("beach") ||
            combinedText.contains("mountain") ||
            combinedText.contains("explore");

      case "Music":
        return combinedText.contains("music") ||
            combinedText.contains("song") ||
            combinedText.contains("audio") ||
            combinedText.contains("sound") ||
            combinedText.contains("beat") ||
            combinedText.contains("voice") ||
            combinedText.contains("sing") ||
            combinedText.contains("track") ||
            combinedText.contains("guitar") ||
            combinedText.contains("melody");

      case "Quotes":
        return combinedText.contains("quote") ||
            combinedText.contains("word") ||
            combinedText.contains("life") ||
            combinedText.contains("motivat") ||
            combinedText.contains("success") ||
            combinedText.contains("love") ||
            combinedText.contains("mind") ||
            combinedText.contains("lesson") ||
            combinedText.contains("wisdom");

      default:
        return combinedText.contains(targetCat);
    }
  }

  /// Fetches real posts and reels from Supabase and aggregates them for Explore grid
  Future<void> _fetchExploreFeed() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch recent Reels
      final reelsRes = await supabase
          .from('reels')
          .select(
            'id, user_id, title, description, video_url, thumbnail_url, category, views_count, likes_count, comments_count, created_at',
          )
          .eq('is_published', true)
          .order('views_count', ascending: false)
          .limit(40);

      // 2. Fetch recent Posts with images
      final postsRes = await supabase
          .from('discussion_posts')
          .select(
            'id, student_id, title, content, image_url, created_at',
          )
          .neq('image_url', '')
          .order('created_at', ascending: false)
          .limit(40);

      // 3. Batch fetch author profiles
      final allUserIds = <String>{};
      for (final r in reelsRes) {
        if (r['user_id'] != null) allUserIds.add(r['user_id'].toString());
      }
      for (final p in postsRes) {
        if (p['student_id'] != null) allUserIds.add(p['student_id'].toString());
      }

      Map<String, Map<String, dynamic>> profilesMap = {};
      if (allUserIds.isNotEmpty) {
        final profilesRes = await supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .filter('id', 'in', allUserIds.toList());
        for (final p in profilesRes) {
          profilesMap[p['id'].toString()] = p;
        }
      }

      final List<ExploreGridItem> combined = [];

      // Convert Reels
      for (final r in reelsRes) {
        final uid = r['user_id']?.toString() ?? '';
        final profile = profilesMap[uid] ?? {};
        final username = profile['username'] ?? 'creator';
        final fullName = "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}".trim();
        final avatar = profile['avatar_url'] ?? '';
        final isVerified = profile['is_verified'] == true;

        final reelItem = ReelItem(
          id: r['id'].toString(),
          userId: uid,
          authorUsername: username,
          authorFullName: fullName,
          authorAvatar: avatar,
          isVerified: isVerified,
          videoUrl: r['video_url'] ?? '',
          thumbnailUrl: r['thumbnail_url'],
          title: r['title'] ?? '',
          description: r['description'] ?? '',
          category: r['category'] ?? 'Explore',
          viewsCount: r['views_count'] ?? 0,
          likesCount: r['likes_count'] ?? 0,
          commentsCount: r['comments_count'] ?? 0,
          createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
        );

        combined.add(ExploreGridItem(
          id: 'reel_${r['id']}',
          type: 'reel',
          mediaUrl: r['video_url'] ?? '',
          thumbnailUrl: r['thumbnail_url'],
          title: r['title'] ?? '',
          description: r['description'] ?? '',
          category: r['category'] ?? 'Reels',
          authorId: uid,
          authorUsername: username,
          authorFullName: fullName,
          authorAvatar: avatar,
          isVerified: isVerified,
          viewsCount: r['views_count'] ?? 0,
          likesCount: r['likes_count'] ?? 0,
          reel: reelItem,
        ));
      }

      // Convert Posts
      for (final p in postsRes) {
        final uid = p['student_id']?.toString() ?? '';
        final profile = profilesMap[uid] ?? {};
        final username = profile['username'] ?? 'user';
        final fullName = "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}".trim();
        final avatar = profile['avatar_url'] ?? '';
        final isVerified = profile['is_verified'] == true;

        final postItem = FeedPostItem(
          id: p['id'].toString(),
          authorId: uid,
          authorUsername: username,
          authorFullName: fullName,
          authorAvatar: avatar,
          isVerified: isVerified,
          title: p['title'] ?? '',
          content: p['content'] ?? '',
          imageUrl: p['image_url'] ?? '',
          likesCount: 0,
          commentsCount: 0,
          createdAt: DateTime.tryParse(p['created_at']?.toString() ?? '') ?? DateTime.now(),
        );

        combined.add(ExploreGridItem(
          id: 'post_${p['id']}',
          type: 'post',
          mediaUrl: p['image_url'] ?? '',
          thumbnailUrl: p['image_url'],
          title: p['title'] ?? '',
          description: p['content'] ?? '',
          category: 'Post',
          authorId: uid,
          authorUsername: username,
          authorFullName: fullName,
          authorAvatar: avatar,
          isVerified: isVerified,
          viewsCount: 0,
          likesCount: 0,
          post: postItem,
        ));
      }

      // Shuffle for natural Instagram mixture
      combined.shuffle();

      if (mounted) {
        setState(() {
          _items = combined;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Explore feed fetch error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchQueryChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchedAccounts = [];
        _searchedReels = [];
        _searchedPosts = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isSearchLoading = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _executeSearch(query.trim());
    });
  }

  Future<void> _executeSearch(String query) async {
    try {
      // 1. Search profiles (Accounts)
      final profilesRes = await supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified, bio')
          .or('username.ilike.%$query%,first_name.ilike.%$query%,last_name.ilike.%$query%')
          .limit(20);

      // 2. Search Reels
      final reelsRes = await supabase
          .from('reels')
          .select(
            'id, user_id, title, description, video_url, thumbnail_url, category, views_count, likes_count, comments_count, created_at',
          )
          .eq('is_published', true)
          .or('title.ilike.%$query%,description.ilike.%$query%')
          .limit(25);

      final reelsList = <ReelItem>[];
      for (final r in reelsRes) {
        reelsList.add(ReelItem(
          id: r['id'].toString(),
          userId: r['user_id']?.toString() ?? '',
          authorUsername: 'creator',
          authorFullName: '',
          authorAvatar: '',
          isVerified: false,
          videoUrl: r['video_url'] ?? '',
          thumbnailUrl: r['thumbnail_url'],
          title: r['title'] ?? '',
          description: r['description'] ?? '',
          viewsCount: r['views_count'] ?? 0,
          likesCount: r['likes_count'] ?? 0,
          commentsCount: r['comments_count'] ?? 0,
          createdAt: DateTime.now(),
        ));
      }

      // 3. Search Posts
      final postsRes = await supabase
          .from('discussion_posts')
          .select('id, student_id, title, content, image_url, created_at')
          .or('title.ilike.%$query%,content.ilike.%$query%')
          .limit(20);

      final postsList = <FeedPostItem>[];
      for (final p in postsRes) {
        postsList.add(FeedPostItem(
          id: p['id'].toString(),
          authorId: p['student_id']?.toString() ?? '',
          authorUsername: 'user',
          authorFullName: '',
          authorAvatar: '',
          title: p['title'] ?? '',
          content: p['content'] ?? '',
          imageUrl: p['image_url'] ?? '',
          likesCount: 0,
          commentsCount: 0,
          createdAt: DateTime.now(),
        ));
      }

      if (mounted) {
        setState(() {
          _searchedAccounts = List<Map<String, dynamic>>.from(profilesRes);
          _searchedReels = reelsList;
          _searchedPosts = postsList;
          _isSearchLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Execute search error: $e");
      if (mounted) setState(() => _isSearchLoading = false);
    }
  }

  void _openDetail(ExploreGridItem item) {
    HapticFeedback.lightImpact();
    if (item.isReel && item.reel != null) {
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
            ),
          ),
        ),
      );
    } else if (item.post != null) {
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
                onCommentsUpdated: _fetchExploreFeed,
              ),
            ),
          ),
        ),
      );
    }
  }

  /// Signature Instagram Long-Press Quick Peek dialog
  void _showQuickPreview(ExploreGridItem item) {
    HapticFeedback.heavyImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Preview",
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, anim1, anim2) {
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFFE2E8F0),
                            backgroundImage: item.authorAvatar.isNotEmpty
                                ? NetworkImage(item.authorAvatar)
                                : null,
                            child: item.authorAvatar.isEmpty
                                ? const Icon(Icons.person, color: Color(0xFF94A3B8), size: 18)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      "@${item.authorUsername}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: Color(0xFF0F172A),
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
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Media Content
                    AspectRatio(
                      aspectRatio: item.isReel ? 9 / 14 : 1.0,
                      child: item.isReel
                          ? ExploreVideoTile(
                              videoUrl: item.mediaUrl,
                              thumbnailUrl: item.thumbnailUrl,
                              autoPlay: true,
                            )
                          : CachedNetworkImage(
                              imageUrl: item.mediaUrl,
                              fit: BoxFit.cover,
                            ),
                    ),

                    // Quick Action Buttons
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      color: const Color(0xFFF8FAFC),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.favorite_border_rounded, size: 24),
                            color: const Color(0xFF0F172A),
                            onPressed: () {
                              Navigator.pop(context);
                              _openDetail(item);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.mode_comment_outlined, size: 22),
                            color: const Color(0xFF0F172A),
                            onPressed: () {
                              Navigator.pop(context);
                              _openDetail(item);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.share_outlined, size: 22),
                            color: const Color(0xFF0F172A),
                            onPressed: () {
                              Navigator.pop(context);
                              HapticFeedback.lightImpact();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.open_in_new_rounded, size: 22),
                            color: ZevColors.primaryBlue,
                            onPressed: () {
                              Navigator.pop(context);
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
    final filtered = _filteredItems;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Search Bar
            _buildSearchBar(),

            // If user is searching, show dedicated Search Results view
            if (_isSearching)
              Expanded(child: _buildSearchResultsView())
            else ...[
              // Topic taxonomy category chips tray
              _buildCategoryChips(),

              // Authentic Instagram Explore Grid
              Expanded(
                child: RefreshIndicator(
                  color: ZevColors.primaryBlue,
                  onRefresh: _fetchExploreFeed,
                  child: _isLoading
                      ? _buildGridShimmer()
                      : filtered.isEmpty
                          ? _buildEmptyState()
                          : _buildExploreGrid(filtered),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _isSearching
                ? ZevColors.primaryBlue.withValues(alpha: 0.6)
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
                onChanged: _onSearchQueryChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
                decoration: const InputDecoration(
                  hintText: "Search accounts, reels, tags...",
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF94A3B8),
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
                icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearchQueryChanged("");
                },
              ),
          ],
        ),
      ),
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
              HapticFeedback.selectionClick();
              setState(() => _selectedCategory = cat);
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
                    color: isSelected ? ZevColors.deepNavy : const Color(0xFF475569),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Authentic Instagram 3-Column Explore Grid with Live Video & Photo Previews
  Widget _buildExploreGrid(List<ExploreGridItem> displayItems) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.82,
      ),
      itemCount: displayItems.length,
      itemBuilder: (context, index) {
        final item = displayItems[index];

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
                  // Media Player / Preview
                  if (item.isReel)
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: item.thumbnailUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 400,
                            memCacheHeight: 400,
                            placeholder: (context, url) => _buildFallbackTile(item),
                            errorWidget: (context, url, error) => _buildFallbackTile(item),
                          )
                        else
                          _buildFallbackTile(item),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.movie_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (item.mediaUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: item.mediaUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 400,
                      memCacheHeight: 400,
                      placeholder: (context, url) => _buildFallbackTile(item),
                      errorWidget: (context, url, error) => _buildFallbackTile(item),
                    )
                  else
                    _buildFallbackTile(item),

                  // Bottom gradient for text readability
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

                  // Reel / Video Badge on Top-Right
                  if (item.isReel)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
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

                  // Author & Info on Bottom-Left
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
                              shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
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
      },
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
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: ZevColors.primaryBlue,
        ),
      );
    }

    return Column(
      children: [
        // Search Tabs: Accounts | Reels | Posts
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildSearchFilterTab(0, "Accounts (${_searchedAccounts.length})"),
              const SizedBox(width: 8),
              _buildSearchFilterTab(1, "Reels (${_searchedReels.length})"),
              const SizedBox(width: 8),
              _buildSearchFilterTab(2, "Posts (${_searchedPosts.length})"),
            ],
          ),
        ),

        Expanded(
          child: _searchTab == 0
              ? _buildAccountsSearchResults()
              : _searchTab == 1
                  ? _buildReelsSearchResults()
                  : _buildPostsSearchResults(),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
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
              style: TextStyle(
                fontSize: 11.5,
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
          style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
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
        final fullName = "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}".trim();

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            ProfileScreen.open(context, userId: user['id'].toString());
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
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFE2E8F0),
                  backgroundImage: user['avatar_url'] != null && user['avatar_url'].isNotEmpty
                      ? CachedNetworkImageProvider(user['avatar_url'])
                      : null,
                  child: user['avatar_url'] == null || user['avatar_url'].isEmpty
                      ? const Icon(Icons.person_rounded, color: Color(0xFF94A3B8), size: 24)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              "@${user['username'] ?? 'user'}",
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
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
                        ],
                      ),
                      if (fullName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: ZevColors.primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "View",
                    style: TextStyle(
                      color: ZevColors.primaryBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
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
          style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
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
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    title: Text(reel.title),
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
              color: const Color(0xFF0F172A),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (reel.thumbnailUrl != null && reel.thumbnailUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: reel.thumbnailUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 400,
                      memCacheHeight: 400,
                      placeholder: (context, url) => Container(color: const Color(0xFF1E293B)),
                      errorWidget: (context, url, error) => Container(
                        color: const Color(0xFF1E293B),
                        child: const Center(
                          child: Icon(Icons.movie_rounded, color: Colors.white54, size: 28),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: const Color(0xFF1E293B),
                      child: const Center(
                        child: Icon(Icons.movie_rounded, color: Colors.white54, size: 28),
                      ),
                    ),
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Row(
                      children: [
                        const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
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
          style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
      itemCount: _searchedPosts.length,
      itemBuilder: (context, index) {
        final post = _searchedPosts[index];
        return FeedPostCard(
          post: post,
          onCommentsUpdated: () {},
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
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
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
                isCategoryFiltered ? Icons.category_outlined : Icons.explore_outlined,
                size: 34,
                color: ZevColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isCategoryFiltered ? "No items in '$_selectedCategory'" : "Explore ZEV",
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
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
                } else {
                  _fetchExploreFeed();
                }
              },
              icon: Icon(
                isCategoryFiltered ? Icons.arrow_back_rounded : Icons.refresh_rounded,
                size: 18,
              ),
              label: Text(isCategoryFiltered ? "Show All Posts" : "Refresh Feed"),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: ZevColors.deepNavy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
