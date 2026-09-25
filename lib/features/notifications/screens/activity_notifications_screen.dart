import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/language_service.dart';
import '../../feed/screens/reels_viewer_screen.dart';

class ActivityNotificationItem {
  final String id;
  final String title;
  final String message;
  final String type; // 'like', 'comment', 'friend_request'
  final String senderName;
  final String senderAvatar;
  final DateTime createdAt;
  final String? linkUrl;

  ActivityNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.senderName,
    required this.senderAvatar,
    required this.createdAt,
    this.linkUrl,
  });
}

class ActivityNotificationsScreen extends StatefulWidget {
  const ActivityNotificationsScreen({super.key});

  @override
  State<ActivityNotificationsScreen> createState() =>
      _ActivityNotificationsScreenState();
}

class _ActivityNotificationsScreenState
    extends State<ActivityNotificationsScreen> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  List<ActivityNotificationItem> allNotifications = [];
  List<ActivityNotificationItem> filteredNotifications = [];

  String selectedFilterKey = 'all';
  final List<String> filterKeys = [
    'all',
    'likes_comments',
    'friend_requests',
  ];

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  @override
  void initState() {
    super.initState();
    _fetchActivityNotifications();
  }

  Future<void> _fetchActivityNotifications() async {
    setState(() => isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => isLoading = false);
        return;
      }

      final currentUserId = user.id;
      List<ActivityNotificationItem> items = [];

      // 1. Fetch general notifications (likes, comments) from user_notifications
      try {
        List notifRows = [];
        try {
          final res = await supabase
              .from("user_notifications")
              .select(
                "*, profiles!sender_id(first_name, last_name, avatar_url)",
              )
              .eq("user_id", currentUserId)
              .inFilter("notification_type", [
                "like_comment",
                "like",
                "comment",
                "story_like",
              ])
              .order("created_at", ascending: false)
              .limit(30);
          notifRows = res as List;
        } catch (_) {
          final res = await supabase
              .from("user_notifications")
              .select()
              .eq("user_id", currentUserId)
              .inFilter("notification_type", [
                "like_comment",
                "like",
                "comment",
                "story_like",
              ])
              .order("created_at", ascending: false)
              .limit(30);
          notifRows = res as List;
        }

        for (var n in notifRows) {
          final p = n['profiles'];
          final name = (p != null)
              ? "${p['first_name'] ?? ''} ${p['last_name'] ?? ''}".trim()
              : 'Someone';
          final avatar = p != null ? (p['avatar_url'] ?? '') : '';

          items.add(
            ActivityNotificationItem(
              id: n['id'].toString(),
              title: n['title'] ?? 'Likes & Comments',
              message: n['message'] ?? '',
              type: n['notification_type'] == 'comment' ? 'comment' : 'like',
              senderName: name.isNotEmpty ? name : 'Student',
              senderAvatar: avatar,
              createdAt:
                  DateTime.tryParse(n['created_at'] ?? '') ?? DateTime.now(),
              linkUrl: n['link_url'],
            ),
          );
        }
      } catch (_) {}

      // 2. Fetch user reels likes
      try {
        final myReelsRes = await supabase
            .from("reels")
            .select("id, title")
            .eq("user_id", currentUserId);

        final myReelIds = (myReelsRes as List)
            .map((r) => r['id'].toString())
            .toList();
        if (myReelIds.isNotEmpty) {
          final reelLikesRes = await supabase
              .from("reel_likes")
              .select(
                "id, reel_id, user_id, created_at, profiles(first_name, last_name, avatar_url)",
              )
              .filter("reel_id", "in", myReelIds)
              .neq("user_id", currentUserId)
              .order("created_at", ascending: false)
              .limit(15);

          for (var l in (reelLikesRes as List)) {
            final p = l['profiles'];
            final name = (p != null)
                ? "${p['first_name'] ?? ''} ${p['last_name'] ?? ''}".trim()
                : 'Someone';
            final avatar = p != null ? (p['avatar_url'] ?? '') : '';

            items.add(
              ActivityNotificationItem(
                id: "reel_like_${l['id']}",
                title: "Liked your Reel ❤️",
                message: "$name liked your educational video.",
                type: 'like',
                senderName: name.isNotEmpty ? name : 'Student',
                senderAvatar: avatar,
                createdAt:
                    DateTime.tryParse(l['created_at'] ?? '') ?? DateTime.now(),
              ),
            );
          }
        }
      } catch (_) {}

      // 3. Fetch friend / connection requests
      try {
        final friendsRes = await supabase
            .from("student_friends")
            .select(
              "id, sender_id, status, created_at, profiles!sender_id(first_name, last_name, avatar_url)",
            )
            .eq("receiver_id", currentUserId)
            .eq("status", "pending")
            .order("created_at", ascending: false);

        for (var f in (friendsRes as List)) {
          final p = f['profiles'];
          final name = (p != null)
              ? "${p['first_name'] ?? ''} ${p['last_name'] ?? ''}".trim()
              : 'Someone';
          final avatar = p != null ? (p['avatar_url'] ?? '') : '';

          items.add(
            ActivityNotificationItem(
              id: "friend_${f['id']}",
              title: "Friend Request 👥",
              message: "$name sent you a friend request.",
              type: 'friend_request',
              senderName: name,
              senderAvatar: avatar,
              createdAt:
                  DateTime.tryParse(f['created_at'] ?? '') ?? DateTime.now(),
            ),
          );
        }
      } catch (_) {}

      // Sort by newest creation timestamp
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          allNotifications = items;
          _applyFilter();
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _applyFilter() {
    if (selectedFilterKey == 'all') {
      filteredNotifications = List.from(allNotifications);
    } else if (selectedFilterKey == 'likes_comments') {
      filteredNotifications = allNotifications
          .where((n) => n.type == 'like' || n.type == 'comment')
          .toList();
    } else if (selectedFilterKey == 'friend_requests') {
      filteredNotifications = allNotifications
          .where((n) => n.type == 'friend_request')
          .toList();
    }
  }

  String _getLocalizedTitle(ActivityNotificationItem item) {
    if (item.type == 'like') {
      return "Liked your Reel ❤️";
    } else if (item.type == 'comment') {
      return "Comment on your Reel 💬";
    } else if (item.type == 'friend_request') {
      return "Connection Request 👥";
    }
    return item.title;
  }

  String _getLocalizedMessage(ActivityNotificationItem item) {
    final name = item.senderName.isNotEmpty ? item.senderName : 'Someone';
    if (item.type == 'like') {
      return "$name liked your reel video.";
    } else if (item.type == 'comment') {
      return "$name commented on your reel video.";
    } else if (item.type == 'friend_request') {
      return "$name sent you a connection request.";
    }
    return item.message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceWhite,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Icon(Icons.favorite_rounded, color: primaryPink, size: 22),
            const SizedBox(width: 8),
            Text(
              context.l10n.activityAndNotifications,
              style: const TextStyle(
                color: textDark,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Category filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: filterKeys.map((fKey) {
                final isSel = selectedFilterKey == fKey;
                final label = fKey == 'likes_comments'
                    ? context.l10n.likesAndComments
                    : fKey == 'friend_requests'
                        ? context.l10n.friendRequests
                        : context.l10n.allActivities;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: isSel,
                    selectedColor: primaryPink,
                    backgroundColor: const Color(0xFFF3F4F6),
                    side: BorderSide.none,
                    showCheckmark: isSel,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSel ? Colors.white : textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          selectedFilterKey = fKey;
                          _applyFilter();
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1, color: cardBorder),

          // Notifications list
          Expanded(
            child: RefreshIndicator(
              color: primaryPink,
              onRefresh: _fetchActivityNotifications,
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: primaryPink,
                        strokeWidth: 2.5,
                      ),
                    )
                  : filteredNotifications.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Column(
                            children: [
                              const Icon(
                                Icons.notifications_off_outlined,
                                size: 60,
                                color: textGrey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.l10n.noActivitiesYet,
                                style: const TextStyle(
                                  color: textDark,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                context.l10n.activitiesEmptyDesc,
                                style: const TextStyle(color: textGrey, fontSize: 11),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredNotifications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = filteredNotifications[index];
                        return GestureDetector(
                          onTap: () {
                            if (item.linkUrl != null) {
                              if (item.linkUrl!.startsWith('/reel/')) {
                                final reelId = item.linkUrl!.split('/').last;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StudentReelsScreen(
                                      targetReelId: reelId,
                                    ),
                                  ),
                                );
                              } else if (item.linkUrl!.startsWith('/post/')) {
                                final postId = item.linkUrl!.split('/').last;
                                _showPostDetail(context, postId);
                              }
                            } else if (item.type == 'like' ||
                                item.type == 'comment') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const StudentReelsScreen(),
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: surfaceWhite,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: cardBorder, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: lightPinkBg,
                                      backgroundImage:
                                          item.senderAvatar.isNotEmpty
                                          ? NetworkImage(item.senderAvatar)
                                          : null,
                                      child: item.senderAvatar.isEmpty
                                          ? Text(
                                              item.senderName.isNotEmpty
                                                  ? item.senderName[0]
                                                  : 'S',
                                              style: const TextStyle(
                                                color: primaryPink,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            )
                                          : null,
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          item.type == 'like'
                                              ? Icons.favorite_rounded
                                              : item.type == 'comment'
                                              ? Icons.chat_bubble_rounded
                                              : Icons.people_rounded,
                                          color: primaryPink,
                                          size: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _getLocalizedTitle(item),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                          color: textDark,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _getLocalizedMessage(item),
                                        style: const TextStyle(
                                          color: textGrey,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 12,
                                  color: textGrey,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPostDetail(BuildContext context, String postId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PostDetailBottomSheet(postId: postId),
    );
  }
}

class _PostDetailBottomSheet extends StatefulWidget {
  final String postId;
  const _PostDetailBottomSheet({required this.postId});

  @override
  State<_PostDetailBottomSheet> createState() => _PostDetailBottomSheetState();
}

class _PostDetailBottomSheetState extends State<_PostDetailBottomSheet> {
  final supabase = Supabase.instance.client;
  bool isPostLoading = true;
  bool isCommentsLoading = true;
  Map<String, dynamic>? postData;
  List<Map<String, dynamic>> comments = [];
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPostDetails();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadPostDetails() async {
    try {
      final res = await supabase
          .from("discussion_posts")
          .select("*, profiles(first_name, last_name, avatar_url)")
          .eq("id", widget.postId)
          .maybeSingle();
      if (mounted) {
        setState(() {
          postData = res;
          isPostLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => isPostLoading = false);
    }
  }

  Future<void> _loadComments() async {
    try {
      final res = await supabase
          .from("discussion_comments")
          .select("*, profiles:student_id(first_name, last_name, avatar_url)")
          .eq("post_id", widget.postId)
          .order("created_at", ascending: true);
      if (mounted) {
        setState(() {
          comments = List<Map<String, dynamic>>.from(res as List);
          isCommentsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => isCommentsLoading = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    _commentController.clear();
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from("discussion_comments").insert({
        'post_id': widget.postId,
        'student_id': user.id,
        'comment_text': text,
      });

      // Send feed post comment notification
      try {
        if (postData != null) {
          final authorId = postData!['student_id']?.toString() ?? '';
          final postTitle = postData!['title'] ?? 'your post';
          if (authorId.isNotEmpty && authorId != user.id) {
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
              'user_id': authorId,
              'sender_id': user.id,
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

      _loadComments();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Container(
      height: screenHeight * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: isPostLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFC466B)),
            )
          : postData == null
          ? Center(
              child: Text(
                context.l10n.postNotFound,
                style: const TextStyle(color: Colors.grey),
              ),
            )
          : Column(
              children: [
                // Header Bar
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      // Author info
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFFFAF4F6),
                            backgroundImage:
                                postData!['profiles']?['avatar_url'] != null &&
                                    postData!['profiles']?['avatar_url']
                                            .toString()
                                            .isNotEmpty ==
                                        true
                                ? NetworkImage(
                                    postData!['profiles']!['avatar_url']!,
                                  )
                                : null,
                            child:
                                postData!['profiles']?['avatar_url'] == null ||
                                    postData!['profiles']?['avatar_url']
                                            .toString()
                                            .isEmpty ==
                                        true
                                ? Text(
                                    (postData!['profiles']?['first_name'] ??
                                            'P')
                                        .toString()[0],
                                    style: const TextStyle(
                                      color: Color(0xFFFC466B),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${postData!['profiles']?['first_name'] ?? 'Academy'} ${postData!['profiles']?['last_name'] ?? 'Member'}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              Text(
                                context.l10n.postedOnFeed,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Post Title
                      Text(
                        postData!['title'] ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Post Content
                      Text(
                        postData!['content'] ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF374151),
                          height: 1.4,
                        ),
                      ),
                      if (postData!['image_url'] != null &&
                          postData!['image_url'].toString().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            postData!['image_url']!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Divider(),
                      // Comments section title
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          context.l10n.commentsTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                      isCommentsLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFFFC466B),
                              ),
                            )
                          : comments.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  context.l10n.noCommentsYet,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: comments.length,
                              itemBuilder: (context, index) {
                                final c = comments[index];
                                final commenterProfile = c['profiles'];
                                final String name = commenterProfile != null
                                    ? "${commenterProfile['first_name'] ?? ''} ${commenterProfile['last_name'] ?? ''}"
                                          .trim()
                                    : 'ZEV Member';
                                final String avatar = commenterProfile != null
                                    ? (commenterProfile['avatar_url'] ?? '')
                                    : '';
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFFFAF4F6),
                                    backgroundImage: avatar.isNotEmpty
                                        ? NetworkImage(avatar)
                                        : null,
                                    child: avatar.isEmpty
                                        ? Text(
                                            name.isNotEmpty ? name[0] : 'S',
                                            style: const TextStyle(
                                              color: Color(0xFFFC466B),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                          )
                                        : null,
                                  ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  subtitle: Text(
                                    c['comment_text'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF374151),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Comment input
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: context.l10n.addComment,
                            hintStyle: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF3F4F6),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          color: Color(0xFFFC466B),
                        ),
                        onPressed: _sendComment,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
