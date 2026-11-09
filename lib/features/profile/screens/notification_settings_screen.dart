import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/zev_theme.dart';

/// Full Dedicated Screen for Notification Preferences on ZEV.
/// Allows granular configuration of likes, comments, stories, DMs and follow alerts
/// with authentic Claymorphic styling.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NotificationSettingsScreen(),
      ),
    );
  }

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
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
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
        title: const Text(
          "Notifications",
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
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
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

            const SizedBox(height: 20),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                "POSTS, STORIES & COMMENTS",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.8,
                ),
              ),
            ),

            _buildToggleCard(
              title: "Likes",
              subtitle: "When people like your photos, reels or stories",
              icon: Icons.favorite_rounded,
              value: _likesAlerts,
              iconColor: const Color(0xFFFF2D55),
              onChanged: _pauseAll
                  ? null
                  : (val) {
                      setState(() => _likesAlerts = val);
                      _savePreference('pref_notif_likes', val);
                      _showSavedFeedback("Likes alert");
                    },
            ),

            const SizedBox(height: 10),

            _buildToggleCard(
              title: "Comments",
              subtitle: "When someone comments on your content",
              icon: Icons.chat_bubble_rounded,
              value: _commentsAlerts,
              iconColor: const Color(0xFF0284C7),
              onChanged: _pauseAll
                  ? null
                  : (val) {
                      setState(() => _commentsAlerts = val);
                      _savePreference('pref_notif_comments', val);
                      _showSavedFeedback("Comments alert");
                    },
            ),

            const SizedBox(height: 10),

            _buildToggleCard(
              title: "Story Reactions",
              subtitle: "When friends send quick reactions to your story",
              icon: Icons.auto_awesome_rounded,
              value: _storyReactionsAlerts,
              iconColor: const Color(0xFFF59E0B),
              onChanged: _pauseAll
                  ? null
                  : (val) {
                      setState(() => _storyReactionsAlerts = val);
                      _savePreference('pref_notif_stories', val);
                      _showSavedFeedback("Story reactions alert");
                    },
            ),

            const SizedBox(height: 20),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                "FOLLOWING & DIRECT MESSAGES",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.8,
                ),
              ),
            ),

            _buildToggleCard(
              title: "New Followers",
              subtitle: "When someone starts following your profile",
              icon: Icons.person_add_rounded,
              value: _newFollowersAlerts,
              iconColor: const Color(0xFF10B981),
              onChanged: _pauseAll
                  ? null
                  : (val) {
                      setState(() => _newFollowersAlerts = val);
                      _savePreference('pref_notif_followers', val);
                      _showSavedFeedback("New followers alert");
                    },
            ),

            const SizedBox(height: 10),

            _buildToggleCard(
              title: "Direct Messages",
              subtitle: "When someone sends you a message in ZEV Chat",
              icon: Icons.mark_chat_unread_rounded,
              value: _directMessagesAlerts,
              iconColor: const Color(0xFF6366F1),
              onChanged: _pauseAll
                  ? null
                  : (val) {
                      setState(() => _directMessagesAlerts = val);
                      _savePreference('pref_notif_dms', val);
                      _showSavedFeedback("Direct messages alert");
                    },
            ),

            const SizedBox(height: 20),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                "DEVICE FEEDBACK",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.8,
                ),
              ),
            ),

            _buildToggleCard(
              title: "Haptic Vibration",
              subtitle: "Vibrate on in-app notifications and interactions",
              icon: Icons.vibration_rounded,
              value: _vibrationEnabled,
              iconColor: const Color(0xFF8B5CF6),
              onChanged: (val) {
                setState(() => _vibrationEnabled = val);
                _savePreference('pref_notif_vibrate', val);
                _showSavedFeedback("Haptic vibration");
              },
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
    required bool value,
    required Color iconColor,
    required ValueChanged<bool>? onChanged,
  }) {
    final isEnabled = onChanged != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: isEnabled ? 0.12 : 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isEnabled ? iconColor : const Color(0xFFCBD5E1),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isEnabled
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isEnabled
                        ? const Color(0xFF64748B)
                        : const Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: const Color(0xFF0284C7),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

