import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../profile/screens/profile_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
    );
  }

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final TabController _tabCtrl;

  String _timeRange = 'weekly'; // 'weekly', 'all_time'
  List<Map<String, dynamic>> _topCreators = [];
  List<Map<String, dynamic>> _topGifters = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadLeaderboard();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch top earners / creators (profiles ordered by coins_balance or creator_points)
      final creatorsRes = await _supabase
          .from('profiles')
          .select('id, username, full_name, avatar_url, is_verified, coins_balance')
          .order('coins_balance', ascending: false)
          .limit(50);

      // 2. Fetch top gifters (from coin_transactions or profiles)
      final giftersRes = await _supabase
          .from('profiles')
          .select('id, username, full_name, avatar_url, is_verified, coins_balance')
          .order('coins_balance', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          _topCreators = List<Map<String, dynamic>>.from(creatorsRes);
          // Reverse order or simulate gifters ranking if needed
          _topGifters = List<Map<String, dynamic>>.from(giftersRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[LeaderboardScreen] error: $e');
      if (mounted) setState(() => _isLoading = false);
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Hall of Fame & Leaderboard",
          style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 17),
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _timeRange == 'weekly' ? "Weekly" : "All-Time",
                    style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF0284C7), size: 16),
                ],
              ),
            ),
            onSelected: (val) {
              setState(() => _timeRange = val);
              _loadLeaderboard();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'weekly', child: Text("Weekly Ranking")),
              PopupMenuItem(value: 'all_time', child: Text("All-Time Champions")),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabCtrl,
              indicatorColor: const Color(0xFF0284C7),
              indicatorWeight: 3,
              labelColor: const Color(0xFF0284C7),
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              tabs: const [
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.military_tech_rounded, size: 18),
                      SizedBox(width: 6),
                      Text("Top Streamers"),
                    ],
                  ),
                ),
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.workspace_premium_rounded, size: 18),
                      SizedBox(width: 6),
                      Text("Top Gifters"),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7)))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildLeaderboardView(_topCreators, isCreators: true),
                _buildLeaderboardView(_topGifters, isCreators: false),
              ],
            ),
    );
  }

  Widget _buildLeaderboardView(List<Map<String, dynamic>> list, {required bool isCreators}) {
    if (list.isEmpty) {
      return const Center(
        child: Text("No rankings recorded yet for this period.", style: TextStyle(color: Color(0xFF94A3B8))),
      );
    }

    final top1 = list.isNotEmpty ? list[0] : null;
    final top2 = list.length > 1 ? list[1] : null;
    final top3 = list.length > 2 ? list[2] : null;
    final remaining = list.length > 3 ? list.sublist(3) : <Map<String, dynamic>>[];

    return RefreshIndicator(
      onRefresh: _loadLeaderboard,
      color: const Color(0xFF0284C7),
      backgroundColor: Colors.white,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Top 3 Podium
          if (top1 != null)
            _buildPodium(top1: top1, top2: top2, top3: top3, isCreators: isCreators),

          const SizedBox(height: 20),

          // Section Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const Icon(Icons.format_list_numbered_rounded, color: Color(0xFF0284C7), size: 18),
                const SizedBox(width: 8),
                Text(
                  "RANKINGS (#4 - #${list.length})",
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Rankings List
          ...remaining.asMap().entries.map((entry) {
            final idx = entry.key + 4;
            final user = entry.value;
            final uid = user['id']?.toString() ?? '';
            final username = user['username'] ?? 'User';
            final fullName = user['full_name'] ?? username;
            final avatar = user['avatar_url'];
            final isVerified = user['is_verified'] == true;
            final coins = (user['coins_balance'] as num?)?.toInt() ?? 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  // Rank number
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        "$idx",
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF64748B), fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Avatar
                  GestureDetector(
                    onTap: () => ProfileScreen.open(context, userId: uid),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF0284C7),
                      backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
                      child: avatar == null
                          ? Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name & Username
                  Expanded(
                    child: GestureDetector(
                      onTap: () => ProfileScreen.open(context, userId: uid),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                                ),
                              ),
                              if (isVerified) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified_rounded, color: Color(0xFF00D4FF), size: 14),
                              ],
                            ],
                          ),
                          Text("@$username", style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                        ],
                      ),
                    ),
                  ),

                  // Coin Score
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFEF3C7)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stars_rounded, color: Color(0xFFEAB308), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          coins.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFFB45309)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPodium({
    required Map<String, dynamic> top1,
    Map<String, dynamic>? top2,
    Map<String, dynamic>? top3,
    required bool isCreators,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // #2 Silver
          if (top2 != null)
            _buildPodiumSpot(
              user: top2,
              rank: 2,
              crownColor: const Color(0xFF94A3B8), // Silver
              avatarRadius: 30,
              height: 140,
            )
          else
            const SizedBox(width: 80),

          // #1 Gold
          _buildPodiumSpot(
            user: top1,
            rank: 1,
            crownColor: const Color(0xFFEAB308), // Gold
            avatarRadius: 38,
            height: 180,
            isFirst: true,
          ),

          // #3 Bronze
          if (top3 != null)
            _buildPodiumSpot(
              user: top3,
              rank: 3,
              crownColor: const Color(0xFFD97706), // Bronze
              avatarRadius: 28,
              height: 125,
            )
          else
            const SizedBox(width: 80),
        ],
      ),
    );
  }

  Widget _buildPodiumSpot({
    required Map<String, dynamic> user,
    required int rank,
    required Color crownColor,
    required double avatarRadius,
    required double height,
    bool isFirst = false,
  }) {
    final uid = user['id']?.toString() ?? '';
    final username = user['username'] ?? 'User';
    final fullName = user['full_name'] ?? username;
    final avatar = user['avatar_url'];
    final coins = (user['coins_balance'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () => ProfileScreen.open(context, userId: uid),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Crown & Rank Badge
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: crownColor, width: isFirst ? 3 : 2),
                  boxShadow: [
                    BoxShadow(
                      color: crownColor.withValues(alpha: 0.3),
                      blurRadius: isFirst ? 14 : 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: avatarRadius,
                  backgroundColor: const Color(0xFF0284C7),
                  backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
                  child: avatar == null
                      ? Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: avatarRadius * 0.7))
                      : null,
                ),
              ),
              Positioned(
                top: -12,
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: crownColor,
                  size: isFirst ? 28 : 22,
                ),
              ),
              Positioned(
                bottom: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: crownColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "#$rank",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Name
          SizedBox(
            width: 85,
            child: Text(
              fullName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Color(0xFF0F172A)),
            ),
          ),
          const SizedBox(height: 2),

          // Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars_rounded, color: Color(0xFFEAB308), size: 12),
                const SizedBox(width: 3),
                Text(
                  "$coins",
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFF0F172A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
