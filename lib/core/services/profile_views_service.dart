import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service managing TikTok-style 30-day Profile Views telemetry.
/// Records visitors when other users view a profile and provides
/// 30-day visitor analytics with optimistic caching.
class ProfileViewsService {
  ProfileViewsService._();
  static final ProfileViewsService instance = ProfileViewsService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  // Cache to avoid sending duplicate record RPC calls within the same app session
  final Set<String> _recordedInSession = {};

  /// Records a profile view if viewed by another authenticated user.
  /// Deduplicated within the app session to save network bandwidth.
  Future<void> recordProfileView(String targetProfileId) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty || targetProfileId.isEmpty) return;
    if (uid == targetProfileId) return; // Never record self-views

    if (_recordedInSession.contains(targetProfileId)) return;
    _recordedInSession.add(targetProfileId);

    try {
      await _supabase.rpc('record_profile_view', params: {
        'p_profile_id': targetProfileId,
      });
    } catch (e) {
      debugPrint('[ProfileViewsService] recordProfileView error: $e');
    }
  }

  /// Fetches viewers who visited the user's profile in the past 30 days.
  /// Returns:
  /// {
  ///   'count': int,
  ///   'viewers': [ { 'id', 'viewer_id', 'username', 'full_name', 'avatar_url', 'is_verified', 'viewed_at', 'is_following' } ]
  /// }
  Future<Map<String, dynamic>> getProfileViews30Days() async {
    final uid = _currentUserId;
    if (uid == null) {
      return {'count': 0, 'viewers': <Map<String, dynamic>>[]};
    }

    try {
      final res = await _supabase.rpc('get_profile_views_30d');
      if (res is Map) {
        final count = (res['count'] as num?)?.toInt() ?? 0;
        final rawList = res['viewers'] as List? ?? [];
        final viewers = rawList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        return {'count': count, 'viewers': viewers};
      }
    } catch (e) {
      debugPrint('[ProfileViewsService] getProfileViews30Days error: $e');
    }

    return {'count': 0, 'viewers': <Map<String, dynamic>>[]};
  }

  /// Returns just the 30-day view count for badge display.
  Future<int> getProfileViewsCount() async {
    final data = await getProfileViews30Days();
    return (data['count'] as int?) ?? 0;
  }
}
