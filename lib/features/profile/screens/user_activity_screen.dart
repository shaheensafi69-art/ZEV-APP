import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session_tracker_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../feed/screens/drafts_scheduled_screen.dart';
import 'activity/activity_archive_screen.dart';
import 'activity/activity_comments_screen.dart';
import 'activity/activity_content_screen.dart';
import 'activity/activity_deleted_screen.dart';
import 'activity/activity_likes_screen.dart';
import 'creator_insights_screen.dart';
import 'privacy_security_screen.dart';

/// Flagship Light Clearmorphic "Your Activity" Center for ZEV.
/// Backed by live Supabase telemetry, `AppSessionTrackerService` usage stats,
/// `search_history`, `user_security_logs`, and dedicated sub-screens.
class UserActivityScreen extends StatefulWidget {
  final Map<String, dynamic> profile;

  const UserActivityScreen({super.key, required this.profile});

  static Future<void> open(
    BuildContext context, {
    required Map<String, dynamic> profile,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserActivityScreen(profile: profile)),
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

  // Time Spent Chart interactive state (live AppSessionTrackerService)
  int _selectedDayIndex = 6;
  int _dailyAverageMinutes = 0;
  List<Map<String, dynamic>> _weeklyUsage = [
    {'day': 'Mon', 'minutes': 0, 'ratio': 0.05},
    {'day': 'Tue', 'minutes': 0, 'ratio': 0.05},
    {'day': 'Wed', 'minutes': 0, 'ratio': 0.05},
    {'day': 'Thu', 'minutes': 0, 'ratio': 0.05},
    {'day': 'Fri', 'minutes': 0, 'ratio': 0.05},
    {'day': 'Sat', 'minutes': 0, 'ratio': 0.05},
    {'day': 'Today', 'minutes': 0, 'ratio': 0.05},
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

    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

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
      final results = await Future.wait<dynamic>([
        supabase
            .from('discussion_posts')
            .count(CountOption.exact)
            .eq('student_id', userId)
            .isFilter('deleted_at', null)
            .eq('is_draft', false),
        supabase
            .from('reels')
            .count(CountOption.exact)
            .eq('user_id', userId)
            .isFilter('deleted_at', null),
        supabase
            .from('discussion_likes')
            .count(CountOption.exact)
            .eq('student_id', userId),
        supabase
            .from('reel_likes')
            .count(CountOption.exact)
            .eq('user_id', userId),
        supabase
            .from('discussion_comments')
            .count(CountOption.exact)
            .eq('student_id', userId)
            .isFilter('deleted_at', null),
        supabase
            .from('reel_comments')
            .count(CountOption.exact)
            .eq('user_id', userId)
            .isFilter('deleted_at', null),
        AppSessionTrackerService.instance.getWeeklyUsage(userId),
        AppSessionTrackerService.instance.getBreakReminderSettings(),
      ]);

      final postsCount = results[0] as int;
      final reelsCount = results[1] as int;
      final postLikes = results[2] as int;
      final reelLikes = results[3] as int;
      final postComments = results[4] as int;
      final reelComments = results[5] as int;
      final usage = results[6] as WeeklyUsageSummary;
      final breakSettings = results[7] as ({bool enabled, int minutes});

      final maxMinutes = usage.dailyMinutes.fold<int>(
        1,
        (prev, m) => math.max(prev, m),
      );
      final bars = <Map<String, dynamic>>[];
      for (var i = 0; i < usage.dayLabels.length; i++) {
        final mins = i < usage.dailyMinutes.length ? usage.dailyMinutes[i] : 0;
        final ratio = maxMinutes <= 0
            ? 0.05
            : (mins / maxMinutes).clamp(0.05, 1.0);
        bars.add({'day': usage.dayLabels[i], 'minutes': mins, 'ratio': ratio});
      }

      if (mounted) {
        setState(() {
          _totalPosts = postsCount;
          _totalReels = reelsCount;
          _totalLikes = postLikes + reelLikes;
          _totalComments = postComments + reelComments;
          _dailyAverageMinutes = usage.dailyAverageMinutes;
          if (bars.isNotEmpty) {
            _weeklyUsage = bars;
            _selectedDayIndex = bars.length - 1;
          }
          _breakReminderEnabled = breakSettings.enabled;
          _breakReminderMinutes = breakSettings.minutes;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Load activity stats error: $e');
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
          color: ZevColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ZevColors.border,
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
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "ZEV will remind you to take a breather after continuous active screen time.",
                style: TextStyle(
                  fontSize: 12.5,
                  color: ZevColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ...[15, 20, 30, 45, 60].map((mins) {
                final isSelected =
                    _breakReminderEnabled && _breakReminderMinutes == mins;
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? ZevColors.secondaryBlue.withValues(alpha: 0.15)
                          : ZevColors.softSurface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.timer_rounded,
                      color: isSelected
                          ? ZevColors.secondaryBlue
                          : ZevColors.textSecondary,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    "Every $mins minutes",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isSelected
                          ? ZevColors.secondaryBlue
                          : ZevColors.deepNavy,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: ZevColors.secondaryBlue,
                        )
                      : null,
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    final messenger = ScaffoldMessenger.of(context);
                    await AppSessionTrackerService.instance.setBreakReminder(
                      enabled: true,
                      minutes: mins,
                    );
                    if (!mounted) return;
                    setState(() {
                      _breakReminderEnabled = true;
                      _breakReminderMinutes = mins;
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text("Break reminder set for $mins minutes!"),
                        backgroundColor: ZevColors.deepNavy,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  },
                );
              }),
              const SizedBox(height: 6),
              if (_breakReminderEnabled)
                Center(
                  child: TextButton(
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      await AppSessionTrackerService.instance.setBreakReminder(
                        enabled: false,
                        minutes: _breakReminderMinutes,
                      );
                      if (!mounted) return;
                      setState(() => _breakReminderEnabled = false);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text(
                      "Turn Off Reminder",
                      style: TextStyle(
                        color: ZevColors.errorRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountHistoryModal() {
    final userId = supabase.auth.currentUser?.id;
    final createdAtStr = widget.profile['created_at']?.toString() ?? '';
    final createdAt = DateTime.tryParse(createdAtStr)?.toLocal();
    final memberSince = createdAt != null
        ? "${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')}"
        : 'Verified member';

    bool loadedOnce = false;
    bool isLoadingLogs = true;
    List<Map<String, dynamic>> logs = [];

    String formatLogDate(String? iso) {
      if (iso == null || iso.isEmpty) return '';
      final dt = DateTime.tryParse(iso)?.toLocal();
      if (dt == null) return '';
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    String formatEventLabel(String raw) {
      return raw
          .replaceAll('_', ' ')
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          if (!loadedOnce) {
            loadedOnce = true;
            Future(() async {
              List<Map<String, dynamic>> fetched = [];
              if (userId != null) {
                try {
                  final res = await supabase
                      .from('user_security_logs')
                      .select('id, event_type, status, platform, created_at')
                      .eq('user_id', userId)
                      .order('created_at', ascending: false)
                      .limit(15);
                  fetched = List<Map<String, dynamic>>.from(res as List);
                } catch (e) {
                  debugPrint('Security logs fetch notice: $e');
                }
              }
              if (context.mounted) {
                setSheetState(() {
                  logs = fetched;
                  isLoadingLogs = false;
                });
              }
            });
          }

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.78,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: ZevColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ZevColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      "Account Milestones & Security Log",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Key account events and security actions synced from ZEV.",
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHistoryItem(
                              icon: Icons.verified_user_rounded,
                              title: "Account Created",
                              subtitle: "Member since $memberSince",
                              color: ZevColors.secondaryBlue,
                            ),
                            const Divider(
                              color: ZevColors.softSurface,
                              height: 18,
                            ),
                            _buildHistoryItem(
                              icon: Icons.shield_rounded,
                              title: "Privacy Setting",
                              subtitle: widget.profile['is_private'] == true
                                  ? "Account is Private (Approved followers only)"
                                  : "Account is Public (Discoverable by everyone)",
                              color: const Color(0xFFF59E0B),
                            ),
                            const Divider(
                              color: ZevColors.softSurface,
                              height: 18,
                            ),
                            _buildHistoryItem(
                              icon: Icons.badge_rounded,
                              title: "Username Handle",
                              subtitle:
                                  "@${widget.profile['username'] ?? 'user'}",
                              color: const Color(0xFF6366F1),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'RECENT SECURITY EVENTS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: ZevColors.textMuted,
                                letterSpacing: 0.7,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (isLoadingLogs)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: ZevColors.primaryBlue,
                                  ),
                                ),
                              )
                            else if (logs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'No recent security log entries recorded.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: ZevColors.textSecondary,
                                  ),
                                ),
                              )
                            else
                              for (final log in logs) ...[
                                _buildHistoryItem(
                                  icon: Icons.security_rounded,
                                  title: formatEventLabel(
                                    (log['event_type'] ?? 'event').toString(),
                                  ),
                                  subtitle:
                                      '${(log['status'] ?? 'ok').toString().toUpperCase()} • ${formatLogDate(log['created_at']?.toString())}',
                                  color:
                                      (log['status'] ?? '')
                                              .toString()
                                              .toLowerCase() ==
                                          'failed'
                                      ? ZevColors.errorRed
                                      : ZevColors.successGreen,
                                ),
                                const SizedBox(height: 12),
                              ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSearchHistoryManager() {
    final userId = supabase.auth.currentUser?.id;
    bool loadedOnce = false;
    bool isLoadingHistory = true;
    List<Map<String, dynamic>> history = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          if (!loadedOnce) {
            loadedOnce = true;
            Future(() async {
              List<Map<String, dynamic>> rows = [];
              if (userId != null) {
                try {
                  final res = await supabase
                      .from('search_history')
                      .select('id, query, search_type, updated_at')
                      .eq('user_id', userId)
                      .order('updated_at', ascending: false)
                      .limit(25);
                  rows = List<Map<String, dynamic>>.from(res as List);
                } catch (e) {
                  debugPrint('Load search_history notice: $e');
                }
              }
              if (ctx.mounted) {
                setSheetState(() {
                  history = rows;
                  isLoadingHistory = false;
                });
              }
            });
          }

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: ZevColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ZevColors.border,
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
                            color: ZevColors.deepNavy,
                          ),
                        ),
                        if (history.isNotEmpty && userId != null)
                          TextButton(
                            onPressed: () async {
                              HapticFeedback.mediumImpact();
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await supabase
                                    .from('search_history')
                                    .delete()
                                    .eq('user_id', userId);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                        "Search history cleared completely!",
                                      ),
                                      backgroundColor: ZevColors.deepNavy,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Could not clear: $e'),
                                      backgroundColor: ZevColors.errorRed,
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text(
                              "Clear All",
                              style: TextStyle(
                                color: ZevColors.secondaryBlue,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Text(
                      "Synced to your ZEV search history.",
                      style: TextStyle(
                        fontSize: 12,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (isLoadingHistory)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: ZevColors.primaryBlue,
                          ),
                        ),
                      )
                    else if (history.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            'No recent searches.',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: ZevColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: history.length,
                          itemBuilder: (_, idx) {
                            final item = history[idx];
                            final rowId = (item['id'] ?? '').toString();
                            final query = (item['query'] ?? '').toString();
                            final type = (item['search_type'] ?? 'general')
                                .toString();

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.history_rounded,
                                    color: ZevColors.textMuted,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          query,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: ZevColors.deepNavy,
                                          ),
                                        ),
                                        Text(
                                          type,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: ZevColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 17,
                                      color: ZevColors.textMuted,
                                    ),
                                    onPressed: () async {
                                      HapticFeedback.lightImpact();
                                      if (userId != null && rowId.isNotEmpty) {
                                        await supabase
                                            .from('search_history')
                                            .delete()
                                            .eq('id', rowId)
                                            .eq('user_id', userId);
                                      }
                                      if (ctx.mounted) {
                                        setSheetState(
                                          () => history.removeWhere(
                                            (r) => r['id'] == rowId,
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
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
    final safeIdx = _selectedDayIndex.clamp(0, _weeklyUsage.length - 1);
    final selectedDay = _weeklyUsage[safeIdx];
    final isDesktop = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: ZevColors.deepNavy,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          "Your activity",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 720 : double.infinity,
            ),
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
                                  color: ZevColors.secondaryBlue.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.access_time_filled_rounded,
                                  color: ZevColors.secondaryBlue,
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
                                        color: ZevColors.deepNavy,
                                      ),
                                    ),
                                    Text(
                                      "Daily average this week",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: ZevColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _isLoading ? '...' : '${_dailyAverageMinutes}m',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: ZevColors.secondaryBlue,
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
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: ZevColors.secondaryBlue.withValues(
                                  alpha: 0.08,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: ZevColors.secondaryBlue.withValues(
                                    alpha: 0.2,
                                  ),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                "${selectedDay['day']}: ${selectedDay['minutes']} minutes on ZEV",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: ZevColors.secondaryBlue,
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
                              final isSelected = safeIdx == idx;
                              final ratio = (item['ratio'] as num).toDouble();

                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedDayIndex = idx);
                                },
                                child: Column(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      curve: Curves.easeOutBack,
                                      width: 18,
                                      height: 68,
                                      decoration: BoxDecoration(
                                        color: ZevColors.softSurface,
                                        borderRadius: BorderRadius.circular(9),
                                        border: isSelected
                                            ? Border.all(
                                                color: ZevColors.secondaryBlue,
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
                                                    ZevColors.primaryBlue,
                                                    ZevColors.secondaryBlue,
                                                  ],
                                                  begin: Alignment.bottomCenter,
                                                  end: Alignment.topCenter,
                                                )
                                              : const LinearGradient(
                                                  colors: [
                                                    ZevColors.textMuted,
                                                    ZevColors.border,
                                                  ],
                                                  begin: Alignment.bottomCenter,
                                                  end: Alignment.topCenter,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                            ? ZevColors.secondaryBlue
                                            : ZevColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),

                          const SizedBox(height: 18),
                          const Divider(color: ZevColors.softSurface),
                          const SizedBox(height: 10),

                          // Break Reminder Action
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: _showBreakReminderPicker,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Daily Break Reminder",
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: ZevColors.deepNavy,
                                        ),
                                      ),
                                      Text(
                                        _breakReminderEnabled
                                            ? "Reminds every $_breakReminderMinutes mins • Tap to change"
                                            : "Schedule reminders to take a break from screen",
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: ZevColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Switch.adaptive(
                                value: _breakReminderEnabled,
                                activeTrackColor: ZevColors.secondaryBlue,
                                onChanged: (val) async {
                                  if (val) {
                                    _showBreakReminderPicker();
                                  } else {
                                    HapticFeedback.selectionClick();
                                    await AppSessionTrackerService.instance
                                        .setBreakReminder(
                                          enabled: false,
                                          minutes: _breakReminderMinutes,
                                        );
                                    if (mounted) {
                                      setState(
                                        () => _breakReminderEnabled = false,
                                      );
                                    }
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
                            color: ZevColors.secondaryBlue,
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
                            color: ZevColors.successGreen,
                            onTap: () => ActivityContentScreen.open(
                              context,
                              initialTabIndex: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildClayStatCard(
                            title: "Reels Shared",
                            count: _isLoading ? "..." : "$_totalReels",
                            icon: Icons.play_circle_fill_rounded,
                            color: const Color(0xFF6366F1),
                            onTap: () => ActivityContentScreen.open(
                              context,
                              initialTabIndex: 1,
                            ),
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
                      iconColor: ZevColors.secondaryBlue,
                      countBadge: _totalComments > 0 ? "$_totalComments" : null,
                      onTap: () => ActivityCommentsScreen.open(context),
                    ),
                    const SizedBox(height: 9),

                    _buildActionTile(
                      icon: Icons.sell_rounded,
                      title: "Tags & Mentions",
                      subtitle: "Manage who can tag or @mention you",
                      iconColor: ZevColors.successGreen,
                      onTap: () => PrivacySecurityScreen.open(
                        context,
                        profile: widget.profile,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ==========================================
                    // 4. CONTENT SHARED
                    // ==========================================
                    _buildSectionTitle("CONTENT YOU SHARED"),

                    _buildActionTile(
                      icon: Icons.insights_rounded,
                      title: "Creator Insights",
                      subtitle:
                          "Views, engagement trends, and top performing content",
                      iconColor: ZevColors.secondaryBlue,
                      onTap: () => CreatorInsightsScreen.open(
                        context,
                        userProfile: widget.profile,
                      ),
                    ),
                    const SizedBox(height: 9),

                    _buildActionTile(
                      icon: Icons.schedule_send_rounded,
                      title: "Drafts & Scheduled Posts",
                      subtitle: "Publish or edit drafts and queued posts",
                      iconColor: const Color(0xFF0EA5E9),
                      onTap: () => DraftsScheduledScreen.open(
                        context,
                        onPostPublished: _loadActivityStats,
                      ),
                    ),
                    const SizedBox(height: 9),

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
                      subtitle:
                          "Clear cached searches and query recommendations",
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
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
