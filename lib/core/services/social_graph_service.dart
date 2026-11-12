import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/zev_theme.dart';
import 'notification_service.dart';

enum FollowToggleStatus {
  following,
  unfollowed,
  requested,
  cancelled,
  blocked,
  error,
}

class UserSafetyFilters {
  final Set<String> blockedUserIds;
  final Set<String> mutedPostUserIds;
  final Set<String> mutedStoryUserIds;
  final Set<String> mutedMessageUserIds;

  const UserSafetyFilters({
    this.blockedUserIds = const {},
    this.mutedPostUserIds = const {},
    this.mutedStoryUserIds = const {},
    this.mutedMessageUserIds = const {},
  });

  Set<String> get feedExcludedUserIds => {...blockedUserIds, ...mutedPostUserIds};
  Set<String> get storyExcludedUserIds => {...blockedUserIds, ...mutedStoryUserIds};
}

/// Centralized social graph, follow requests, blocking, muting, hiding, and reporting service.
class SocialGraphService {
  SocialGraphService._();
  static final SocialGraphService instance = SocialGraphService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<FollowToggleStatus> toggleFollow(String targetUserId) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null || targetUserId.isEmpty || me == targetUserId) {
      return FollowToggleStatus.error;
    }

    try {
      final raw = await _supabase.rpc(
        'toggle_follow_user',
        params: {'p_target_id': targetUserId},
      );
      final status = (raw is Map ? raw['status'] : null)?.toString() ?? '';
      switch (status) {
        case 'following':
          unawaited(
            NotificationService().dispatchPushNotification(
              recipientUserId: targetUserId,
              title: 'New Follower',
              body: 'started following you on ZEV.',
              notificationType: 'follow',
              deepLink: '/profile/$me',
            ),
          );
          return FollowToggleStatus.following;
        case 'unfollowed':
          return FollowToggleStatus.unfollowed;
        case 'requested':
          unawaited(
            NotificationService().dispatchPushNotification(
              recipientUserId: targetUserId,
              title: 'Follow Request',
              body: 'requested to follow you on ZEV.',
              notificationType: 'follow_request',
              deepLink: '/profile/$me',
            ),
          );
          return FollowToggleStatus.requested;
        case 'cancelled':
          return FollowToggleStatus.cancelled;
        case 'blocked':
          return FollowToggleStatus.blocked;
        default:
          return FollowToggleStatus.error;
      }
    } catch (e) {
      debugPrint('[SocialGraphService] toggleFollow error: $e');
      return FollowToggleStatus.error;
    }
  }

  Future<bool> acceptFollowRequest(String requestId) async {
    try {
      String? requesterId;
      try {
        final reqRow = await _supabase
            .from('follow_requests')
            .select('requester_id')
            .eq('id', requestId)
            .maybeSingle();
        requesterId = reqRow?['requester_id']?.toString();
      } catch (_) {}

      final res = await _supabase.rpc(
        'accept_follow_request',
        params: {'p_request_id': requestId},
      );
      if (res == true && requesterId != null && requesterId.isNotEmpty) {
        final me = _supabase.auth.currentUser?.id;
        unawaited(
          NotificationService().dispatchPushNotification(
            recipientUserId: requesterId,
            title: 'Follow Request Accepted',
            body: 'accepted your follow request on ZEV.',
            notificationType: 'follow_accepted',
            deepLink: me != null ? '/profile/$me' : null,
          ),
        );
      }
      return res == true;
    } catch (e) {
      debugPrint('[SocialGraphService] acceptFollowRequest error: $e');
      return false;
    }
  }

  Future<bool> rejectFollowRequest(String requestId) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return false;
    try {
      await _supabase
          .from('follow_requests')
          .delete()
          .eq('id', requestId)
          .eq('target_id', me);
      return true;
    } catch (e) {
      debugPrint('[SocialGraphService] rejectFollowRequest error: $e');
      return false;
    }
  }

  Future<bool> removeFollower(String followerId) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null || followerId.isEmpty) return false;
    try {
      await _supabase
          .from('user_follows')
          .delete()
          .eq('follower_id', followerId)
          .eq('following_id', me);
      return true;
    } catch (e) {
      debugPrint('[SocialGraphService] removeFollower error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchPendingIncomingRequests() async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return [];
    try {
      final reqs = await _supabase
          .from('follow_requests')
          .select('id, requester_id, created_at')
          .eq('target_id', me)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(reqs as List);
      if (rows.isEmpty) return [];

      final requesterIds = rows
          .map((r) => r['requester_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final profilesRes = await _supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified')
          .inFilter('id', requesterIds);

      final pMap = <String, Map<String, dynamic>>{};
      for (final p in (profilesRes as List)) {
        final m = Map<String, dynamic>.from(p as Map);
        pMap[m['id'].toString()] = m;
      }

      return rows.map((r) {
        final reqId = r['requester_id']?.toString() ?? '';
        final profile = pMap[reqId] ?? <String, dynamic>{};
        final fn = (profile['first_name'] ?? '').toString().trim();
        final ln = (profile['last_name'] ?? '').toString().trim();
        final full = "$fn $ln".trim();
        final uname = (profile['username'] ?? 'user').toString();
        return {
          'request_id': r['id'].toString(),
          'requester_id': reqId,
          'created_at': r['created_at']?.toString() ?? '',
          'username': uname,
          'full_name': full.isNotEmpty ? full : '@$uname',
          'avatar_url': (profile['avatar_url'] ?? '').toString(),
          'is_verified': profile['is_verified'] == true,
        };
      }).toList();
    } catch (e) {
      debugPrint('[SocialGraphService] fetchPendingIncomingRequests error: $e');
      return [];
    }
  }

  Future<int> fetchPendingRequestCount() async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return 0;
    try {
      final rows = await _supabase
          .from('follow_requests')
          .select('id')
          .eq('target_id', me)
          .eq('status', 'pending');
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, dynamic>> getInteractionPolicy(String targetUserId) async {
    if (targetUserId.isEmpty) {
      return {'is_blocked': false, 'can_view_content': false};
    }
    try {
      final raw = await _supabase.rpc(
        'get_user_interaction_policy',
        params: {'p_target_id': targetUserId},
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (e) {
      debugPrint('[SocialGraphService] getInteractionPolicy notice: $e');
    }
    return {
      'is_blocked': false,
      'is_private': false,
      'is_following': false,
      'is_pending_request': false,
      'is_followed_by': false,
      'hide_online_status': false,
      'can_view_content': true,
      'can_message': true,
      'can_mention': true,
      'can_tag': true,
      'can_reply_story': true,
    };
  }

  Future<bool> blockUser(String targetUserId) async {
    try {
      final res = await _supabase.rpc(
        'block_user_atomic',
        params: {'p_blocked_id': targetUserId},
      );
      return res == true;
    } catch (e) {
      debugPrint('[SocialGraphService] blockUser error: $e');
      return false;
    }
  }

  Future<bool> unblockUser(String targetUserId) async {
    try {
      final res = await _supabase.rpc(
        'unblock_user_atomic',
        params: {'p_blocked_id': targetUserId},
      );
      return res == true;
    } catch (e) {
      debugPrint('[SocialGraphService] unblockUser error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchBlockedUsers() async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return [];
    try {
      final rows = await _supabase
          .from('user_blocks')
          .select('blocked_id, created_at')
          .eq('blocker_id', me)
          .order('created_at', ascending: false);

      final blockList = List<Map<String, dynamic>>.from(rows as List);
      if (blockList.isEmpty) return [];

      final ids = blockList
          .map((b) => b['blocked_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      final profiles = await _supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified')
          .inFilter('id', ids);

      final pMap = <String, Map<String, dynamic>>{};
      for (final p in (profiles as List)) {
        final m = Map<String, dynamic>.from(p as Map);
        pMap[m['id'].toString()] = m;
      }

      return blockList.map((b) {
        final id = b['blocked_id']?.toString() ?? '';
        final p = pMap[id] ?? <String, dynamic>{};
        final fn = (p['first_name'] ?? '').toString().trim();
        final ln = (p['last_name'] ?? '').toString().trim();
        final full = "$fn $ln".trim();
        final uname = (p['username'] ?? 'user').toString();
        return {
          'id': id,
          'username': uname,
          'full_name': full.isNotEmpty ? full : '@$uname',
          'avatar_url': (p['avatar_url'] ?? '').toString(),
          'is_verified': p['is_verified'] == true,
          'created_at': b['created_at']?.toString() ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint('[SocialGraphService] fetchBlockedUsers error: $e');
      return [];
    }
  }

  Future<bool> muteUser(
    String targetUserId, {
    bool mutePosts = true,
    bool muteStories = true,
    bool muteMessages = false,
  }) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null || targetUserId.isEmpty || me == targetUserId) return false;
    try {
      await _supabase.from('user_mutes').upsert({
        'muter_id': me,
        'muted_id': targetUserId,
        'mute_posts': mutePosts,
        'mute_stories': muteStories,
        'mute_messages': muteMessages,
      }, onConflict: 'muter_id,muted_id');
      return true;
    } catch (e) {
      debugPrint('[SocialGraphService] muteUser error: $e');
      return false;
    }
  }

  Future<bool> unmuteUser(String targetUserId) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null || targetUserId.isEmpty) return false;
    try {
      await _supabase
          .from('user_mutes')
          .delete()
          .eq('muter_id', me)
          .eq('muted_id', targetUserId);
      return true;
    } catch (e) {
      debugPrint('[SocialGraphService] unmuteUser error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchMutedUsers() async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return [];
    try {
      final rows = await _supabase
          .from('user_mutes')
          .select('muted_id, mute_posts, mute_stories, mute_messages, created_at')
          .eq('muter_id', me)
          .order('created_at', ascending: false);

      final muteList = List<Map<String, dynamic>>.from(rows as List);
      if (muteList.isEmpty) return [];

      final ids = muteList
          .map((m) => m['muted_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      final profiles = await _supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified')
          .inFilter('id', ids);

      final pMap = <String, Map<String, dynamic>>{};
      for (final p in (profiles as List)) {
        final pm = Map<String, dynamic>.from(p as Map);
        pMap[pm['id'].toString()] = pm;
      }

      return muteList.map((m) {
        final id = m['muted_id']?.toString() ?? '';
        final p = pMap[id] ?? <String, dynamic>{};
        final fn = (p['first_name'] ?? '').toString().trim();
        final ln = (p['last_name'] ?? '').toString().trim();
        final full = "$fn $ln".trim();
        final uname = (p['username'] ?? 'user').toString();
        return {
          'id': id,
          'username': uname,
          'full_name': full.isNotEmpty ? full : '@$uname',
          'avatar_url': (p['avatar_url'] ?? '').toString(),
          'is_verified': p['is_verified'] == true,
          'mute_posts': m['mute_posts'] != false,
          'mute_stories': m['mute_stories'] != false,
          'mute_messages': m['mute_messages'] == true,
        };
      }).toList();
    } catch (e) {
      debugPrint('[SocialGraphService] fetchMutedUsers error: $e');
      return [];
    }
  }

  Future<UserSafetyFilters> fetchSafetyFilters() async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) return const UserSafetyFilters();
    try {
      final results = await Future.wait([
        _supabase.from('user_blocks').select('blocked_id').eq('blocker_id', me),
        _supabase
            .from('user_mutes')
            .select('muted_id, mute_posts, mute_stories, mute_messages')
            .eq('muter_id', me),
      ]);

      final blockedIds = <String>{};
      for (final row in (results[0] as List)) {
        final id = row['blocked_id']?.toString() ?? '';
        if (id.isNotEmpty) blockedIds.add(id);
      }

      final mutedPosts = <String>{};
      final mutedStories = <String>{};
      final mutedMessages = <String>{};
      for (final row in (results[1] as List)) {
        final id = row['muted_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (row['mute_posts'] != false) mutedPosts.add(id);
        if (row['mute_stories'] != false) mutedStories.add(id);
        if (row['mute_messages'] == true) mutedMessages.add(id);
      }

      return UserSafetyFilters(
        blockedUserIds: blockedIds,
        mutedPostUserIds: mutedPosts,
        mutedStoryUserIds: mutedStories,
        mutedMessageUserIds: mutedMessages,
      );
    } catch (e) {
      debugPrint('[SocialGraphService] fetchSafetyFilters notice: $e');
      return const UserSafetyFilters();
    }
  }

  Future<bool> hideContent({
    required String targetId,
    required String targetType,
    String reason = 'not_interested',
  }) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null || targetId.isEmpty) return false;
    try {
      await _supabase.from('hidden_posts').upsert({
        'user_id': me,
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
      }, onConflict: 'user_id,target_type,target_id');
      return true;
    } catch (e) {
      debugPrint('[SocialGraphService] hideContent error: $e');
      return false;
    }
  }

  Future<({Set<String> hiddenPostIds, Set<String> hiddenReelIds})>
      fetchHiddenContentIds() async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) {
      return (hiddenPostIds: <String>{}, hiddenReelIds: <String>{});
    }
    try {
      final rows = await _supabase
          .from('hidden_posts')
          .select('target_type, target_id')
          .eq('user_id', me);
      final postIds = <String>{};
      final reelIds = <String>{};
      for (final row in (rows as List)) {
        final type = row['target_type']?.toString();
        final id = row['target_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (type == 'post') postIds.add(id);
        if (type == 'reel') reelIds.add(id);
      }
      return (hiddenPostIds: postIds, hiddenReelIds: reelIds);
    } catch (e) {
      debugPrint('[SocialGraphService] fetchHiddenContentIds notice: $e');
      return (hiddenPostIds: <String>{}, hiddenReelIds: <String>{});
    }
  }

  Future<bool> reportUser({
    required String reportedUserId,
    required String reason,
    String details = '',
  }) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null || reportedUserId.isEmpty || me == reportedUserId) {
      return false;
    }
    try {
      await _supabase.from('user_reports').insert({
        'reporter_id': me,
        'reported_user_id': reportedUserId,
        'reason': reason,
        'details': details,
      });
      return true;
    } catch (e) {
      debugPrint('[SocialGraphService] reportUser error: $e');
      return false;
    }
  }

  Future<bool> reportContent({
    required String targetType,
    required String targetId,
    required String reportedUserId,
    required String reason,
    String details = '',
  }) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null || targetId.isEmpty || reportedUserId.isEmpty) {
      return false;
    }
    try {
      await _supabase.from('post_reports').insert({
        'reporter_id': me,
        'target_type': targetType,
        'target_id': targetId,
        'reported_user_id': reportedUserId,
        'reason': reason,
        'details': details,
      });
      return true;
    } catch (e) {
      debugPrint('[SocialGraphService] reportContent error: $e');
      return false;
    }
  }

  Future<bool> showReportSheet(
    BuildContext context, {
    required String targetType, // 'user' | 'post' | 'reel' | 'comment' | 'story' | 'message'
    required String targetId,
    required String reportedUserId,
    String? targetLabel,
  }) async {
    const reasons = [
      'Spam or misleading content',
      'Harassment, bullying, or hate speech',
      'Nudity or sexual content',
      'Violence or dangerous behavior',
      'Scam, fraud, or impersonation',
      'Intellectual property violation',
      'Other policy violation',
    ];

    String selectedReason = reasons.first;
    final detailsCtrl = TextEditingController();
    bool submitting = false;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: ZevColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: ZevColors.errorRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.flag_rounded,
                        color: ZevColors.errorRed,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            targetLabel != null
                                ? 'Report $targetLabel'
                                : 'Report Content',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          const Text(
                            'Your report is anonymous to the other user.',
                            style: TextStyle(
                              fontSize: 12,
                              color: ZevColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...reasons.map((r) {
                  final active = selectedReason == r;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setModalState(() => selectedReason = r);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? ZevColors.primaryBlue.withValues(alpha: 0.1)
                              : ZevColors.softSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: active
                                ? ZevColors.primaryBlue
                                : ZevColors.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                r,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: ZevColors.deepNavy,
                                ),
                              ),
                            ),
                            if (active)
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: ZevColors.secondaryBlue,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                TextField(
                  controller: detailsCtrl,
                  maxLines: 2,
                  maxLength: 300,
                  decoration: InputDecoration(
                    hintText: 'Additional details (optional)...',
                    filled: true,
                    fillColor: ZevColors.softSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: ZevColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: ZevColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            setModalState(() => submitting = true);
                            final ok = targetType == 'user'
                                ? await reportUser(
                                    reportedUserId: reportedUserId,
                                    reason: selectedReason,
                                    details: detailsCtrl.text.trim(),
                                  )
                                : await reportContent(
                                    targetType: targetType,
                                    targetId: targetId,
                                    reportedUserId: reportedUserId,
                                    reason: selectedReason,
                                    details: detailsCtrl.text.trim(),
                                  );
                            if (sheetCtx.mounted) {
                              Navigator.pop(sheetCtx, ok);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZevColors.errorRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Submit Report',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    detailsCtrl.dispose();

    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Report submitted. Our safety team will review it shortly.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ZevColors.deepNavy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }

    return submitted == true;
  }
}

