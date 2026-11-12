import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/zev_theme.dart';

/// Light Clearmorphic Notification Preferences Screen synced directly with
/// PostgreSQL `notification_preferences` (plus local SharedPreferences cache).
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
    extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _osPermissionGranted = true;
  bool _isSendingTest = false;
  String? _testStatusMessage;
  bool _testStatusSuccess = false;
  bool _pushEnabled = true;
  bool _pauseAll = false;
  bool _likesEnabled = true;
  bool _commentsEnabled = true;
  bool _mentionsEnabled = true;
  bool _storiesEnabled = true;
  bool _followsEnabled = true;
  bool _messagesEnabled = true;
  bool _liveEnabled = true;
  bool _marketingEnabled = false;
  bool _vibrationEnabled = true;

  bool _quietHoursEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOsPermission();
    _loadPreferences();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkOsPermission();
    }
  }

  Future<void> _checkOsPermission() async {
    final granted = await NotificationService().hasOsNotificationPermission();
    if (mounted) {
      setState(() => _osPermissionGranted = granted);
    }
  }

  Future<void> _requestOsPermission() async {
    HapticFeedback.selectionClick();
    final granted = await NotificationService().requestOsPermission();
    if (!mounted) return;
    setState(() => _osPermissionGranted = granted);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'Device notifications enabled!'
              : 'Notification permission is blocked in device Settings.',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: granted ? ZevColors.deepNavy : ZevColors.errorRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _runPushTest() async {
    if (_isSendingTest) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isSendingTest = true;
      _testStatusMessage = null;
    });

    final result = await NotificationService().sendTestNotification();
    await _checkOsPermission();

    if (!mounted) return;
    setState(() {
      _isSendingTest = false;
      _testStatusSuccess = result.localShown && result.serverSent;
      _testStatusMessage = result.detail;
    });
  }

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _pushEnabled = prefs.getBool('pref_notif_push_enabled') ?? true;
          _pauseAll = prefs.getBool('pref_notif_pause_all') ?? false;
          _likesEnabled = prefs.getBool('pref_notif_likes') ?? true;
          _commentsEnabled = prefs.getBool('pref_notif_comments') ?? true;
          _mentionsEnabled = prefs.getBool('pref_notif_mentions') ?? true;
          _storiesEnabled = prefs.getBool('pref_notif_stories') ?? true;
          _followsEnabled = prefs.getBool('pref_notif_followers') ?? true;
          _messagesEnabled = prefs.getBool('pref_notif_dms') ?? true;
          _liveEnabled = prefs.getBool('pref_notif_live') ?? true;
          _marketingEnabled = prefs.getBool('pref_notif_marketing') ?? false;
          _vibrationEnabled = prefs.getBool('pref_notif_vibrate') ?? true;
        });
      }

      final uid = _currentUserId;
      if (uid != null) {
        final raw = await _supabase.rpc('get_or_init_notification_preferences');
        final Map<dynamic, dynamic>? row = raw is Map
            ? raw
            : (raw is List && raw.isNotEmpty && raw.first is Map
                ? raw.first as Map
                : null);
        if (row != null && mounted) {
          final qs = row['quiet_hours_start']?.toString() ?? '';
          final qe = row['quiet_hours_end']?.toString() ?? '';
          final parsedStart = _parseTimeOfDay(qs);
          final parsedEnd = _parseTimeOfDay(qe);

          setState(() {
            _pushEnabled = row['push_enabled'] != false;
            _pauseAll = row['pause_all'] == true;
            _likesEnabled = row['likes_enabled'] != false;
            _commentsEnabled = row['comments_enabled'] != false;
            _mentionsEnabled = row['mentions_enabled'] != false;
            _storiesEnabled = row['stories_enabled'] != false;
            _followsEnabled = row['follows_enabled'] != false;
            _messagesEnabled = row['messages_enabled'] != false;
            _liveEnabled = row['live_enabled'] != false;
            _marketingEnabled = row['marketing_enabled'] == true;
            _quietHoursEnabled = parsedStart != null && parsedEnd != null;
            if (parsedStart != null) _quietStart = parsedStart;
            if (parsedEnd != null) _quietEnd = parsedEnd;
            _isLoading = false;
          });
          unawaited(_syncLocalCache());
          return;
        }
      }
    } catch (e) {
      debugPrint('[NotificationSettingsScreen] load notice: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  TimeOfDay? _parseTimeOfDay(String raw) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!) ?? -1;
    final min = int.tryParse(m.group(2)!) ?? -1;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return TimeOfDay(hour: h, minute: min);
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _syncLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pref_notif_push_enabled', _pushEnabled);
      await prefs.setBool('pref_notif_pause_all', _pauseAll);
      await prefs.setBool('pref_notif_likes', _likesEnabled);
      await prefs.setBool('pref_notif_comments', _commentsEnabled);
      await prefs.setBool('pref_notif_mentions', _mentionsEnabled);
      await prefs.setBool('pref_notif_stories', _storiesEnabled);
      await prefs.setBool('pref_notif_followers', _followsEnabled);
      await prefs.setBool('pref_notif_dms', _messagesEnabled);
      await prefs.setBool('pref_notif_live', _liveEnabled);
      await prefs.setBool('pref_notif_marketing', _marketingEnabled);
      await prefs.setBool('pref_notif_vibrate', _vibrationEnabled);
    } catch (_) {}
  }

  Future<void> _saveToBackend(String label) async {
    unawaited(_syncLocalCache());
    final uid = _currentUserId;
    if (uid == null) {
      _showSavedFeedback(label);
      return;
    }

    try {
      await _supabase.from('notification_preferences').upsert({
        'user_id': uid,
        'push_enabled': _pushEnabled,
        'pause_all': _pauseAll,
        'likes_enabled': _likesEnabled,
        'comments_enabled': _commentsEnabled,
        'mentions_enabled': _mentionsEnabled,
        'stories_enabled': _storiesEnabled,
        'follows_enabled': _followsEnabled,
        'messages_enabled': _messagesEnabled,
        'live_enabled': _liveEnabled,
        'marketing_enabled': _marketingEnabled,
        'quiet_hours_start':
            _quietHoursEnabled ? _formatTimeOfDay(_quietStart) : null,
        'quiet_hours_end':
            _quietHoursEnabled ? _formatTimeOfDay(_quietEnd) : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
      if (mounted) _showSavedFeedback(label);
    } catch (e) {
      debugPrint('[NotificationSettingsScreen] save error: $e');
      if (mounted) _showSavedFeedback(label, isError: true);
    }
  }

  void _showSavedFeedback(String label, {bool isError = false}) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isError ? 'Saved locally; sync retry pending' : '$label updated',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: isError ? ZevColors.errorRed : ZevColors.deepNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _pickQuietHour({required bool isStart}) async {
    final initial = isStart ? _quietStart : _quietEnd;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _quietStart = picked;
      } else {
        _quietEnd = picked;
      }
      _quietHoursEnabled = true;
    });
    await _saveToBackend('Quiet hours schedule');
  }

  @override
  Widget build(BuildContext context) {
    final masterActive = _pushEnabled && !_pauseAll;

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
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
        title: const Text(
          'Notification Settings',
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
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: ZevColors.primaryBlue),
              )
            : ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
                children: [
                  if (!_osPermissionGranted) ...[
                    _buildPermissionWarningCard(),
                    const SizedBox(height: 12),
                  ],
                  _buildToggleCard(
                    title: 'Push Notifications',
                    subtitle: 'Receive real-time alerts on this and linked devices',
                    icon: Icons.notifications_active_rounded,
                    value: _pushEnabled,
                    iconColor: ZevColors.secondaryBlue,
                    onChanged: (val) {
                      setState(() => _pushEnabled = val);
                      _saveToBackend('Push notifications');
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildToggleCard(
                    title: 'Pause All',
                    subtitle: 'Temporarily pause every notification across ZEV',
                    icon: Icons.notifications_off_rounded,
                    value: _pauseAll,
                    iconColor: ZevColors.errorRed,
                    onChanged: (val) {
                      setState(() => _pauseAll = val);
                      _saveToBackend('Pause all notifications');
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildQuietHoursCard(),
                  const SizedBox(height: 20),
                  _sectionHeader('POSTS, REELS, STORIES & COMMENTS'),
                  _buildToggleCard(
                    title: 'Likes',
                    subtitle: 'When someone likes your posts, reels, or stories',
                    icon: Icons.favorite_rounded,
                    value: _likesEnabled,
                    iconColor: const Color(0xFFFF2D55),
                    onChanged: !masterActive
                        ? null
                        : (val) {
                            setState(() => _likesEnabled = val);
                            _saveToBackend('Likes alerts');
                          },
                  ),
                  const SizedBox(height: 10),
                  _buildToggleCard(
                    title: 'Comments & Replies',
                    subtitle: 'When someone comments on or replies to you',
                    icon: Icons.chat_bubble_rounded,
                    value: _commentsEnabled,
                    iconColor: ZevColors.secondaryBlue,
                    onChanged: !masterActive
                        ? null
                        : (val) {
                            setState(() => _commentsEnabled = val);
                            _saveToBackend('Comments alerts');
                          },
                  ),
                  const SizedBox(height: 10),
                  _buildToggleCard(
                    title: 'Mentions & Tags',
                    subtitle: 'When you are @mentioned or tagged in posts',
                    icon: Icons.alternate_email_rounded,
                    value: _mentionsEnabled,
                    iconColor: const Color(0xFFF59E0B),
                    onChanged: !masterActive
                        ? null
                        : (val) {
                            setState(() => _mentionsEnabled = val);
                            _saveToBackend('Mentions alerts');
                          },
                  ),
                  const SizedBox(height: 10),
                  _buildToggleCard(
                    title: 'Story Reactions & Replies',
                    subtitle: 'When friends react or reply to your story',
                    icon: Icons.auto_awesome_rounded,
                    value: _storiesEnabled,
                    iconColor: const Color(0xFFF59E0B),
                    onChanged: !masterActive
                        ? null
                        : (val) {
                            setState(() => _storiesEnabled = val);
                            _saveToBackend('Story alerts');
                          },
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader('FOLLOWING, MESSAGES & LIVE'),
                  _buildToggleCard(
                    title: 'New Followers & Requests',
                    subtitle: 'When someone follows or requests to follow you',
                    icon: Icons.person_add_rounded,
                    value: _followsEnabled,
                    iconColor: ZevColors.successGreen,
                    onChanged: !masterActive
                        ? null
                        : (val) {
                            setState(() => _followsEnabled = val);
                            _saveToBackend('Follower alerts');
                          },
                  ),
                  const SizedBox(height: 10),
                  _buildToggleCard(
                    title: 'Direct & Group Messages',
                    subtitle: 'When someone sends a message or invites you to a group',
                    icon: Icons.mark_chat_unread_rounded,
                    value: _messagesEnabled,
                    iconColor: const Color(0xFF6366F1),
                    onChanged: !masterActive
                        ? null
                        : (val) {
                            setState(() => _messagesEnabled = val);
                            _saveToBackend('Messages alerts');
                          },
                  ),
                  const SizedBox(height: 10),
                  _buildToggleCard(
                    title: 'Live Broadcasts',
                    subtitle: 'When accounts you follow start a live video',
                    icon: Icons.sensors_rounded,
                    value: _liveEnabled,
                    iconColor: const Color(0xFFE11D48),
                    onChanged: !masterActive
                        ? null
                        : (val) {
                            setState(() => _liveEnabled = val);
                            _saveToBackend('Live alerts');
                          },
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader('ANNOUNCEMENTS & DEVICE'),
                  _buildToggleCard(
                    title: 'Product & Community Announcements',
                    subtitle: 'Feature updates, creator programs, and verification news',
                    icon: Icons.campaign_rounded,
                    value: _marketingEnabled,
                    iconColor: const Color(0xFF0EA5E9),
                    onChanged: !masterActive
                        ? null
                        : (val) {
                            setState(() => _marketingEnabled = val);
                            _saveToBackend('Announcements');
                          },
                  ),
                  const SizedBox(height: 10),
                  _buildToggleCard(
                    title: 'Haptic Vibration',
                    subtitle: 'Vibrate on in-app notification banners and taps',
                    icon: Icons.vibration_rounded,
                    value: _vibrationEnabled,
                    iconColor: const Color(0xFF8B5CF6),
                    onChanged: (val) {
                      setState(() => _vibrationEnabled = val);
                      _syncLocalCache();
                      _showSavedFeedback('Haptic vibration');
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTestPushCard(),
                ],
              ),
      ),
    );
  }

  Widget _buildPermissionWarningCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.notifications_paused_rounded,
              color: Color(0xFFD97706),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device Notifications Disabled',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Allow notification permission so ZEV can alert you even when the app is closed.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _requestOsPermission,
            style: ElevatedButton.styleFrom(
              backgroundColor: ZevColors.secondaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Enable',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestPushCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ZevColors.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ZevColors.primaryBlue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.send_to_mobile_rounded,
                  color: ZevColors.secondaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Push Notification',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Verify local tray alert and live server FCM delivery on this device',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSendingTest ? null : _runPushTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.deepNavy,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSendingTest
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Test',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ],
          ),
          if (_testStatusMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: (_testStatusSuccess
                        ? ZevColors.successGreen
                        : ZevColors.secondaryBlue)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _testStatusMessage!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _testStatusSuccess
                      ? ZevColors.successGreen
                      : ZevColors.deepNavy,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: ZevColors.textMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildQuietHoursCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ZevColors.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bedtime_rounded,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quiet Hours (UTC)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Silence push alerts while keeping notifications saved in-app',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _quietHoursEnabled,
                activeTrackColor: ZevColors.secondaryBlue,
                onChanged: (val) {
                  setState(() => _quietHoursEnabled = val);
                  _saveToBackend('Quiet hours');
                },
              ),
            ],
          ),
          if (_quietHoursEnabled) ...[
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickQuietHour(isStart: true),
                    icon: const Icon(Icons.nightlight_round, size: 16),
                    label: Text('Start: ${_formatTimeOfDay(_quietStart)} UTC'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZevColors.deepNavy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickQuietHour(isStart: false),
                    icon: const Icon(Icons.wb_sunny_outlined, size: 16),
                    label: Text('End: ${_formatTimeOfDay(_quietEnd)} UTC'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZevColors.deepNavy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
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
          color: ZevColors.border,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.04),
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
                        ? ZevColors.deepNavy
                        : ZevColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isEnabled
                        ? ZevColors.textSecondary
                        : const Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: ZevColors.secondaryBlue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
