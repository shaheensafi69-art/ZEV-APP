import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import 'profile_screen.dart';

/// Full Dedicated Screen for Followers & Following on ZEV.
/// Replaces the bottom sheet with a 100% full-screen Claymorphic experience,
/// supporting responsive layout, live search, follow/unfollow actions, and tab switching.
class UserFollowsScreen extends StatefulWidget {
  final String userId;
  final String username;
  final int initialTabIndex; // 0 = Followers, 1 = Following

  const UserFollowsScreen({
    super.key,
    required this.userId,
    required this.username,
    this.initialTabIndex = 0,
  });

  static Future<void> open(
    BuildContext context, {
    required String userId,
    required String username,
    int initialTabIndex = 0,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserFollowsScreen(
          userId: userId,
          username: username,
          initialTabIndex: initialTabIndex,
        ),
      ),
    );
  }

  @override
  State<UserFollowsScreen> createState() => _UserFollowsScreenState();
}

class _UserFollowsScreenState extends State<UserFollowsScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TabController _tabCtrl;
  final TextEditingController _searchCtrl = TextEditingController();

  int _activeTabIndex = 0;

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
    _activeTabIndex = widget.initialTabIndex;
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );

    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging || _tabCtrl.index != _activeTabIndex) {
        setState(() => _activeTabIndex = _tabCtrl.index);
      }
    });

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
          final username = (u['username'] ?? '').toString().toLowerCase();
          final name = (u['name'] ?? '').toString().toLowerCase();
          return username.contains(q) || name.contains(q);
        }).toList();

        _filteredFollowing = _following.where((u) {
          final username = (u['username'] ?? '').toString().toLowerCase();
          final name = (u['name'] ?? '').toString().toLowerCase();
          return username.contains(q) || name.contains(q);
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

      if (mounted) {
        setState(() {
          _myFollowedIds.clear();
          for (final row in (res as List)) {
            final fId = row['following_id']?.toString();
            if (fId != null) _myFollowedIds.add(fId);
          }
        });
      }
    } catch (e) {
      debugPrint("Fetch my follows error: $e");
    }
  }

  Future<void> _fetchFollowers() async {
    try {
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
      // Rollback on error
      if (mounted) {
        setState(() {
          if (isFollowing) {
            _myFollowedIds.add(targetUserId);
          } else {
            _myFollowedIds.remove(targetUserId);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF0F172A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.people_alt_rounded,
                    size: 15,
                    color: Color(0xFF0284C7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "@${widget.username}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Clay Segmented Tab Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                    const BoxShadow(
                      color: Colors.white,
                      blurRadius: 4,
                      offset: Offset(0, -1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildClayTabItem(
                        index: 0,
                        label: "Followers",
                        count: _followers.length,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _buildClayTabItem(
                        index: 1,
                        label: "Following",
                        count: _following.length,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Clay Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.95),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                    const BoxShadow(
                      color: Colors.white,
                      blurRadius: 5,
                      offset: Offset(0, -1),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: const InputDecoration(
                          hintText: "Search people...",
                          hintStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_searchCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _searchCtrl.clear();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE2E8F0),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildUserList(
                    items: _filteredFollowers,
                    isLoading: _isLoadingFollowers,
                    emptyTitle: "No followers yet",
                    emptySubtitle:
                        "When people follow @${widget.username}, they'll appear here.",
                    icon: Icons.people_outline_rounded,
                  ),
                  _buildUserList(
                    items: _filteredFollowing,
                    isLoading: _isLoadingFollowing,
                    emptyTitle: "Not following anyone",
                    emptySubtitle:
                        "@${widget.username} isn't following anyone yet.",
                    icon: Icons.person_add_alt_1_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClayTabItem({
    required int index,
    required String label,
    required int count,
  }) {
    final isSelected = _activeTabIndex == index;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _tabCtrl.animateTo(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(
                  color: Colors.white,
                  width: 1.2,
                )
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                  const BoxShadow(
                    color: Colors.white,
                    blurRadius: 4,
                    offset: Offset(0, -1),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                    : const Color(0xFFCBD5E1).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 9999
                    ? "${(count / 1000).toStringAsFixed(1)}K"
                    : count.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isSelected
                      ? const Color(0xFF0284C7)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList({
    required List<Map<String, dynamic>> items,
    required bool isLoading,
    required String emptyTitle,
    required String emptySubtitle,
    required IconData icon,
  }) {
    if (isLoading) {
      return _buildClayShimmerList();
    }

    if (items.isEmpty) {
      return _buildClayEmptyState(
        icon: icon,
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }

    final currentUserId = supabase.auth.currentUser?.id;

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final u = items[index];
        final id = u['id'] as String;
        final username = u['username'] as String;
        final name = u['name'] as String;
        final avatar = u['avatar_url'] as String;
        final isVerified = u['is_verified'] == true;
        final isMe = currentUserId != null && currentUserId == id;
        final isFollowing = _myFollowedIds.contains(id);

        return _buildClayUserCard(
          id: id,
          username: username,
          name: name,
          avatar: avatar,
          isVerified: isVerified,
          isMe: isMe,
          isFollowing: isFollowing,
        );
      },
    );
  }

  Widget _buildClayUserCard({
    required String id,
    required String username,
    required String name,
    required String avatar,
    required bool isVerified,
    required bool isMe,
    required bool isFollowing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                ProfileScreen.open(context, userId: id);
              },
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF0F172A).withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: avatar.isNotEmpty
                          ? ZevCachedImage.avatar(
                              imageUrl: avatar,
                              size: 46,
                            )
                          : Container(
                              color: const Color(0xFFE2E8F0),
                              child: const Icon(
                                Icons.person_rounded,
                                color: Color(0xFF94A3B8),
                                size: 24,
                              ),
                            ),
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
                                username,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.2,
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
                                color: Color(0xFF0284C7),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
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
          const SizedBox(width: 10),
          if (!isMe)
            _buildClayFollowButton(
              userId: id,
              username: username,
              isFollowing: isFollowing,
            ),
        ],
      ),
    );
  }

  Widget _buildClayFollowButton({
    required String userId,
    required String username,
    required bool isFollowing,
  }) {
    return GestureDetector(
      onTap: () => _toggleFollow(userId, username),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isFollowing ? const Color(0xFFF1F5F9) : const Color(0xFF0284C7),
          borderRadius: BorderRadius.circular(14),
          border: isFollowing
              ? Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 1.2,
                )
              : null,
          boxShadow: isFollowing
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                  const BoxShadow(
                    color: Colors.white,
                    blurRadius: 3,
                    offset: Offset(0, -1),
                  ),
                ],
        ),
        child: Text(
          isFollowing ? "Following" : "Follow",
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: isFollowing ? const Color(0xFF0F172A) : Colors.white,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }

  Widget _buildClayEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                  const BoxShadow(
                    color: Colors.white,
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: 38,
                color: const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClayShimmerList() {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
      itemCount: 8,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFFE2E8F0),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 80,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 76,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

