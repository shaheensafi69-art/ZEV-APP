import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/badge_counter_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_skeleton.dart';
import '../../profile/screens/profile_screen.dart';

/// Dedicated Instagram-Grade Follow Requests Screen for Private Accounts.
/// Displays all pending incoming follow requests with instant optimistic
/// [Confirm] and [Delete] responses.
class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  static Future<bool?> open(BuildContext context) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const FollowRequestsScreen()),
    );
  }

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _requests = [];
  final Set<String> _busyRequestIds = {};
  final Set<String> _confirmedRequestIds = {};
  bool _hasChanges = false;

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    final uid = _currentUserId;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final raw = await _supabase
          .from('follow_requests')
          .select('id, requester_id, created_at')
          .eq('target_id', uid)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(100);

      final list = List.from(raw as List? ?? []);
      if (list.isEmpty) {
        if (mounted) {
          setState(() {
            _requests = [];
            _isLoading = false;
          });
        }
        return;
      }

      final requesterIds = list
          .map((r) => r['requester_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final profs = await _supabase
          .from('profiles')
          .select('id, username, full_name, avatar_url, is_verified')
          .inFilter('id', requesterIds);

      final profMap = <String, Map<String, dynamic>>{};
      for (final p in List.from(profs as List? ?? [])) {
        final id = p['id']?.toString() ?? '';
        if (id.isNotEmpty) profMap[id] = Map<String, dynamic>.from(p as Map);
      }

      final enriched = <Map<String, dynamic>>[];
      for (final r in list) {
        final reqId = r['id']?.toString() ?? '';
        final requesterId = r['requester_id']?.toString() ?? '';
        final profile = profMap[requesterId] ?? {};
        enriched.add({
          'request_id': reqId,
          'requester_id': requesterId,
          'username': profile['username']?.toString() ?? 'user',
          'full_name': profile['full_name']?.toString() ?? '',
          'avatar_url': profile['avatar_url']?.toString() ?? '',
          'is_verified': profile['is_verified'] == true,
          'created_at': r['created_at']?.toString() ?? '',
        });
      }

      if (mounted) {
        setState(() {
          _requests = enriched;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[FollowRequestsScreen] Fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _respond(Map<String, dynamic> req, {required bool accept}) async {
    final reqId = req['request_id']?.toString() ?? '';
    final requesterId = req['requester_id']?.toString() ?? '';
    final uid = _currentUserId;
    if (reqId.isEmpty || uid == null) return;

    HapticFeedback.lightImpact();
    _hasChanges = true;

    // Optimistic UI update
    setState(() {
      _busyRequestIds.add(reqId);
      if (accept) {
        _confirmedRequestIds.add(reqId);
      } else {
        _requests.removeWhere((r) => r['request_id'] == reqId);
      }
    });

    try {
      final ok = accept
          ? await SocialGraphService.instance.acceptFollowRequest(reqId)
          : await SocialGraphService.instance.rejectFollowRequest(reqId);

      if (accept && ok) {
        unawaited(
          NotificationService().sendNotificationToUser(
            targetUserId: requesterId,
            title: 'Follow Accepted',
            message: 'accepted your follow request.',
            notificationType: 'follow',
            linkUrl: uid,
          ),
        );
      }

      BadgeCounterService.instance.refreshCounts();
    } catch (e) {
      debugPrint('[FollowRequestsScreen] Action error: $e');
    } finally {
      if (mounted) {
        setState(() => _busyRequestIds.remove(reqId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, _) {
        // Return changes flag if needed
      },
      child: Scaffold(
        backgroundColor: ZevColors.softSurface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: ZevColors.deepNavy,
              size: 20,
            ),
            onPressed: () => Navigator.of(context).pop(_hasChanges),
          ),
          title: Text(
            'Follow requests',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: ZevColors.deepNavy,
            ),
          ),
        ),
        body: _isLoading
            ? _buildShimmerList()
            : _requests.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _fetchRequests,
                    color: ZevColors.primaryBlue,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      itemCount: _requests.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _buildRequestCard(_requests[index]);
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final reqId = req['request_id']?.toString() ?? '';
    final requesterId = req['requester_id']?.toString() ?? '';
    final username = req['username']?.toString() ?? 'user';
    final fullName = req['full_name']?.toString() ?? '';
    final avatarUrl = req['avatar_url']?.toString() ?? '';
    final isVerified = req['is_verified'] == true;
    final isConfirmed = _confirmedRequestIds.contains(reqId);
    final isBusy = _busyRequestIds.contains(reqId);
    final dt = DateTime.tryParse(req['created_at']?.toString() ?? '') ??
        DateTime.now();
    final timeStr = TimeAgo.format(dt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ZevColors.border,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          GestureDetector(
            onTap: () => ProfileScreen.open(context, userId: requesterId),
            child: ZevCachedImage.avatar(imageUrl: avatarUrl, size: 48),
          ),
          const SizedBox(width: 12),

          // User info
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ProfileScreen.open(context, userId: requesterId),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: ZevColors.primaryBlue,
                        ),
                      ],
                    ],
                  ),
                  if (fullName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 11,
                      color: ZevColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Action Buttons
          if (isConfirmed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Following',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else if (isBusy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Confirm Button
                GestureDetector(
                  onTap: () => _respond(req, accept: true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7.5,
                    ),
                    decoration: BoxDecoration(
                      gradient: ZevColors.brandGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Delete Button
                GestureDetector(
                  onTap: () => _respond(req, accept: false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: const Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF1F5F9),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
              ),
              child: const Icon(
                Icons.mark_email_read_outlined,
                size: 38,
                color: ZevColors.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Follow Requests',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'When people request to follow your private account, they will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ZevColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ZevColors.border),
        ),
        child: Row(
          children: [
            const ZevSkeleton(width: 48, height: 48, shape: BoxShape.circle),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ZevSkeleton(
                    width: 120,
                    height: 14,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  const SizedBox(height: 6),
                  ZevSkeleton(
                    width: 80,
                    height: 11,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ZevSkeleton(
              width: 64,
              height: 32,
              borderRadius: BorderRadius.circular(12),
            ),
            const SizedBox(width: 6),
            ZevSkeleton(
              width: 54,
              height: 32,
              borderRadius: BorderRadius.circular(12),
            ),
          ],
        ),
      ),
    );
  }
}
