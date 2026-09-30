import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/fast_cached_image.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../core/services/language_service.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../feed/screens/feed_viewer_screen.dart';
import '../../feed/screens/reels_viewer_screen.dart';
import '../../feed/screens/user_profile_screen.dart';
import '../../feed/widgets/zev_reels_preview_grid.dart';

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
          .select(
            'id, first_name, last_name, avatar_url, cover_image_url, bio, role, username',
          )
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

    final cleanQuery = _searchQuery.replaceFirst('@', '').trim();

    try {
      final usersRes = await supabase
          .from('profiles')
          .select(
            'id, first_name, last_name, avatar_url, cover_image_url, bio, role, username',
          )
          .or(
            'first_name.ilike.%$cleanQuery%,last_name.ilike.%$cleanQuery%,username.ilike.%$cleanQuery%,bio.ilike.%$cleanQuery%',
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
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
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
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
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
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
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
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
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
      child: ZevReelsPreviewGrid(
        reels: _trendingReels,
        onReelTap: (reel, index) {
          final reelId = reel['id']?.toString();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentReelsScreen(targetReelId: reelId),
            ),
          );
        },
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

    final isDesktopWeb =
        ResponsiveLayout.isDesktop(context) ||
        ResponsiveLayout.isTablet(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isSearching) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Row(
              children: [
                const Icon(Icons.stars_rounded, color: primaryPink, size: 20),
                const SizedBox(width: 8),
                Text(
                  "Active Community on ZEV",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "${list.length} suggested",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Expanded(
          child: isDesktopWeb
              ? _buildPeopleWebGrid(list, isDark)
              : _buildPeopleMobileList(list, isDark),
        ),
      ],
    );
  }

  Widget _buildPeopleWebGrid(List<Map<String, dynamic>> list, bool isDark) {
    final columns = ResponsiveLayout.gridColumns(
      context,
      mobile: 2,
      tablet: 3,
      desktop: 4,
    );

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.64,
      ),
      itemCount: list.length,
      itemBuilder: (context, index) {
        return _buildPeopleCard(list[index], index, isDark, isMobile: false);
      },
    );
  }

  Widget _buildPeopleMobileList(List<Map<String, dynamic>> list, bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: list.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _buildPeopleMobileItem(list[index], index, isDark);
      },
    );
  }

  Widget _buildPeopleMobileItem(
    Map<String, dynamic> user,
    int index,
    bool isDark,
  ) {
    final uid = user['id']?.toString() ?? '';
    final name = "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}"
        .trim();
    final displayName = name.isNotEmpty ? name : (user['username'] ?? 'User');
    final avatar = user['avatar_url']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';
    final bio = user['bio']?.toString() ?? '';
    final role = user['role']?.toString() ?? 'student';
    final isFollowing = _followingUserIds.contains(uid);

    final isAdmin = role == 'admin' || role == 'super_admin';
    final isTeacher = role == 'teacher';
    final roleColor = isAdmin
        ? Colors.deepPurple
        : (isTeacher ? Colors.blueAccent : primaryPink);
    final String? roleBadge = isAdmin
        ? "OFFICIAL 🛡️"
        : (isTeacher ? "TEACHER 🎓" : null);

    final bool isOnline =
        user['is_online'] == true ||
        (user['last_seen'] != null &&
            DateTime.tryParse(user['last_seen'].toString()) != null &&
            DateTime.now()
                    .difference(DateTime.parse(user['last_seen'].toString()))
                    .inMinutes <
                5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => UserProfileScreen(userId: uid)),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131926) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar with online badge
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isOnline
                          ? const LinearGradient(
                              colors: [primaryPink, Color(0xFF10B981)],
                            )
                          : null,
                      border: !isOnline
                          ? Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : const Color(0xFFE2E8F0),
                              width: 1.5,
                            )
                          : null,
                    ),
                    child: CircleAvatar(
                      radius: 23,
                      backgroundColor: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFFAF4F6),
                      backgroundImage: avatar.isNotEmpty
                          ? NetworkImage(avatar)
                          : null,
                      child: avatar.isEmpty
                          ? Text(
                              displayName.isNotEmpty
                                  ? displayName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: primaryPink,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            )
                          : null,
                    ),
                  ),
                  if (isOnline)
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF131926)
                                : Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // User info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
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
                              color: roleColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              roleBadge,
                              style: TextStyle(
                                color: roleColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "@$username",
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        bio,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF475569),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Compact Follow/Following button
              InkWell(
                onTap: () => _toggleFollow(uid),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isFollowing
                        ? (isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF1F5F9))
                        : null,
                    gradient: !isFollowing
                        ? const LinearGradient(
                            colors: [primaryPink, Color(0xFFFF5277)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    border: isFollowing
                        ? Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : const Color(0xFFCBD5E1),
                            width: 1,
                          )
                        : null,
                    boxShadow: !isFollowing
                        ? [
                            BoxShadow(
                              color: primaryPink.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    isFollowing
                        ? context.zevTr('following')
                        : context.zevTr('follow'),
                    style: TextStyle(
                      color: isFollowing
                          ? (isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B))
                          : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

  Widget _buildPeopleCard(
    Map<String, dynamic> user,
    int index,
    bool isDark, {
    required bool isMobile,
  }) {
    final uid = user['id']?.toString() ?? '';
    final name = "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}"
        .trim();
    final avatar = user['avatar_url']?.toString() ?? '';
    final coverUrl = user['cover_image_url']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';
    final bio = user['bio']?.toString() ?? '';
    final role = user['role']?.toString() ?? 'student';
    final isFollowing = _followingUserIds.contains(uid);

    final isAdmin = role == 'admin' || role == 'super_admin';
    final isTeacher = role == 'teacher';
    final roleColor = isAdmin
        ? Colors.deepPurple
        : (isTeacher ? Colors.blueAccent : primaryPink);
    final String? roleBadge = isAdmin
        ? "OFFICIAL 🛡️"
        : (isTeacher ? "TEACHER 🎓" : null);

    final bannerGradients = [
      [const Color(0xFF6A11CB), const Color(0xFF2575FC)],
      [const Color(0xFFFC466B), const Color(0xFFFF8E53)],
      [const Color(0xFF11998E), const Color(0xFF38EF7D)],
      [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)],
      [const Color(0xFFF857A6), const Color(0xFFFF5858)],
    ];
    final cardGradient = bannerGradients[index % bannerGradients.length];
    final double coverHeight = isMobile ? 130.0 : 110.0;
    final double avatarRadius = isMobile ? 38.0 : 34.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => UserProfileScreen(userId: uid)),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111422) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.black.withValues(alpha: 0.07),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Large Top Cover Page Banner
                SizedBox(
                  height: coverHeight,
                  width: double.infinity,
                  child: coverUrl.isNotEmpty
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: coverHeight,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: cardGradient,
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                  ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withValues(alpha: 0.0),
                                    Colors.black.withValues(alpha: 0.35),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: cardGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                ),

                // 2. Centered Profile Avatar Overlapping Cover
                Transform.translate(
                  offset: Offset(0, -avatarRadius),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF111422) : Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: avatarRadius,
                      backgroundColor: primaryPink.withValues(alpha: 0.15),
                      backgroundImage: avatar.isNotEmpty
                          ? NetworkImage(avatar)
                          : null,
                      child: avatar.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'Z',
                              style: TextStyle(
                                color: primaryPink,
                                fontSize: avatarRadius * 0.7,
                                fontWeight: FontWeight.w900,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),

                // 3. User Identity Information (Above the button)
                Transform.translate(
                  offset: Offset(0, -avatarRadius + 8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
                        // Name and Badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                name.isNotEmpty ? name : 'ZEV User',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            if (roleBadge != null) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: roleColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: roleColor.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Text(
                                  roleBadge,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: roleColor,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Username
                        if (username.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            "@$username",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: primaryPink,
                            ),
                          ),
                        ],

                        // Community tag / Bio
                        const SizedBox(height: 6),
                        Text(
                          bio.isNotEmpty ? bio : "Member of ZEV Community",
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: isDark
                                ? Colors.white54
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // 4. Follow Action Button at the very bottom of the card
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: ElevatedButton(
                      onPressed: () => _toggleFollow(uid),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFollowing
                            ? (isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF1F5F9))
                            : primaryPink,
                        foregroundColor: isFollowing
                            ? (isDark
                                  ? Colors.white70
                                  : const Color(0xFF334155))
                            : Colors.white,
                        elevation: isFollowing ? 0 : 3,
                        shadowColor: primaryPink.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: isFollowing
                              ? BorderSide(
                                  color: isDark
                                      ? Colors.white12
                                      : const Color(0xFFE2E8F0),
                                  width: 1.2,
                                )
                              : BorderSide.none,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        isFollowing
                            ? context.zevTr('following')
                            : context.zevTr('follow'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
