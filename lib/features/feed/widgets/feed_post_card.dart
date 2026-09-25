import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/utils/zev_alert.dart';
import '../../../core/widgets/auth_required_modal.dart';
import '../../../core/widgets/fast_cached_image.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../screens/user_profile_screen.dart';
import 'feed_comments_sheet.dart';

class FeedPostItem {
  final String id;
  final String studentId;
  final String rawTitle;
  final String content;
  final String? imageUrl;
  final String createdAt;
  String authorName;
  String authorAvatar;
  int likesCount;
  bool isLikedByMe;
  bool isSavedByMe;
  int commentsCount;

  String moodTag;
  String cleanTitle;

  FeedPostItem({
    required this.id,
    required this.studentId,
    required this.rawTitle,
    required this.content,
    this.imageUrl,
    required this.createdAt,
    this.authorName = "ZEV Member",
    this.authorAvatar = "",
    this.likesCount = 0,
    this.isLikedByMe = false,
    this.isSavedByMe = false,
    this.commentsCount = 0,
  }) : moodTag = _extractMood(rawTitle),
       cleanTitle = _extractCleanTitle(rawTitle);

  static String _extractMood(String title) {
    if (title.startsWith('[') && title.contains(']')) {
      int endIndex = title.indexOf(']');
      return title.substring(1, endIndex);
    }
    return "📢 Post";
  }

  static String _extractCleanTitle(String title) {
    if (title.startsWith('[') && title.contains(']')) {
      int endIndex = title.indexOf(']');
      return title.substring(endIndex + 1).trim();
    }
    return title;
  }

  factory FeedPostItem.fromJson(
    Map<String, dynamic> json, {
    String name = "ZEV Member",
    String avatar = "",
    int likes = 0,
    bool liked = false,
    bool saved = false,
    int comments = 0,
  }) {
    return FeedPostItem(
      id: json['id']?.toString() ?? '',
      studentId: json['student_id']?.toString() ?? '',
      rawTitle: json['title'] ?? '',
      content: json['content'] ?? '',
      imageUrl: json['image_url'],
      createdAt: json['created_at'] ?? '',
      authorName: name,
      authorAvatar: avatar,
      likesCount: likes,
      isLikedByMe: liked,
      isSavedByMe: saved,
      commentsCount: comments,
    );
  }
}

/// Modular, self-contained Feed Post Card widget.
/// Manages its own local like state to avoid rebuilding the entire feed list on interaction.
class FeedPostCard extends StatefulWidget {
  final FeedPostItem post;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onCommentsUpdated;

  const FeedPostCard({
    super.key,
    required this.post,
    this.onDelete,
    this.onEdit,
    this.onCommentsUpdated,
  });

  @override
  State<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<FeedPostCard> {
  final supabase = Supabase.instance.client;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  late bool isLiked;
  late bool isSaved;
  late int likesCount;
  bool isReposted = false;
  int repostsCount = 0;

  @override
  void initState() {
    super.initState();
    isLiked = widget.post.isLikedByMe;
    isSaved = widget.post.isSavedByMe;
    likesCount = widget.post.likesCount;
    _checkRepostState();
  }

  Future<void> _checkRepostState() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('post_reposts')
          .select('id')
          .eq('post_id', widget.post.id)
          .eq('user_id', user.id)
          .maybeSingle();

      final countRes = await supabase
          .from('post_reposts')
          .select('id')
          .eq('post_id', widget.post.id);

      if (mounted) {
        setState(() {
          isReposted = res != null;
          repostsCount = (countRes as List).length;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleRepost() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      AuthRequiredModal.show(context, actionName: "repost this post");
      return;
    }

    final willRepost = !isReposted;
    setState(() {
      isReposted = willRepost;
      repostsCount += willRepost ? 1 : -1;
      if (repostsCount < 0) repostsCount = 0;
    });

    try {
      if (willRepost) {
        await supabase.from('post_reposts').insert({
          'post_id': widget.post.id,
          'user_id': user.id,
          'created_at': DateTime.now().toIso8601String(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Post reposted to your profile & followers! 🔁"),
              backgroundColor: primaryPink,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        await supabase
            .from('post_reposts')
            .delete()
            .eq('post_id', widget.post.id)
            .eq('user_id', user.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Repost removed."),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isReposted = !willRepost;
          repostsCount += willRepost ? -1 : 1;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Repost error: $e")));
      }
    }
  }

  @override
  void didUpdateWidget(covariant FeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.isLikedByMe != widget.post.isLikedByMe ||
        oldWidget.post.isSavedByMe != widget.post.isSavedByMe ||
        oldWidget.post.likesCount != widget.post.likesCount) {
      isLiked = widget.post.isLikedByMe;
      isSaved = widget.post.isSavedByMe;
      likesCount = widget.post.likesCount;
    }
  }

  Future<void> _toggleBookmark() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      AuthRequiredModal.show(context, actionName: "save posts");
      return;
    }

    final willSave = !isSaved;
    setState(() {
      isSaved = willSave;
      widget.post.isSavedByMe = isSaved;
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              willSave
                  ? Icons.bookmark_added_rounded
                  : Icons.bookmark_remove_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              willSave
                  ? "Post saved to your bookmarks 🔖"
                  : "Post removed from bookmarks",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: willSave
            ? const Color(0xFF1E293B)
            : const Color(0xFF475569),
      ),
    );

    try {
      if (willSave) {
        await supabase.from("discussion_bookmarks").insert({
          "post_id": widget.post.id,
          "user_id": user.id,
        });
      } else {
        await supabase
            .from("discussion_bookmarks")
            .delete()
            .eq("post_id", widget.post.id)
            .eq("user_id", user.id);
      }
    } catch (e) {
      debugPrint("Error toggling bookmark: $e");
    }
  }

  Future<void> _toggleLike() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      AuthRequiredModal.show(context, actionName: "like posts");
      return;
    }

    final willLike = !isLiked;
    setState(() {
      isLiked = willLike;
      likesCount += willLike ? 1 : -1;
      if (likesCount < 0) likesCount = 0;
      widget.post.isLikedByMe = isLiked;
      widget.post.likesCount = likesCount;
    });

    try {
      if (!willLike) {
        await supabase
            .from("discussion_likes")
            .delete()
            .eq("post_id", widget.post.id)
            .eq("student_id", user.id);
      } else {
        await supabase.from("discussion_likes").insert({
          "post_id": widget.post.id,
          "student_id": user.id,
        });

        if (widget.post.studentId != user.id) {
          try {
            final senderProfile = await supabase
                .from("profiles")
                .select("first_name, last_name")
                .eq("id", user.id)
                .maybeSingle();
            final String senderName = (senderProfile != null)
                ? "${senderProfile['first_name'] ?? 'Someone'} ${senderProfile['last_name'] ?? ''}"
                      .trim()
                : 'Someone';

            await supabase.from("user_notifications").insert({
              'user_id': widget.post.studentId,
              'sender_id': user.id,
              'title': "Liked your post ❤️",
              'message':
                  "$senderName liked your post: \"${widget.post.cleanTitle}\"",
              'notification_type': "like",
              'link_url': "/post/${widget.post.id}",
              'is_read': false,
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint("Error toggling like: $e");
    }
  }

  void _openComments() {
    FeedCommentsSheet.show(
      context,
      postId: widget.post.id,
      currentUserId: supabase.auth.currentUser?.id ?? '',
    ).then((_) {
      widget.onCommentsUpdated?.call();
    });
  }

  void _showPostActionMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: const BoxDecoration(
          color: surfaceWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: primaryPink),
              title: Text(
                ctx.zevTr('editPost'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () {
                Navigator.pop(ctx);
                widget.onEdit?.call();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              title: Text(
                ctx.zevTr('deletePost'),
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                widget.onDelete?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final currentUserId = supabase.auth.currentUser?.id;

    // Responsive dimensions
    final double cardPadding = context.respSpacing(phone: 16.0, tablet: 22.0, desktop: 24.0);
    final double avatarRadius = context.responsive(phone: 20.0, tablet: 26.0, desktop: 28.0);
    final double authorNameSize = context.respFont(phone: 15.0, tablet: 17.5, desktop: 18.5);
    final double metaFontSize = context.respFont(phone: 11.0, tablet: 13.0, desktop: 13.5);
    final double moodTagFontSize = context.respFont(phone: 11.0, tablet: 13.0, desktop: 13.5);
    final double titleFontSize = context.respFont(phone: 16.0, tablet: 19.5, desktop: 20.5);
    final double contentFontSize = context.respFont(phone: 14.0, tablet: 16.5, desktop: 16.5);

    // Responsive action icon sizes
    final double heartIconSize = context.respIcon(phone: 26.0, tablet: 31.0, desktop: 27.0);
    final double commentIconSize = context.respIcon(phone: 24.0, tablet: 29.0, desktop: 25.0);
    final double repostIconSize = context.respIcon(phone: 25.0, tablet: 30.0, desktop: 26.0);
    final double sendIconSize = context.respIcon(phone: 23.0, tablet: 28.0, desktop: 24.0);
    final double bookmarkIconSize = context.respIcon(phone: 26.0, tablet: 31.0, desktop: 27.0);
    final double actionTextSize = context.respFont(phone: 13.0, tablet: 15.0, desktop: 14.0);
    final double actionSpacing = context.respSpacing(phone: 18.0, tablet: 26.0, desktop: 28.0);

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: context.respSpacing(phone: 16.0, tablet: 20.0, desktop: 24.0),
      ),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(context.responsive(phone: 24.0, tablet: 28.0, desktop: 30.0)),
        border: Border.all(color: cardBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User header
          Padding(
            padding: EdgeInsets.all(cardPadding),
            child: Row(
              children: [
                FastCircleAvatar(
                  imageUrl: post.authorAvatar,
                  radius: avatarRadius,
                  fallbackText: post.authorName.isNotEmpty
                      ? post.authorName[0]
                      : 'U',
                  border: Border.all(
                    color: primaryPink.withValues(alpha: 0.2),
                    width: 2,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(userId: post.studentId),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            UserProfileScreen(userId: post.studentId),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.authorName,
                          style: TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: authorNameSize,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.public, color: textGrey, size: metaFontSize + 1),
                            const SizedBox(width: 4),
                            Text(
                              post.createdAt.isNotEmpty
                                  ? post.createdAt.split('T')[0]
                                  : '',
                              style: TextStyle(
                                color: textGrey,
                                fontSize: metaFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (currentUserId != null &&
                    currentUserId != post.studentId) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: EdgeInsets.symmetric(
                      horizontal: context.respSpacing(phone: 14.0, tablet: 18.0, desktop: 20.0),
                      vertical: context.respSpacing(phone: 5.0, tablet: 7.0, desktop: 8.0),
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      "Follow",
                      style: TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.bold,
                        fontSize: metaFontSize + 1,
                      ),
                    ),
                  ),
                ],
                IconButton(
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: textDark,
                    size: context.respIcon(phone: 22.0, tablet: 26.0, desktop: 24.0),
                  ),
                  onPressed: _showPostActionMenu,
                ),
              ],
            ),
          ),

          // Vibe tag
          Padding(
            padding: EdgeInsets.symmetric(horizontal: cardPadding),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: context.respSpacing(phone: 10.0, tablet: 14.0, desktop: 16.0),
                vertical: context.respSpacing(phone: 4.0, tablet: 6.0, desktop: 6.0),
              ),
              decoration: BoxDecoration(
                color: lightPinkBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                post.moodTag,
                style: TextStyle(
                  color: primaryPink,
                  fontSize: moodTagFontSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Post title and body
          Padding(
            padding: EdgeInsets.symmetric(horizontal: cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.cleanTitle.isNotEmpty) ...[
                  Text(
                    post.cleanTitle,
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: titleFontSize,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  post.content,
                  style: TextStyle(
                    color: const Color(0xFF374151),
                    fontSize: contentFontSize,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // Post image via FastCachedImage
          if (post.imageUrl != null && post.imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: cardPadding),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(context.responsive(phone: 20.0, tablet: 24.0, desktop: 26.0)),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: context.responsive(
                      phone: MediaQuery.of(context).size.height * 0.4,
                      tablet: 500.0,
                      desktop: 600.0,
                    ),
                  ),
                  width: double.infinity,
                  color: Colors.grey.shade100,
                  child: FastCachedImage(
                    imageUrl: post.imageUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 1080,
                  ),
                ),
              ),
            ),
          ],

          // Action buttons (Heart, Comment, Repost, Send, Bookmark)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: cardPadding - 2, vertical: 10),
            child: Row(
              children: [
                // 1. Like Heart
                GestureDetector(
                  onTap: _toggleLike,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isLiked ? primaryPink : textDark,
                        size: heartIconSize,
                      ),
                      if (likesCount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          likesCount >= 1000
                              ? "${(likesCount / 1000).toStringAsFixed(1)}K"
                              : "$likesCount",
                          style: TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w800,
                            fontSize: actionTextSize,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: actionSpacing),

                // 2. Comments
                GestureDetector(
                  onTap: _openComments,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: textDark,
                        size: commentIconSize,
                      ),
                      if (post.commentsCount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          post.commentsCount >= 1000
                              ? "${(post.commentsCount / 1000).toStringAsFixed(1)}K"
                              : "${post.commentsCount}",
                          style: TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w800,
                            fontSize: actionTextSize,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: actionSpacing),

                // 3. Repost / Remix
                GestureDetector(
                  onTap: _toggleRepost,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Icon(
                        Icons.repeat_rounded,
                        color: isReposted ? primaryPink : textDark,
                        size: repostIconSize,
                      ),
                      if (repostsCount > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          "$repostsCount",
                          style: TextStyle(
                            color: isReposted ? primaryPink : textDark,
                            fontWeight: FontWeight.w800,
                            fontSize: actionTextSize,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: actionSpacing),

                // 4. Send / Share Post with Friends
                GestureDetector(
                  onTap: () => _showSharePostSheet(context),
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.send_outlined,
                    color: textDark,
                    size: sendIconSize,
                  ),
                ),

                const Spacer(),

                // 5. Bookmark / Save
                GestureDetector(
                  onTap: _toggleBookmark,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    isSaved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: isSaved ? primaryPink : textDark,
                    size: bookmarkIconSize,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSharePostSheet(BuildContext context) {
    final user = supabase.auth.currentUser;
    if (user == null) {
      AuthRequiredModal.show(context, actionName: "share posts");
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PostShareSheet(post: widget.post),
    );
  }
}

class _PostShareSheet extends StatefulWidget {
  final FeedPostItem post;

  const _PostShareSheet({required this.post});

  @override
  State<_PostShareSheet> createState() => _PostShareSheetState();
}

class _PostShareSheetState extends State<_PostShareSheet> {
  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _filteredFriends = [];
  final Set<String> _sentUserIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadShareRecipients();
  }

  Future<void> _loadShareRecipients() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Fetch friend relationships
      final relations = await supabase
          .from('student_friends')
          .select('sender_id, receiver_id')
          .or('sender_id.eq.${user.id},receiver_id.eq.${user.id}')
          .limit(40);

      Set<String> friendIds = {};
      for (var r in (relations as List)) {
        final sId = r['sender_id']?.toString() ?? '';
        final rId = r['receiver_id']?.toString() ?? '';
        if (sId.isNotEmpty && sId != user.id) friendIds.add(sId);
        if (rId.isNotEmpty && rId != user.id) friendIds.add(rId);
      }

      List<Map<String, dynamic>> peers = [];
      if (friendIds.isNotEmpty) {
        final profs = await supabase
            .from('profiles')
            .select('id, first_name, last_name, avatar_url, role')
            .inFilter('id', friendIds.toList())
            .limit(30);
        peers = List<Map<String, dynamic>>.from(profs);
      }

      // If friends are few, supplement with active members
      if (peers.length < 10) {
        final activeRes = await supabase
            .from('profiles')
            .select('id, first_name, last_name, avatar_url, role')
            .neq('id', user.id)
            .order('created_at', ascending: false)
            .limit(20);

        final existingIds = peers.map((p) => p['id']?.toString()).toSet();
        for (var a in (activeRes as List)) {
          if (!existingIds.contains(a['id']?.toString())) {
            peers.add(Map<String, dynamic>.from(a));
          }
        }
      }

      if (mounted) {
        setState(() {
          _friends = peers;
          _filteredFriends = peers;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading share recipients: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase().trim();
      if (_searchQuery.isEmpty) {
        _filteredFriends = _friends;
      } else {
        _filteredFriends = _friends.where((f) {
          final fullName = "${f['first_name'] ?? ''} ${f['last_name'] ?? ''}"
              .toLowerCase();
          return fullName.contains(_searchQuery);
        }).toList();
      }
    });
  }

  Future<void> _sendPostToFriend(Map<String, dynamic> friend) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final friendId = friend['id']?.toString() ?? '';
    if (friendId.isEmpty || _sentUserIds.contains(friendId)) return;

    setState(() {
      _sentUserIds.add(friendId);
    });

    try {
      final postTitle = widget.post.cleanTitle.isNotEmpty
          ? widget.post.cleanTitle
          : widget.post.content;
      final postSnippet = postTitle.length > 60
          ? '${postTitle.substring(0, 60)}...'
          : postTitle;

      await supabase.from('direct_messages').insert({
        'sender_id': user.id,
        'receiver_id': friendId,
        'message_text':
            '📝 [Post] $postSnippet\nhttps://zevapp.com/post/${widget.post.id}',
        'attachment_url': widget.post.imageUrl,
        'attachment_type': 'post',
        'is_delivered': true,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Notification to friend
      try {
        final myProfile = await supabase
            .from('profiles')
            .select('first_name, last_name')
            .eq('id', user.id)
            .maybeSingle();
        final myName = myProfile != null
            ? '${myProfile['first_name'] ?? 'A member'} ${myProfile['last_name'] ?? ''}'
                  .trim()
            : 'A member';

        await supabase.from('user_notifications').insert({
          'user_id': friendId,
          'sender_id': user.id,
          'title': '📝 Post Shared With You',
          'message': '$myName sent you a post: "$postSnippet"',
          'notification_type': 'direct_message',
          'link_url': '/post/${widget.post.id}',
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

      if (mounted) {
        ZevAlert.show(
          context,
          "Post sent to ${friend['first_name'] ?? 'friend'} 🚀",
        );
      }
    } catch (e) {
      debugPrint("Error sending post to friend: $e");
      if (mounted) {
        setState(() {
          _sentUserIds.remove(friendId);
        });
        ZevAlert.show(context, "Could not send post", isError: true);
      }
    }
  }

  void _copyPostLink() {
    final pureLink = 'https://zevapp.com/post/${widget.post.id}';
    Clipboard.setData(ClipboardData(text: pureLink));
    Navigator.pop(context);
    ZevAlert.show(context, "Post link copied to clipboard! 📋");
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
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 14),

          // Header Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Share Post 🚀",
                  style: TextStyle(
                    color: textDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: textDark),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Quick Action Bar: Copy Link & Share External
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _copyPostLink,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.link_rounded, color: textDark, size: 20),
                          SizedBox(width: 8),
                          Text(
                            "Copy Post Link",
                            style: TextStyle(
                              color: textDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cardBorder),
              ),
              child: TextField(
                onChanged: _onSearch,
                style: const TextStyle(fontSize: 13, color: textDark),
                decoration: const InputDecoration(
                  hintText: "Search people...",
                  hintStyle: TextStyle(color: textGrey, fontSize: 13),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: textGrey,
                    size: 18,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: cardBorder),

          // Recipients List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: primaryPink),
                  )
                : _filteredFriends.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? "No members match '$_searchQuery'"
                          : "No members available",
                      style: const TextStyle(color: textGrey, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    itemCount: _filteredFriends.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final friend = _filteredFriends[index];
                      final friendId = friend['id']?.toString() ?? '';
                      final isSent = _sentUserIds.contains(friendId);
                      final name =
                          "${friend['first_name'] ?? ''} ${friend['last_name'] ?? ''}"
                              .trim();
                      final avatarUrl = friend['avatar_url']?.toString() ?? '';

                      return Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: lightPinkBg,
                            backgroundImage: avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl.isEmpty
                                ? Text(
                                    name.isNotEmpty ? name[0] : 'U',
                                    style: const TextStyle(
                                      color: primaryPink,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name.isNotEmpty ? name : 'ZEV Member',
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: isSent
                                ? null
                                : () => _sendPostToFriend(friend),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSent
                                    ? const Color(0xFFE2E8F0)
                                    : primaryPink,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                isSent ? "Sent ✓" : "Send",
                                style: TextStyle(
                                  color: isSent ? textGrey : Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
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
  }
}
