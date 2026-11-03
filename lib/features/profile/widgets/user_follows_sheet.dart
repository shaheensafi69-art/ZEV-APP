import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../screens/profile_screen.dart';

/// Serene, Instagram-Grade Followers & Following Bottom Sheet for ZEV.
/// Displays followers and following lists with search bar and live toggle actions.
class UserFollowsSheet extends StatefulWidget {
  final String userId;
  final String username;
  final int initialTabIndex; // 0 = Followers, 1 = Following

  const UserFollowsSheet({
    super.key,
    required this.userId,
    required this.username,
    this.initialTabIndex = 0,
  });

  static void show(
    BuildContext context, {
    required String userId,
    required String username,
    int initialTabIndex = 0,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UserFollowsSheet(
        userId: userId,
        username: username,
        initialTabIndex: initialTabIndex,
      ),
    );
  }

  @override
  State<UserFollowsSheet> createState() => _UserFollowsSheetState();
}

class _UserFollowsSheetState extends State<UserFollowsSheet>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TabController _tabCtrl;
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _filteredFollowers = [];
  bool _isLoadingFollowers = true;

  List<Map<String, dynamic>> _following = [];
  List<Map<String, dynamic>> _filteredFollowing = [];
  bool _isLoadingFollowing = true;

  final Set<String> _myFollowedIds = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );

    _searchCtrl.addListener(_onSearchChanged);
    _fetchFollowers();
    _fetchFollowing();
    _fetchMyFollows();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredFollowers = List.from(_followers);
        _filteredFollowing = List.from(_following);
      } else {
        _filteredFollowers = _followers.where((u) {
          final un = (u['username'] ?? '').toString().toLowerCase();
          final fn = (u['name'] ?? '').toString().toLowerCase();
          return un.contains(q) || fn.contains(q);
        }).toList();

        _filteredFollowing = _following.where((u) {
          final un = (u['username'] ?? '').toString().toLowerCase();
          final fn = (u['name'] ?? '').toString().toLowerCase();
          return un.contains(q) || fn.contains(q);
        }).toList();
      }
    });
  }

  Future<void> _fetchMyFollows() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;
    try {
      final res = await supabase
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', currentUserId);

      final ids = (res as List)
          .map((r) => r['following_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      if (mounted) setState(() => _myFollowedIds.addAll(ids));
    } catch (_) {}
  }

  Future<void> _fetchFollowers() async {
    try {
      // 1. Get follower IDs from user_follows
      final res = await supabase
          .from('user_follows')
          .select('follower_id')
          .eq('following_id', widget.userId);

      final userIds = (res as List)
          .map((r) => r['follower_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (userIds.isEmpty) {
        if (mounted) {
          setState(() {
            _followers = [];
            _filteredFollowers = [];
            _isLoadingFollowers = false;
          });
        }
        return;
      }

      // 2. Query profiles
      final profs = await supabase
          .from('profiles')
          .select(
            'id, username, first_name, last_name, avatar_url, is_verified',
          )
          .inFilter('id', userIds);

      final list = (profs as List).map((p) {
        final fn = p['first_name'] ?? '';
        final ln = p['last_name'] ?? '';
        final full = "$fn $ln".trim();
        return {
          'id': p['id'].toString(),
          'username': p['username'] ?? 'user',
          'name': full.isNotEmpty ? full : (p['username'] ?? 'User'),
          'avatar_url': p['avatar_url'] ?? '',
          'is_verified': p['is_verified'] == true,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _followers = list;
          _filteredFollowers = list;
          _isLoadingFollowers = false;
        });
      }
    } catch (e) {
      debugPrint("Fetch followers error: $e");
      if (mounted) setState(() => _isLoadingFollowers = false);
    }
  }

  Future<void> _fetchFollowing() async {
    try {
      final res = await supabase
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', widget.userId);

      final userIds = (res as List)
          .map((r) => r['following_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (userIds.isEmpty) {
        if (mounted) {
          setState(() {
            _following = [];
            _filteredFollowing = [];
            _isLoadingFollowing = false;
          });
        }
        return;
      }

      final profs = await supabase
          .from('profiles')
          .select(
            'id, username, first_name, last_name, avatar_url, is_verified',
          )
          .inFilter('id', userIds);

      final list = (profs as List).map((p) {
        final fn = p['first_name'] ?? '';
        final ln = p['last_name'] ?? '';
        final full = "$fn $ln".trim();
        return {
          'id': p['id'].toString(),
          'username': p['username'] ?? 'user',
          'name': full.isNotEmpty ? full : (p['username'] ?? 'User'),
          'avatar_url': p['avatar_url'] ?? '',
          'is_verified': p['is_verified'] == true,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _following = list;
          _filteredFollowing = list;
          _isLoadingFollowing = false;
        });
      }
    } catch (e) {
      debugPrint("Fetch following error: $e");
      if (mounted) setState(() => _isLoadingFollowing = false);
    }
  }

  Future<void> _toggleFollow(String targetUserId, String username) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    HapticFeedback.lightImpact();
    final isFollowing = _myFollowedIds.contains(targetUserId);

    setState(() {
      if (isFollowing) {
        _myFollowedIds.remove(targetUserId);
      } else {
        _myFollowedIds.add(targetUserId);
      }
    });

    try {
      if (isFollowing) {
        await supabase
            .from('user_follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', targetUserId);

        try {
          await supabase.from('student_friends').delete().match({
            'user_id': currentUserId,
            'friend_id': targetUserId,
          });
        } catch (_) {}
      } else {
        await supabase.from('user_follows').insert({
          'follower_id': currentUserId,
          'following_id': targetUserId,
        });

        try {
          await supabase.from('student_friends').upsert({
            'user_id': currentUserId,
            'friend_id': targetUserId,
            'status': 'accepted',
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}

        unawaited(
          NotificationService().sendNotificationToUser(
            targetUserId: targetUserId,
            title: "New Follower",
            message: "Started following you on ZEV",
            notificationType: "follow",
            senderId: currentUserId,
          ).catchError((err) {
            debugPrint("Notification dispatch notice: $err");
          }),
        );
      }
    } catch (e) {
      debugPrint("Toggle follow error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.78,
      decoration: const BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 38,
            height: 4.5,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 10),

          // User title
          Text(
            widget.username,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ZevColors.deepNavy,
            ),
          ),
          const SizedBox(height: 8),

          // Tab Bar
          TabBar(
            controller: _tabCtrl,
            indicatorColor: ZevColors.primaryBlue,
            indicatorWeight: 2.5,
            labelColor: ZevColors.deepNavy,
            unselectedLabelColor: ZevColors.textMuted,
            labelStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            tabs: [
              Tab(text: "${_followers.length} Followers"),
              Tab(text: "${_following.length} Following"),
            ],
          ),
          const Divider(height: 1, color: ZevColors.border),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: ZevColors.softSurface,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: ZevColors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 13, color: ZevColors.deepNavy),
                decoration: const InputDecoration(
                  hintText: "Search",
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: ZevColors.textMuted,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: ZevColors.textMuted,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildUserList(
                  items: _filteredFollowers,
                  isLoading: _isLoadingFollowers,
                  emptyText: "No followers yet",
                ),
                _buildUserList(
                  items: _filteredFollowing,
                  isLoading: _isLoadingFollowing,
                  emptyText: "Not following anyone yet",
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList({
    required List<Map<String, dynamic>> items,
    required bool isLoading,
    required String emptyText,
  }) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: ZevColors.primaryBlue,
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Text(
          emptyText,
          style: const TextStyle(fontSize: 13, color: ZevColors.textMuted),
        ),
      );
    }

    final currentUserId = supabase.auth.currentUser?.id;

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final u = items[index];
        final id = u['id'] as String;
        final username = u['username'] as String;
        final name = u['name'] as String;
        final avatar = u['avatar_url'] as String;
        final isVerified = u['is_verified'] == true;
        final isMe = currentUserId != null && currentUserId == id;
        final isFollowing = _myFollowedIds.contains(id);

        return Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                  ProfileScreen.open(context, userId: id);
                },
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: ZevColors.softSurface,
                      backgroundImage:
                          avatar.isNotEmpty ? NetworkImage(avatar) : null,
                      child: avatar.isEmpty
                          ? const Icon(
                              Icons.person,
                              color: ZevColors.textMuted,
                              size: 22,
                            )
                          : null,
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
                                  username,
                                  style: const TextStyle(
                                    fontSize: 13.5,
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
                                  size: 14,
                                  color: ZevColors.primaryBlue,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: ZevColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!isMe)
              SizedBox(
                height: 32,
                child: ElevatedButton(
                  onPressed: () => _toggleFollow(id, username),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFollowing
                        ? ZevColors.softSurface
                        : const Color(0xFF0095F6),
                    foregroundColor: isFollowing
                        ? ZevColors.deepNavy
                        : Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: isFollowing
                          ? const BorderSide(color: ZevColors.border)
                          : BorderSide.none,
                    ),
                  ),
                  child: Text(
                    isFollowing ? "Following" : "Follow",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isFollowing ? ZevColors.deepNavy : Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
