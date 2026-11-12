import 'package:flutter/material.dart';

import '../../../core/widgets/comments_thread_sheet.dart';

/// Light Clearmorphic Comments Sheet for ZEV Feed Posts.
/// Connected directly to Supabase `discussion_comments`, `comment_likes`, and `comment_pins`.
class FeedCommentsSheet extends StatelessWidget {
  final String postId;
  final String postAuthorUsername;
  final String? postAuthorId;
  final VoidCallback? onCommentAdded;
  final VoidCallback? onCommentDeleted;

  const FeedCommentsSheet({
    super.key,
    required this.postId,
    required this.postAuthorUsername,
    this.postAuthorId,
    this.onCommentAdded,
    this.onCommentDeleted,
  });

  static Future<void> show(
    BuildContext context, {
    required String postId,
    required String postAuthorUsername,
    String? postAuthorId,
    VoidCallback? onCommentAdded,
    VoidCallback? onCommentDeleted,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeedCommentsSheet(
        postId: postId,
        postAuthorUsername: postAuthorUsername,
        postAuthorId: postAuthorId,
        onCommentAdded: onCommentAdded,
        onCommentDeleted: onCommentDeleted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommentsThreadSheet(
      targetType: 'post',
      targetId: postId,
      targetAuthorUsername: postAuthorUsername,
      targetAuthorId: postAuthorId,
      onCommentAdded: onCommentAdded,
      onCommentDeleted: onCommentDeleted,
    );
  }
}
