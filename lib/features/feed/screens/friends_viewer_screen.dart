import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../chat/screens/direct_chat_screen.dart';
import 'user_profile_screen.dart';

typedef StudentFriendsScreen = FriendsViewerScreen;
typedef TeacherFriendsScreen = FriendsViewerScreen;
typedef AdminFriendsScreen = FriendsViewerScreen;

class FriendsViewerScreen extends StatefulWidget {
  const FriendsViewerScreen({super.key});

  @override
  State<FriendsViewerScreen> createState() => _FriendsViewerScreenState();
}

class _FriendsViewerScreenState extends State<FriendsViewerScreen> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;

  List<Map<String, dynamic>> exploreUsers = [];
  List<Map<String, dynamic>> followersList = [];
  List<Map<String, dynamic>> followingList = [];
  List<Map<String, dynamic>> pendingRequests = [];
  Set<String> myFollowingIds = {};

  String activeTab = "explore"; // "explore", "followers", "following", "requests"
  String searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  @override
  void initState() {
    super.initState();
    _fetchSocialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSocialData() async {
    setState(() => isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }
      final myId = user.id;

      List<Map<String, dynamic>> followers = [];
      List<Map<String, dynamic>> following = [];
      Set<String> followingIds = {};

      // 1. Fetch Following & Followers from user_follows
      try {
        final followingRes = await supabase
            .from('user_follows')
            .select('following_id')
            .eq('follower_id', myId);

        for (var f in (followingRes as List)) {
          final fid = f['following_id']?.toString();
          if (fid != null && fid.isNotEmpty) {
            followingIds.add(fid);
          }
        }

        // Fetch profiles for followed users
        if (followingIds.isNotEmpty) {
          final followedProfiles = await supabase
              .from('profiles')
              .select('*')
              .inFilter('id', followingIds.toList());
          for (var p in (followedProfiles as List)) {
            following.add(p);
          }
        }

        // Fetch Followers
        final followersRes = await supabase
            .from('user_follows')
            .select('follower_id')
            .eq('following_id', myId);

        Set<String> followerIds = {};
        for (var f in (followersRes as List)) {
          final fid = f['follower_id']?.toString();
          if (fid != null && fid.isNotEmpty) {
            followerIds.add(fid);
          }
        }

        if (followerIds.isNotEmpty) {
          final followerProfiles = await supabase
              .from('profiles')
              .select('*')
              .inFilter('id', followerIds.toList());
          for (var p in (followerProfiles as List)) {
            followers.add(p);
          }
        }
      } catch (err) {
        debugPrint("user_follows table query note: $err. Falling back to student_friends.");
        // Fallback to student_friends if user_follows not populated
        final friendsRel = await supabase
            .from('student_friends')
            .select('*')
            .or('sender_id.eq.$myId,receiver_id.eq.$myId');

        for (var r in (friendsRel as List)) {
          if (r['status'] == 'accepted') {
            final otherId = (r['sender_id'] == myId) ? r['receiver_id'] : r['sender_id'];
            if (otherId != null) {
              final otherIdStr = otherId.toString();
              followingIds.add(otherIdStr);
              final p = await _fetchProfile(otherIdStr);
              if (p != null) {
                following.add(p);
                followers.add(p);
              }
            }
          }
        }
      }

      // 2. Fetch pending friend requests (if any from legacy system)
      List<Map<String, dynamic>> requests = [];
      try {
        final reqRes = await supabase
            .from('student_friends')
            .select('*')
            .eq('receiver_id', myId)
            .eq('status', 'pending');

        for (var r in (reqRes as List)) {
          final p = await _fetchProfile(r['sender_id'].toString());
          if (p != null) {
            requests.add({...p, 'rel_id': r['id']});
          }
        }
      } catch (_) {}

      // 3. Fetch explore/discover profiles
      final profilesRes = await supabase
          .from('profiles')
          .select('*')
          .neq('id', myId)
          .order('created_at', ascending: false)
          .limit(60);

      List<Map<String, dynamic>> explore = [];
      for (var p in (profilesRes as List)) {
        explore.add(p);
      }

      if (mounted) {
        setState(() {
          followingList = following;
          followersList = followers;
          exploreUsers = explore;
          pendingRequests = requests;
          myFollowingIds = followingIds;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching social data: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<Map<String, dynamic>?> _fetchProfile(String uId) async {
    try {
      final res = await supabase
          .from("profiles")
          .select("*")
          .eq("id", uId)
          .maybeSingle();
      return res;
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggleFollow(String targetUserId, String targetName) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final myId = user.id;

    final isFollowing = myFollowingIds.contains(targetUserId);

    setState(() {
      if (isFollowing) {
        myFollowingIds.remove(targetUserId);
        followingList.removeWhere((p) => p['id'].toString() == targetUserId);
      } else {
        myFollowingIds.add(targetUserId);
        final profile = exploreUsers.firstWhere(
          (p) => p['id'].toString() == targetUserId,
          orElse: () => followersList.firstWhere(
            (p) => p['id'].toString() == targetUserId,
            orElse: () => {'id': targetUserId, 'first_name': targetName},
          ),
        );
        if (!followingList.any((p) => p['id'].toString() == targetUserId)) {
          followingList.add(profile);
        }
      }
    });

    try {
      if (isFollowing) {
        // Unfollow
        try {
          await supabase
              .from('user_follows')
              .delete()
              .match({'follower_id': myId, 'following_id': targetUserId});
        } catch (_) {
          await supabase
              .from('student_friends')
              .delete()
              .or('and(sender_id.eq.$myId,receiver_id.eq.$targetUserId),and(sender_id.eq.$targetUserId,receiver_id.eq.$myId)');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Unfollowed $targetName"),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.grey[800],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        // Follow
        try {
          await supabase.from('user_follows').insert({
            'follower_id': myId,
            'following_id': targetUserId,
          });
        } catch (_) {
          await supabase.from('student_friends').upsert({
            'sender_id': myId,
            'receiver_id': targetUserId,
            'status': 'accepted',
          });
        }

        // Notify
        final myProfile = await supabase
            .from('profiles')
            .select('first_name, last_name')
            .eq('id', myId)
            .maybeSingle();
        final myName = myProfile != null
            ? "${myProfile['first_name'] ?? 'Someone'} ${myProfile['last_name'] ?? ''}".trim()
            : 'Someone';

        await supabase.from('user_notifications').insert({
          'user_id': targetUserId,
          'sender_id': myId,
          'title': "👤 New Follower",
          'message': "$myName started following you.",
          'notification_type': "follow",
          'link_url': "/profile?id=$myId",
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Following $targetName! ✨"),
              duration: const Duration(seconds: 2),
              backgroundColor: primaryPink,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error toggling follow: $e");
      // Revert on failure
      setState(() {
        if (isFollowing) {
          myFollowingIds.add(targetUserId);
        } else {
          myFollowingIds.remove(targetUserId);
        }
      });
    }
  }

  Future<void> _acceptRequest(String relId, String otherUserId) async {
    setState(() => isLoading = true);
    try {
      await supabase
          .from("student_friends")
          .update({'status': 'accepted'})
          .eq('id', relId);

      myFollowingIds.add(otherUserId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Request accepted! 🤝"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      await _fetchSocialData();
    } catch (e) {
      debugPrint("Error accepting request: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _declineRequest(String relId) async {
    setState(() => isLoading = true);
    try {
      await supabase.from("student_friends").delete().eq('id', relId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Request declined."),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      await _fetchSocialData();
    } catch (e) {
      debugPrint("Error declining request: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> activeList = [];
    if (activeTab == "explore") activeList = exploreUsers;
    if (activeTab == "followers") activeList = followersList;
    if (activeTab == "following") activeList = followingList;
    if (activeTab == "requests") activeList = pendingRequests;

    final filteredList = activeList.where((item) {
      final fullName = "${item['first_name'] ?? ''} ${item['last_name'] ?? ''}"
          .toLowerCase();
      final email = (item['email'] ?? '').toLowerCase();
      final country = (item['country'] ?? '').toLowerCase();
      final q = searchQuery.toLowerCase();
      return fullName.contains(q) || email.contains(q) || country.contains(q);
    }).toList();

    return ZevLoadingOverlay(
      isLoading: isLoading,
      message: "SYNCING COMMUNITY...",
      child: Scaffold(
        backgroundColor: surfaceWhite,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFFF0F5),
                surfaceWhite,
                lightPinkBg.withOpacity(0.3),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Instagram-style modern header ---
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [surfaceWhite, lightPinkBg.withOpacity(0.6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: primaryPink.withOpacity(0.15),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: primaryPink.withOpacity(0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [primaryPink, Color(0xFFFF85A2)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryPink.withOpacity(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.explore_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Discover & Connect",
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: textDark,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  "Follow friends, creators & grow your ZEV circle",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textGrey.withOpacity(0.9),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Refresh button
                          IconButton(
                            onPressed: _fetchSocialData,
                            icon: const Icon(Icons.refresh_rounded, color: primaryPink),
                            tooltip: "Refresh",
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // --- Instagram / TikTok style tab bar ---
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildTabChip(
                            label: "Discover",
                            icon: Icons.explore_outlined,
                            count: exploreUsers.length,
                            tabKey: "explore",
                          ),
                          const SizedBox(width: 8),
                          _buildTabChip(
                            label: "Followers",
                            icon: Icons.people_outline_rounded,
                            count: followersList.length,
                            tabKey: "followers",
                          ),
                          const SizedBox(width: 8),
                          _buildTabChip(
                            label: "Following",
                            icon: Icons.person_add_disabled_outlined,
                            count: followingList.length,
                            tabKey: "following",
                          ),
                          if (pendingRequests.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _buildTabChip(
                              label: "Requests",
                              icon: Icons.mail_outline_rounded,
                              count: pendingRequests.length,
                              tabKey: "requests",
                              isBadge: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- Modern search input ---
                    TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => searchQuery = val),
                      cursorColor: primaryPink,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: "Search by name, email, or country...",
                        hintStyle: TextStyle(
                          color: textGrey.withOpacity(0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: primaryPink,
                          size: 22,
                        ),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: textGrey),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => searchQuery = "");
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: cardBorder.withOpacity(0.7),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: primaryPink,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- User list with modern social media cards ---
                    filteredList.isNotEmpty
                        ? ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredList.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final userItem = filteredList[index];
                              final uId = userItem['id'].toString();
                              final name = "${userItem['first_name'] ?? ''} ${userItem['last_name'] ?? ''}".trim();
                              final avatar = userItem['avatar_url']?.toString() ?? '';
                              final country = userItem['country']?.toString() ?? 'Global Member';
                              final role = userItem['role']?.toString().toLowerCase() ?? 'student';
                              final score = userItem['total_score'] ?? 0;
                              final isFollowing = myFollowingIds.contains(uId);

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: surfaceWhite,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: cardBorder,
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.02),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    // User avatar with Instagram gradient ring
                                    GestureDetector(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => UserProfileScreen(userId: uId),
                                        ),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(2.5),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: const LinearGradient(
                                            colors: [
                                              primaryPink,
                                              Color(0xFFFF85A2),
                                              Color(0xFFBA68C8),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                        ),
                                        child: CircleAvatar(
                                          radius: 25,
                                          backgroundColor: surfaceWhite,
                                          child: CircleAvatar(
                                            radius: 23,
                                            backgroundColor: lightPinkBg,
                                            backgroundImage: avatar.isNotEmpty
                                                ? NetworkImage(avatar)
                                                : null,
                                            child: avatar.isEmpty
                                                ? Text(
                                                    name.isNotEmpty ? name[0].toUpperCase() : 'S',
                                                    style: const TextStyle(
                                                      color: primaryPink,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 18,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // User information
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => UserProfileScreen(userId: uId),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    name.isNotEmpty ? name : 'ZEV Member',
                                                    style: const TextStyle(
                                                      color: textDark,
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 14.5,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                _buildRoleBadge(role),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              "$country • ⚡ $score pts",
                                              style: TextStyle(
                                                color: textGrey.withOpacity(0.85),
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),

                                    // Actions (Follow / Message / Accept)
                                    if (activeTab == "requests") ...[
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            height: 34,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                              ),
                                              onPressed: () => _acceptRequest(userItem['rel_id'], uId),
                                              child: const Text(
                                                "Accept",
                                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          SizedBox(
                                            height: 34,
                                            width: 34,
                                            child: IconButton(
                                              style: IconButton.styleFrom(
                                                backgroundColor: cardBorder,
                                                padding: EdgeInsets.zero,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                              ),
                                              icon: const Icon(Icons.close_rounded, size: 16, color: textGrey),
                                              onPressed: () => _declineRequest(userItem['rel_id']),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ] else ...[
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Follow / Unfollow button
                                          SizedBox(
                                            height: 34,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: isFollowing ? cardBorder : primaryPink,
                                                foregroundColor: isFollowing ? textDark : Colors.white,
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  side: isFollowing
                                                      ? BorderSide(color: textGrey.withOpacity(0.2))
                                                      : BorderSide.none,
                                                ),
                                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                              ),
                                              onPressed: () => _toggleFollow(uId, name.isNotEmpty ? name : 'User'),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (isFollowing) ...[
                                                    const Icon(Icons.check_rounded, size: 14, color: textDark),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  Text(
                                                    isFollowing ? "Following" : "Follow",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: isFollowing ? textDark : Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),

                                          // Direct chat button
                                          Container(
                                            height: 34,
                                            width: 34,
                                            decoration: BoxDecoration(
                                              color: lightPinkBg,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(
                                                Icons.chat_bubble_outline_rounded,
                                                size: 16,
                                                color: primaryPink,
                                              ),
                                              onPressed: () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => DirectChatScreen(
                                                    peerId: uId,
                                                    peerName: name.isNotEmpty ? name : 'Student',
                                                    peerAvatar: avatar,
                                                  ),
                                                ),
                                              ),
                                              tooltip: "Message",
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          )
                        : Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.people_outline_rounded,
                                    size: 60,
                                    color: textGrey.withOpacity(0.3),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    activeTab == "followers"
                                        ? "No followers yet. Share reels to gain followers!"
                                        : activeTab == "following"
                                            ? "You haven't followed anyone yet."
                                            : "No members found.",
                                    style: const TextStyle(
                                      color: textGrey,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    Color bg;
    Color fg;
    String label;

    switch (role) {
      case 'admin':
        bg = Colors.red.withOpacity(0.12);
        fg = Colors.redAccent;
        label = "ADMIN";
        break;
      case 'teacher':
      case 'instructor':
        bg = Colors.purple.withOpacity(0.12);
        fg = Colors.purpleAccent;
        label = "TEACHER";
        break;
      default:
        bg = primaryPink.withOpacity(0.12);
        fg = primaryPink;
        label = "STUDENT";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTabChip({
    required String label,
    required IconData icon,
    required int count,
    required String tabKey,
    bool isBadge = false,
  }) {
    final isSelected = activeTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => activeTab = tabKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? primaryPink : cardBorder.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryPink.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : textGrey,
            ),
            const SizedBox(width: 6),
            Text(
              "$label ($count)",
              style: TextStyle(
                color: isSelected ? Colors.white : textDark,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ZevLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final String message;
  final Widget child;

  const ZevLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message = "LOADING...",
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.white.withOpacity(0.92),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  color: Color(0xFFFC466B),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 20),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
