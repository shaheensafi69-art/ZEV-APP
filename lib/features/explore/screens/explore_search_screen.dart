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
          .select('id, first_name, last_name, avatar_url, cover_image_url, bio, role, username')
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
          .select('id, first_name, last_name, avatar_url, cover_image_url, bio, role, username')
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.68,
      ),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final user = list[index];
        final uid = user['id']?.toString() ?? '';
        final name =
            "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}".trim();
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

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(userId: uid),
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111422) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  children: [
                    // Top banner / cover image header
                    SizedBox(
                      height: 84,
                      width: double.infinity,
                      child: coverUrl.isNotEmpty
                          ? Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 84,
                              errorBuilder: (_, __, ___) => Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: cardGradient,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),
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
                    // Centered Avatar overlapping banner
                    Transform.translate(
                      offset: const Offset(0, -30),
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? const Color(0xFF111422)
                              : Colors.white,
                        ),
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor: primaryPink.withValues(alpha: 0.15),
                          backgroundImage: avatar.isNotEmpty
                              ? NetworkImage(avatar)
                              : null,
                          child: avatar.isEmpty
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'Z',
                                  style: const TextStyle(
                                    color: primaryPink,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    // User info & action
                    Transform.translate(
                      offset: const Offset(0, -24),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          children: [
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
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                if (roleBadge != null) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: roleColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      roleBadge,
                                      style: TextStyle(
                                        fontSize: 7.5,
                                        fontWeight: FontWeight.w900,
                                        color: roleColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (username.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                "@$username",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: primaryPink,
                                ),
                              ),
                            ],
                            const SizedBox(height: 5),
                            Text(
                              bio.isNotEmpty ? bio : "Member of ZEV Community",
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: isDark
                                    ? Colors.white54
                                    : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 14),
                            // Web Follow Action Button at bottom
                            SizedBox(
                              width: double.infinity,
                              height: 34,
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
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: isFollowing
                                        ? BorderSide(
                                            color: isDark
                                                ? Colors.white12
                                                : const Color(0xFFE2E8F0),
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
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildPeopleMobileList(List<Map<String, dynamic>> list, bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, _) =>
          Divider(color: isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
      itemBuilder: (context, index) {
        final user = list[index];
        final uid = user['id']?.toString() ?? '';
        final name =
            "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}".trim();
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
              MaterialPageRoute(builder: (_) => UserProfileScreen(userId: uid)),
            );
          },
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: primaryPink.withValues(alpha: 0.15),
            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
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
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
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
                    border: Border.all(color: roleColor.withValues(alpha: 0.2)),
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
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
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
    );
  }
}
