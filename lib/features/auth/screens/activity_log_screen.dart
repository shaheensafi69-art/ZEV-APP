import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/services/language_service.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<ActivityLogEntry> _logs = [];

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs({bool forceSync = false}) async {
    setState(() => _isLoading = true);
    final user = supabase.auth.currentUser;
    if (user != null) {
      if (forceSync) {
        await ActivityLogService.instance.recordLogin(user.id, force: true);
      }
      final logs = await ActivityLogService.instance.getLogs(user.id);
      if (mounted) {
        setState(() {
          _logs = logs;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDateTime(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return "$year/$month/$day • $hour:$minute";
  }

  IconData _getDeviceIcon(String model, String os) {
    final lower = (model + os).toLowerCase();
    if (lower.contains('iphone') || lower.contains('android') || lower.contains('samsung') || lower.contains('xiaomi')) {
      return Icons.phone_iphone_rounded;
    } else if (lower.contains('ipad') || lower.contains('tablet')) {
      return Icons.tablet_mac_rounded;
    } else if (lower.contains('mac') || lower.contains('windows') || lower.contains('pc')) {
      return Icons.laptop_mac_rounded;
    }
    return Icons.devices_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final currentSession = _logs.where((l) => l.isCurrent).toList();
    final pastSessions = _logs.where((l) => !l.isCurrent).toList();

    return Scaffold(
      backgroundColor: surfaceWhite,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        centerTitle: true,
        title: Text(
          context.l10n.activityLog,
          style: const TextStyle(
            color: textDark,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: const IconThemeData(color: textDark),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: textGrey),
            tooltip: context.l10n.refresh,
            onPressed: () => _loadLogs(forceSync: true),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryPink))
          : RefreshIndicator(
              color: primaryPink,
              onRefresh: () => _loadLogs(forceSync: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ================= Activity log banner =================
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: lightPinkBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: primaryPink.withValues(alpha: 0.25), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: surfaceWhite,
                              shape: BoxShape.circle,
                              border: Border.all(color: primaryPink.withValues(alpha: 0.3)),
                            ),
                            child: const Icon(Icons.security_rounded, color: primaryPink, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.loginActivity,
                                  style: const TextStyle(
                                    color: textDark,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context.l10n.activeSessions,
                                  style: const TextStyle(
                                    color: textGrey,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ================= Current session (this device) =================
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.currentDevice,
                          style: const TextStyle(
                            color: textDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (currentSession.isNotEmpty)
                      _buildSessionCard(currentSession.first, isCurrent: true)
                    else if (_logs.isNotEmpty)
                      _buildSessionCard(_logs.first, isCurrent: true),

                    const SizedBox(height: 28),

                    // ================= Previous sessions & logins =================
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${context.l10n.pastSessions} (${pastSessions.length})",
                          style: const TextStyle(
                            color: textDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (pastSessions.isNotEmpty)
                          TextButton(
                            onPressed: () async {
                              final user = supabase.auth.currentUser;
                              if (user != null) {
                                await ActivityLogService.instance.clearLogs(user.id);
                                _loadLogs();
                              }
                            },
                            child: Text(
                              context.l10n.clear,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (pastSessions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: surfaceWhite,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cardBorder, width: 1.5),
                        ),
                        child: Text(
                          context.l10n.noOtherActiveSessions,
                          style: const TextStyle(color: textGrey, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pastSessions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => _buildSessionCard(pastSessions[index]),
                      ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSessionCard(ActivityLogEntry entry, {bool isCurrent = false}) {
    final icon = _getDeviceIcon(entry.deviceModel, entry.osName);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrent ? primaryPink.withValues(alpha: 0.4) : cardBorder,
          width: isCurrent ? 1.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isCurrent ? 0.04 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isCurrent ? lightPinkBg : cardBorder,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: isCurrent ? primaryPink : textGrey, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.deviceModel,
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          context.l10n.activeNow,
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, color: textGrey, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      entry.location,
                      style: const TextStyle(color: textGrey, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, color: textGrey, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      _formatDateTime(entry.timestamp),
                      style: const TextStyle(color: textGrey, fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isCurrent)
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
              tooltip: "Log out device",
              onPressed: () => _confirmRemoveSession(entry),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveSession(ActivityLogEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Text(
              "Log Out Device",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          "Are you sure you want to log out from ${entry.deviceModel}?\nThis session will be revoked.",
          style: const TextStyle(fontSize: 13, color: textGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel, style: const TextStyle(color: textGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Log Out"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final user = supabase.auth.currentUser;
      if (user != null) {
        await ActivityLogService.instance.removeSession(user.id, entry.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("${entry.deviceModel} logged out successfully"),
              backgroundColor: Colors.green,
            ),
          );
          _loadLogs();
        }
      }
    }
  }
}
