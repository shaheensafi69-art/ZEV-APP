import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/feed/models/feed_post_item.dart';
import '../../features/reels/models/reel_item.dart';
import '../theme/zev_theme.dart';
import 'cloudflare_storage_service.dart';

/// Centralized Content Lifecycle Service (Edit, Archive, Soft-Trash, Restore, Permanent Delete + R2 cleanup).
class ContentDeletionService {
  ContentDeletionService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static bool canDeletePost(FeedPostItem post) {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) return false;
    return currentUserId == post.authorId;
  }

  static bool canDeleteReel(ReelItem reel) {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) return false;
    return currentUserId == reel.userId;
  }

  /// Edits title, caption content, and optional location on a user's post.
  static Future<FeedPostItem?> showEditPostDialog(
    BuildContext context, {
    required FeedPostItem post,
    ValueChanged<FeedPostItem>? onUpdated,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != post.authorId) {
      _showNotice(
        context,
        'Permission denied: You can only edit your own posts.',
        isError: true,
      );
      return null;
    }

    final titleCtrl = TextEditingController(text: post.title);
    final contentCtrl = TextEditingController(text: post.content);
    final locationCtrl = TextEditingController(text: post.location);
    bool saving = false;

    final updatedPost = await showModalBottomSheet<FeedPostItem>(
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
                const Text(
                  'Edit Post',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  maxLength: 140,
                  decoration: InputDecoration(
                    labelText: 'Headline / Title (optional)',
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
                TextField(
                  controller: contentCtrl,
                  maxLines: 5,
                  minLines: 3,
                  maxLength: 2200,
                  decoration: InputDecoration(
                    labelText: 'Caption',
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
                TextField(
                  controller: locationCtrl,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: 'Location (optional)',
                    prefixIcon: const Icon(Icons.location_on_outlined, size: 19),
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: saving
                        ? null
                        : () async {
                            final newTitle = titleCtrl.text.trim();
                            final newContent = contentCtrl.text.trim();
                            final newLocation = locationCtrl.text.trim();
                            if (newContent.isEmpty && post.imageUrl.isEmpty) {
                              _showNotice(
                                ctx,
                                'Post caption cannot be empty.',
                                isError: true,
                              );
                              return;
                            }
                            setModalState(() => saving = true);
                            final now = DateTime.now().toUtc();
                            try {
                              await _supabase
                                  .from('discussion_posts')
                                  .update({
                                    'title': newTitle,
                                    'content': newContent,
                                    'location': newLocation.isEmpty
                                        ? null
                                        : newLocation,
                                    'edited_at': now.toIso8601String(),
                                    'updated_at': now.toIso8601String(),
                                  })
                                  .eq('id', post.id)
                                  .eq('student_id', currentUserId);

                              final next = post.copyWith(
                                title: newTitle,
                                content: newContent,
                                location: newLocation,
                                editedAt: now,
                              );
                              if (sheetCtx.mounted) {
                                Navigator.pop(sheetCtx, next);
                              }
                            } catch (e) {
                              debugPrint('Edit post error: $e');
                              setModalState(() => saving = false);
                              if (sheetCtx.mounted) {
                                _showNotice(
                                  sheetCtx,
                                  'Failed to save changes.',
                                  isError: true,
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZevColors.primaryBlue,
                      foregroundColor: ZevColors.deepNavy,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ZevColors.deepNavy,
                            ),
                          )
                        : const Text(
                            'Save Changes',
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

    titleCtrl.dispose();
    contentCtrl.dispose();
    locationCtrl.dispose();

    if (updatedPost != null) {
      HapticFeedback.mediumImpact();
      onUpdated?.call(updatedPost);
      if (context.mounted) {
        _showNotice(context, 'Post updated.');
      }
    }
    return updatedPost;
  }

  /// Archives or unarchives a post via `discussion_posts.is_draft`.
  static Future<bool> setPostArchived(
    BuildContext context, {
    required FeedPostItem post,
    required bool archived,
    VoidCallback? onUpdated,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != post.authorId) return false;
    try {
      await _supabase
          .from('discussion_posts')
          .update({
            'is_draft': archived,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', post.id)
          .eq('student_id', currentUserId);
      HapticFeedback.mediumImpact();
      if (context.mounted) {
        _showNotice(
          context,
          archived ? 'Moved to Archive.' : 'Restored to your profile.',
        );
      }
      onUpdated?.call();
      return true;
    } catch (e) {
      debugPrint('setPostArchived error: $e');
      if (context.mounted) {
        _showNotice(context, 'Could not update archive status.', isError: true);
      }
      return false;
    }
  }

  /// Soft-deletes a post into Recently Deleted (`deleted_at = now()`, 30-day recovery).
  static Future<bool> movePostToTrash(
    BuildContext context, {
    required FeedPostItem post,
    VoidCallback? onTrashed,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != post.authorId) {
      _showNotice(
        context,
        'Permission denied: You can only delete your own posts.',
        isError: true,
      );
      return false;
    }

    final confirmed = await _showConfirmationDialog(
      context,
      title: 'Move Post to Trash?',
      message:
          'You can restore this post from Your Activity -> Recently Deleted within 30 days before permanent removal.',
      confirmButtonText: 'Move to Trash',
    );
    if (confirmed != true) return false;

    try {
      await _supabase
          .from('discussion_posts')
          .update({
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', post.id)
          .eq('student_id', currentUserId);
      HapticFeedback.mediumImpact();
      if (context.mounted) {
        _showNotice(context, 'Post moved to Recently Deleted.');
      }
      onTrashed?.call();
      return true;
    } catch (e) {
      debugPrint('movePostToTrash error: $e');
      if (context.mounted) {
        _showNotice(context, 'Failed to move post to trash.', isError: true);
      }
      return false;
    }
  }

  /// Soft-deletes a reel into Recently Deleted (`deleted_at = now()`, 30-day recovery).
  static Future<bool> moveReelToTrash(
    BuildContext context, {
    required ReelItem reel,
    VoidCallback? onTrashed,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != reel.userId) {
      _showNotice(
        context,
        'Permission denied: You can only delete your own reels.',
        isError: true,
      );
      return false;
    }

    final confirmed = await _showConfirmationDialog(
      context,
      title: 'Move Reel to Trash?',
      message:
          'You can restore this reel from Your Activity -> Recently Deleted within 30 days before permanent removal.',
      confirmButtonText: 'Move to Trash',
    );
    if (confirmed != true) return false;

    try {
      await _supabase
          .from('reels')
          .update({
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', reel.id)
          .eq('user_id', currentUserId);
      HapticFeedback.mediumImpact();
      if (context.mounted) {
        _showNotice(context, 'Reel moved to Recently Deleted.');
      }
      onTrashed?.call();
      return true;
    } catch (e) {
      debugPrint('moveReelToTrash error: $e');
      if (context.mounted) {
        _showNotice(context, 'Failed to move reel to trash.', isError: true);
      }
      return false;
    }
  }

  /// Restores a soft-deleted post, reel, or story from Recently Deleted.
  static Future<bool> restoreContent({
    required String type, // 'post' | 'reel' | 'story'
    required String id,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || id.isEmpty) return false;
    try {
      if (type == 'post') {
        await _supabase
            .from('discussion_posts')
            .update({'deleted_at': null})
            .eq('id', id)
            .eq('student_id', currentUserId);
      } else if (type == 'reel') {
        await _supabase
            .from('reels')
            .update({'deleted_at': null})
            .eq('id', id)
            .eq('user_id', currentUserId);
      } else if (type == 'story') {
        await _supabase
            .from('user_stories')
            .update({'deleted_at': null})
            .eq('id', id)
            .eq('user_id', currentUserId);
      }
      return true;
    } catch (e) {
      debugPrint('restoreContent error: $e');
      return false;
    }
  }

  /// Confirms and permanently deletes a user's post plus R2 media assets.
  static Future<bool> confirmAndDeletePost(
    BuildContext context, {
    required FeedPostItem post,
    VoidCallback? onDeleted,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != post.authorId) {
      _showNotice(
        context,
        'Permission denied: You can only delete your own posts.',
        isError: true,
      );
      return false;
    }

    final confirmed = await _showConfirmationDialog(
      context,
      title: 'Delete Post Permanently?',
      message:
          'Are you sure you want to permanently delete this post? All likes, comments, reposts, and media will be removed.',
      confirmButtonText: 'Delete Permanently',
    );

    if (confirmed != true || !context.mounted) return false;

    final nav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: ZevColors.primaryBlue),
      ),
    );

    try {
      final mediaUrls = <String>[];
      if (post.imageUrl.trim().isNotEmpty) {
        mediaUrls.add(post.imageUrl.trim());
      }
      try {
        final pm = await _supabase
            .from('post_media')
            .select('media_url, thumbnail_url')
            .eq('post_id', post.id);
        for (final row in (pm as List)) {
          final mUrl = row['media_url']?.toString().trim() ?? '';
          final tUrl = row['thumbnail_url']?.toString().trim() ?? '';
          if (mUrl.isNotEmpty) mediaUrls.add(mUrl);
          if (tUrl.isNotEmpty) mediaUrls.add(tUrl);
        }
      } catch (_) {}

      await _deletePostChildRows(post.id);

      await _supabase
          .from('discussion_posts')
          .delete()
          .eq('id', post.id)
          .eq('student_id', currentUserId);

      await _cleanupMediaUrls(userId: currentUserId, urls: mediaUrls, reason: 'post_deleted');

      HapticFeedback.mediumImpact();
      nav.pop();

      if (context.mounted) {
        _showNotice(context, 'Post deleted permanently.');
      }

      onDeleted?.call();
      return true;
    } catch (e) {
      nav.pop();
      debugPrint('Post deletion error: $e');
      if (context.mounted) {
        _showNotice(
          context,
          'Failed to delete post. Please try again.',
          isError: true,
        );
      }
      return false;
    }
  }

  /// Confirms and permanently deletes a user's reel plus R2 media assets.
  static Future<bool> confirmAndDeleteReel(
    BuildContext context, {
    required ReelItem reel,
    VoidCallback? onDeleted,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != reel.userId) {
      _showNotice(
        context,
        'Permission denied: You can only delete your own reels.',
        isError: true,
      );
      return false;
    }

    final confirmed = await _showConfirmationDialog(
      context,
      title: 'Delete Reel Permanently?',
      message:
          'Are you sure you want to permanently delete this reel? All views, likes, comments, and video files will be removed.',
      confirmButtonText: 'Delete Permanently',
    );

    if (confirmed != true || !context.mounted) return false;

    final nav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: ZevColors.primaryBlue),
      ),
    );

    try {
      final mediaUrls = <String>[
        if (reel.videoUrl.trim().isNotEmpty) reel.videoUrl.trim(),
        if ((reel.thumbnailUrl ?? '').trim().isNotEmpty)
          reel.thumbnailUrl!.trim(),
      ];

      await _deleteReelChildRows(reel.id);

      await _supabase
          .from('reels')
          .delete()
          .eq('id', reel.id)
          .eq('user_id', currentUserId);

      await _cleanupMediaUrls(userId: currentUserId, urls: mediaUrls, reason: 'reel_deleted');

      HapticFeedback.mediumImpact();
      nav.pop();

      if (context.mounted) {
        _showNotice(context, 'Reel deleted permanently.');
      }

      onDeleted?.call();
      return true;
    } catch (e) {
      nav.pop();
      debugPrint('Reel deletion error: $e');
      if (context.mounted) {
        _showNotice(
          context,
          'Failed to delete reel. Please try again.',
          isError: true,
        );
      }
      return false;
    }
  }

  /// Permanently deletes an owned post, reel, or story by ID (e.g., from Recently Deleted).
  static Future<bool> permanentDeleteById({
    required String type, // 'post' | 'reel' | 'story'
    required String id,
    List<String> mediaUrls = const [],
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || id.isEmpty) return false;
    try {
      if (type == 'post') {
        await _deletePostChildRows(id);
        await _supabase
            .from('discussion_posts')
            .delete()
            .eq('id', id)
            .eq('student_id', currentUserId);
      } else if (type == 'reel') {
        await _deleteReelChildRows(id);
        await _supabase
            .from('reels')
            .delete()
            .eq('id', id)
            .eq('user_id', currentUserId);
      } else if (type == 'story') {
        await _supabase
            .from('user_stories')
            .delete()
            .eq('id', id)
            .eq('user_id', currentUserId);
      }
      await _cleanupMediaUrls(
        userId: currentUserId,
        urls: mediaUrls,
        reason: '${type}_deleted',
      );
      return true;
    } catch (e) {
      debugPrint('permanentDeleteById error: $e');
      return false;
    }
  }

  static Future<void> _deletePostChildRows(String postId) async {
    try {
      await _supabase.from('discussion_likes').delete().eq('post_id', postId);
    } catch (_) {}
    try {
      await _supabase.from('comment_pins').delete().match({
        'target_type': 'post',
        'target_id': postId,
      });
    } catch (_) {}
    try {
      await _supabase.from('discussion_comments').delete().eq('post_id', postId);
    } catch (_) {}
    try {
      await _supabase.from('post_reposts').delete().eq('post_id', postId);
    } catch (_) {}
    try {
      await _supabase.from('discussion_bookmarks').delete().eq('post_id', postId);
    } catch (_) {}
    try {
      await _supabase.from('post_hashtags').delete().eq('post_id', postId);
    } catch (_) {}
  }

  static Future<void> _deleteReelChildRows(String reelId) async {
    try {
      await _supabase.from('reel_likes').delete().eq('reel_id', reelId);
    } catch (_) {}
    try {
      await _supabase.from('comment_pins').delete().match({
        'target_type': 'reel',
        'target_id': reelId,
      });
    } catch (_) {}
    try {
      await _supabase.from('reel_comments').delete().eq('reel_id', reelId);
    } catch (_) {}
    try {
      await _supabase.from('reel_bookmarks').delete().eq('reel_id', reelId);
    } catch (_) {}
    try {
      await _supabase.from('reel_views').delete().eq('reel_id', reelId);
    } catch (_) {}
    try {
      await _supabase.from('reel_hashtags').delete().eq('reel_id', reelId);
    } catch (_) {}
  }

  static Future<void> _cleanupMediaUrls({
    required String userId,
    required List<String> urls,
    required String reason,
  }) async {
    final cleanUrls =
        urls.map((u) => u.trim()).where((u) => u.isNotEmpty).toSet().toList();
    if (cleanUrls.isEmpty) return;

    final deleted = await CloudflareStorageService.instance.deleteUrls(cleanUrls);
    if (!deleted) {
      for (final url in cleanUrls) {
        final uri = Uri.tryParse(url);
        final rawPath = uri?.path ?? '';
        final key = rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
        if (!key.startsWith('zev/')) continue;
        try {
          await _supabase.from('media_deletion_queue').insert({
            'user_id': userId,
            'r2_key': key,
            'media_url': url,
            'reason': reason,
            'status': 'pending',
          });
        } catch (_) {}
      }
    }
  }

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
              'Cancel',
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
