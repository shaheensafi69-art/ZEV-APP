import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/zev_theme.dart';

/// Next-Generation Push & In-App Notification Preferences Sheet.
/// Allows granular configuration of likes, comments, stories, DMs and follow alerts.
class NotificationSettingsSheet extends StatefulWidget {
  const NotificationSettingsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationSettingsSheet(),
    );
  }

  @override
  State<NotificationSettingsSheet> createState() => _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState extends State<NotificationSettingsSheet> {
  bool _pauseAll = false;
  bool _likesAlerts = true;
  bool _commentsAlerts = true;
  bool _newFollowersAlerts = true;
  bool _directMessagesAlerts = true;
  bool _storyReactionsAlerts = true;
  bool _vibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _pauseAll = prefs.getBool('pref_notif_pause_all') ?? false;
          _likesAlerts = prefs.getBool('pref_notif_likes') ?? true;
          _commentsAlerts = prefs.getBool('pref_notif_comments') ?? true;
          _newFollowersAlerts = prefs.getBool('pref_notif_followers') ?? true;
          _directMessagesAlerts = prefs.getBool('pref_notif_dms') ?? true;
          _storyReactionsAlerts = prefs.getBool('pref_notif_stories') ?? true;
          _vibrationEnabled = prefs.getBool('pref_notif_vibrate') ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _savePreference(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  void _showSavedFeedback(String label) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "$label updated",
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: ZevColors.deepNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
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
                    "Notifications",
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

            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                children: [
                  // Master Pause All
                  _buildToggleCard(
                    title: "Pause all",
                    subtitle: "Temporarily pause all push notifications",
                    icon: Icons.notifications_off_rounded,
                    value: _pauseAll,
                    iconColor: const Color(0xFFFF3366),
                    onChanged: (val) {
                      setState(() => _pauseAll = val);
                      _savePreference('pref_notif_pause_all', val);
                      _showSavedFeedback("Pause all notifications");
                    },
                  ),

                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      "Posts, Stories & Comments",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                  _buildToggleCard(
                    title: "Likes & Reactions",
                    subtitle: "Notify when someone likes your posts or comments",
                    icon: Icons.favorite_rounded,
                    value: _likesAlerts,
                    iconColor: const Color(0xFFFF2D55),
                    onChanged: (val) {
                      setState(() => _likesAlerts = val);
                      _savePreference('pref_notif_likes', val);
                      _showSavedFeedback("Likes notifications");
                    },
                  ),
                  const SizedBox(height: 8),

                  _buildToggleCard(
                    title: "Comments & Replies",
                    subtitle: "Notify when someone comments on your photo or reel",
                    icon: Icons.chat_bubble_rounded,
                    value: _commentsAlerts,
                    iconColor: const Color(0xFF00D4FF),
                    onChanged: (val) {
                      setState(() => _commentsAlerts = val);
                      _savePreference('pref_notif_comments', val);
                      _showSavedFeedback("Comments notifications");
                    },
                  ),
                  const SizedBox(height: 8),

                  _buildToggleCard(
                    title: "Story Updates",
                    subtitle: "Notify when friends share their first story of the day",
                    icon: Icons.flash_on_rounded,
                    value: _storyReactionsAlerts,
                    iconColor: const Color(0xFFFF9500),
                    onChanged: (val) {
                      setState(() => _storyReactionsAlerts = val);
                      _savePreference('pref_notif_stories', val);
                      _showSavedFeedback("Story updates");
                    },
                  ),

                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      "Following & Messages",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                  _buildToggleCard(
                    title: "New Followers",
                    subtitle: "Notify when someone starts following your profile",
                    icon: Icons.person_add_rounded,
                    value: _newFollowersAlerts,
                    iconColor: const Color(0xFF536DFE),
                    onChanged: (val) {
                      setState(() => _newFollowersAlerts = val);
                      _savePreference('pref_notif_followers', val);
                      _showSavedFeedback("Followers notifications");
                    },
                  ),
                  const SizedBox(height: 8),

                  _buildToggleCard(
                    title: "Direct Messages (Chat)",
                    subtitle: "Notify for incoming voice, text and media messages",
                    icon: Icons.send_rounded,
                    value: _directMessagesAlerts,
                    iconColor: const Color(0xFF10B981),
                    onChanged: (val) {
                      setState(() => _directMessagesAlerts = val);
                      _savePreference('pref_notif_dms', val);
                      _showSavedFeedback("Direct messages notifications");
                    },
                  ),

                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      "Sound & Haptics",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                  _buildToggleCard(
                    title: "Haptic Feedback & Vibration",
                    subtitle: "Vibrate on interactions, likes, and message delivery",
                    icon: Icons.vibration_rounded,
                    value: _vibrationEnabled,
                    iconColor: const Color(0xFF8B5CF6),
                    onChanged: (val) {
                      setState(() => _vibrationEnabled = val);
                      _savePreference('pref_notif_vibrate', val);
                      _showSavedFeedback("Vibration feedback");
                    },
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

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
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
                    fontSize: 14.5,
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
          Switch.adaptive(
            value: value,
            activeTrackColor: ZevColors.primaryBlue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
