import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../feed/screens/post_detail_screen.dart';

/// Instagram-Grade Comments Activity Screen for ZEV.
/// Displays all comments posted by the user with time, post preview, and quick navigation.
class ActivityCommentsScreen extends StatefulWidget {
  const ActivityCommentsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ActivityCommentsScreen(),
      ),
    );
  }

  @override
  State<ActivityCommentsScreen> createState() => _ActivityCommentsScreenState();
}

class _ActivityCommentsScreenState extends State<ActivityCommentsScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _comments = [];

  @override
  void initState() {
    super.initState();
    _fetchUserComments();
  }

  Future<void> _fetchUserComments() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch comments from discussion_comments
      final postCommentsRes = await supabase
          .from('discussion_comments')
          .select('id, post_id, content, created_at, likes_count')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      final List<Map<String, dynamic>> list = [];
      for (final row in (postCommentsRes as List)) {
        list.add({
          'id': row['id'].toString(),
          'type': 'post',
          'target_id': row['post_id']?.toString() ?? '',
          'content': row['content'] ?? '',
          'likes_count': row['likes_count'] ?? 0,
          'created_at': row['created_at'] ?? '',
        });
      }

      // 2. Fetch comments from reel_comments
      try {
        final reelCommentsRes = await supabase
            .from('reel_comments')
            .select('id, reel_id, content, created_at, likes_count')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(50);

        for (final row in (reelCommentsRes as List)) {
          list.add({
            'id': row['id'].toString(),
            'type': 'reel',
            'target_id': row['reel_id']?.toString() ?? '',
            'content': row['content'] ?? '',
            'likes_count': row['likes_count'] ?? 0,
            'created_at': row['created_at'] ?? '',
          });
        }
      } catch (_) {}

      // Sort all comments newest first
      list.sort((a, b) {
        final tA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(2000);
        final tB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(2000);
        return tB.compareTo(tA);
      });

      if (mounted) {
        setState(() {
          _comments = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fetch user comments error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTimestamp(String ts) {
    final dt = DateTime.tryParse(ts);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      return "${diff.inMinutes}m ago";
    } else if (diff.inHours < 24) {
      return "${diff.inHours}h ago";
    } else if (diff.inDays < 7) {
      return "${diff.inDays}d ago";
    } else {
      return "${dt.year}/${dt.month}/${dt.day}";
    }
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
        title: Column(
          children: [
            const Text(
              "Comments",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            Text(
              "${_comments.length} comments shared",
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? _buildShimmerList()
            : _comments.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
                    itemCount: _comments.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _comments[index];
                      return _buildCommentCard(item);
                    },
                  ),
      ),
    );
  }

  Widget _buildCommentCard(Map<String, dynamic> item) {
    final isReel = item['type'] == 'reel';
    final content = item['content'] as String;
    final targetId = item['target_id'] as String;
    final timeStr = _formatTimestamp(item['created_at'] as String);

    return Container(
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.lightImpact();
            if (!isReel && targetId.isNotEmpty) {
              PostDetailScreen.open(context, postId: targetId);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Opening discussion thread..."),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isReel ? Icons.play_arrow_rounded : Icons.chat_bubble_rounded,
                    color: const Color(0xFF0284C7),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isReel ? "Comment on Reel" : "Comment on Post",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        content,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Color(0xFFCBD5E1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 34,
                color: Color(0xFF0284C7),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "No Comments Yet",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "When you comment on posts and reels across ZEV, they will appear here.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF64748B),
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
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      itemCount: 6,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return Container(
          height: 70,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
        );
      },
    );
  }
}

