import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/feed/models/feed_post_item.dart';
import '../../features/reels/models/reel_item.dart';
import '../theme/zev_theme.dart';

/// Centralized Content Deletion Service for ZEV.
/// Enforces strict ownership rules:
/// 1. Users can ONLY delete their own posts (matching student_id/authorId).
/// 2. Users can ONLY delete their own reels (matching user_id).
/// 3. Others' content will never show delete options, and attempts to delete will be rejected.
/// 4. Handles safe cascading deletions for likes, comments, and bookmarks.
class ContentDeletionService {
  ContentDeletionService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Check if the currently authenticated user owns this post
  static bool canDeletePost(FeedPostItem post) {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) return false;
    return currentUserId == post.authorId;
  }

  /// Check if the currently authenticated user owns this reel
  static bool canDeleteReel(ReelItem reel) {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) return false;
    return currentUserId == reel.userId;
  }

  /// Confirms and deletes a user's post with double verification and feedback
  static Future<bool> confirmAndDeletePost(
    BuildContext context, {
    required FeedPostItem post,
    VoidCallback? onDeleted,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;

    // Strict ownership verification
    if (currentUserId == null || currentUserId != post.authorId) {
      _showNotice(
        context,
        "Permission denied: You can only delete your own posts.",
        isError: true,
      );
      return false;
    }

    final confirmed = await _showConfirmationDialog(
      context,
      title: "Delete Post?",
      message:
          "Are you sure you want to permanently delete this post? All likes, comments, and reposts will be removed.",
      confirmButtonText: "Delete Post",
    );

    if (confirmed != true) return false;

    if (!context.mounted) return false;

    // Show loading overlay
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: ZevColors.primaryBlue),
      ),
    );

    try {
      // 1. Delete associated interactions to prevent foreign key errors
      try {
        await _supabase
            .from('discussion_likes')
            .delete()
            .eq('post_id', post.id);
      } catch (_) {}

      try {
        await _supabase
            .from('discussion_comments')
            .delete()
            .eq('post_id', post.id);
      } catch (_) {}

      try {
        await _supabase
            .from('post_reposts')
            .delete()
            .eq('post_id', post.id);
      } catch (_) {}

      try {
        await _supabase
            .from('post_bookmarks')
            .delete()
            .eq('post_id', post.id);
      } catch (_) {}

      // 2. Strict deletion query enforcing both post.id and student_id
      await _supabase
          .from('discussion_posts')
          .delete()
          .eq('id', post.id)
          .eq('student_id', currentUserId);

      HapticFeedback.mediumImpact();
      nav.pop(); // dismiss loading dialog

      if (context.mounted) {
        _showNotice(context, "Post deleted successfully.");
      }

      onDeleted?.call();
      return true;
    } catch (e) {
      nav.pop(); // dismiss loading dialog
      debugPrint("Post deletion error: $e");
      if (context.mounted) {
        _showNotice(
          context,
          "Failed to delete post. Please try again.",
          isError: true,
        );
      }
      return false;
    }
  }

  /// Confirms and deletes a user's reel with double verification and feedback
  static Future<bool> confirmAndDeleteReel(
    BuildContext context, {
    required ReelItem reel,
    VoidCallback? onDeleted,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;

    // Strict ownership verification
    if (currentUserId == null || currentUserId != reel.userId) {
      _showNotice(
        context,
        "Permission denied: You can only delete your own reels.",
        isError: true,
      );
      return false;
    }

    final confirmed = await _showConfirmationDialog(
      context,
      title: "Delete Reel?",
      message:
          "Are you sure you want to permanently delete this reel? All views, likes, and comments will be removed.",
      confirmButtonText: "Delete Reel",
    );

    if (confirmed != true) return false;

    if (!context.mounted) return false;

    // Show loading overlay
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: ZevColors.primaryBlue),
      ),
    );

    try {
      // 1. Delete associated interactions to prevent foreign key errors
      try {
        await _supabase.from('reel_likes').delete().eq('reel_id', reel.id);
      } catch (_) {}

      try {
        await _supabase.from('reel_comments').delete().eq('reel_id', reel.id);
      } catch (_) {}

      try {
        await _supabase.from('reel_bookmarks').delete().eq('reel_id', reel.id);
      } catch (_) {}

      // 2. Strict deletion query enforcing both reel.id and user_id
      await _supabase
          .from('reels')
          .delete()
          .eq('id', reel.id)
          .eq('user_id', currentUserId);

      HapticFeedback.mediumImpact();
      nav.pop(); // dismiss loading dialog

      if (context.mounted) {
        _showNotice(context, "Reel deleted successfully.");
      }

      onDeleted?.call();
      return true;
    } catch (e) {
      nav.pop(); // dismiss loading dialog
      debugPrint("Reel deletion error: $e");
      if (context.mounted) {
        _showNotice(
          context,
          "Failed to delete reel. Please try again.",
          isError: true,
        );
      }
      return false;
    }
  }

  /// Displays the luxury ZEV claymorphic confirmation dialog
  static Future<bool?> _showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmButtonText,
  }) {
    HapticFeedback.lightImpact();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 22),
        actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFCA5A5), width: 1),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFDC2626),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: ZevColors.deepNavy,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: ZevColors.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              "Cancel",
              style: TextStyle(
                color: ZevColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              confirmButtonText,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _showNotice(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? const Color(0xFFDC2626) : ZevColors.deepNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

