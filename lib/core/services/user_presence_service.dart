import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Telemetry model representing a user's privacy-aware live online status & last seen.
class UserPresenceInfo {
  final bool isOnline;
  final String statusText;
  final DateTime? lastSeen;
  final bool isHidden;

  const UserPresenceInfo({
    required this.isOnline,
    required this.statusText,
    this.lastSeen,
    this.isHidden = false,
  });

  static const UserPresenceInfo offline = UserPresenceInfo(
    isOnline: false,
    statusText: 'Offline',
  );

  static const UserPresenceInfo hidden = UserPresenceInfo(
    isOnline: false,
    statusText: '',
    isHidden: true,
  );
}

/// Privacy-aware Real-Time Presence & Last Seen Service for ZEV.
/// - Honors `user_privacy_settings.hide_online_status` (both outgoing & mutual lookup)
/// - Uses a 45-second heartbeat only while app is active in foreground
/// - Does NOT mutate `profiles` on minor requests
/// - Distinguishes genuine online presence (< 2.5 minutes) from human-readable Last Seen
class UserPresenceService {
  static final UserPresenceService instance = UserPresenceService._();
  UserPresenceService._();

  Timer? _heartbeatTimer;
  bool _hideOnlineStatus = false;
  DateTime? _lastPresenceWriteAt;
  bool _hasLoadedPreference = false;

  bool get isHidingOnlineStatus => _hideOnlineStatus;

  /// Loads the current user's `hide_online_status` privacy preference.
  Future<void> refreshPrivacyPreference() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _hideOnlineStatus = false;
      _hasLoadedPreference = false;
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('user_privacy_settings')
          .select('hide_online_status')
          .eq('user_id', user.id)
          .maybeSingle();
      _hideOnlineStatus = row?['hide_online_status'] == true;
      _hasLoadedPreference = true;
    } catch (e) {
      debugPrint('Presence preference load notice: $e');
    }
  }

  /// Updates the local cache & DB immediately when user toggles Show Activity Status.
  Future<void> setHideOnlineStatus(bool hide) async {
    _hideOnlineStatus = hide;
    _hasLoadedPreference = true;
    await updatePresence(isOnline: !hide, forceWrite: true);
  }

  /// Starts the 45-second presence heartbeat loop while user is actively using ZEV.
  void startPresenceHeartbeat() {
    unawaited(_initAndBeat());
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      updatePresence(isOnline: true);
    });
  }

  Future<void> _initAndBeat() async {
    await refreshPrivacyPreference();
    await updatePresence(isOnline: true, forceWrite: true);
  }

  /// Stops presence heartbeat and marks user as offline cleanly.
  void stopPresenceHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    updatePresence(isOnline: false, forceWrite: true);
  }

  /// Marks all pending undelivered incoming messages as delivered (`message_deliveries` + `direct_messages`).
  Future<void> markPendingMessagesDelivered() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.rpc('mark_messages_delivered');
    } catch (e) {
      debugPrint('markPendingMessagesDelivered notice: $e');
    }
  }

  /// Updates current user's presence in Supabase profiles with throttling and privacy gating.
  Future<void> updatePresence({
    required bool isOnline,
    bool forceWrite = false,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    if (!_hasLoadedPreference) {
      await refreshPrivacyPreference();
    }

    final now = DateTime.now().toUtc();
    if (!forceWrite &&
        _lastPresenceWriteAt != null &&
        now.difference(_lastPresenceWriteAt!).inSeconds < 25) {
      return;
    }
    _lastPresenceWriteAt = now;

    // Never advertise active online status when privacy hides activity status.
    final bool effectiveOnline = _hideOnlineStatus ? false : isOnline;
    final nowIso = now.toIso8601String();

    try {
      final Map<String, dynamic> payload = {
        'is_online': effectiveOnline,
      };
      if (!_hideOnlineStatus) {
        payload['last_seen'] = nowIso;
        payload['last_seen_at'] = nowIso;
      }
      await Supabase.instance.client
          .from('profiles')
          .update(payload)
          .eq('id', user.id);
    } catch (err) {
      debugPrint('Presence update notice: $err');
    }

    if (isOnline) {
      unawaited(markPendingMessagesDelivered());
    }
  }

  /// Batch-fetches mutual-privacy-masked presence for a list of user IDs via `get_profiles_presence`.
  Future<Map<String, UserPresenceInfo>> fetchPresenceMap(
    List<String> userIds,
  ) async {
    final cleanIds =
        userIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList();
    if (cleanIds.isEmpty) return {};

    try {
      final res = await Supabase.instance.client.rpc(
        'get_profiles_presence',
        params: {'p_user_ids': cleanIds},
      );
      final Map<String, UserPresenceInfo> out = {};
      if (res is List) {
        for (final row in res) {
          if (row is Map) {
            final uid = row['user_id']?.toString() ?? '';
            if (uid.isEmpty) continue;
            final hidden = row['hide_online_status'] == true;
            if (hidden) {
              out[uid] = UserPresenceInfo.hidden;
              continue;
            }
            out[uid] = computePresence({
              'is_online': row['is_online'],
              'last_seen': row['last_seen'],
              'hide_online_status': false,
            });
          }
        }
      }
      return out;
    } catch (e) {
      debugPrint('fetchPresenceMap notice: $e');
      return {};
    }
  }

  /// Computes accurate presence status from a profile or presence map.
  /// Respects `hide_online_status` on either target or current user.
  static UserPresenceInfo computePresence(
    Map<String, dynamic>? profile, {
    bool? callerHidesStatus,
  }) {
    if (profile == null || profile.isEmpty) {
      return UserPresenceInfo.offline;
    }

    final bool hides =
        (callerHidesStatus ?? instance.isHidingOnlineStatus) ||
        profile['hide_online_status'] == true;
    if (hides) {
      return UserPresenceInfo.hidden;
    }

    final isOnlineFlag = profile['is_online'] == true;
    final lastSeenStr =
        profile['last_seen_at']?.toString() ??
        profile['last_seen']?.toString();

    if (lastSeenStr == null || lastSeenStr.isEmpty) {
      return isOnlineFlag
          ? const UserPresenceInfo(isOnline: true, statusText: 'Active now')
          : UserPresenceInfo.offline;
    }

    final lastSeen = DateTime.tryParse(lastSeenStr);
    if (lastSeen == null) {
      return UserPresenceInfo.offline;
    }

    final nowUtc = DateTime.now().toUtc();
    final lastSeenUtc = lastSeen.toUtc();
    final difference = nowUtc.difference(lastSeenUtc);

    // Online ONLY if is_online is true AND heartbeat was within 2.5 minutes
    if (isOnlineFlag && difference.inSeconds <= 150) {
      return UserPresenceInfo(
        isOnline: true,
        statusText: 'Active now',
        lastSeen: lastSeen,
      );
    }

    String text;
    if (difference.inMinutes < 1) {
      text = 'Last seen just now';
    } else if (difference.inMinutes < 60) {
      final m = difference.inMinutes.clamp(1, 59);
      text = 'Last seen ${m}m ago';
    } else if (difference.inHours < 24) {
      final h = difference.inHours.clamp(1, 23);
      text = 'Last seen ${h}h ago';
    } else if (difference.inDays == 1) {
      final local = lastSeen.toLocal();
      final timeStr =
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      text = 'Last seen yesterday at $timeStr';
    } else if (difference.inDays < 7) {
      final d = difference.inDays.clamp(1, 6);
      text = 'Last seen ${d}d ago';
    } else {
      text = 'Last seen recently';
    }

    return UserPresenceInfo(
      isOnline: false,
      statusText: text,
      lastSeen: lastSeen,
    );
  }
}
