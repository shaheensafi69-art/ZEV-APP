import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized live unread counter manager backed by PostgreSQL RPC `get_unread_badge_counts()`
/// and scoped Supabase Realtime listeners so unread counts sync across all devices.
class BadgeCounterService {
  BadgeCounterService._();
  static final BadgeCounterService instance = BadgeCounterService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  final ValueNotifier<int> unreadNotificationsCount = ValueNotifier<int>(0);
  final ValueNotifier<int> unreadMessagesCount = ValueNotifier<int>(0);
  final ValueNotifier<int> unreadRequestsCount = ValueNotifier<int>(0);
  final ValueNotifier<int> totalUnreadCount = ValueNotifier<int>(0);

  RealtimeChannel? _channel;
  String? _listeningUserId;
  Timer? _debounceTimer;
  bool _isRefreshing = false;

  void startListening() {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      stopListening();
      return;
    }
    if (_listeningUserId == uid && _channel != null) {
      unawaited(refreshCounts());
      return;
    }

    stopListening(resetValues: false);
    _listeningUserId = uid;

    try {
      _channel = _supabase
          .channel('badges:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'user_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: (_) => scheduleRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'direct_messages',
            callback: (_) => scheduleRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'message_reads',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: (_) => scheduleRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'message_requests',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'recipient_id',
              value: uid,
            ),
            callback: (_) => scheduleRefresh(),
          )
          .subscribe();
    } catch (e) {
      debugPrint('[BadgeCounterService] Realtime notice: $e');
    }

    unawaited(refreshCounts());
  }

  void scheduleRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 220), () {
      unawaited(refreshCounts());
    });
  }

  Future<void> refreshCounts() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      _setValues(0, 0, 0);
      return;
    }
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      final raw = await _supabase.rpc('get_unread_badge_counts');
      if (raw is Map) {
        final notif = (raw['unread_notifications'] as num?)?.toInt() ?? 0;
        final msgs = (raw['unread_messages'] as num?)?.toInt() ?? 0;
        final reqs = (raw['unread_requests'] as num?)?.toInt() ?? 0;
        _setValues(notif, msgs, reqs);
      }
    } catch (e) {
      debugPrint('[BadgeCounterService] refreshCounts notice: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  void markNotificationsReadOptimistic() {
    unreadNotificationsCount.value = 0;
    totalUnreadCount.value = unreadMessagesCount.value;
    scheduleRefresh();
  }

  void stopListening({bool resetValues = true}) {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _channel?.unsubscribe();
    _channel = null;
    _listeningUserId = null;
    if (resetValues) {
      _setValues(0, 0, 0);
    }
  }

  void _setValues(int notifications, int messages, int requests) {
    final safeNotif = notifications < 0 ? 0 : notifications;
    final safeMsgs = messages < 0 ? 0 : messages;
    final safeReqs = requests < 0 ? 0 : requests;
    if (unreadNotificationsCount.value != safeNotif) {
      unreadNotificationsCount.value = safeNotif;
    }
    if (unreadMessagesCount.value != safeMsgs) {
      unreadMessagesCount.value = safeMsgs;
    }
    if (unreadRequestsCount.value != safeReqs) {
      unreadRequestsCount.value = safeReqs;
    }
    final nextTotal = safeNotif + safeMsgs;
    if (totalUnreadCount.value != nextTotal) {
      totalUnreadCount.value = nextTotal;
    }
  }
}
