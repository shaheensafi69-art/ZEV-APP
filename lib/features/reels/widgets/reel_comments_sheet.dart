import 'package:flutter/material.dart';

import '../../../core/widgets/comments_thread_sheet.dart';

/// Light Clearmorphic Comments Sheet for ZEV Reels.
/// Connected directly to Supabase `reel_comments`, `comment_likes`, and `comment_pins`.
class ReelCommentsSheet extends StatelessWidget {
  final String reelId;
  final String reelAuthorUsername;
  final String? reelAuthorId;
  final VoidCallback? onCommentAdded;
  final VoidCallback? onCommentDeleted;

  const ReelCommentsSheet({
    super.key,
    required this.reelId,
    required this.reelAuthorUsername,
    this.reelAuthorId,
    this.onCommentAdded,
    this.onCommentDeleted,
  });

  static Future<void> show(
    BuildContext context, {
    required String reelId,
    required String reelAuthorUsername,
    String? reelAuthorId,
    VoidCallback? onCommentAdded,
    VoidCallback? onCommentDeleted,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReelCommentsSheet(
        reelId: reelId,
        reelAuthorUsername: reelAuthorUsername,
        reelAuthorId: reelAuthorId,
        onCommentAdded: onCommentAdded,
        onCommentDeleted: onCommentDeleted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommentsThreadSheet(
      targetType: 'reel',
      targetId: reelId,
      targetAuthorUsername: reelAuthorUsername,
      targetAuthorId: reelAuthorId,
      onCommentAdded: onCommentAdded,
      onCommentDeleted: onCommentDeleted,
    );
  }
}
