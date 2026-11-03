import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/notification_service.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../../../core/utils/time_ago.dart';

/// Serene, Instagram-Grade Comments Sheet for ZEV Reels.
class ReelCommentsSheet extends StatefulWidget {
  final String reelId;
  final String reelAuthorUsername;
  final VoidCallback? onCommentAdded;

  const ReelCommentsSheet({
    super.key,
    required this.reelId,
    required this.reelAuthorUsername,
    this.onCommentAdded,
  });

  static void show(
    BuildContext context, {
    required String reelId,
    required String reelAuthorUsername,
    VoidCallback? onCommentAdded,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReelCommentsSheet(
        reelId: reelId,
        reelAuthorUsername: reelAuthorUsername,
        onCommentAdded: onCommentAdded,
      ),
    );
  }

  @override
  State<ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<ReelCommentsSheet> {
  final supabase = Supabase.instance.client;
  final TextEditingController _commentCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
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
          .from('reel_comments')
          .select('id, user_id, comment, created_at')
          .eq('reel_id', widget.reelId)
          .order('created_at', ascending: true);

      final rawList = List<Map<String, dynamic>>.from(res as List);
      if (rawList.isEmpty) {
        if (mounted) setState(() => _comments = []);
        return;
      }

      final userIds =
          rawList.map((c) => c['user_id']?.toString() ?? '').toSet().toList();

      Map<String, Map<String, dynamic>> profilesMap = {};
      if (userIds.isNotEmpty) {
        final profs = await supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .inFilter('id', userIds);

        for (var p in (profs as List)) {
          profilesMap[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }

      final formatted = rawList.map((c) {
        final uId = c['user_id']?.toString() ?? '';
        final profile = profilesMap[uId] ?? {};
        final fn = profile['first_name'] ?? '';
        final ln = profile['last_name'] ?? '';
        final full = "$fn $ln".trim();

        return {
          'id': c['id'].toString(),
          'user_id': uId,
          'content': c['comment'] ?? '',
          'created_at': DateTime.tryParse(c['created_at']?.toString() ?? '') ??
              DateTime.now(),
          'username': profile['username'] ?? (full.isNotEmpty ? full : 'user'),
          'avatar_url': profile['avatar_url'] ?? '',
          'is_verified': profile['is_verified'] == true,
        };
      }).toList();

      if (mounted) {
        setState(() => _comments = formatted);
      }
    } catch (e) {
      debugPrint("Fetch reel comments error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to comment.")),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isSubmitting = true);

    // Optimistic item
    final optimisticItem = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'user_id': user.id,
      'content': text,
      'created_at': DateTime.now(),
      'username': 'you',
      'avatar_url': _myAvatarUrl,
      'is_verified': false,
    };

    setState(() {
      _comments.add(optimisticItem);
    });
    _commentCtrl.clear();

    try {
      await supabase.from('reel_comments').insert({
        'reel_id': widget.reelId,
        'user_id': user.id,
        'comment': text,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Dispatch notification to reel author
      try {
        final reelRes = await supabase
            .from('reels')
            .select('user_id')
            .eq('id', widget.reelId)
            .maybeSingle();
        final authorId = reelRes?['user_id']?.toString() ?? '';
        if (authorId.isNotEmpty && authorId != user.id) {
          unawaited(NotificationService().sendNotificationToUser(
            targetUserId: authorId,
            title: "Reel Comment",
            message: "commented on your reel: \"$text\"",
            notificationType: "comment",
            linkUrl: widget.reelId,
            senderId: user.id,
          ));
        }
      } catch (_) {}

      // Increment comments_count on reels
      try {
        await supabase.rpc('increment_reel_comments', params: {'reel_id': widget.reelId});
      } catch (_) {}

      widget.onCommentAdded?.call();
      _fetchComments();
    } catch (e) {
      debugPrint("Submit reel comment error: $e");
      if (mounted) {
        setState(() => _comments.remove(optimisticItem));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't post comment. Please retry.")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.70,
      decoration: const BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 38,
            height: 4.5,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 24),
                const Text(
                  "Comments",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
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
          const Divider(height: 16, thickness: 0.8, color: ZevColors.border),

          // Comments List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ZevColors.primaryBlue,
                    ),
                  )
                : _comments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 44,
                              color: ZevColors.textMuted,
                            ),
                            SizedBox(height: 12),
                            Text(
                              "No comments yet",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              "Start the conversation.",
                              style: TextStyle(
                                fontSize: 12.5,
                                color: ZevColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        physics: const BouncingScrollPhysics(),
                        itemCount: _comments.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final c = _comments[index];
                          final content = c['content'] as String;
                          final username = c['username'] as String;
                          final avatar = c['avatar_url'] as String;
                          final isVerified = c['is_verified'] == true;
                          final timeStr = TimeAgo.format(c['created_at']);
                          final isRtl = TextDirectionHelper.isRtl(content);

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 17,
                                backgroundColor: ZevColors.softSurface,
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          username,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: ZevColors.deepNavy,
                                          ),
                                        ),
                                        if (isVerified) ...[
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.verified_rounded,
                                            size: 13,
                                            color: ZevColors.primaryBlue,
                                          ),
                                        ],
                                        const SizedBox(width: 8),
                                        Text(
                                          timeStr,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: ZevColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      content,
                                      textDirection: isRtl
                                          ? TextDirection.rtl
                                          : TextDirection.ltr,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: ZevColors.deepNavy,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
          ),

          // Quick Comment Input Field
          Container(
            padding: EdgeInsets.only(
              left: 14,
              right: 14,
              top: 8,
              bottom: bottomInset > 0 ? bottomInset + 8 : 16,
            ),
            decoration: const BoxDecoration(
              color: ZevColors.white,
              border: Border(
                top: BorderSide(color: ZevColors.border, width: 0.8),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: ZevColors.softSurface,
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
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: ZevColors.border, width: 1.0),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _commentCtrl,
                      minLines: 1,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: ZevColors.deepNavy,
                      ),
                      decoration: const InputDecoration(
                        hintText: "Add a comment...",
                        hintStyle: TextStyle(
                          fontSize: 13.5,
                          color: ZevColors.textMuted,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (_) => _submitComment(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSubmitting ? null : _submitComment,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ZevColors.primaryBlue,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: ZevColors.primaryBlue,
                          size: 22,
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
