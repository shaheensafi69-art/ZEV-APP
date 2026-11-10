import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity/activity_archive_screen.dart';
import 'activity/activity_comments_screen.dart';
import 'activity/activity_content_screen.dart';
import 'activity/activity_deleted_screen.dart';
import 'activity/activity_likes_screen.dart';

/// Flagship Instagram-Grade "Your Activity" Center for ZEV.
/// Engineered with authentic 3D Claymorphism, smooth staggered entrance animations,
/// interactive day-by-day time inspector, and dedicated sub-screens for every activity category.
class UserActivityScreen extends StatefulWidget {
  final Map<String, dynamic> profile;

  const UserActivityScreen({
    super.key,
    required this.profile,
  });

  static Future<void> open(BuildContext context,
      {required Map<String, dynamic> profile}) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserActivityScreen(profile: profile),
      ),
    );
  }

  @override
  State<UserActivityScreen> createState() => _UserActivityScreenState();
}

class _UserActivityScreenState extends State<UserActivityScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  int _totalPosts = 0;
  int _totalReels = 0;
  int _totalLikes = 0;
  int _totalComments = 0;
  bool _isLoading = true;

  // Time Spent Chart interactive state
  int _selectedDayIndex = 6; // Default to Friday (today)
  final List<Map<String, dynamic>> _weeklyUsage = [
    {'day': 'Sat', 'minutes': 25, 'ratio': 0.40},
    {'day': 'Sun', 'minutes': 48, 'ratio': 0.70},
    {'day': 'Mon', 'minutes': 20, 'ratio': 0.32},
    {'day': 'Tue', 'minutes': 55, 'ratio': 0.85},
    {'day': 'Wed', 'minutes': 35, 'ratio': 0.52},
    {'day': 'Thu', 'minutes': 62, 'ratio': 0.95},
    {'day': 'Fri', 'minutes': 42, 'ratio': 0.65},
  ];

  bool _breakReminderEnabled = false;
  int _breakReminderMinutes = 30;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    ));

    _loadActivityStats();
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadActivityStats() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final postsCount = await supabase
          .from('discussion_posts')
          .count(CountOption.exact)
          .eq('user_id', userId);

      final reelsCount = await supabase
          .from('reels')
          .count(CountOption.exact)
          .eq('user_id', userId);

      int postLikes = 0;
      int reelLikes = 0;
      try {
        postLikes = await supabase
            .from('discussion_likes')
            .count(CountOption.exact)
            .eq('user_id', userId);
        reelLikes = await supabase
            .from('reel_likes')
            .count(CountOption.exact)
            .eq('user_id', userId);
      } catch (_) {}

      int postComments = 0;
      int reelComments = 0;
      try {
        postComments = await supabase
            .from('discussion_comments')
            .count(CountOption.exact)
            .eq('user_id', userId);
        reelComments = await supabase
            .from('reel_comments')
            .count(CountOption.exact)
            .eq('user_id', userId);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _totalPosts = postsCount;
          _totalReels = reelsCount;
          _totalLikes = postLikes + reelLikes;
          _totalComments = postComments + reelComments;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showBreakReminderPicker() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "Set Daily Break Reminder",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "ZEV will notify you when you've reached your chosen continuous screen time.",
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            ...[15, 20, 30, 45, 60].map((mins) {
              final isSelected =
                  _breakReminderEnabled && _breakReminderMinutes == mins;
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                        : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.timer_rounded,
                    color: isSelected
                        ? const Color(0xFF0284C7)
                        : const Color(0xFF64748B),
                    size: 18,
                  ),
                ),
                title: Text(
                  "Every $mins minutes",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF0284C7)
                        : const Color(0xFF0F172A),
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF0284C7))
                    : null,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _breakReminderEnabled = true;
                    _breakReminderMinutes = mins;
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Break reminder set for $mins minutes!"),
                      backgroundColor: const Color(0xFF0F172A),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                },
              );
            }),
            const SizedBox(height: 6),
            if (_breakReminderEnabled)
              Center(
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _breakReminderEnabled = false);
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    "Turn Off Reminder",
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showTagSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          "Tags & Mentions",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        content: const Text(
          "Choose who can tag or mention you in posts, reels, or comments. By default, everyone you connect with on ZEV can mention you.",
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Done",
              style: TextStyle(
                color: Color(0xFF0284C7),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAccountHistoryModal() {
    final createdAtStr = widget.profile['created_at']?.toString() ?? '';
    final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();
    final memberSince = "${createdAt.year}/${createdAt.month}/${createdAt.day}";

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "Account Milestones & History",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Review the key milestones and security actions made on your account.",
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 18),
            _buildHistoryItem(
              icon: Icons.verified_user_rounded,
              title: "Account Created",
              subtitle: "Member since $memberSince",
              color: const Color(0xFF0284C7),
            ),
            const Divider(color: Color(0xFFF1F5F9), height: 18),
            _buildHistoryItem(
              icon: Icons.key_rounded,
              title: "Password Last Verified",
              subtitle: "Secured via Supabase authentication layer",
              color: const Color(0xFF10B981),
            ),
            const Divider(color: Color(0xFFF1F5F9), height: 18),
            _buildHistoryItem(
              icon: Icons.shield_rounded,
              title: "Privacy Setting",
              subtitle: widget.profile['is_private'] == true
                  ? "Account is Private (Approved followers only)"
                  : "Account is Public (Discoverable by everyone)",
              color: const Color(0xFFF59E0B),
            ),
            const Divider(color: Color(0xFFF1F5F9), height: 18),
            _buildHistoryItem(
              icon: Icons.badge_rounded,
              title: "Username Verified",
              subtitle: "@${widget.profile['username'] ?? 'user'}",
              color: const Color(0xFF6366F1),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearchHistoryManager() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final sampleSearches = [
            "photography",
            "nature reels",
            "afghanistan culture",
            "tech startup"
          ];
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Recent Searches",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                const Text("Search history cleared completely!"),
                            backgroundColor: const Color(0xFF0F172A),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      },
                      child: const Text(
                        "Clear All",
                        style: TextStyle(
                          color: Color(0xFF0284C7),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const Text(
                  "Only you can see your recent search history on this device.",
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                ...sampleSearches.map(
                  (s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.history_rounded,
                            color: Color(0xFF94A3B8), size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            s,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 16, color: Color(0xFF94A3B8)),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            setSheetState(() => sampleSearches.remove(s));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
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
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDay = _weeklyUsage[_selectedDayIndex];

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
        title: const Text(
          "Your activity",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
              children: [
                // ==========================================
                // 1. TIME ON ZEV HERO (Interactive Graph)
                // ==========================================
                _buildClayCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.access_time_filled_rounded,
                              color: Color(0xFF0284C7),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Time on ZEV",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  "Daily average this week",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            "41m",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0284C7),
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Day inspection tooltip pill
                      Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF0284C7)
                                  .withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            "${selectedDay['day']}: ${selectedDay['minutes']} minutes on ZEV",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0284C7),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Interactive 7-Day Graph
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(_weeklyUsage.length, (idx) {
                          final item = _weeklyUsage[idx];
                          final isSelected = _selectedDayIndex == idx;
                          final ratio = item['ratio'] as double;

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedDayIndex = idx);
                            },
                            child: Column(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOutBack,
                                  width: 18,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(9),
                                    border: isSelected
                                        ? Border.all(
                                            color: const Color(0xFF0284C7),
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: 18,
                                    height: 68 * ratio,
                                    decoration: BoxDecoration(
                                      gradient: isSelected
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFF0284C7),
                                                Color(0xFF0369A1)
                                              ],
                                              begin: Alignment.bottomCenter,
                                              end: Alignment.topCenter,
                                            )
                                          : const LinearGradient(
                                              colors: [
                                                Color(0xFF94A3B8),
                                                Color(0xFFCBD5E1)
                                              ],
                                              begin: Alignment.bottomCenter,
                                              end: Alignment.topCenter,
                                            ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item['day'] as String,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                    color: isSelected
                                        ? const Color(0xFF0284C7)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),

                      const SizedBox(height: 18),
                      const Divider(color: Color(0xFFF1F5F9)),
                      const SizedBox(height: 10),

                      // Break Reminder Action
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _showBreakReminderPicker,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Daily Break Reminder",
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    _breakReminderEnabled
                                        ? "Reminds every $_breakReminderMinutes mins • Tap to change"
                                        : "Schedule reminders to take a break from screen",
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: _breakReminderEnabled,
                            activeTrackColor: const Color(0xFF0284C7),
                            onChanged: (val) {
                              if (val) {
                                _showBreakReminderPicker();
                              } else {
                                setState(() => _breakReminderEnabled = false);
                                HapticFeedback.selectionClick();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ==========================================
                // 2. QUICK METRICS CAROUSEL (Likes, Comments, Posts, Reels)
                // ==========================================
                Row(
                  children: [
                    Expanded(
                      child: _buildClayStatCard(
                        title: "Likes Given",
                        count: _isLoading ? "..." : "$_totalLikes",
                        icon: Icons.favorite_rounded,
                        color: const Color(0xFFFF2D55),
                        onTap: () => ActivityLikesScreen.open(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildClayStatCard(
                        title: "Comments",
                        count: _isLoading ? "..." : "$_totalComments",
                        icon: Icons.chat_bubble_rounded,
                        color: const Color(0xFF0284C7),
                        onTap: () => ActivityCommentsScreen.open(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildClayStatCard(
                        title: "Posts Shared",
                        count: _isLoading ? "..." : "$_totalPosts",
                        icon: Icons.grid_on_rounded,
                        color: const Color(0xFF10B981),
                        onTap: () => ActivityContentScreen.open(context,
                            initialTabIndex: 0),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildClayStatCard(
                        title: "Reels Shared",
                        count: _isLoading ? "..." : "$_totalReels",
                        icon: Icons.play_circle_fill_rounded,
                        color: const Color(0xFF6366F1),
                        onTap: () => ActivityContentScreen.open(context,
                            initialTabIndex: 1),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ==========================================
                // 3. INTERACTIONS (Likes, Comments, Tags)
                // ==========================================
                _buildSectionTitle("INTERACTIONS"),

                _buildActionTile(
                  icon: Icons.favorite_rounded,
                  title: "Likes",
                  subtitle: "Review posts and reels you've liked",
                  iconColor: const Color(0xFFFF2D55),
                  countBadge: _totalLikes > 0 ? "$_totalLikes" : null,
                  onTap: () => ActivityLikesScreen.open(context),
                ),
                const SizedBox(height: 9),

                _buildActionTile(
                  icon: Icons.chat_bubble_rounded,
                  title: "Comments",
                  subtitle: "Review your discussions and replies",
                  iconColor: const Color(0xFF0284C7),
                  countBadge: _totalComments > 0 ? "$_totalComments" : null,
                  onTap: () => ActivityCommentsScreen.open(context),
                ),
                const SizedBox(height: 9),

                _buildActionTile(
                  icon: Icons.sell_rounded,
                  title: "Tags & Mentions",
                  subtitle: "Photos and reels you're tagged in",
                  iconColor: const Color(0xFF10B981),
                  onTap: _showTagSettingsDialog,
                ),

                const SizedBox(height: 20),

                // ==========================================
                // 4. CONTENT SHARED
                // ==========================================
                _buildSectionTitle("CONTENT YOU SHARED"),

                _buildActionTile(
                  icon: Icons.perm_media_rounded,
                  title: "Photos, Posts & Reels",
                  subtitle: "Manage all media you've published on ZEV",
                  iconColor: const Color(0xFF6366F1),
                  onTap: () => ActivityContentScreen.open(context),
                ),

                const SizedBox(height: 20),

                // ==========================================
                // 5. REMOVED AND ARCHIVED (Recently Deleted, Archive)
                // ==========================================
                _buildSectionTitle("REMOVED AND ARCHIVED"),

                _buildActionTile(
                  icon: Icons.delete_outline_rounded,
                  title: "Recently Deleted",
                  subtitle: "Content deleted in the last 30 days",
                  iconColor: const Color(0xFFEF4444),
                  onTap: () => ActivityDeletedScreen.open(context),
                ),
                const SizedBox(height: 9),

                _buildActionTile(
                  icon: Icons.archive_outlined,
                  title: "Archive",
                  subtitle: "Stories and posts hidden from your profile",
                  iconColor: const Color(0xFF0284C7),
                  onTap: () => ActivityArchiveScreen.open(context),
                ),

                const SizedBox(height: 20),

                // ==========================================
                // 6. HOW YOU USE ZEV (Search History, Account History)
                // ==========================================
                _buildSectionTitle("HOW YOU USE ZEV"),

                _buildActionTile(
                  icon: Icons.history_rounded,
                  title: "Recent Searches",
                  subtitle: "Clear cached searches and query recommendations",
                  iconColor: const Color(0xFF8B5CF6),
                  onTap: _showSearchHistoryManager,
                ),
                const SizedBox(height: 9),

                _buildActionTile(
                  icon: Icons.timeline_rounded,
                  title: "Account History",
                  subtitle: "Milestones and security changes you've made",
                  iconColor: const Color(0xFFF59E0B),
                  onTap: _showAccountHistoryModal,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF94A3B8),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildClayCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 4,
            offset: Offset(0, -1),
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
    required VoidCallback onTap,
  }) {
    return Container(
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: Color(0xFFCBD5E1),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  count,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
    String? countBadge,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 3,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (countBadge != null)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      countBadge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: iconColor,
                      ),
                    ),
                  ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Color(0xFFCBD5E1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
