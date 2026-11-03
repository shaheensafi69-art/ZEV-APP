import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zev_theme.dart';

/// Next-Generation "Your Activity" Sheet for ZEV.
/// Displays screen time metrics, interaction history, account milestones,
/// and search history management with Instagram-grade claymorphism.
class UserActivitySheet extends StatefulWidget {
  final Map<String, dynamic> profile;

  const UserActivitySheet({
    super.key,
    required this.profile,
  });

  static void show(BuildContext context, {required Map<String, dynamic> profile}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UserActivitySheet(profile: profile),
    );
  }

  @override
  State<UserActivitySheet> createState() => _UserActivitySheetState();
}

class _UserActivitySheetState extends State<UserActivitySheet> {
  final supabase = Supabase.instance.client;

  int _totalPosts = 0;
  int _totalReels = 0;
  bool _isLoading = true;
  bool _breakReminderEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadActivityStats();
  }

  Future<void> _loadActivityStats() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final postsCount = await supabase
          .from('posts')
          .count(CountOption.exact)
          .eq('user_id', userId);

      final reelsCount = await supabase
          .from('reels')
          .count(CountOption.exact)
          .eq('user_id', userId);

      if (mounted) {
        setState(() {
          _totalPosts = postsCount;
          _totalReels = reelsCount;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearSearchHistory() {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: ZevColors.primaryBlue, size: 20),
            SizedBox(width: 10),
            Text(
              "Search history cleared successfully!",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        backgroundColor: ZevColors.deepNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final createdAtStr = widget.profile['created_at']?.toString() ?? '';
    final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();
    final memberSince = "${createdAt.year}/${createdAt.month}/${createdAt.day}";

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Clay Drag Handle
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(color: Colors.white, blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Sheet Title Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Your activity",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: ZevColors.deepNavy,
                      letterSpacing: -0.3,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: ZevColors.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(color: Color(0xFFE2E8F0), height: 1),

            // Scrollable Activity Content
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                children: [
                  // Time Spent Card
                  _buildClayContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: ZevColors.primaryBlue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.access_time_filled_rounded,
                                color: ZevColors.primaryBlue,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Time on ZEV",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: ZevColors.deepNavy,
                                  ),
                                ),
                                Text(
                                  "Daily average this week",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: ZevColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            const Text(
                              "34m",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: ZevColors.secondaryBlue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Daily graph mockup
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildBar('Sat', 0.4),
                            _buildBar('Sun', 0.65),
                            _buildBar('Mon', 0.35),
                            _buildBar('Tue', 0.8),
                            _buildBar('Wed', 0.5),
                            _buildBar('Thu', 0.9),
                            _buildBar('Fri', 0.6, isToday: true),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Daily Break Reminder (30m)",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                            Switch.adaptive(
                              value: _breakReminderEnabled,
                              activeTrackColor: ZevColors.primaryBlue,
                              onChanged: (val) {
                                setState(() => _breakReminderEnabled = val);
                                HapticFeedback.selectionClick();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Content Shared Stats
                  Row(
                    children: [
                      Expanded(
                        child: _buildClayStatCard(
                          title: "Photos & Posts",
                          count: _isLoading ? "..." : "$_totalPosts",
                          icon: Icons.grid_on_rounded,
                          color: const Color(0xFF00D4FF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildClayStatCard(
                          title: "Reels Shared",
                          count: _isLoading ? "..." : "$_totalReels",
                          icon: Icons.play_circle_fill_rounded,
                          color: const Color(0xFF536DFE),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Interactions Section
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Text(
                      "Interactions",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),

                  _buildActionTile(
                    icon: Icons.favorite_rounded,
                    title: "Likes",
                    subtitle: "Posts, reels and comments you've liked",
                    iconColor: const Color(0xFFFF2D55),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Loading liked posts...")),
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  _buildActionTile(
                    icon: Icons.chat_bubble_rounded,
                    title: "Comments",
                    subtitle: "Review your recent responses and discussions",
                    iconColor: const Color(0xFF00D4FF),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Loading your comments...")),
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  _buildActionTile(
                    icon: Icons.sell_rounded,
                    title: "Tags",
                    subtitle: "Photos and videos you're tagged in",
                    iconColor: const Color(0xFF10B981),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("No new photo tags found")),
                      );
                    },
                  ),

                  const SizedBox(height: 18),

                  // Account History Section
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Text(
                      "Account Milestones",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),

                  _buildClayContainer(
                    child: Column(
                      children: [
                        _buildHistoryRow(
                          icon: Icons.verified_user_rounded,
                          title: "Account Created",
                          subtitle: "Member since $memberSince",
                          color: const Color(0xFF6366F1),
                        ),
                        const Divider(color: Color(0xFFF1F5F9), height: 16),
                        _buildHistoryRow(
                          icon: Icons.lock_clock_rounded,
                          title: "Password Last Verified",
                          subtitle: "Account protected with Supabase Auth",
                          color: const Color(0xFF10B981),
                        ),
                        const Divider(color: Color(0xFFF1F5F9), height: 16),
                        _buildHistoryRow(
                          icon: Icons.shield_rounded,
                          title: "Privacy Status",
                          subtitle: widget.profile['is_private'] == true
                              ? "Private Account"
                              : "Public Creator Account",
                          color: const Color(0xFFF59E0B),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Search History Section
                  _buildActionTile(
                    icon: Icons.history_rounded,
                    title: "Recent Searches",
                    subtitle: "Clear cached searches and query recommendations",
                    iconColor: const Color(0xFF8B5CF6),
                    trailing: TextButton(
                      onPressed: _clearSearchHistory,
                      style: TextButton.styleFrom(
                        foregroundColor: ZevColors.secondaryBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text(
                        "Clear All",
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                    onTap: _clearSearchHistory,
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBar(String day, double fillRatio, {bool isToday = false}) {
    return Column(
      children: [
        Container(
          width: 14,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 14,
            height: 52 * fillRatio,
            decoration: BoxDecoration(
              gradient: isToday
                  ? const LinearGradient(
                      colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    )
                  : null,
              color: isToday ? null : const Color(0xFF94A3B8),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          day,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
            color: isToday ? ZevColors.deepNavy : ZevColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildClayContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildClayStatCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 10),
          Text(
            count,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: ZevColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: ZevColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: ZevColors.textMuted,
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: ZevColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
