import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin Approval Queue for Private Community Join Requests.
class CommunityJoinRequestsSheet extends StatefulWidget {
  final String communityId;
  final String communityName;
  final VoidCallback onUpdated;

  const CommunityJoinRequestsSheet({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.onUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required String communityId,
    required String communityName,
    required VoidCallback onUpdated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunityJoinRequestsSheet(
        communityId: communityId,
        communityName: communityName,
        onUpdated: onUpdated,
      ),
    );
  }

  @override
  State<CommunityJoinRequestsSheet> createState() =>
      _CommunityJoinRequestsSheetState();
}

class _CommunityJoinRequestsSheetState
    extends State<CommunityJoinRequestsSheet> {
  final _client = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client
          .from('community_members')
          .select('id, user_id, role, created_at, profiles(username, full_name, avatar_url, is_verified)')
          .eq('community_id', widget.communityId)
          .eq('role', 'pending')
          .order('created_at', ascending: false);

      setState(() {
        _requests = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[CommunityJoinRequestsSheet] fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approveRequest(String memberId, String username) async {
    HapticFeedback.mediumImpact();
    try {
      await _client
          .from('community_members')
          .update({'role': 'member'})
          .eq('id', memberId);

      setState(() {
        _requests.removeWhere((r) => r['id'] == memberId);
      });
      widget.onUpdated();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('@$username approved to join ${widget.communityName}!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving request: $e')),
        );
      }
    }
  }

  Future<void> _declineRequest(String memberId, String username) async {
    HapticFeedback.lightImpact();
    try {
      await _client.from('community_members').delete().eq('id', memberId);

      setState(() {
        _requests.removeWhere((r) => r['id'] == memberId);
      });
      widget.onUpdated();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Join request from @$username declined.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error declining request: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.person_add_rounded,
                  color: Color(0xFF0284C7),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Join Requests (${_requests.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0284C7)),
                  )
                : _requests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 48,
                              color: Color(0xFF94A3B8),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No pending requests',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'All prospective members have been reviewed.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        itemCount: _requests.length,
                        separatorBuilder: (ctx, i) =>
                            const Divider(height: 16, color: Color(0xFFF1F5F9)),
                        itemBuilder: (ctx, idx) {
                          final req = _requests[idx];
                          final prof =
                              req['profiles'] as Map<String, dynamic>? ?? {};
                          final name = prof['full_name'] ?? 'Member';
                          final username = prof['username'] ?? 'user';
                          final avatar = prof['avatar_url']?.toString();

                          return Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: const Color(0xFF0284C7),
                                backgroundImage: avatar != null && avatar.isNotEmpty
                                    ? CachedNetworkImageProvider(avatar)
                                    : null,
                                child: avatar == null || avatar.isEmpty
                                    ? Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      '@$username',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Actions
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Decline
                                  GestureDetector(
                                    onTap: () =>
                                        _declineRequest(req['id'], username),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Decline',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Approve
                                  GestureDetector(
                                    onTap: () =>
                                        _approveRequest(req['id'], username),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF0284C7),
                                            Color(0xFF06B6D4)
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Approve',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
