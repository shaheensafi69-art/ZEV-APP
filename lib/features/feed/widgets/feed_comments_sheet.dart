import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/auth_required_modal.dart';
import '../../../core/widgets/fast_cached_image.dart';

/// Modular, high-performance comments modal sheet for Feed Posts.
class FeedCommentsSheet extends StatefulWidget {
  final String postId;
  final String currentUserId;

  const FeedCommentsSheet({
    super.key,
    required this.postId,
    required this.currentUserId,
  });

  static Future<void> show(
    BuildContext context, {
    required String postId,
    required String currentUserId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FeedCommentsSheet(
        postId: postId,
        currentUserId: currentUserId,
      ),
    );
  }

  @override
  State<FeedCommentsSheet> createState() => _FeedCommentsSheetState();
}

class _FeedCommentsSheetState extends State<FeedCommentsSheet> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  bool isSending = false;
  List<Map<String, dynamic>> comments = [];

  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  String? replyingToCommentId;
  String? replyingToName;

  static const Color primaryPink = Color(0xFFFC466B);

  @override
  void initState() {
    super.initState();
    _fetchComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchComments() async {
    setState(() => isLoading = true);
    try {
      final res = await supabase
          .from("discussion_comments")
          .select("*")
          .eq("post_id", widget.postId)
          .order("created_at", ascending: true);

      List<Map<String, dynamic>> fetchedComments =
          List<Map<String, dynamic>>.from(res as List);

      final studentIds = fetchedComments
          .map((c) => c['student_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> profilesMap = {};

      if (studentIds.isNotEmpty) {
        try {
          final profilesRes = await supabase
              .from("profiles")
              .select("id, first_name, last_name, avatar_url")
              .inFilter("id", studentIds);

          for (var p in (profilesRes as List)) {
            profilesMap[p['id'].toString()] = p;
          }
        } catch (_) {}
      }

      for (var c in fetchedComments) {
        String sId = c['student_id']?.toString() ?? '';
        c['profiles'] = profilesMap[sId] ?? {
          'first_name': 'Student',
          'last_name': '',
          'avatar_url': '',
        };
      }

      if (mounted) {
        setState(() {
          comments = fetchedComments;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching comments: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _sendComment() async {
    if (widget.currentUserId.isEmpty) {
      AuthRequiredModal.show(context, actionName: "post comments");
      return;
    }

    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => isSending = true);
    try {
      final insertData = {
        'post_id': widget.postId,
        'student_id': widget.currentUserId,
        'comment_text': text,
      };

      if (replyingToCommentId != null) {
        insertData['parent_comment_id'] = replyingToCommentId!;
      }

      await supabase.from("discussion_comments").insert(insertData);

      // Send feed post comment notification
      try {
        final postData = await supabase
            .from("discussion_posts")
            .select("student_id, title")
            .eq("id", widget.postId)
            .maybeSingle();

        if (postData != null) {
          final authorId = postData['student_id']?.toString() ?? '';
          final postTitle = postData['title'] ?? 'your post';
          if (authorId.isNotEmpty && authorId != widget.currentUserId) {
            final senderProfile = await supabase
                .from("profiles")
                .select("first_name, last_name")
                .eq("id", widget.currentUserId)
                .maybeSingle();
            final String senderName = (senderProfile != null)
                ? "${senderProfile['first_name'] ?? 'Someone'} ${senderProfile['last_name'] ?? ''}"
                    .trim()
                : 'Someone';

            await supabase.from("user_notifications").insert({
              'user_id': authorId,
              'sender_id': widget.currentUserId,
              'title': "💬 Comment on your post",
              'message': "$senderName commented on \"$postTitle\": \"$text\"",
              'notification_type': "comment",
              'link_url': "/post/${widget.postId}",
              'is_read': false,
              'created_at': DateTime.now().toIso8601String(),
            });
          }
        }
      } catch (_) {}

      _commentController.clear();
      _commentFocusNode.unfocus();
      setState(() {
        replyingToCommentId = null;
        replyingToName = null;
      });
      await _fetchComments();
    } catch (e) {
      debugPrint("Error sending comment: $e");
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  void _startReplying(String commentId, String authorName) {
    if (widget.currentUserId.isEmpty) {
      AuthRequiredModal.show(context, actionName: "reply to comments");
      return;
    }
    setState(() {
      replyingToCommentId = commentId;
      replyingToName = authorName;
    });
    _commentFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      replyingToCommentId = null;
      replyingToName = null;
    });
    _commentFocusNode.unfocus();
  }

  List<Widget> _buildCommentTree(String? parentId, double leftPadding) {
    final childComments = comments.where((c) {
      if (parentId == null) return c['parent_comment_id'] == null;
      return c['parent_comment_id']?.toString() == parentId;
    }).toList();

    List<Widget> commentWidgets = [];
    for (var c in childComments) {
      final String authorName =
          "${c['profiles']?['first_name'] ?? 'User'} ${c['profiles']?['last_name'] ?? ''}"
              .trim();
      final String cId = c['id'].toString();
      final String avatar = c['profiles']?['avatar_url']?.toString() ?? '';

      commentWidgets.add(
        Padding(
          padding: EdgeInsets.only(left: leftPadding, bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FastCircleAvatar(
                imageUrl: avatar,
                radius: 16,
                fallbackText: authorName.isNotEmpty ? authorName[0] : 'U',
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authorName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c['comment_text'] ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF374151),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          c['created_at'] != null
                              ? c['created_at'].toString().split('T')[0]
                              : '',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _startReplying(cId, authorName),
                          child: const Text(
                            "Reply",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: primaryPink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      final nextPadding = leftPadding == 0 ? 32.0 : leftPadding;
      commentWidgets.addAll(_buildCommentTree(cId, nextPadding));
    }
    return commentWidgets;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 45,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "Comments",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const Divider(height: 30),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: primaryPink),
                  )
                : comments.isEmpty
                ? const Center(
                    child: Text(
                      "No comments yet. Start the conversation!",
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    physics: const BouncingScrollPhysics(),
                    children: _buildCommentTree(null, 0),
                  ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyingToName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Replying to $replyingToName",
                          style: const TextStyle(
                            fontSize: 12,
                            color: primaryPink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        GestureDetector(
                          onTap: _cancelReply,
                          child: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        focusNode: _commentFocusNode,
                        cursorColor: primaryPink,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF111827),
                        ),
                        decoration: InputDecoration(
                          hintText: replyingToName != null
                              ? "Write a reply..."
                              : "Add a comment...",
                          hintStyle: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF3F4F6),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: const BoxDecoration(
                        color: primaryPink,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: isSending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                        onPressed: isSending ? null : _sendComment,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
