import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart';
import '../theme/zev_theme.dart';
import 'mfa_service.dart';

class WeeklyUsageSummary {
  final List<String> dayLabels;
  final List<int> dailyMinutes;
  final int dailyAverageMinutes;
  final int todayMinutes;

  const WeeklyUsageSummary({
    required this.dayLabels,
    required this.dailyMinutes,
    required this.dailyAverageMinutes,
    required this.todayMinutes,
  });
}

/// Tracks foreground app session timing using app lifecycle hooks without
/// spamming Supabase on navigation or scroll events.
class AppSessionTrackerService {
  AppSessionTrackerService._();
  static final AppSessionTrackerService instance = AppSessionTrackerService._();

  static const String _breakEnabledKey = 'zev_break_reminder_enabled';
  static const String _breakMinutesKey = 'zev_break_reminder_minutes';

  SupabaseClient get _supabase => Supabase.instance.client;

  Timer? _tickTimer;
  DateTime? _sessionStartUtc;
  DateTime? _lastFlushUtc;
  DateTime? _lastDbSyncUtc;
  int _continuousMinutesSinceBreak = 0;
  bool _breakEnabled = false;
  int _breakIntervalMinutes = 30;
  bool _showingBreakDialog = false;

  Future<void> init() async {
    await _loadBreakSettings();
    onAppResumed();
  }

  Future<void> _loadBreakSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _breakEnabled = prefs.getBool(_breakEnabledKey) ?? false;
      _breakIntervalMinutes = prefs.getInt(_breakMinutesKey) ?? 30;
    } catch (_) {}
  }

  Future<({bool enabled, int minutes})> getBreakReminderSettings() async {
    await _loadBreakSettings();
    return (enabled: _breakEnabled, minutes: _breakIntervalMinutes);
  }

  Future<void> setBreakReminder({
    required bool enabled,
    required int minutes,
  }) async {
    _breakEnabled = enabled;
    _breakIntervalMinutes = math.max(5, minutes);
    _continuousMinutesSinceBreak = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_breakEnabledKey, enabled);
      await prefs.setInt(_breakMinutesKey, _breakIntervalMinutes);
    } catch (_) {}
  }

  void onAppResumed() {
    final now = DateTime.now().toUtc();
    _sessionStartUtc ??= now;
    _lastFlushUtc ??= now;

    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_flushElapsedSeconds(syncDb: false));
    });

    unawaited(_syncSessionToDb(isActive: true));
  }

  void onAppPaused() {
    _tickTimer?.cancel();
    _tickTimer = null;
    unawaited(_flushElapsedSeconds(syncDb: true, isActive: false));
    _lastFlushUtc = null;
    _sessionStartUtc = null;
    _continuousMinutesSinceBreak = 0;
  }

  void dispose() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  String _dayBucketKey(String userId, DateTime localDate) {
    final dayStr = DateFormat('yyyy-MM-dd').format(localDate);
    return 'zev_usage_sec_${userId}_$dayStr';
  }

  Future<void> _flushElapsedSeconds({
    bool syncDb = false,
    bool isActive = true,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    final now = DateTime.now().toUtc();
    final last = _lastFlushUtc;
    _lastFlushUtc = now;

    if (userId == null || userId.isEmpty || last == null) return;

    final elapsedSec = now.difference(last).inSeconds;
    if (elapsedSec > 0 && elapsedSec < 600) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = _dayBucketKey(userId, DateTime.now());
        final currentSec = prefs.getInt(key) ?? 0;
        await prefs.setInt(key, currentSec + elapsedSec);
      } catch (_) {}

      if (_breakEnabled) {
        final prevMins = _continuousMinutesSinceBreak;
        final nextMins = prevMins + (elapsedSec >= 30 ? 1 : 0);
        _continuousMinutesSinceBreak = nextMins;
        if (nextMins >= _breakIntervalMinutes && !_showingBreakDialog) {
          _continuousMinutesSinceBreak = 0;
          _showBreakDialog();
        }
      }
    }

    final shouldSyncDb = syncDb ||
        _lastDbSyncUtc == null ||
        now.difference(_lastDbSyncUtc!).inSeconds >= 60;
    if (shouldSyncDb) {
      await _syncSessionToDb(isActive: isActive);
    }
  }

  Future<void> _syncSessionToDb({required bool isActive}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    try {
      final now = DateTime.now().toUtc();
      _lastDbSyncUtc = now;
      final prefs = await SharedPreferences.getInstance();
      final todaySec = prefs.getInt(_dayBucketKey(userId, DateTime.now())) ?? 0;
      final deviceId = await MfaService.instance.getOrCreateDeviceId();
      final deviceName = await MfaService.instance.getDeviceName();
      final platform = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

      await _supabase.from('user_sessions').upsert({
        'user_id': userId,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'app_version': '1.0.0+9',
        'is_active': isActive,
        'started_at': (_sessionStartUtc ?? now).toIso8601String(),
        'last_active_at': now.toIso8601String(),
        if (!isActive) 'ended_at': now.toIso8601String(),
        'duration_seconds': todaySec,
      }, onConflict: 'user_id,device_id');
    } catch (e) {
      debugPrint('[AppSessionTracker] DB sync notice: $e');
    }
  }

  Future<WeeklyUsageSummary> getWeeklyUsage(String userId) async {
    await _flushElapsedSeconds(syncDb: false);
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();

    final List<String> labels = [];
    final List<int> minutes = [];

    for (int offset = 6; offset >= 0; offset--) {
      final date = today.subtract(Duration(days: offset));
      labels.add(DateFormat('E').format(date));
      final sec = prefs.getInt(_dayBucketKey(userId, date)) ?? 0;
      minutes.add((sec / 60).round());
    }

    // Backfill current session if user_sessions has higher stored today value
    try {
      final deviceId = await MfaService.instance.getOrCreateDeviceId();
      final row = await _supabase
          .from('user_sessions')
          .select('duration_seconds, last_active_at')
          .eq('user_id', userId)
          .eq('device_id', deviceId)
          .maybeSingle();
      if (row != null) {
        final storedSec = (row['duration_seconds'] as num?)?.toInt() ?? 0;
        final lastActive = DateTime.tryParse(row['last_active_at']?.toString() ?? '');
        if (lastActive != null &&
            lastActive.toLocal().year == today.year &&
            lastActive.toLocal().month == today.month &&
            lastActive.toLocal().day == today.day) {
          final storedMins = (storedSec / 60).round();
          if (storedMins > minutes.last) {
            minutes[minutes.length - 1] = storedMins;
          }
        }
      }
    } catch (_) {}

    final totalMinutes = minutes.fold<int>(0, (sum, m) => sum + m);
    final avg = (totalMinutes / 7).round();

    return WeeklyUsageSummary(
      dayLabels: labels,
      dailyMinutes: minutes,
      dailyAverageMinutes: avg,
      todayMinutes: minutes.isNotEmpty ? minutes.last : 0,
    );
  }

  void _showBreakDialog() {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    _showingBreakDialog = true;
    showDialog<void>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ZevColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.self_improvement_rounded, color: ZevColors.secondaryBlue),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Time for a Quick Break',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.deepNavy,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          "You've spent $_breakIntervalMinutes minutes on ZEV. Rest your eyes, stretch, and hydrate.",
          style: const TextStyle(
            fontSize: 13.5,
            color: ZevColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx),
            style: ElevatedButton.styleFrom(
              backgroundColor: ZevColors.primaryBlue,
              foregroundColor: ZevColors.deepNavy,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Got it',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      _showingBreakDialog = false;
    });
  }
}

