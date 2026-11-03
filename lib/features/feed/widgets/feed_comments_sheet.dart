import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/notification_service.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/utils/time_ago.dart';

/// Instagram-Grade Comments Sheet for ZEV.
/// Connected directly to Supabase `discussion_comments` and `profiles`.
class FeedCommentsSheet extends StatefulWidget {
  final String postId;
  final String postAuthorUsername;
  final VoidCallback? onCommentAdded;

  const FeedCommentsSheet({
    super.key,
    required this.postId,
    required this.postAuthorUsername,
    this.onCommentAdded,
  });

  static Future<void> show(
    BuildContext context, {
    required String postId,
    required String postAuthorUsername,
    VoidCallback? onCommentAdded,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeedCommentsSheet(
        postId: postId,
        postAuthorUsername: postAuthorUsername,
        onCommentAdded: onCommentAdded,
      ),
    );
  }

  @override
  State<FeedCommentsSheet> createState() => _FeedCommentsSheetState();
}

class _FeedCommentsSheetState extends State<FeedCommentsSheet> {
  final supabase = Supabase.instance.client;
  final TextEditingController _commentCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  bool _isLoading = true;
  bool _isSending = false;
  List<Map<String, dynamic>> _comments = [];
  String _myAvatarUrl = '';

  @override
  void initState() {
    super.initState();
    _loadMyAvatar();
    _fetchComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMyAvatar() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() => _myAvatarUrl = res['avatar_url'] ?? '');
      }
    } catch (_) {}
  }

  Future<void> _fetchComments() async {
    try {
      final res = await supabase
          .from('discussion_comments')
          .select('id, post_id, student_id, comment_text, created_at')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: true);

      final rawList = List<Map<String, dynamic>>.from(res as List);
      final authorIds =
          rawList.map((c) => c['student_id']?.toString() ?? '').toSet().toList();

      Map<String, Map<String, dynamic>> profilesMap = {};
      if (authorIds.isNotEmpty) {
        final profs = await supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url')
            .inFilter('id', authorIds);

        for (var p in (profs as List)) {
          profilesMap[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }

      final enriched = rawList.map((c) {
        final authorId = c['student_id']?.toString() ?? '';
        final profile = profilesMap[authorId] ?? {};
        return {
          'id': c['id'],
          'text': c['comment_text'] ?? '',
          'created_at': c['created_at'],
          'username': profile['username'] ?? 'user',
          'avatar_url': profile['avatar_url'] ?? '',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _comments = enriched;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Comments fetch warning: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePostComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to post comments.")),
      );
      return;
    }

    HapticFeedback.lightImpact();
    _commentCtrl.clear();
    setState(() => _isSending = true);

    // Optimistic addition
    final optimisticItem = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'text': text,
      'created_at': DateTime.now().toIso8601String(),
      'username': 'You',
      'avatar_url': _myAvatarUrl,
    };

    setState(() {
      _comments.add(optimisticItem);
    });

    try {
      await supabase.from('discussion_comments').insert({
        'post_id': widget.postId,
        'student_id': user.id,
        'comment_text': text,
      });

      // Dispatch in-app notification to post author
      try {
        final postRes = await supabase
            .from('discussion_posts')
            .select('student_id')
            .eq('id', widget.postId)
            .maybeSingle();
        final authorId = postRes?['student_id']?.toString() ?? '';
        if (authorId.isNotEmpty && authorId != user.id) {
          unawaited(NotificationService().sendNotificationToUser(
            targetUserId: authorId,
            title: "New Comment",
            message: "commented on your post: \"$text\"",
            notificationType: "comment",
            linkUrl: widget.postId,
            senderId: user.id,
          ));
        }
      } catch (_) {}

      widget.onCommentAdded?.call();

      // Scroll to bottom
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      debugPrint("Post comment error: $e");
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.72,
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.white,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Header
          const Text(
            "Comments",
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: Colors.white,
          ),

          // Comments List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: ZevColors.primaryBlue,
                    ),
                  )
                : _comments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 48,
                              color: ZevColors.textMuted.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              "No comments yet",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Start the conversation.",
                              style: TextStyle(
                                fontSize: 13,
                                color: ZevColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: _comments.length,
                        itemBuilder: (context, index) {
                          final item = _comments[index];
                          final avatar = item['avatar_url'] as String;
                          final username = item['username'] as String;
                          final text = item['text'] as String;
                          final timeAgo = TimeAgo.fromIsoString(
                            item['created_at']?.toString(),
                          );

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white, width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 17,
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  backgroundImage: avatar.isNotEmpty
                                      ? NetworkImage(avatar)
                                      : null,
                                  child: avatar.isEmpty
                                      ? const Icon(
                                          Icons.person_rounded,
                                          size: 20,
                                          color: ZevColors.textMuted,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Builder(
                                    builder: (context) {
                                      final isCommentRtl = TextDirectionHelper.isRtl(text);
                                      return Column(
                                        crossAxisAlignment: isCommentRtl
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          RichText(
                                            textDirection: isCommentRtl
                                                ? TextDirection.rtl
                                                : TextDirection.ltr,
                                            textAlign: isCommentRtl
                                                ? TextAlign.right
                                                : TextAlign.left,
                                            text: TextSpan(
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                color: ZevColors.deepNavy,
                                                height: 1.35,
                                              ),
                                              children: [
                                                TextSpan(
                                                  text: isCommentRtl
                                                      ? " $username "
                                                      : "$username ",
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                TextSpan(text: text),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            timeAgo,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: ZevColors.textMuted,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // Bottom Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF1F5F9),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFF1F5F9),
                    backgroundImage: _myAvatarUrl.isNotEmpty
                        ? NetworkImage(_myAvatarUrl)
                        : null,
                    child: _myAvatarUrl.isEmpty
                        ? const Icon(
                            Icons.person_rounded,
                            size: 18,
                            color: ZevColors.textMuted,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _commentCtrl,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: ZevColors.deepNavy,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handlePostComment(),
                      decoration: InputDecoration(
                        hintText: "Add a comment for @${widget.postAuthorUsername}...",
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: ZevColors.textMuted,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isSending ? null : _handlePostComment,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

