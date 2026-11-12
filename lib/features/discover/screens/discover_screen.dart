import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_skeleton.dart';
import '../../../core/widgets/zev_video_thumbnail.dart';
import '../../profile/screens/profile_screen.dart';

/// Flagship Light Clearmorphic Discover People & Creators Screen for ZEV.
/// Backed by PostgreSQL `get_discover_creators` and `SocialGraphService.toggleFollow`.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  static Future<void> open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DiscoverScreen()),
    );
  }

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  String _selectedTab = "Suggested"; // "Suggested", "Popular", "New", "Verified"
  String _searchQuery = "";
  int _fetchGeneration = 0;
  Timer? _debounceTimer;

  List<Map<String, dynamic>> _creators = [];
  final Set<String> _busyFollowIds = {};

  final List<String> _tabs = ["Suggested", "Popular", "New", "Verified"];

  @override
  void initState() {
    super.initState();
    _fetchDiscoverData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDiscoverData() async {
    final int gen = ++_fetchGeneration;
    if (mounted && _creators.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final rawRes = await supabase.rpc(
        'get_discover_creators',
        params: {
          'p_tab': _selectedTab,
          'p_query': _searchQuery,
          'p_limit': 40,
        },
      );

      if (gen != _fetchGeneration) return;

      final rows = rawRes is List
          ? List<Map<String, dynamic>>.from(
              rawRes.map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : <Map<String, dynamic>>[];

      final List<Map<String, dynamic>> list = rows.map((p) {
        final fn = (p['first_name'] ?? '').toString();
        final ln = (p['last_name'] ?? '').toString();
        final full = "$fn $ln".trim();
        final username = (p['username'] ?? 'user').toString();

        final rawThumbs = p['media_thumbnails'];
        final thumbs = <String>[];
        if (rawThumbs is List) {
          for (final item in rawThumbs) {
            final u = item?.toString() ?? '';
            if (u.isNotEmpty) thumbs.add(u);
          }
        }

        return <String, dynamic>{
          'id': p['id']?.toString() ?? '',
          'username': username,
          'full_name': full.isNotEmpty ? full : username,
          'avatar_url': (p['avatar_url'] ?? '').toString(),
          'is_verified': p['is_verified'] == true,
          'is_private': p['is_private'] == true,
          'bio': (p['bio'] ?? '').toString(),
          'followers_count': (p['followers_count'] as num?)?.toInt() ?? 0,
          'posts_count': (p['posts_count'] as num?)?.toInt() ?? 0,
          'reels_count': (p['reels_count'] as num?)?.toInt() ?? 0,
          'is_following': p['is_following'] == true,
          'is_requested': p['is_requested'] == true,
          'media_thumbnails': thumbs,
        };
      }).toList();

      if (mounted && gen == _fetchGeneration) {
        setState(() {
          _creators = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching discover creators: $e");
      if (mounted && gen == _fetchGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleFollow(int index) async {
    final creator = _creators[index];
    final targetUserId = creator['id']?.toString() ?? '';
    final username = creator['username']?.toString() ?? 'user';
    if (targetUserId.isEmpty || _busyFollowIds.contains(targetUserId)) return;

    if (supabase.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to follow users.")),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _busyFollowIds.add(targetUserId));

    final status = await SocialGraphService.instance.toggleFollow(targetUserId);

    if (!mounted) return;
    setState(() {
      _busyFollowIds.remove(targetUserId);
      final updated = Map<String, dynamic>.from(_creators[index]);
      final currentFollowers =
          (updated['followers_count'] as num?)?.toInt() ?? 0;

      switch (status) {
        case FollowToggleStatus.following:
          if (updated['is_following'] != true) {
            updated['followers_count'] = currentFollowers + 1;
          }
          updated['is_following'] = true;
          updated['is_requested'] = false;
          break;
        case FollowToggleStatus.requested:
          updated['is_following'] = false;
          updated['is_requested'] = true;
          break;
        case FollowToggleStatus.unfollowed:
          if (updated['is_following'] == true && currentFollowers > 0) {
            updated['followers_count'] = currentFollowers - 1;
          }
          updated['is_following'] = false;
          updated['is_requested'] = false;
          break;
        case FollowToggleStatus.cancelled:
          updated['is_following'] = false;
          updated['is_requested'] = false;
          break;
        case FollowToggleStatus.blocked:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Cannot follow @$username.")),
          );
          break;
        case FollowToggleStatus.error:
          break;
      }
      _creators[index] = updated;
    });
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final clean = val.trim();
      if (clean != _searchQuery) {
        setState(() {
          _searchQuery = clean;
          _isLoading = true;
        });
        _fetchDiscoverData();
      }
    });
  }

  void _shareAppInvite() {
    HapticFeedback.lightImpact();
    Share.share(
      "Join me on ZEV - The Next Generation Social Network!\nDownload now and connect: https://zevapp.com",
      subject: "Join ZEV Social Network",
    );
  }

  bool _isVideoMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('.webm') ||
        lower.contains('.m4v');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "Discover People",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.share_rounded,
                size: 18,
                color: ZevColors.deepNavy,
              ),
            ),
            tooltip: "Invite Friends",
            onPressed: _shareAppInvite,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBox(),
          _buildFilterTabs(),
          Expanded(
            child: RefreshIndicator(
              color: ZevColors.primaryBlue,
              onRefresh: _fetchDiscoverData,
              child: _isLoading
                  ? _buildShimmerLoading()
                  : _creators.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 90),
                            _buildEmptyView(),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          itemCount: _creators.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _buildCreatorCard(index);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: Color(0xFF64748B),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ZevColors.deepNavy,
                ),
                decoration: const InputDecoration(
                  hintText: "Search creators by name, @username, or bio...",
                  hintStyle: TextStyle(
                    color: ZevColors.textMuted,
                    fontSize: 13.5,
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
                  size: 16,
                  color: Color(0xFF64748B),
                ),
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearchChanged("");
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      height: 44,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _tabs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = _tabs[index];
          final isSelected = tab == _selectedTab;

          return Center(
            child: GestureDetector(
              onTap: () {
                if (tab == _selectedTab) return;
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedTab = tab;
                  _isLoading = true;
                });
                _fetchDiscoverData();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? ZevColors.deepNavy
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  tab,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color:
                        isSelected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCreatorCard(int index) {
    final creator = _creators[index];
    final id = creator['id'] as String;
    final username = creator['username'] as String;
    final fullName = creator['full_name'] as String;
    final avatar = creator['avatar_url'] as String;
    final isVerified = creator['is_verified'] == true;
    final isPrivate = creator['is_private'] == true;
    final bio = creator['bio'] as String;
    final followersCount = (creator['followers_count'] as num?)?.toInt() ?? 0;
    final postsCount = (creator['posts_count'] as num?)?.toInt() ?? 0;
    final reelsCount = (creator['reels_count'] as num?)?.toInt() ?? 0;
    final isFollowing = creator['is_following'] == true;
    final isRequested = creator['is_requested'] == true;
    final isBusy = _busyFollowIds.contains(id);
    final thumbnails = (creator['media_thumbnails'] as List<String>?) ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => ProfileScreen.open(context, userId: id),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [ZevColors.primaryBlue, ZevColors.secondaryBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ZevColors.primaryBlue.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(2.0),
                  child: ClipOval(
                    child: avatar.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: avatar,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: const Color(0xFFE2E8F0)),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.person,
                              color: Colors.white70,
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 24,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: GestureDetector(
                  onTap: () => ProfileScreen.open(context, userId: id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              fullName,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: ZevColors.deepNavy,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                          if (isPrivate) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.lock_outline_rounded,
                              size: 13,
                              color: ZevColors.textMuted,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "@$username  •  $followersCount followers",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ZevColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),

              ElevatedButton(
                onPressed: isBusy ? null : () => _toggleFollow(index),
                style: ElevatedButton.styleFrom(
                  backgroundColor: (isFollowing || isRequested)
                      ? const Color(0xFFF1F5F9)
                      : ZevColors.primaryBlue,
                  foregroundColor: ZevColors.deepNavy,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: (isFollowing || isRequested)
                          ? const Color(0xFFE2E8F0)
                          : Colors.transparent,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  minimumSize: const Size(84, 34),
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
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ],
          ),

          if (bio.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              bio,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF334155),
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          if (thumbnails.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Row(
                children: List.generate(3, (idx) {
                  if (idx < thumbnails.length) {
                    final thumb = thumbnails[idx];
                    final isVideo = _isVideoMediaUrl(thumb);
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => ProfileScreen.open(context, userId: id),
                        child: Container(
                          height: 94,
                          margin: EdgeInsets.only(right: idx < 2 ? 4 : 0),
                          child: isVideo
                              ? ZevVideoThumbnail(
                                  videoUrl: thumb,
                                  showViews: false,
                                  showPlayBadge: true,
                                  fit: BoxFit.cover,
                                )
                              : CachedNetworkImage(
                                  imageUrl: thumb,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      Container(color: const Color(0xFFE2E8F0)),
                                  errorWidget: (context, url, error) =>
                                      Container(
                                    color: const Color(0xFFF1F5F9),
                                    child: const Icon(
                                      Icons.image_outlined,
                                      color: Color(0xFFCBD5E1),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    );
                  }
                  return Expanded(
                    child: Container(
                      height: 94,
                      margin: EdgeInsets.only(right: idx < 2 ? 4 : 0),
                      color: const Color(0xFFF8FAFC),
                      child: const Center(
                        child: Icon(
                          Icons.photo_camera_back_outlined,
                          color: Color(0xFFE2E8F0),
                          size: 24,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ] else if (postsCount > 0 || reelsCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: ZevColors.softSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ZevColors.border),
              ),
              child: Text(
                isPrivate && !isFollowing
                    ? "Private account • $postsCount posts • $reelsCount reels"
                    : "$postsCount posts • $reelsCount reels",
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: ZevColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                size: 36,
                color: ZevColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              "No Creators Found",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Try searching with another keyword or explore other tabs.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
      itemCount: 5,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: ZevColors.border),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ZevSkeleton(width: 48, height: 48, shape: BoxShape.circle),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ZevSkeleton(width: 120, height: 14),
                      SizedBox(height: 6),
                      ZevSkeleton(width: 160, height: 11),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                ZevSkeleton(width: 82, height: 34),
              ],
            ),
            SizedBox(height: 12),
            ZevSkeleton(width: double.infinity, height: 92),
          ],
        ),
      ),
    );
  }
}
