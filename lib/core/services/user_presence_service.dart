import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Telemetry model representing a user's live online status and last seen timestamp
class UserPresenceInfo {
  final bool isOnline;
  final String statusText;
  final DateTime? lastSeen;

  const UserPresenceInfo({
    required this.isOnline,
    required this.statusText,
    this.lastSeen,
  });

  static const UserPresenceInfo offline = UserPresenceInfo(
    isOnline: false,
    statusText: "Offline",
  );
}

/// Enterprise-grade Real-Time Presence & Last Seen Telemetry Service.
/// Accurately detects whether a user is genuinely "Active now" or offline,
/// and computes human-readable last active timestamps (e.g. "Active 5m ago", "Active 2h ago", "Active yesterday").
class UserPresenceService {
  static final UserPresenceService instance = UserPresenceService._();
  UserPresenceService._();

  Timer? _heartbeatTimer;

  /// Starts the presence heartbeat loop when user is actively in the app
  void startPresenceHeartbeat() {
    updatePresence(isOnline: true);
    _heartbeatTimer?.cancel();
    // Heartbeat every 90 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      updatePresence(isOnline: true);
    });
  }

  /// Stops presence heartbeat and marks user as offline
  void stopPresenceHeartbeat() {
    _heartbeatTimer?.cancel();
    updatePresence(isOnline: false);
  }

  /// Updates current user's presence in Supabase profiles
  Future<void> updatePresence({required bool isOnline}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();

    try {
      await Supabase.instance.client.from('profiles').update({
        'last_seen': nowIso,
        'is_online': isOnline,
      }).eq('id', user.id);
    } catch (_) {
      // Graceful fallback if is_online column does not exist
      try {
        await Supabase.instance.client.from('profiles').update({
          'updated_at': nowIso,
        }).eq('id', user.id);
      } catch (err) {
        debugPrint("Presence update notice: $err");
      }
    }
  }

  /// Computes accurate presence status from a profile record map.
  /// A user is ONLY considered "Active now" if their last seen is within 4 minutes.
  static UserPresenceInfo computePresence(Map<String, dynamic>? profile) {
    if (profile == null || profile.isEmpty) {
      return UserPresenceInfo.offline;
    }

    final isOnlineFlag = profile['is_online'] == true;
    final lastSeenStr = profile['last_seen']?.toString() ??
        profile['updated_at']?.toString() ??
        profile['created_at']?.toString();

    if (lastSeenStr == null || lastSeenStr.isEmpty) {
      return UserPresenceInfo.offline;
    }

    final lastSeen = DateTime.tryParse(lastSeenStr);
    if (lastSeen == null) {
      return UserPresenceInfo.offline;
    }

    final nowUtc = DateTime.now().toUtc();
    final lastSeenUtc = lastSeen.toUtc();
    final difference = nowUtc.difference(lastSeenUtc);

    // If within 4 minutes AND flag is true (or recently pulsed), user is truly Active Now
    if (isOnlineFlag && difference.inMinutes < 4) {
      return UserPresenceInfo(
        isOnline: true,
        statusText: "Active now",
        lastSeen: lastSeen,
      );
    }

    // Human-readable Last Seen computation
    String text;
    if (difference.inMinutes < 1) {
      text = "Active just now";
    } else if (difference.inMinutes < 60) {
      final m = difference.inMinutes.clamp(1, 59);
      text = "Active ${m}m ago";
    } else if (difference.inHours < 24) {
      final h = difference.inHours.clamp(1, 23);
      text = "Active ${h}h ago";
    } else if (difference.inDays == 1) {
      text = "Active yesterday";
    } else if (difference.inDays < 7) {
      final d = difference.inDays.clamp(1, 6);
      text = "Active ${d}d ago";
    } else {
      text = "Active recently";
    }

    return UserPresenceInfo(
      isOnline: false,
      statusText: text,
      lastSeen: lastSeen,
    );
  }
}

