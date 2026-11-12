import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/profile/screens/profile_screen.dart';
import '../services/notification_service.dart';
import '../services/social_graph_service.dart';
import '../theme/zev_theme.dart';
import '../utils/rich_text_helper.dart';
import '../utils/text_direction_helper.dart';
import '../utils/time_ago.dart';
import 'zev_cached_image.dart';

class _CommentItem {
  final String id;
  final String authorId;
  final String? parentCommentId;
  final String text;
  final DateTime createdAt;
  final DateTime? editedAt;
  final int likesCount;
  final bool isPinned;
  final bool isLikedByMe;
  final String username;
  final String avatarUrl;
  final bool isVerified;

  const _CommentItem({
    required this.id,
    required this.authorId,
    this.parentCommentId,
    required this.text,
    required this.createdAt,
    this.editedAt,
    this.likesCount = 0,
    this.isPinned = false,
    this.isLikedByMe = false,
    required this.username,
    this.avatarUrl = '',
    this.isVerified = false,
  });

  _CommentItem copyWith({
    String? id,
    String? text,
    DateTime? editedAt,
    int? likesCount,
    bool? isPinned,
    bool? isLikedByMe,
  }) {
    return _CommentItem(
      id: id ?? this.id,
      authorId: authorId,
      parentCommentId: parentCommentId,
      text: text ?? this.text,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      likesCount: likesCount ?? this.likesCount,
      isPinned: isPinned ?? this.isPinned,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      username: username,
      avatarUrl: avatarUrl,
      isVerified: isVerified,
    );
  }
}

/// Unified Light Clearmorphic Comments Sheet for both Posts and Reels.
/// Supports nested replies, likes, author pinning, editing, RLS-safe deletion,
/// blocked-user filtering, clickable @mentions, and reporting.
class CommentsThreadSheet extends StatefulWidget {
  final String targetType; // 'post' | 'reel'
  final String targetId;
  final String targetAuthorUsername;
  final String? targetAuthorId;
  final VoidCallback? onCommentAdded;
  final VoidCallback? onCommentDeleted;

  const CommentsThreadSheet({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.targetAuthorUsername,
    this.targetAuthorId,
    this.onCommentAdded,
    this.onCommentDeleted,
  });

  @override
  State<CommentsThreadSheet> createState() => _CommentsThreadSheetState();
}

class _CommentsThreadSheetState extends State<CommentsThreadSheet> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  List<_CommentItem> _allComments = [];
  String _myAvatarUrl = '';
  String _myUsername = 'you';
  bool _myVerified = false;
  String? _ownerId;

  // Reply / Edit state
  String? _replyToParentId;
  String? _replyToUsername;
  _CommentItem? _editingComment;

  // Expanded reply threads
  final Set<String> _expandedThreadIds = {};

  String get _commentsTable =>
      widget.targetType == 'reel' ? 'reel_comments' : 'discussion_comments';
  String get _parentTable =>
      widget.targetType == 'reel' ? 'reels' : 'discussion_posts';
  String get _fkCol => widget.targetType == 'reel' ? 'reel_id' : 'post_id';
  String get _authorCol => widget.targetType == 'reel' ? 'user_id' : 'student_id';

  @override
  void initState() {
    super.initState();
    _ownerId = widget.targetAuthorId;
    _initData();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _inputFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    await Future.wait([
      _loadMyProfile(),
      _resolveOwnerIdIfNeeded(),
      _fetchComments(),
    ]);
  }

  Future<void> _loadMyProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await _supabase
          .from('profiles')
          .select('username, avatar_url, is_verified')
          .eq('id', user.id)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _myAvatarUrl = (res['avatar_url'] ?? '').toString();
          _myUsername = (res['username'] ?? 'you').toString();
          _myVerified = res['is_verified'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _resolveOwnerIdIfNeeded() async {
    if (_ownerId != null && _ownerId!.isNotEmpty) return;
    try {
      final res = await _supabase
          .from(_parentTable)
          .select(_authorCol)
          .eq('id', widget.targetId)
          .maybeSingle();
      final resolved = res?[_authorCol]?.toString();
      if (resolved != null && resolved.isNotEmpty && mounted) {
        setState(() => _ownerId = resolved);
      }
    } catch (_) {}
  }

  Future<void> _fetchComments() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    try {
      final results = await Future.wait<dynamic>([
        SocialGraphService.instance.fetchSafetyFilters(),
        _supabase
            .from(_commentsTable)
            .select(
              'id, $_fkCol, $_authorCol, parent_comment_id, comment_text, likes_count, is_pinned, edited_at, created_at',
            )
            .eq(_fkCol, widget.targetId)
            .isFilter('deleted_at', null)
            .order('is_pinned', ascending: false)
            .order('created_at', ascending: true),
      ]);

      final filters = results[0] as UserSafetyFilters;
      final rawList = List<Map<String, dynamic>>.from(results[1] as List);

      final visibleRows = rawList.where((row) {
        final aId = row[_authorCol]?.toString() ?? '';
        return !filters.blockedUserIds.contains(aId);
      }).toList();

      if (visibleRows.isEmpty) {
        if (mounted) {
          setState(() {
            _allComments = [];
            _isLoading = false;
          });
        }
        return;
      }

      final authorIds = visibleRows
          .map((c) => c[_authorCol]?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final commentIds = visibleRows
          .map((c) => c['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      final profilesMap = <String, Map<String, dynamic>>{};
      if (authorIds.isNotEmpty) {
        final profs = await _supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .inFilter('id', authorIds);
        for (final p in (profs as List)) {
          final m = Map<String, dynamic>.from(p as Map);
          profilesMap[m['id'].toString()] = m;
        }
      }

      final likedIds = <String>{};
      if (currentUserId != null && commentIds.isNotEmpty) {
        try {
          final likesRes = await _supabase
              .from('comment_likes')
              .select('comment_id')
              .eq('comment_type', widget.targetType)
              .eq('user_id', currentUserId)
              .inFilter('comment_id', commentIds);
          for (final l in (likesRes as List)) {
            final cid = l['comment_id']?.toString() ?? '';
            if (cid.isNotEmpty) likedIds.add(cid);
          }
        } catch (_) {}
      }

      final parsed = visibleRows.map((c) {
        final id = c['id'].toString();
        final aId = c[_authorCol]?.toString() ?? '';
        final profile = profilesMap[aId] ?? <String, dynamic>{};
        final fn = (profile['first_name'] ?? '').toString().trim();
        final ln = (profile['last_name'] ?? '').toString().trim();
        final full = "$fn $ln".trim();
        final uname = (profile['username'] ?? '').toString().trim();

        return _CommentItem(
          id: id,
          authorId: aId,
          parentCommentId: c['parent_comment_id']?.toString(),
          text: (c['comment_text'] ?? '').toString(),
          createdAt:
              DateTime.tryParse(c['created_at']?.toString() ?? '') ??
              DateTime.now(),
          editedAt: DateTime.tryParse(c['edited_at']?.toString() ?? ''),
          likesCount: (c['likes_count'] as int?) ?? 0,
          isPinned: c['is_pinned'] == true,
          isLikedByMe: likedIds.contains(id),
          username: uname.isNotEmpty ? uname : (full.isNotEmpty ? full : 'user'),
          avatarUrl: (profile['avatar_url'] ?? '').toString(),
          isVerified: profile['is_verified'] == true,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _allComments = parsed;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[CommentsThreadSheet] fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startReply(_CommentItem target) {
    HapticFeedback.selectionClick();
    final rootParentId = target.parentCommentId ?? target.id;
    setState(() {
      _editingComment = null;
      _replyToParentId = rootParentId;
      _replyToUsername = target.username;
      _expandedThreadIds.add(rootParentId);
    });
    if (!_commentCtrl.text.startsWith('@${target.username} ')) {
      _commentCtrl.text = '@${target.username} ';
      _commentCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _commentCtrl.text.length),
      );
    }
    _inputFocus.requestFocus();
  }

  void _startEdit(_CommentItem comment) {
    HapticFeedback.selectionClick();
    setState(() {
      _replyToParentId = null;
      _replyToUsername = null;
      _editingComment = comment;
    });
    _commentCtrl.text = comment.text;
    _commentCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: comment.text.length),
    );
    _inputFocus.requestFocus();
  }

  void _cancelReplyOrEdit() {
    setState(() {
      _replyToParentId = null;
      _replyToUsername = null;
      _editingComment = null;
    });
    _commentCtrl.clear();
  }

  Future<void> _submitInput() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _isSubmitting) return;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showNotice('Please sign in to comment.', isError: true);
      return;
    }

    HapticFeedback.lightImpact();

    if (_editingComment != null) {
      await _commitEdit(_editingComment!, text, user.id);
      return;
    }

    final parentId = _replyToParentId;
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = _CommentItem(
      id: tempId,
      authorId: user.id,
      parentCommentId: parentId,
      text: text,
      createdAt: DateTime.now(),
      username: _myUsername,
      avatarUrl: _myAvatarUrl,
      isVerified: _myVerified,
    );

    setState(() {
      _isSubmitting = true;
      _allComments = [..._allComments, optimistic];
      if (parentId != null) {
        _expandedThreadIds.add(parentId);
      }
      _replyToParentId = null;
      _replyToUsername = null;
    });
    _commentCtrl.clear();

    try {
      final inserted = await _supabase
          .from(_commentsTable)
          .insert({
            _fkCol: widget.targetId,
            _authorCol: user.id,
            'parent_comment_id': ?parentId,
            'comment_text': text,
          })
          .select(
            'id, parent_comment_id, comment_text, likes_count, is_pinned, edited_at, created_at',
          )
          .single();

      if (mounted) {
        setState(() {
          _allComments = _allComments.map((c) {
            if (c.id == tempId) {
              return c.copyWith(id: inserted['id'].toString());
            }
            return c;
          }).toList();
        });
      }

      widget.onCommentAdded?.call();

      final snippet = text.length > 80 ? '${text.substring(0, 80)}...' : text;
      final isReel = widget.targetType == 'reel';
      String? pushRecipientId;
      if (parentId != null) {
        for (final c in _allComments) {
          if (c.id == parentId && c.authorId != user.id) {
            pushRecipientId = c.authorId;
            break;
          }
        }
      }
      pushRecipientId ??=
          (_ownerId != null && _ownerId != user.id) ? _ownerId : null;

      if (pushRecipientId != null && pushRecipientId.isNotEmpty) {
        unawaited(
          NotificationService().dispatchPushNotification(
            recipientUserId: pushRecipientId,
            title: parentId != null ? 'New Reply' : 'New Comment',
            body: '@$_myUsername commented: "$snippet"',
            notificationType: isReel
                ? 'reel_comment'
                : (parentId != null ? 'comment_reply' : 'comment'),
            deepLink: isReel
                ? '/reel/${widget.targetId}'
                : '/post/${widget.targetId}',
          ),
        );
      }

      if (parentId == null && _scrollCtrl.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(
              _scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('[CommentsThreadSheet] submit error: $e');
      if (mounted) {
        setState(() {
          _allComments = _allComments.where((c) => c.id != tempId).toList();
        });
        _showNotice("Couldn't post comment. Please retry.", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _commitEdit(
    _CommentItem target,
    String newText,
    String userId,
  ) async {
    setState(() => _isSubmitting = true);
    final now = DateTime.now().toUtc();
    final previous = _allComments;

    setState(() {
      _allComments = _allComments.map((c) {
        if (c.id == target.id) {
          return c.copyWith(text: newText, editedAt: now);
        }
        return c;
      }).toList();
      _editingComment = null;
    });
    _commentCtrl.clear();

    try {
      await _supabase
          .from(_commentsTable)
          .update({
            'comment_text': newText,
            'edited_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          })
          .eq('id', target.id)
          .eq(_authorCol, userId);
      _showNotice('Comment updated.');
    } catch (e) {
      debugPrint('[CommentsThreadSheet] edit error: $e');
      if (mounted) {
        setState(() => _allComments = previous);
        _showNotice('Failed to update comment.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _toggleCommentLike(_CommentItem comment) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showNotice('Please sign in to like comments.');
      return;
    }
    if (comment.id.startsWith('temp_')) return;

    HapticFeedback.selectionClick();
    final nextLiked = !comment.isLikedByMe;
    final nextCount = nextLiked
        ? comment.likesCount + 1
        : (comment.likesCount > 0 ? comment.likesCount - 1 : 0);

    setState(() {
      _allComments = _allComments.map((c) {
        if (c.id == comment.id) {
          return c.copyWith(isLikedByMe: nextLiked, likesCount: nextCount);
        }
        return c;
      }).toList();
    });

    try {
      if (nextLiked) {
        await _supabase.from('comment_likes').insert({
          'comment_id': comment.id,
          'comment_type': widget.targetType,
          'user_id': user.id,
        });
      } else {
        await _supabase
            .from('comment_likes')
            .delete()
            .eq('comment_id', comment.id)
            .eq('comment_type', widget.targetType)
            .eq('user_id', user.id);
      }
    } catch (e) {
      debugPrint('[CommentsThreadSheet] like error: $e');
      if (mounted) {
        setState(() {
          _allComments = _allComments.map((c) {
            if (c.id == comment.id) {
              return c.copyWith(
                isLikedByMe: comment.isLikedByMe,
                likesCount: comment.likesCount,
              );
            }
            return c;
          }).toList();
        });
      }
    }
  }

  Future<void> _togglePinComment(_CommentItem comment) async {
    final user = _supabase.auth.currentUser;
    if (user == null || user.id != _ownerId) return;
    if (comment.id.startsWith('temp_')) return;

    HapticFeedback.mediumImpact();
    final willPin = !comment.isPinned;
    final previous = _allComments;

    setState(() {
      _allComments = _allComments.map((c) {
        if (c.id == comment.id) {
          return c.copyWith(isPinned: willPin);
        }
        if (willPin && c.isPinned) {
          return c.copyWith(isPinned: false);
        }
        return c;
      }).toList();
    });

    try {
      // Clear any previous pin on this post/reel so one pinned comment stays featured cleanly.
      await _supabase
          .from('comment_pins')
          .delete()
          .eq('target_type', widget.targetType)
          .eq('target_id', widget.targetId);

      if (willPin) {
        await _supabase.from('comment_pins').insert({
          'target_type': widget.targetType,
          'target_id': widget.targetId,
          'comment_id': comment.id,
          'pinned_by': user.id,
        });
        _showNotice('Comment pinned.');
      } else {
        _showNotice('Comment unpinned.');
      }
    } catch (e) {
      debugPrint('[CommentsThreadSheet] pin error: $e');
      if (mounted) {
        setState(() => _allComments = previous);
        _showNotice('Could not update pinned comment.', isError: true);
      }
    }
  }

  Future<void> _deleteComment(_CommentItem comment) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    if (comment.id.startsWith('temp_')) return;

    final previous = _allComments;
    setState(() {
      _allComments = _allComments
          .where((c) => c.id != comment.id && c.parentCommentId != comment.id)
          .toList();
    });

    try {
      if (comment.isPinned && user.id == _ownerId) {
        try {
          await _supabase
              .from('comment_pins')
              .delete()
              .eq('target_type', widget.targetType)
              .eq('target_id', widget.targetId)
              .eq('comment_id', comment.id);
        } catch (_) {}
      }

      // RLS allows DELETE for both comment author and post/reel owner (and cascades replies + updates triggers).
      await _supabase.from(_commentsTable).delete().eq('id', comment.id);
      HapticFeedback.mediumImpact();
      widget.onCommentDeleted?.call();
      _showNotice('Comment deleted.');
    } catch (e) {
      debugPrint('[CommentsThreadSheet] delete error: $e');
      if (mounted) {
        setState(() => _allComments = previous);
        _showNotice('Could not delete comment.', isError: true);
      }
    }
  }

  void _showCommentActions(_CommentItem comment) {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || comment.id.startsWith('temp_')) return;

    final isAuthor = currentUserId == comment.authorId;
    final isOwner = currentUserId == _ownerId;
    final isTopLevel = comment.parentCommentId == null;

    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            _actionTile(
              icon: Icons.reply_rounded,
              label: 'Reply',
              color: ZevColors.deepNavy,
              onTap: () {
                Navigator.pop(ctx);
                _startReply(comment);
              },
            ),
            if (isOwner && isTopLevel) ...[
              const SizedBox(height: 8),
              _actionTile(
                icon: comment.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
                label: comment.isPinned ? 'Unpin Comment' : 'Pin Comment',
                color: ZevColors.secondaryBlue,
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePinComment(comment);
                },
              ),
            ],
            if (isAuthor) ...[
              const SizedBox(height: 8),
              _actionTile(
                icon: Icons.edit_outlined,
                label: 'Edit Comment',
                color: ZevColors.deepNavy,
                onTap: () {
                  Navigator.pop(ctx);
                  _startEdit(comment);
                },
              ),
            ],
            if (isAuthor || isOwner) ...[
              const SizedBox(height: 8),
              _actionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete Comment',
                color: ZevColors.errorRed,
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteComment(comment);
                },
              ),
            ],
            if (!isAuthor) ...[
              const SizedBox(height: 8),
              _actionTile(
                icon: Icons.flag_outlined,
                label: 'Report Comment',
                color: ZevColors.errorRed,
                onTap: () {
                  Navigator.pop(ctx);
                  SocialGraphService.instance.showReportSheet(
                    context,
                    targetType: 'comment',
                    targetId: comment.id,
                    reportedUserId: comment.authorId,
                    targetLabel: 'Comment',
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotice(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? ZevColors.errorRed : ZevColors.deepNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    // Organize parents (pinned first, chronological) and child replies map
    final parentIds = <String>{};
    final parents = <_CommentItem>[];
    for (final c in _allComments) {
      if (c.parentCommentId == null) {
        parentIds.add(c.id);
        parents.add(c);
      }
    }

    final repliesByParent = <String, List<_CommentItem>>{};
    for (final c in _allComments) {
      final pId = c.parentCommentId;
      if (pId == null) continue;
      if (parentIds.contains(pId)) {
        repliesByParent.putIfAbsent(pId, () => []).add(c);
      } else {
        // Fallback so orphan non-deleted replies remain visible
        parents.add(c);
      }
    }

    parents.sort((a, b) {
      if (a.isPinned != b.isPinned) return b.isPinned ? 1 : -1;
      return a.createdAt.compareTo(b.createdAt);
    });

    return Container(
      height: mediaQuery.size.height * 0.76,
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
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 28),
                Text(
                  _allComments.isEmpty
                      ? 'Comments'
                      : 'Comments (${_allComments.length})',
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                    letterSpacing: -0.3,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 22,
                    color: ZevColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.white),

          // Comments Thread List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: ZevColors.primaryBlue,
                    ),
                  )
                : parents.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 46,
                              color: ZevColors.textMuted.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No comments yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Start the conversation.',
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
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                        itemCount: parents.length,
                        itemBuilder: (context, index) {
                          final parent = parents[index];
                          final replies =
                              repliesByParent[parent.id] ?? const [];
                          final isExpanded =
                              _expandedThreadIds.contains(parent.id) ||
                              replies.length <= 1;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCommentCard(parent, isReply: false),
                              if (replies.isNotEmpty) ...[
                                if (replies.length > 1)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 48,
                                      top: 4,
                                      bottom: 2,
                                    ),
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          if (_expandedThreadIds.contains(
                                            parent.id,
                                          )) {
                                            _expandedThreadIds.remove(
                                              parent.id,
                                            );
                                          } else {
                                            _expandedThreadIds.add(parent.id);
                                          }
                                        });
                                      },
                                      child: Text(
                                        isExpanded
                                            ? 'Hide replies'
                                            : 'View ${replies.length} replies',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: ZevColors.secondaryBlue,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (isExpanded)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 34),
                                    child: Column(
                                      children: replies
                                          .map(
                                            (r) => _buildCommentCard(
                                              r,
                                              isReply: true,
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                              ],
                            ],
                          );
                        },
                      ),
          ),

          // Reply / Edit Banner
          if (_replyToUsername != null || _editingComment != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: ZevColors.primaryBlue.withValues(alpha: 0.1),
                border: const Border(
                  top: BorderSide(color: Colors.white, width: 1.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _editingComment != null
                        ? Icons.edit_rounded
                        : Icons.reply_rounded,
                    size: 16,
                    color: ZevColors.secondaryBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _editingComment != null
                          ? 'Editing comment'
                          : 'Replying to @$_replyToUsername',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelReplyOrEdit,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: ZevColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),

          // Bottom Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
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
                _avatarWidget(_myAvatarUrl, 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _commentCtrl,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: ZevColors.deepNavy,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitInput(),
                      decoration: InputDecoration(
                        hintText: _editingComment != null
                            ? 'Update your comment...'
                            : _replyToUsername != null
                                ? 'Reply to @$_replyToUsername...'
                                : 'Add a comment for @${widget.targetAuthorUsername}...',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: ZevColors.textMuted,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isSubmitting ? null : _submitInput,
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
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.38),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _editingComment != null
                                  ? Icons.check_rounded
                                  : Icons.arrow_upward_rounded,
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

  Widget _avatarWidget(String url, double size) {
    if (url.isNotEmpty) {
      return ZevCachedImage.avatar(imageUrl: url, size: size);
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFF1F5F9),
      ),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.56,
        color: ZevColors.textMuted,
      ),
    );
  }

  Widget _buildCommentCard(_CommentItem c, {required bool isReply}) {
    final isRtl = TextDirectionHelper.isRtl(c.text);
    final timeStr = TimeAgo.format(c.createdAt);
    final avatarSize = isReply ? 26.0 : 34.0;

    return GestureDetector(
      onLongPress: () => _showCommentActions(c),
      child: Container(
        margin: EdgeInsets.symmetric(vertical: isReply ? 3 : 4),
        padding: EdgeInsets.symmetric(
          horizontal: isReply ? 12 : 14,
          vertical: isReply ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: c.isPinned ? const Color(0xFFF0FAFF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: c.isPinned
                ? ZevColors.primaryBlue.withValues(alpha: 0.45)
                : Colors.white,
            width: 1.2,
          ),
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
            GestureDetector(
              onTap: () {
                if (c.authorId.isNotEmpty) {
                  ProfileScreen.open(context, userId: c.authorId);
                }
              },
              child: _avatarWidget(c.avatarUrl, avatarSize),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.push_pin_rounded,
                            size: 12,
                            color: ZevColors.secondaryBlue,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Pinned by author',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: ZevColors.secondaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: () {
                            if (c.authorId.isNotEmpty) {
                              ProfileScreen.open(context, userId: c.authorId);
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  c.username,
                                  style: TextStyle(
                                    fontSize: isReply ? 12.5 : 13,
                                    fontWeight: FontWeight.w800,
                                    color: ZevColors.deepNavy,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (c.isVerified) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 13,
                                  color: ZevColors.primaryBlue,
                                ),
                              ],
                              if (c.authorId == _ownerId) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ZevColors.primaryBlue.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text(
                                    'Author',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: ZevColors.secondaryBlue,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        c.editedAt != null ? '$timeStr • edited' : timeStr,
                        style: const TextStyle(
                          fontSize: 11,
                          color: ZevColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: double.infinity,
                    child: ZevRichText(
                      text: c.text,
                      textDirection:
                          isRtl ? TextDirection.rtl : TextDirection.ltr,
                      textAlign: isRtl ? TextAlign.right : TextAlign.left,
                      style: TextStyle(
                        fontSize: isReply ? 12.8 : 13.5,
                        color: ZevColors.deepNavy,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _startReply(c),
                        child: const Text(
                          'Reply',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: ZevColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      GestureDetector(
                        onTap: () => _showCommentActions(c),
                        child: const Icon(
                          Icons.more_horiz_rounded,
                          size: 16,
                          color: ZevColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _toggleCommentLike(c),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  children: [
                    Icon(
                      c.isLikedByMe
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 17,
                      color: c.isLikedByMe
                          ? Colors.redAccent
                          : ZevColors.textMuted,
                    ),
                    if (c.likesCount > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${c.likesCount}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: c.isLikedByMe
                              ? Colors.redAccent
                              : ZevColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
