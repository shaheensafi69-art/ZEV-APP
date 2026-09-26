import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/fast_cached_image.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../core/services/language_service.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../feed/screens/feed_viewer_screen.dart';
import '../../feed/screens/reels_viewer_screen.dart';
import '../../feed/screens/user_profile_screen.dart';

class ExploreSearchScreen extends StatefulWidget {
  const ExploreSearchScreen({super.key});

  @override
  State<ExploreSearchScreen> createState() => _ExploreSearchScreenState();
}

class _ExploreSearchScreenState extends State<ExploreSearchScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  bool _isLoading = true;
  String _searchQuery = '';
  List<Map<String, dynamic>> _trendingPosts = [];
  List<Map<String, dynamic>> _trendingReels = [];
  List<Map<String, dynamic>> _searchedUsers = [];
  List<Map<String, dynamic>> _suggestedUsers = [];
  final Set<String> _followingUserIds = {};

  static const Color primaryPink = Color(0xFFFC466B);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchExploreContent();
    _fetchMyFollows();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchMyFollows() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;
    try {
      final res = await supabase
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', currentUserId);
      if (mounted) {
        setState(() {
          _followingUserIds.clear();
          for (var item in res) {
            final fid = item['following_id']?.toString();
            if (fid != null) _followingUserIds.add(fid);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchExploreContent() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch explore posts with images
      final postsRes = await supabase
          .from('discussion_posts')
          .select('id, title, content, image_url, created_at, student_id')
          .not('image_url', 'is', null)
          .order('created_at', ascending: false)
          .limit(30);

      // 2. Fetch reels
      final reelsRes = await supabase
          .from('reels')
          .select(
            'id, title, description, thumbnail_url, video_url, views_count, likes_count, user_id',
          )
          .order('views_count', ascending: false)
          .limit(30);

      // 3. Fetch active users by default
      final activeUsersRes = await supabase
          .from('profiles')
          .select('id, first_name, last_name, avatar_url, bio, role')
          .order('created_at', ascending: false)
          .limit(30);

      if (mounted) {
        setState(() {
          _trendingPosts = List<Map<String, dynamic>>.from(postsRes);
          _trendingReels = List<Map<String, dynamic>>.from(reelsRes);
          _suggestedUsers = List<Map<String, dynamic>>.from(activeUsersRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Explore fetch error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _searchQuery = query.trim();
    });

    if (_searchQuery.isEmpty) {
      return;
    }

    try {
      final usersRes = await supabase
          .from('profiles')
          .select('id, first_name, last_name, avatar_url, bio, role')
          .or(
            'first_name.ilike.%$_searchQuery%,last_name.ilike.%$_searchQuery%,bio.ilike.%$_searchQuery%',
          )
          .limit(20);

      if (mounted) {
        setState(() {
          _searchedUsers = List<Map<String, dynamic>>.from(usersRes);
        });
      }
    } catch (e) {
      debugPrint("Search error: $e");
    }
  }

  Future<void> _toggleFollow(String targetUserId) async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    final isFollowing = _followingUserIds.contains(targetUserId);
    setState(() {
      if (isFollowing) {
        _followingUserIds.remove(targetUserId);
      } else {
        _followingUserIds.add(targetUserId);
      }
    });

    try {
      if (isFollowing) {
        await supabase.from('user_follows').delete().match({
          'follower_id': myId,
          'following_id': targetUserId,
        });
      } else {
        await supabase.from('user_follows').insert({
          'follower_id': myId,
          'following_id': targetUserId,
        });
      }
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          if (isFollowing) {
            _followingUserIds.add(targetUserId);
          } else {
            _followingUserIds.remove(targetUserId);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, activeLocale, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final isRtl = LanguageService.isRtl(activeLocale.languageCode);

        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            backgroundColor: isDark
                ? const Color(0xFF090D16)
                : const Color(0xFFF8FAFC),
            appBar: AppBar(
              backgroundColor: isDark ? const Color(0xFF090D16) : Colors.white,
              elevation: 0,
              titleSpacing: 16,
              title: ResponsiveLayout.isPhone(context)
                  ? Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white10
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _performSearch,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: context.zevTr('searchZevHint'),
                          hintStyle: TextStyle(
                            color: isDark
                                ? Colors.white38
                                : const Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: isDark
                                ? Colors.white54
                                : const Color(0xFF64748B),
                            size: 20,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    _performSearch('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white10
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: _performSearch,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              hintText: context.zevTr('searchZevHint'),
                              hintStyle: TextStyle(
                                color: isDark
                                    ? Colors.white38
                                    : const Color(0xFF94A3B8),
                                fontSize: 13,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: isDark
                                    ? Colors.white54
                                    : const Color(0xFF64748B),
                                size: 20,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                        _performSearch('');
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: ResponsiveLayout.isPhone(context)
                    ? TabBar(
                        controller: _tabController,
                        indicatorColor: primaryPink,
                        indicatorWeight: 3,
                        labelColor: primaryPink,
                        unselectedLabelColor: isDark
                            ? Colors.white54
                            : const Color(0xFF64748B),
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        tabs: [
                          Tab(text: "🔥 ${context.zevTr('trending')}"),
                          Tab(text: "🎬 ${context.zevTr('reels')}"),
                          Tab(text: "👥 ${context.zevTr('people')}"),
                        ],
                      )
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: TabBar(
                            controller: _tabController,
                            indicatorColor: primaryPink,
                            indicatorWeight: 3,
                            labelColor: primaryPink,
                            unselectedLabelColor: isDark
                                ? Colors.white54
                                : const Color(0xFF64748B),
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            tabs: [
                              Tab(text: "🔥 ${context.zevTr('trending')}"),
                              Tab(text: "🎬 ${context.zevTr('reels')}"),
                              Tab(text: "👥 ${context.zevTr('people')}"),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            body: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: primaryPink),
                  )
                : ResponsiveLayout.pageConstraint(
                    maxWidth: ResponsiveLayout.isPhone(context) ? 720 : 1200,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTrendingGrid(isDark),
                        _buildReelsGrid(isDark),
                        _buildPeopleList(isDark),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildTrendingGrid(bool isDark) {
    if (_trendingPosts.isEmpty) {
      return Center(
        child: Text(
          context.zevTr('noTrendingPosts'),
          style: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchExploreContent,
      color: primaryPink,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: ResponsiveLayout.gridColumns(
            context,
            mobile: 3,
            tablet: 4,
            desktop: 5,
          ),
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 1,
        ),
        itemCount: _trendingPosts.length,
        itemBuilder: (context, index) {
          final post = _trendingPosts[index];
          final imgUrl = post['image_url']?.toString() ?? '';

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FeedViewerScreen()),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FastCachedImage(imageUrl: imgUrl, fit: BoxFit.cover),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.collections_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReelsGrid(bool isDark) {
    if (_trendingReels.isEmpty) {
      return Center(
        child: Text(
          "No reels found.",
          style: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchExploreContent,
      color: primaryPink,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: ResponsiveLayout.gridColumns(
            context,
            mobile: 3,
            tablet: 4,
            desktop: 5,
          ),
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 0.65,
        ),
        itemCount: _trendingReels.length,
        itemBuilder: (context, index) {
          final reel = _trendingReels[index];
          final reelId = reel['id']?.toString();

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentReelsScreen(targetReelId: reelId),
                ),
              );
            },
            child: _buildReelPreview(reel, index),
          );
        },
      ),
    );
  }

  Widget _buildReelPreview(Map<String, dynamic> reel, int index) {
    final thumbUrl = reel['thumbnail_url']?.toString() ?? '';
    final title = reel['title']?.toString() ?? '';
    final views = reel['views_count'] ?? 0;

    final gradients = [
      [const Color(0xFF6A11CB), const Color(0xFF2575FC)],
      [const Color(0xFFFF0844), const Color(0xFFFFB199)],
      [const Color(0xFF4A00E0), const Color(0xFF8E2DE2)],
      [const Color(0xFF0BA360), const Color(0xFF3CBA92)],
      [const Color(0xFFF857A6), const Color(0xFFFF5858)],
      [const Color(0xFF13547A), const Color(0xFF80D0C7)],
      [const Color(0xFFFC466B), const Color(0xFF3F5EFB)],
    ];
    final gradientColors = gradients[index % gradients.length];

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumbUrl.isNotEmpty)
            FastCachedImage(
              imageUrl: thumbUrl,
              fit: BoxFit.cover,
              errorWidget: _buildGradientFallback(title, gradientColors),
            )
          else
            _buildGradientFallback(title, gradientColors),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black87],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            left: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 15,
                ),
                const SizedBox(width: 2),
                Text(
                  views >= 1000000
                      ? '${(views / 1000000).toStringAsFixed(1)}M'
                      : views >= 1000
                      ? '${(views / 1000).toStringAsFixed(1)}K'
                      : '$views',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientFallback(String title, List<Color> colors) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30),
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 10,
                height: 1.2,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeopleList(bool isDark) {
    final isSearching = _searchQuery.isNotEmpty;
    final list = isSearching ? _searchedUsers : _suggestedUsers;

    if (list.isEmpty && isSearching) {
      return Center(
        child: Text(
          "No users matching '$_searchQuery'",
          style: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
        ),
      );
    }

    if (list.isEmpty && !isSearching) {
      return const Center(child: CircularProgressIndicator(color: primaryPink));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isSearching) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(
              children: [
                const Icon(Icons.stars_rounded, color: primaryPink, size: 20),
                const SizedBox(width: 8),
                Text(
                  "Active Community on ZEV",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                Text(
                  "${list.length} suggested",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: list.length,
            separatorBuilder: (_, _) => Divider(
              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
            ),
            itemBuilder: (context, index) {
              final user = list[index];
              final uid = user['id']?.toString() ?? '';
              final name =
                  "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}"
                      .trim();
              final avatar = user['avatar_url']?.toString() ?? '';
              final bio = user['bio']?.toString() ?? '';
              final role = user['role']?.toString() ?? 'student';
              final isFollowing = _followingUserIds.contains(uid);

              final isAdmin = role == 'admin' || role == 'super_admin';
              final isTeacher = role == 'teacher';
              final roleColor = isAdmin
                  ? Colors.deepPurple
                  : (isTeacher ? Colors.blueAccent : primaryPink);
              final String? roleBadge = isAdmin ? "OFFICIAL 🛡️" : null;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(userId: uid),
                    ),
                  );
                },
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: primaryPink.withValues(alpha: 0.15),
                  backgroundImage: avatar.isNotEmpty
                      ? NetworkImage(avatar)
                      : null,
                  child: avatar.isEmpty
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'Z',
                          style: const TextStyle(
                            color: primaryPink,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isNotEmpty ? name : 'ZEV User',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (roleBadge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: roleColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          roleBadge,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: roleColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: bio.isNotEmpty
                    ? Text(
                        bio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : const Color(0xFF64748B),
                        ),
                      )
                    : null,
                trailing: SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    onPressed: () => _toggleFollow(uid),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFollowing
                          ? (isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFE2E8F0))
                          : primaryPink,
                      foregroundColor: isFollowing
                          ? (isDark ? Colors.white70 : const Color(0xFF334155))
                          : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: Text(
                      isFollowing
                          ? context.zevTr('following')
                          : context.zevTr('follow'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
