import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/zev_localizations.dart';
import 'user_profile_screen.dart';
import '../../chat/screens/direct_chat_screen.dart';

class UserFollowsListScreen extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;
  final int initialTabIndex; // 0: Followers, 1: Following

  const UserFollowsListScreen({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    this.initialTabIndex = 0,
  });

  @override
  State<UserFollowsListScreen> createState() => _UserFollowsListScreenState();
}

class _UserFollowsListScreenState extends State<UserFollowsListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  List<Map<String, dynamic>> followers = [];
  List<Map<String, dynamic>> following = [];
  Set<String> myFollowingIds =
      {}; // IDs that the current logged in user follows

  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  static const Color primaryPink = Color(0xFFFF2B85);
  static const Color lightPinkBg = Color(0xFFFFF0F5);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF1E293B);
  static const Color textGrey = Color(0xFF64748B);
  static const Color cardBorder = Color(0xFFF1F5F9);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    final currentUserId = supabase.auth.currentUser?.id;

    try {
      // 1. Fetch current logged-in user's following list (to know if follow button should say "Following" or "Follow")
      if (currentUserId != null) {
        try {
          final myF = await supabase
              .from('user_follows')
              .select('following_id')
              .eq('follower_id', currentUserId);
          myFollowingIds = (myF as List)
              .map((e) => e['following_id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
        } catch (_) {}
      }

      // 2. Fetch Followers of target user
      List<String> followerIds = [];
      try {
        final fRes = await supabase
            .from('user_follows')
            .select('follower_id')
            .eq('following_id', widget.targetUserId);
        for (var item in (fRes as List)) {
          final id = item['follower_id']?.toString();
          if (id != null && id.isNotEmpty) followerIds.add(id);
        }
      } catch (_) {
        // Fallback to student_friends
        final fRes = await supabase
            .from('student_friends')
            .select('sender_id, receiver_id')
            .or(
              'sender_id.eq.${widget.targetUserId},receiver_id.eq.${widget.targetUserId}',
            )
            .eq('status', 'accepted');
        for (var f in (fRes as List)) {
          final sId = f['sender_id']?.toString();
          final rId = f['receiver_id']?.toString();
          final other = (sId == widget.targetUserId) ? rId : sId;
          if (other != null &&
              other.isNotEmpty &&
              !followerIds.contains(other)) {
            followerIds.add(other);
          }
        }
      }

      // 3. Fetch Following of target user
      List<String> followingIds = [];
      try {
        final fRes = await supabase
            .from('user_follows')
            .select('following_id')
            .eq('follower_id', widget.targetUserId);
        for (var item in (fRes as List)) {
          final id = item['following_id']?.toString();
          if (id != null && id.isNotEmpty) followingIds.add(id);
        }
      } catch (_) {
        // Fallback to student_friends
        final fRes = await supabase
            .from('student_friends')
            .select('sender_id, receiver_id')
            .or(
              'sender_id.eq.${widget.targetUserId},receiver_id.eq.${widget.targetUserId}',
            )
            .eq('status', 'accepted');
        for (var f in (fRes as List)) {
          final sId = f['sender_id']?.toString();
          final rId = f['receiver_id']?.toString();
          final other = (sId == widget.targetUserId) ? rId : sId;
          if (other != null &&
              other.isNotEmpty &&
              !followingIds.contains(other)) {
            followingIds.add(other);
          }
        }
      }

      // 4. Batch query profiles for followers
      List<Map<String, dynamic>> loadedFollowers = [];
      if (followerIds.isNotEmpty) {
        final res = await supabase
            .from('profiles')
            .select('id, first_name, last_name, avatar_url, role, bio')
            .inFilter('id', followerIds);
        loadedFollowers = List<Map<String, dynamic>>.from(res as List);
      }

      // 5. Batch query profiles for following
      List<Map<String, dynamic>> loadedFollowing = [];
      if (followingIds.isNotEmpty) {
        final res = await supabase
            .from('profiles')
            .select('id, first_name, last_name, avatar_url, role, bio')
            .inFilter('id', followingIds);
        loadedFollowing = List<Map<String, dynamic>>.from(res as List);
      }

      if (mounted) {
        setState(() {
          followers = loadedFollowers;
          following = loadedFollowing;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading follows data: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _toggleFollow(String otherUserId) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId == otherUserId) return;

    final isFollowing = myFollowingIds.contains(otherUserId);

    setState(() {
      if (isFollowing) {
        myFollowingIds.remove(otherUserId);
      } else {
        myFollowingIds.add(otherUserId);
      }
    });

    try {
      if (isFollowing) {
        await supabase
            .from('user_follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', otherUserId);
      } else {
        await supabase.from('user_follows').insert({
          'follower_id': currentUserId,
          'following_id': otherUserId,
        });
      }
    } catch (e) {
      debugPrint("Error toggling follow in list: $e");
      // Revert if error
      if (mounted) {
        setState(() {
          if (isFollowing) {
            myFollowingIds.add(otherUserId);
          } else {
            myFollowingIds.remove(otherUserId);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0B0F19)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF131926) : surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.targetUserName.isNotEmpty
              ? widget.targetUserName
              : context.zevTr('connections'),
          style: TextStyle(
            color: isDark ? Colors.white : textDark,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF1E293B) : cardBorder,
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: primaryPink,
              indicatorWeight: 3,
              labelColor: primaryPink,
              unselectedLabelColor: isDark ? Colors.white60 : textGrey,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              tabs: [
                Tab(
                  text: "${context.zevTr('followers')} (${followers.length})",
                ),
                Tab(
                  text: "${context.zevTr('following')} (${following.length})",
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Search box
          Container(
            color: isDark ? const Color(0xFF131926) : surfaceWhite,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) =>
                    setState(() => searchQuery = val.trim().toLowerCase()),
                style: TextStyle(
                  color: isDark ? Colors.white : textDark,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: "${context.zevTr('search')}...",
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : textGrey,
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: isDark ? Colors.white60 : textGrey,
                    size: 20,
                  ),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            color: textGrey,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: primaryPink),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildUserList(followers, isFollowersTab: true),
                      _buildUserList(following, isFollowersTab: false),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList(
    List<Map<String, dynamic>> list, {
    required bool isFollowersTab,
  }) {
    final currentUserId = supabase.auth.currentUser?.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filtered = list.where((user) {
      if (searchQuery.isEmpty) return true;
      final name = "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}"
          .toLowerCase();
      final role = (user['role'] ?? '').toString().toLowerCase();
      return name.contains(searchQuery) || role.contains(searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : lightPinkBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFollowersTab
                      ? Icons.people_outline_rounded
                      : Icons.person_search_rounded,
                  size: 48,
                  color: primaryPink,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                searchQuery.isNotEmpty
                    ? "No users found matching \"$searchQuery\""
                    : (isFollowersTab
                          ? "No followers yet"
                          : "Not following anyone yet"),
                style: TextStyle(
                  color: isDark ? Colors.white : textDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                isFollowersTab
                    ? "When someone follows this profile, they will appear here."
                    : "Profiles followed by this user will be listed here.",
                style: TextStyle(
                  color: isDark ? Colors.white60 : textGrey,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: primaryPink,
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final user = filtered[index];
          final uid = user['id']?.toString() ?? '';
          final name = "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}"
              .trim();
          final avatarUrl = user['avatar_url']?.toString() ?? '';
          final role = (user['role'] ?? 'student').toString().toUpperCase();
          final isMe = uid == currentUserId;
          final isFollowing = myFollowingIds.contains(uid);

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131926) : surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF1E293B) : cardBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Avatar
                GestureDetector(
                  onTap: () => _navigateToProfile(uid),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: lightPinkBg,
                    backgroundImage: avatarUrl.isNotEmpty
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: avatarUrl.isEmpty
                        ? const Icon(
                            Icons.person_rounded,
                            color: primaryPink,
                            size: 26,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),

                // Name & Role
                Expanded(
                  child: GestureDetector(
                    onTap: () => _navigateToProfile(uid),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isNotEmpty ? name : "User",
                          style: TextStyle(
                            color: isDark ? Colors.white : textDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: role == 'TEACHER'
                                    ? Colors.blue.withValues(alpha: 0.1)
                                    : (role == 'ADMIN'
                                          ? Colors.purple.withValues(alpha: 0.1)
                                          : lightPinkBg),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                role,
                                style: TextStyle(
                                  color: role == 'TEACHER'
                                      ? Colors.blue.shade700
                                      : (role == 'ADMIN'
                                            ? Colors.purple.shade700
                                            : primaryPink),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Action Buttons
                if (!isMe && currentUserId != null) ...[
                  // Message shortcut
                  IconButton(
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: textGrey,
                      size: 20,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DirectChatScreen(
                            peerId: uid,
                            peerName: name.isNotEmpty ? name : "User",
                            peerAvatar: avatarUrl,
                          ),
                        ),
                      );
                    },
                    tooltip: "Message",
                  ),
                  const SizedBox(width: 4),

                  // Follow / Following toggle button
                  InkWell(
                    onTap: () => _toggleFollow(uid),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isFollowing
                            ? (isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF1F5F9))
                            : primaryPink,
                        borderRadius: BorderRadius.circular(12),
                        border: isFollowing
                            ? Border.all(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFCBD5E1),
                              )
                            : null,
                      ),
                      child: Text(
                        isFollowing
                            ? context.zevTr('following')
                            : context.zevTr('follow'),
                        style: TextStyle(
                          color: isFollowing
                              ? (isDark ? Colors.white : textDark)
                              : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _navigateToProfile(String uid) {
    if (uid.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: uid)),
    );
  }
}
