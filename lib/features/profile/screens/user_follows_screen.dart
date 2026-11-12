import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import 'profile_screen.dart';

/// Full Dedicated Screen for Followers, Following & Follow Requests on ZEV.
/// Light Clearmorphic experience with private-account gating, live search,
/// follow/request management, and owner follower removal.
class UserFollowsScreen extends StatefulWidget {
  final String userId;
  final String username;
  final int initialTabIndex; // 0 = Followers, 1 = Following, 2 = Requests (owner)

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

  bool get _isOwner {
    final me = supabase.auth.currentUser?.id;
    return me != null && me == widget.userId;
  }

  bool _isCheckingPolicy = false;
  bool _canViewContent = true;
  bool _isBlocked = false;

  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _filteredFollowers = [];
  bool _isLoadingFollowers = true;

  List<Map<String, dynamic>> _following = [];
  List<Map<String, dynamic>> _filteredFollowing = [];
  bool _isLoadingFollowing = true;

  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _filteredRequests = [];
  bool _isLoadingRequests = false;

  final Set<String> _myFollowedIds = {};
  final Set<String> _myRequestedIds = {};

  @override
  void initState() {
    super.initState();
    final tabCount = _isOwner ? 3 : 2;
    _activeTabIndex = widget.initialTabIndex.clamp(0, tabCount - 1);
    _tabCtrl = TabController(
      length: tabCount,
      vsync: this,
      initialIndex: _activeTabIndex,
    );

    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging || _tabCtrl.index != _activeTabIndex) {
        setState(() => _activeTabIndex = _tabCtrl.index);
      }
    });

    _searchCtrl.addListener(_onSearchChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!_isOwner) {
      setState(() => _isCheckingPolicy = true);
      final policy = await SocialGraphService.instance.getInteractionPolicy(
        widget.userId,
      );
      final blocked = policy['is_blocked'] == true;
      final canView = policy['can_view_content'] != false && !blocked;
      if (!mounted) return;
      setState(() {
        _isCheckingPolicy = false;
        _isBlocked = blocked;
        _canViewContent = canView;
      });
      if (!canView) {
        setState(() {
          _isLoadingFollowers = false;
          _isLoadingFollowing = false;
        });
        return;
      }
    }

    _fetchFollowers();
    _fetchFollowing();
    _fetchMyFollows();
    if (_isOwner) {
      _fetchRequests();
    }
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
        _filteredRequests = List.from(_requests);
      } else {
        bool matches(Map<String, dynamic> u) {
          final username = (u['username'] ?? '').toString().toLowerCase();
          final name = (u['name'] ?? u['full_name'] ?? '').toString().toLowerCase();
          return username.contains(q) || name.contains(q);
        }

        _filteredFollowers = _followers.where(matches).toList();
        _filteredFollowing = _following.where(matches).toList();
        _filteredRequests = _requests.where(matches).toList();
      }
    });
  }

  Future<void> _fetchMyFollows() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final [followsRes, reqsRes] = await Future.wait([
        supabase
            .from('user_follows')
            .select('following_id')
            .eq('follower_id', currentUserId),
        supabase
            .from('follow_requests')
            .select('target_id')
            .eq('requester_id', currentUserId)
            .eq('status', 'pending'),
      ]);

      if (mounted) {
        setState(() {
          _myFollowedIds.clear();
          for (final row in (followsRes as List)) {
            final fId = row['following_id']?.toString();
            if (fId != null && fId.isNotEmpty) _myFollowedIds.add(fId);
          }
          _myRequestedIds.clear();
          for (final row in (reqsRes as List)) {
            final tId = row['target_id']?.toString();
            if (tId != null && tId.isNotEmpty) _myRequestedIds.add(tId);
          }
        });
      }
    } catch (e) {
      debugPrint("Fetch my follows error: $e");
    }
  }

  Future<void> _fetchRequests() async {
    if (!_isOwner) return;
    if (mounted) setState(() => _isLoadingRequests = true);
    try {
      final reqs =
          await SocialGraphService.instance.fetchPendingIncomingRequests();
      if (mounted) {
        setState(() {
          _requests = reqs;
          _filteredRequests = List.from(reqs);
          _isLoadingRequests = false;
        });
        _onSearchChanged();
      }
    } catch (e) {
      debugPrint("Fetch requests error: $e");
      if (mounted) setState(() => _isLoadingRequests = false);
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
        _onSearchChanged();
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
        _onSearchChanged();
      }
    } catch (e) {
      debugPrint("Fetch following error: $e");
      if (mounted) setState(() => _isLoadingFollowing = false);
    }
  }

  Future<void> _toggleFollow(String targetUserId, String username) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId == targetUserId) return;

    HapticFeedback.lightImpact();
    final status = await SocialGraphService.instance.toggleFollow(targetUserId);
    if (!mounted) return;

    setState(() {
      switch (status) {
        case FollowToggleStatus.following:
          _myFollowedIds.add(targetUserId);
          _myRequestedIds.remove(targetUserId);
          break;
        case FollowToggleStatus.requested:
          _myRequestedIds.add(targetUserId);
          _myFollowedIds.remove(targetUserId);
          break;
        case FollowToggleStatus.unfollowed:
        case FollowToggleStatus.cancelled:
          _myFollowedIds.remove(targetUserId);
          _myRequestedIds.remove(targetUserId);
          break;
        case FollowToggleStatus.blocked:
        case FollowToggleStatus.error:
          break;
      }
    });

    if (status == FollowToggleStatus.blocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot follow @$username.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ZevColors.deepNavy,
        ),
      );
    } else if (status == FollowToggleStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update follow status.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ZevColors.errorRed,
        ),
      );
    }
  }

  Future<void> _confirmRemoveFollower(
    String followerId,
    String username,
  ) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZevColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Remove Follower?',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: ZevColors.deepNavy,
          ),
        ),
        content: Text(
          'ZEV won\'t tell @$username they were removed from your followers.',
          style: const TextStyle(
            color: ZevColors.textSecondary,
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ZevColors.errorRed,
              foregroundColor: ZevColors.white,
              elevation: 0,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await SocialGraphService.instance.removeFollower(followerId);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _followers.removeWhere((u) => u['id'] == followerId);
        _filteredFollowers.removeWhere((u) => u['id'] == followerId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed @$username from followers'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ZevColors.deepNavy,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove follower'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ZevColors.errorRed,
        ),
      );
    }
  }

  Future<void> _handleRequestAction(
    Map<String, dynamic> req, {
    required bool accept,
  }) async {
    final requestId = (req['request_id'] ?? '').toString();
    final username = (req['username'] ?? 'user').toString();
    if (requestId.isEmpty) return;

    HapticFeedback.lightImpact();
    final ok = accept
        ? await SocialGraphService.instance.acceptFollowRequest(requestId)
        : await SocialGraphService.instance.rejectFollowRequest(requestId);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _requests.removeWhere((r) => r['request_id'] == requestId);
        _filteredRequests.removeWhere((r) => r['request_id'] == requestId);
      });
      if (accept) {
        _fetchFollowers();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Accepted @$username'
                : 'Declined follow request from @$username',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ZevColors.deepNavy,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update follow request'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ZevColors.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
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
                color: ZevColors.secondaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.people_alt_rounded,
                    size: 15,
                    color: ZevColors.secondaryBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "@${widget.username}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
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
        child: _isCheckingPolicy
            ? const Center(
                child: CircularProgressIndicator(color: ZevColors.primaryBlue),
              )
            : !_canViewContent
                ? _buildClayEmptyState(
                    icon: _isBlocked
                        ? Icons.block_rounded
                        : Icons.lock_outline_rounded,
                    title: _isBlocked
                        ? "Account Unavailable"
                        : "This Account is Private",
                    subtitle: _isBlocked
                        ? "Followers and following lists are unavailable."
                        : "Follow @${widget.username} to view their followers and following.",
                  )
                : Column(
                    children: [
                      const SizedBox(height: 12),
                      // Clay Segmented Tab Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: ZevColors.border,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: ZevColors.deepNavy.withValues(alpha: 0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                              const BoxShadow(
                                color: ZevColors.white,
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
                              if (_isOwner) ...[
                                const SizedBox(width: 4),
                                Expanded(
                                  child: _buildClayTabItem(
                                    index: 2,
                                    label: "Requests",
                                    count: _requests.length,
                                  ),
                                ),
                              ],
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
                            color: ZevColors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: ZevColors.white.withValues(alpha: 0.95),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: ZevColors.deepNavy.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                              const BoxShadow(
                                color: ZevColors.white,
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
                                  color: ZevColors.secondaryBlue.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.search_rounded,
                                  size: 16,
                                  color: ZevColors.secondaryBlue,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: ZevColors.deepNavy,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: "Search people...",
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: ZevColors.textMuted,
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
                                      color: ZevColors.border,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 13,
                                      color: ZevColors.textSecondary,
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
                              allowRemoveFollower: _isOwner,
                            ),
                            _buildUserList(
                              items: _filteredFollowing,
                              isLoading: _isLoadingFollowing,
                              emptyTitle: "Not following anyone",
                              emptySubtitle:
                                  "@${widget.username} isn't following anyone yet.",
                              icon: Icons.person_add_alt_1_outlined,
                            ),
                            if (_isOwner) _buildRequestsList(),
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
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? ZevColors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(color: ZevColors.white, width: 1.2)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: ZevColors.deepNavy.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                  const BoxShadow(
                    color: ZevColors.white,
                    blurRadius: 4,
                    offset: Offset(0, -1),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? ZevColors.deepNavy
                      : ZevColors.textSecondary,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? ZevColors.secondaryBlue.withValues(alpha: 0.14)
                      : ZevColors.textMuted.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count > 9999
                      ? "${(count / 1000).toStringAsFixed(1)}K"
                      : count.toString(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: isSelected
                        ? ZevColors.secondaryBlue
                        : ZevColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
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
    bool allowRemoveFollower = false,
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
        final isRequested = _myRequestedIds.contains(id);

        return _buildClayUserCard(
          id: id,
          username: username,
          name: name,
          avatar: avatar,
          isVerified: isVerified,
          isMe: isMe,
          isFollowing: isFollowing,
          isRequested: isRequested,
          allowRemoveFollower: allowRemoveFollower,
        );
      },
    );
  }

  Widget _buildRequestsList() {
    if (_isLoadingRequests) {
      return _buildClayShimmerList();
    }
    if (_filteredRequests.isEmpty) {
      return _buildClayEmptyState(
        icon: Icons.mark_email_read_outlined,
        title: "No Follow Requests",
        subtitle:
            "When people request to follow your private account, they'll appear here.",
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
      itemCount: _filteredRequests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final req = _filteredRequests[index];
        final requesterId = (req['requester_id'] ?? '').toString();
        final username = (req['username'] ?? 'user').toString();
        final fullName = (req['full_name'] ?? username).toString();
        final avatar = (req['avatar_url'] ?? '').toString();
        final isVerified = req['is_verified'] == true;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: ZevColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ZevColors.white.withValues(alpha: 0.95),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: ZevColors.deepNavy.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
              const BoxShadow(
                color: ZevColors.white,
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
                  onTap: () => ProfileScreen.open(context, userId: requesterId),
                  child: Row(
                    children: [
                      ZevCachedImage.avatar(imageUrl: avatar, size: 46),
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: ZevColors.deepNavy,
                                    ),
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
                            const SizedBox(height: 2),
                            Text(
                              fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
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
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _handleRequestAction(req, accept: true),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: ZevColors.secondaryBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _handleRequestAction(req, accept: false),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: ZevColors.softSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ZevColors.border),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
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
    required bool isRequested,
    bool allowRemoveFollower = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ZevColors.white.withValues(alpha: 0.95),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          const BoxShadow(
            color: ZevColors.white,
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
                        color: ZevColors.secondaryBlue.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.deepNavy.withValues(alpha: 0.06),
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
                              color: ZevColors.border,
                              child: const Icon(
                                Icons.person_rounded,
                                color: ZevColors.textMuted,
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
                                  color: ZevColors.deepNavy,
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
                                color: ZevColors.primaryBlue,
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
                            color: ZevColors.textSecondary,
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
          const SizedBox(width: 8),
          if (!isMe)
            _buildClayFollowButton(
              userId: id,
              username: username,
              isFollowing: isFollowing,
              isRequested: isRequested,
            ),
          if (allowRemoveFollower && !isMe) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Remove follower',
              child: GestureDetector(
                onTap: () => _confirmRemoveFollower(id, username),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: ZevColors.softSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: ZevColors.border),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClayFollowButton({
    required String userId,
    required String username,
    required bool isFollowing,
    required bool isRequested,
  }) {
    final isPassive = isFollowing || isRequested;
    final label = isFollowing
        ? "Following"
        : (isRequested ? "Requested" : "Follow");

    return GestureDetector(
      onTap: () => _toggleFollow(userId, username),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isPassive ? ZevColors.softSurface : ZevColors.secondaryBlue,
          borderRadius: BorderRadius.circular(14),
          border: isPassive
              ? Border.all(color: ZevColors.border, width: 1.2)
              : null,
          boxShadow: isPassive
              ? [
                  BoxShadow(
                    color: ZevColors.deepNavy.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [
                  BoxShadow(
                    color: ZevColors.secondaryBlue.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                  const BoxShadow(
                    color: ZevColors.white,
                    blurRadius: 3,
                    offset: Offset(0, -1),
                  ),
                ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: isPassive ? ZevColors.deepNavy : ZevColors.white,
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

