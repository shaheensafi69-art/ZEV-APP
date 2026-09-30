import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/utils/app_media_picker.dart';
import '../../chat/screens/direct_chat_screen.dart';
import 'reels_viewer_screen.dart';
import 'user_follows_list_screen.dart';
import '../../profile/screens/zev_settings_screen.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../widgets/zev_reels_preview_grid.dart';

class UserProfileScreen extends StatefulWidget {
  final String? userId;
  final VoidCallback? onExit;

  const UserProfileScreen({super.key, this.userId, this.onExit});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  bool isCoverUploading = false;
  bool isAvatarUploading = false;
  Map<String, dynamic>? profileData;
  List<Map<String, dynamic>> userPosts = [];
  List<Map<String, dynamic>> userReels = [];
  List<Map<String, dynamic>> userLikedReels = [];
  List<Map<String, dynamic>> userSavedReels = [];
  List<Map<String, dynamic>> userSavedPosts = [];
  List<Map<String, dynamic>> userReposts = [];
  int activeTab = 0; // 0: Posts, 1: Reels, 2: Liked, 3: Reposts, 4: Saved
  String activeWebTab = 'posts';
  int activeSavedSubTab = 0; // 0: Saved Reels, 1: Saved Posts

  int followersCount = 0;
  int followingCount = 0;
  bool isFollowedByMe = false;

  String friendshipStatus = 'none';
  bool isActionLoading = false;
  int friendsCount = 0;
  bool isProfileInfoExpanded = false;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  @override
  void initState() {
    super.initState();
    if (!isMyProfile) {
      if (activeTab >= 2) activeTab = 0;
      if (activeWebTab == 'liked' || activeWebTab == 'saved') {
        activeWebTab = 'posts';
      }
    }
    _fetchProfileAndPosts();
  }

  String get targetUserId =>
      (widget.userId != null && widget.userId!.isNotEmpty)
      ? widget.userId!
      : (supabase.auth.currentUser?.id ?? '');
  bool get isMyProfile =>
      widget.userId == null ||
      widget.userId!.isEmpty ||
      widget.userId == supabase.auth.currentUser?.id;

  String _extractMood(String title) {
    if (title.startsWith('[') && title.contains(']')) {
      int endIndex = title.indexOf(']');
      return title.substring(1, endIndex);
    }
    return "📢 Post";
  }

  String _extractCleanTitle(String title) {
    if (title.startsWith('[') && title.contains(']')) {
      int endIndex = title.indexOf(']');
      return title.substring(endIndex + 1).trim();
    }
    return title;
  }

  Future<void> _fetchProfileAndPosts() async {
    setState(() => isLoading = true);
    try {
      if (targetUserId.isEmpty) return;

      final res = await supabase
          .from("profiles")
          .select("*")
          .eq("id", targetUserId)
          .maybeSingle();
      final friendsRes = await supabase
          .from("student_friends")
          .select("id")
          .or("sender_id.eq.$targetUserId,receiver_id.eq.$targetUserId")
          .eq("status", "accepted");
      int count = (friendsRes as List).length;

      String status = 'none';
      final currentUser = supabase.auth.currentUser;
      if (!isMyProfile && currentUser != null) {
        final relsRes = await supabase
            .from("student_friends")
            .select("*")
            .or(
              "sender_id.eq.${currentUser.id},receiver_id.eq.${currentUser.id}",
            );

        dynamic relRes;
        for (var r in (relsRes as List)) {
          final sId = r['sender_id']?.toString() ?? '';
          final recId = r['receiver_id']?.toString() ?? '';
          if ((sId == currentUser.id && recId == targetUserId) ||
              (sId == targetUserId && recId == currentUser.id)) {
            relRes = r;
            break;
          }
        }

        if (relRes != null) {
          if (relRes['status'] == 'accepted') {
            status = 'friends';
          } else if (relRes['sender_id'] == currentUser.id) {
            status = 'pending_sent';
          } else {
            status = 'pending_received';
          }
        }
      }

      final postsRes = await supabase
          .from("discussion_posts")
          .select("*")
          .eq("student_id", targetUserId)
          .order("created_at", ascending: false);
      List<Map<String, dynamic>> enrichedPosts = [];
      for (var post in postsRes) {
        String pId = post['id'].toString();
        int likesCount = 0;
        bool isLikedByMe = false;
        try {
          final likesRes = await supabase
              .from("discussion_likes")
              .select("student_id")
              .eq("post_id", pId);
          likesCount = likesRes.length;
          if (currentUser != null) {
            isLikedByMe = likesRes.any(
              (like) => like['student_id'] == currentUser.id,
            );
          }
        } catch (_) {}

        int commentsCount = 0;
        try {
          final commentsRes = await supabase
              .from("discussion_comments")
              .select("id")
              .eq("post_id", pId);
          commentsCount = commentsRes.length;
        } catch (_) {}

        enrichedPosts.add({
          ...post,
          'likes_count': likesCount,
          'comments_count': commentsCount,
          'is_liked_by_me': isLikedByMe,
        });
      }

      // Fetch user reels
      List<Map<String, dynamic>> enrichedReels = [];
      try {
        final reelsRes = await supabase
            .from("reels")
            .select("*")
            .eq("user_id", targetUserId)
            .order("created_at", ascending: false);
        for (var r in reelsRes) {
          enrichedReels.add(Map<String, dynamic>.from(r));
        }
      } catch (_) {}

      // Fetch followers and following
      int followers = 0;
      int following = 0;
      bool followedByMe = false;
      try {
        final fRes = await supabase
            .from("user_follows")
            .select("follower_id")
            .eq("following_id", targetUserId);
        followers = (fRes as List).length;
        if (currentUser != null) {
          followedByMe = (fRes as List).any(
            (f) => f['follower_id']?.toString() == currentUser.id,
          );
        }
      } catch (_) {
        followers = count;
      }

      try {
        final fRes = await supabase
            .from("user_follows")
            .select("following_id")
            .eq("follower_id", targetUserId);
        following = (fRes as List).length;
      } catch (_) {
        following = count;
      }

      // Fetch liked reels (private to account owner)
      List<Map<String, dynamic>> likedReels = [];
      if (isMyProfile && currentUser != null) {
        try {
          final lRes = await supabase
              .from("reel_likes")
              .select("reel_id, reels(*)")
              .eq("user_id", targetUserId)
              .order("created_at", ascending: false);
          for (var item in (lRes as List)) {
            final rData = item['reels'];
            if (rData != null && rData is Map<String, dynamic>) {
              likedReels.add(Map<String, dynamic>.from(rData));
            }
          }
        } catch (e) {
          debugPrint("Error fetching liked reels: $e");
        }
      }

      // Fetch saved reels and posts (Saved Items)
      List<Map<String, dynamic>> savedReels = [];
      List<Map<String, dynamic>> savedPosts = [];
      if (isMyProfile && currentUser != null) {
        try {
          final bReelsRes = await supabase
              .from("reel_bookmarks")
              .select("reel_id, reels(*)")
              .eq("user_id", currentUser.id)
              .order("created_at", ascending: false);
          for (var item in (bReelsRes as List)) {
            final rData = item['reels'];
            if (rData != null && rData is Map<String, dynamic>) {
              savedReels.add(Map<String, dynamic>.from(rData));
            }
          }
        } catch (e) {
          debugPrint("Error fetching saved reels: $e");
        }

        try {
          final bPostsRes = await supabase
              .from("discussion_bookmarks")
              .select("post_id, discussion_posts(*)")
              .eq("user_id", currentUser.id)
              .order("created_at", ascending: false);
          for (var item in (bPostsRes as List)) {
            final pData = item['discussion_posts'];
            if (pData != null && pData is Map<String, dynamic>) {
              savedPosts.add(Map<String, dynamic>.from(pData));
            }
          }
        } catch (e) {
          debugPrint("Error fetching saved posts: $e");
        }
      }

      // Fetch user reposts
      List<Map<String, dynamic>> repostsList = [];
      try {
        final repRes = await supabase
            .from("post_reposts")
            .select("post_id, discussion_posts(*)")
            .eq("user_id", targetUserId)
            .order("created_at", ascending: false);
        for (var item in (repRes as List)) {
          final pData = item['discussion_posts'];
          if (pData != null && pData is Map<String, dynamic>) {
            repostsList.add(Map<String, dynamic>.from(pData));
          }
        }
      } catch (e) {
        debugPrint("Notice: post_reposts fetch: $e");
      }

      if (mounted) {
        setState(() {
          profileData = res;
          friendsCount = count;
          followersCount = followers;
          followingCount = following;
          isFollowedByMe = followedByMe;
          friendshipStatus = status;
          userPosts = enrichedPosts;
          userReels = enrichedReels;
          userLikedReels = likedReels;
          userSavedReels = savedReels;
          userSavedPosts = savedPosts;
          userReposts = repostsList;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching profile & posts: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    final willFollow = !isFollowedByMe;
    setState(() {
      isFollowedByMe = willFollow;
      followersCount += willFollow ? 1 : -1;
      if (followersCount < 0) followersCount = 0;
    });

    try {
      if (willFollow) {
        await supabase.from("user_follows").insert({
          "follower_id": currentUser.id,
          "following_id": targetUserId,
        });
      } else {
        await supabase
            .from("user_follows")
            .delete()
            .eq("follower_id", currentUser.id)
            .eq("following_id", targetUserId);
      }
    } catch (e) {
      debugPrint("Error toggling follow: $e");
    }
  }

  // Upload cover image to Cloudflare R2 and update Supabase
  Future<void> _handleCoverUpload() async {
    final file = await AppMediaPicker.instance.pickImage(
      maxWidth: 2560,
      maxHeight: 1440,
    );
    if (file == null) return;

    setState(() => isCoverUploading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final fileExt = file.path.split('.').lastOrNull ?? 'jpg';
      final fileName =
          'cover-${user.id}-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final bytes = await file.readAsBytes();

      final publicUrl = await CloudflareStorageService.instance.upload(
        bucket: 'covers',
        path: fileName,
        bytes: bytes,
        contentType: 'image/jpeg',
      );

      await supabase
          .from('profiles')
          .update({'cover_image_url': publicUrl})
          .eq('id', user.id);

      setState(() {
        if (profileData != null) {
          profileData!['cover_image_url'] = publicUrl;
          profileData!['cover_url'] = publicUrl;
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Cover photo updated successfully! 🖼️✅"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint("Cover upload error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to upload cover: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => isCoverUploading = false);
    }
  }

  // Upload avatar image to Cloudflare R2 and update Supabase
  Future<void> _handleAvatarUpload() async {
    final file = await AppMediaPicker.instance.pickImage(
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (file == null) return;

    setState(() => isAvatarUploading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final fileExt = file.path.split('.').lastOrNull ?? 'jpg';
      final fileName =
          'avatar-${user.id}-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final bytes = await file.readAsBytes();

      final publicUrl = await CloudflareStorageService.instance.upload(
        bucket: 'avatars',
        path: fileName,
        bytes: bytes,
        contentType: 'image/jpeg',
      );

      await supabase
          .from('profiles')
          .update({'avatar_url': publicUrl})
          .eq('id', user.id);

      setState(() {
        if (profileData != null) {
          profileData!['avatar_url'] = publicUrl;
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile avatar updated successfully! 👤✅"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint("Avatar upload error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to upload avatar: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => isAvatarUploading = false);
    }
  }

  // Edit profile dialog
  void _showEditProfileModal() {
    final TextEditingController firstNameController = TextEditingController(
      text: profileData?['first_name'] ?? '',
    );
    final TextEditingController lastNameController = TextEditingController(
      text: profileData?['last_name'] ?? '',
    );
    final TextEditingController usernameController = TextEditingController(
      text: (profileData?['username'] ?? '').toString().replaceFirst('@', ''),
    );
    final TextEditingController emailController = TextEditingController(
      text: profileData?['email'] ?? supabase.auth.currentUser?.email ?? '',
    );
    final TextEditingController fatherNameController = TextEditingController(
      text: profileData?['father_name'] ?? '',
    );
    final TextEditingController phoneController = TextEditingController(
      text: profileData?['phone_number'] ?? '',
    );
    final TextEditingController countryController = TextEditingController(
      text: profileData?['country'] ?? '',
    );
    final TextEditingController dobController = TextEditingController(
      text: profileData?['date_of_birth'] ?? '',
    );
    final TextEditingController bioController = TextEditingController(
      text: profileData?['bio'] ?? '',
    );

    // Privacy toggles (hide / show from public profile)
    bool isPhoneHidden = profileData?['is_phone_hidden'] == true;
    bool isDobHidden = profileData?['is_dob_hidden'] == true;
    bool isFatherNameHidden = profileData?['is_father_name_hidden'] == true;
    bool isCountryHidden = profileData?['is_country_hidden'] == true;
    bool isSavingProfile = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (modalContext, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Edit Profile ✏️",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: textGrey),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Manage avatar and cover images
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: lightPinkBg.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: primaryPink.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            await _handleAvatarUpload();
                            setModalState(() {});
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: surfaceWhite,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cardBorder),
                            ),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: primaryPink.withValues(
                                    alpha: 0.1,
                                  ),
                                  backgroundImage:
                                      profileData?['avatar_url'] != null &&
                                          profileData!['avatar_url']
                                              .toString()
                                              .isNotEmpty
                                      ? NetworkImage(profileData!['avatar_url'])
                                      : null,
                                  child: isAvatarUploading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: primaryPink,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.camera_alt_rounded,
                                          color: primaryPink,
                                          size: 20,
                                        ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  "Change Photo 👤",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: textDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            await _handleCoverUpload();
                            setModalState(() {});
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: surfaceWhite,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cardBorder),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.purple.withValues(alpha: 0.1),
                                    image:
                                        (profileData?['cover_image_url'] ??
                                                    profileData?['cover_url']) !=
                                                null &&
                                            (profileData!['cover_image_url'] ??
                                                    profileData!['cover_url'])
                                                .toString()
                                                .isNotEmpty
                                        ? DecorationImage(
                                            image: NetworkImage(
                                              (profileData!['cover_image_url'] ??
                                                      profileData!['cover_url'])
                                                  .toString(),
                                            ),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: isCoverUploading
                                      ? const Center(
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.purple,
                                            ),
                                          ),
                                        )
                                      : const Center(
                                          child: Icon(
                                            Icons.image_rounded,
                                            color: Colors.purple,
                                            size: 22,
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  "Change Cover 🖼️",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: textDark,
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
                const SizedBox(height: 18),

                // Name fields
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: firstNameController,
                        cursorColor: primaryPink,
                        decoration: _inputDecoration("First Name"),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: lastNameController,
                        cursorColor: primaryPink,
                        decoration: _inputDecoration("Last Name"),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: textDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Username field (customizable, unique)
                TextField(
                  controller: usernameController,
                  cursorColor: primaryPink,
                  decoration: _inputDecoration("Username (e.g. zev_star)")
                      .copyWith(
                        prefixIcon: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Text(
                            "@",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: primaryPink,
                            ),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                        helperText:
                            "Unique username (3-30 letters, numbers, or _)",
                        helperStyle: const TextStyle(
                          fontSize: 11,
                          color: textGrey,
                        ),
                      ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 12),

                // Email field (Read-only / Non-editable as requested)
                TextField(
                  controller: emailController,
                  readOnly: true,
                  decoration: _inputDecoration("Email Address").copyWith(
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: textGrey,
                      size: 20,
                    ),
                    suffixIcon: const Tooltip(
                      message: "Email cannot be changed (غیر قابل تغییر)",
                      child: Icon(
                        Icons.lock_rounded,
                        color: textGrey,
                        size: 18,
                      ),
                    ),
                    helperText:
                        "Email cannot be changed (ایمیل ثابت و غیر قابل تغییر است)",
                    helperStyle: const TextStyle(fontSize: 11, color: textGrey),
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: textGrey,
                  ),
                ),
                const SizedBox(height: 14),

                // Privacy info banner
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blueGrey.withValues(alpha: 0.15),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: textGrey,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Tap the 👁️ eye icon on any field below to hide (🔒) or show it on your public profile.",
                          style: TextStyle(
                            fontSize: 10.5,
                            color: textGrey,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Father's Name with privacy toggle
                TextField(
                  controller: fatherNameController,
                  cursorColor: primaryPink,
                  decoration: _inputDecoration("Father's Name").copyWith(
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      color: textGrey,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isFatherNameHidden
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: isFatherNameHidden
                            ? Colors.redAccent
                            : Colors.teal,
                        size: 20,
                      ),
                      tooltip: isFatherNameHidden
                          ? "Hidden from public (پنهان)"
                          : "Visible to public (نمایان)",
                      onPressed: () => setModalState(
                        () => isFatherNameHidden = !isFatherNameHidden,
                      ),
                    ),
                    helperText: isFatherNameHidden
                        ? "🔒 Hidden from others (پنهان)"
                        : "👁️ Visible to public (نمایان)",
                    helperStyle: TextStyle(
                      fontSize: 11,
                      color: isFatherNameHidden
                          ? Colors.redAccent
                          : Colors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 12),

                // Phone with privacy toggle
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  cursorColor: primaryPink,
                  decoration: _inputDecoration("Phone Number (+...)").copyWith(
                    prefixIcon: const Icon(
                      Icons.phone_outlined,
                      color: textGrey,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isPhoneHidden
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: isPhoneHidden ? Colors.redAccent : Colors.teal,
                        size: 20,
                      ),
                      tooltip: isPhoneHidden
                          ? "Hidden from public (پنهان)"
                          : "Visible to public (نمایان)",
                      onPressed: () =>
                          setModalState(() => isPhoneHidden = !isPhoneHidden),
                    ),
                    helperText: isPhoneHidden
                        ? "🔒 Hidden from others (پنهان)"
                        : "👁️ Visible to public (نمایان)",
                    helperStyle: TextStyle(
                      fontSize: 11,
                      color: isPhoneHidden ? Colors.redAccent : Colors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 12),

                // Country with privacy toggle
                TextField(
                  controller: countryController,
                  cursorColor: primaryPink,
                  decoration: _inputDecoration("Country / Location").copyWith(
                    prefixIcon: const Icon(
                      Icons.public_rounded,
                      color: textGrey,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isCountryHidden
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: isCountryHidden ? Colors.redAccent : Colors.teal,
                        size: 20,
                      ),
                      tooltip: isCountryHidden
                          ? "Hidden from public (پنهان)"
                          : "Visible to public (نمایان)",
                      onPressed: () => setModalState(
                        () => isCountryHidden = !isCountryHidden,
                      ),
                    ),
                    helperText: isCountryHidden
                        ? "🔒 Hidden from others (پنهان)"
                        : "👁️ Visible to public (نمایان)",
                    helperStyle: TextStyle(
                      fontSize: 11,
                      color: isCountryHidden ? Colors.redAccent : Colors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 12),

                // Date of birth with privacy toggle
                TextField(
                  controller: dobController,
                  cursorColor: primaryPink,
                  decoration: _inputDecoration("Date of Birth (YYYY-MM-DD)")
                      .copyWith(
                        prefixIcon: const Icon(
                          Icons.cake_outlined,
                          color: textGrey,
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isDobHidden
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: isDobHidden ? Colors.redAccent : Colors.teal,
                            size: 20,
                          ),
                          tooltip: isDobHidden
                              ? "Hidden from public (پنهان)"
                              : "Visible to public (نمایان)",
                          onPressed: () =>
                              setModalState(() => isDobHidden = !isDobHidden),
                        ),
                        helperText: isDobHidden
                            ? "🔒 Hidden from others (پنهان)"
                            : "👁️ Visible to public (نمایان)",
                        helperStyle: TextStyle(
                          fontSize: 11,
                          color: isDobHidden ? Colors.redAccent : Colors.teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 12),

                // Bio
                TextField(
                  controller: bioController,
                  cursorColor: primaryPink,
                  maxLines: 3,
                  decoration: _inputDecoration("Biography / About Me"),
                  style: const TextStyle(fontSize: 14, color: textDark),
                ),
                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryPink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: isSavingProfile
                        ? null
                        : () async {
                            final user = supabase.auth.currentUser;
                            if (user == null) return;

                            final rawUsername = usernameController.text
                                .trim()
                                .toLowerCase()
                                .replaceAll('@', '');
                            if (rawUsername.isNotEmpty) {
                              final validRegex = RegExp(r'^[a-z0-9_]{3,30}$');
                              if (!validRegex.hasMatch(rawUsername)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Username must be 3-30 letters, numbers, or underscores (نام کاربری باید ۳ تا ۳۰ کاراکتر انگلیسی و بدون فاصله باشد)",
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }

                              setModalState(() => isSavingProfile = true);
                              try {
                                final existing = await supabase
                                    .from("profiles")
                                    .select("id")
                                    .eq("username", rawUsername)
                                    .neq("id", user.id)
                                    .maybeSingle();

                                if (existing != null) {
                                  setModalState(() => isSavingProfile = false);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "This username is already taken! این نام کاربری قبلاً انتخاب شده است",
                                      ),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                  return;
                                }
                              } catch (e) {
                                debugPrint("Check username error: $e");
                              }
                            } else {
                              setModalState(() => isSavingProfile = true);
                            }

                            try {
                              final updatePayload = <String, dynamic>{
                                'first_name': firstNameController.text.trim(),
                                'last_name': lastNameController.text.trim(),
                                'father_name': fatherNameController.text.trim(),
                                'phone_number': phoneController.text.trim(),
                                'country': countryController.text.trim(),
                                'date_of_birth':
                                    dobController.text.trim().isEmpty
                                    ? null
                                    : dobController.text.trim(),
                                'bio': bioController.text.trim(),
                                'is_phone_hidden': isPhoneHidden,
                                'is_dob_hidden': isDobHidden,
                                'is_father_name_hidden': isFatherNameHidden,
                                'is_country_hidden': isCountryHidden,
                              };
                              if (rawUsername.isNotEmpty) {
                                updatePayload['username'] = rawUsername;
                              }

                              await supabase
                                  .from("profiles")
                                  .update(updatePayload)
                                  .eq("id", user.id);

                              if (!mounted) return;
                              Navigator.pop(sheetContext);
                              await _fetchProfileAndPosts();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Profile updated successfully! ✅",
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              setModalState(() => isSavingProfile = false);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Error updating profile: $e"),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          },
                    child: isSavingProfile
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            "SAVE CHANGES",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: textGrey, fontSize: 13),
      filled: true,
      fillColor: cardBorder.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: cardBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primaryPink, width: 1.5),
      ),
    );
  }

  Future<void> _handleFriendAction() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;
    setState(() => isActionLoading = true);
    try {
      if (friendshipStatus == 'none') {
        await supabase.from("student_friends").insert({
          'sender_id': currentUser.id,
          'receiver_id': targetUserId,
          'status': 'pending',
        });
        if (!mounted) return;
        setState(() => friendshipStatus = 'pending_sent');
      } else if (friendshipStatus == 'pending_sent' ||
          friendshipStatus == 'friends') {
        await supabase
            .from("student_friends")
            .delete()
            .or(
              "and(sender_id.eq.${currentUser.id},receiver_id.eq.$targetUserId),and(sender_id.eq.$targetUserId,receiver_id.eq.${currentUser.id})",
            );
        if (!mounted) return;
        setState(() => friendshipStatus = 'none');
      } else if (friendshipStatus == 'pending_received') {
        await supabase
            .from("student_friends")
            .update({'status': 'accepted'})
            .or(
              "and(sender_id.eq.$targetUserId,receiver_id.eq.${currentUser.id})",
            );
        if (!mounted) return;
        setState(() => friendshipStatus = 'friends');
      }
    } catch (e) {
      debugPrint("Error handling friendship: $e");
    } finally {
      if (mounted) setState(() => isActionLoading = false);
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      await supabase.from("discussion_posts").delete().eq("id", postId);
      if (!mounted) return;
      setState(
        () => userPosts.removeWhere((p) => p['id'].toString() == postId),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Post deleted successfully.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error deleting post: $e")));
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> post, int index) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    bool currentlyLiked = post['is_liked_by_me'] ?? false;
    int currentLikes = post['likes_count'] ?? 0;

    setState(() {
      if (currentlyLiked) {
        userPosts[index]['is_liked_by_me'] = false;
        userPosts[index]['likes_count'] = (currentLikes > 0)
            ? currentLikes - 1
            : 0;
      } else {
        userPosts[index]['is_liked_by_me'] = true;
        userPosts[index]['likes_count'] = currentLikes + 1;
      }
    });

    try {
      if (currentlyLiked) {
        await supabase
            .from("discussion_likes")
            .delete()
            .eq("post_id", post['id'])
            .eq("student_id", currentUser.id);
      } else {
        await supabase.from("discussion_likes").insert({
          "post_id": post['id'],
          "student_id": currentUser.id,
        });
      }
    } catch (e) {
      _fetchProfileAndPosts();
    }
  }

  void _showPostActionMenu(Map<String, dynamic> post) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 45,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 24),
              InkWell(
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDeleteConfirmation(post['id'].toString());
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        "Delete Post",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: Colors.red,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.red.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(String postId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Delete Post",
          style: TextStyle(fontWeight: FontWeight.w900, color: textDark),
        ),
        content: const Text(
          "Are you sure you want to delete this post? This action cannot be undone.",
          style: TextStyle(color: textGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              "Cancel",
              style: TextStyle(color: textGrey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _deletePost(postId);
            },
            child: const Text(
              "Delete",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openCommentsBottomSheet(String postId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CommentsWidget(
        postId: postId,
        currentUserId: supabase.auth.currentUser?.id ?? '',
      ),
    ).then((_) => _fetchProfileAndPosts());
  }

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveLayout.isPhone(context)) {
      return _buildDesktopWebProfile(context);
    }

    bool isAdmin =
        profileData?['role'] == 'admin' ||
        profileData?['role'] == 'super_admin';
    bool isTeacher =
        profileData?['role'] == 'teacher' ||
        profileData?['role'] == 'instructor';
    Color roleColor = isAdmin ? Colors.deepPurple : primaryPink;
    String? roleLabel = isAdmin ? "OFFICIAL 🛡️" : null;

    return Scaffold(
      backgroundColor: surfaceWhite,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        iconTheme: const IconThemeData(color: textDark),
        title: Text(
          isMyProfile
              ? context.zevTr('myProfile')
              : context.zevTr('zevProfile'),
          style: const TextStyle(
            color: textDark,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        actions: [
          if (isMyProfile)
            IconButton(
              icon: const Icon(
                Icons.settings_outlined,
                color: textDark,
                size: 24,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ZevSettingsScreen()),
                );
              },
            )
          else
            IconButton(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: textDark,
                size: 24,
              ),
              onPressed: () {},
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFFF0F5),
              surfaceWhite,
              lightPinkBg.withValues(alpha: 0.2),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: primaryPink,
                  strokeWidth: 3,
                ),
              )
            : profileData != null
            ? RefreshIndicator(
                color: primaryPink,
                onRefresh: _fetchProfileAndPosts,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: context.responsive(
                          phone: double.infinity,
                          tablet: 850.0,
                          desktop: 960.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Profile info card with cover and avatar
                          Container(
                            decoration: BoxDecoration(
                              color: surfaceWhite,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: roleColor.withValues(alpha: 0.15),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: roleColor.withValues(alpha: 0.08),
                                  blurRadius: 25,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                // Cover section
                                Stack(
                                  children: [
                                    Container(
                                      height: context.responsive(
                                        phone: 180.0,
                                        tablet: 240.0,
                                        desktop: 270.0,
                                      ),
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            roleColor.withValues(alpha: 0.85),
                                            primaryPink,
                                            const Color(0xFF6366F1),
                                          ],
                                        ),
                                      ),
                                      child:
                                          (profileData!['cover_image_url'] ??
                                                      profileData!['cover_url']) !=
                                                  null &&
                                              (profileData!['cover_image_url'] ??
                                                      profileData!['cover_url'])
                                                  .toString()
                                                  .isNotEmpty
                                          ? Image.network(
                                              (profileData!['cover_image_url'] ??
                                                      profileData!['cover_url'])
                                                  .toString(),
                                              width: double.infinity,
                                              height: context.responsive(
                                                phone: 180.0,
                                                tablet: 240.0,
                                                desktop: 270.0,
                                              ),
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => Center(
                                                    child: Icon(
                                                      Icons.landscape_rounded,
                                                      size: 48,
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                    ),
                                                  ),
                                            )
                                          : Center(
                                              child: Icon(
                                                Icons.landscape_rounded,
                                                size: 48,
                                                color: Colors.white.withValues(
                                                  alpha: 0.35,
                                                ),
                                              ),
                                            ),
                                    ),
                                    // Bottom cover gradient
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      height: 50,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black.withValues(
                                                alpha: 0.35,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Change cover button
                                    if (isMyProfile)
                                      Positioned(
                                        top: 14,
                                        right: 14,
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: isCoverUploading
                                                ? null
                                                : _handleCoverUpload,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.65,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.35),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.25,
                                                        ),
                                                    blurRadius: 8,
                                                  ),
                                                ],
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (isCoverUploading)
                                                    const SizedBox(
                                                      width: 13,
                                                      height: 13,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.white,
                                                          ),
                                                    )
                                                  else
                                                    const Icon(
                                                      Icons.camera_alt_rounded,
                                                      size: 14,
                                                      color: Colors.white,
                                                    ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    isCoverUploading
                                                        ? "Uploading..."
                                                        : "Cover Photo",
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),

                                // Avatar and user details section
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    20,
                                  ),
                                  child: Column(
                                    children: [
                                      // Overlapping avatar
                                      Transform.translate(
                                        offset: const Offset(0, -44),
                                        child: Center(
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Container(
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: surfaceWhite,
                                                    width: 4,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.12,
                                                          ),
                                                      blurRadius: 16,
                                                      offset: const Offset(
                                                        0,
                                                        4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: CircleAvatar(
                                                  radius: context.responsive(
                                                    phone: 46.0,
                                                    tablet: 62.0,
                                                    desktop: 68.0,
                                                  ),
                                                  backgroundColor: roleColor
                                                      .withValues(alpha: 0.12),
                                                  backgroundImage:
                                                      profileData!['avatar_url'] !=
                                                              null &&
                                                          profileData!['avatar_url']
                                                              .toString()
                                                              .isNotEmpty
                                                      ? NetworkImage(
                                                          profileData!['avatar_url'],
                                                        )
                                                      : null,
                                                  child:
                                                      profileData!['avatar_url'] ==
                                                              null ||
                                                          profileData!['avatar_url']
                                                              .toString()
                                                              .isEmpty
                                                      ? Text(
                                                          profileData!['first_name'] !=
                                                                      null &&
                                                                  profileData!['first_name']
                                                                      .toString()
                                                                      .isNotEmpty
                                                              ? profileData!['first_name'][0]
                                                              : 'U',
                                                          style: TextStyle(
                                                            color: roleColor,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            fontSize: 28,
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                              ),
                                              // Change avatar button
                                              if (isMyProfile)
                                                Positioned(
                                                  bottom: 2,
                                                  right: 2,
                                                  child: GestureDetector(
                                                    onTap: isAvatarUploading
                                                        ? null
                                                        : _handleAvatarUpload,
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            7,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: primaryPink,
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: surfaceWhite,
                                                          width: 2.5,
                                                        ),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors.black
                                                                .withValues(
                                                                  alpha: 0.2,
                                                                ),
                                                            blurRadius: 6,
                                                          ),
                                                        ],
                                                      ),
                                                      child: isAvatarUploading
                                                          ? const SizedBox(
                                                              width: 14,
                                                              height: 14,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                            )
                                                          : const Icon(
                                                              Icons
                                                                  .camera_alt_rounded,
                                                              size: 14,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // User name and role
                                      Transform.translate(
                                        offset: const Offset(0, -32),
                                        child: Column(
                                          children: [
                                            Text(
                                              "${profileData!['first_name'] ?? ''} ${profileData!['last_name'] ?? ''}"
                                                      .trim()
                                                      .isEmpty
                                                  ? "Safi User"
                                                  : "${profileData!['first_name'] ?? ''} ${profileData!['last_name'] ?? ''}",
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: textDark,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 20,
                                                letterSpacing: -0.3,
                                              ),
                                            ),
                                            if (profileData?['username'] != null &&
                                                profileData!['username'].toString().trim().isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                "@${profileData!['username'].toString().trim().replaceFirst('@', '')}",
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: primaryPink,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ],
                                            if (roleLabel != null) ...[
                                              const SizedBox(height: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: roleColor.withValues(
                                                    alpha: 0.1,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: roleColor.withValues(
                                                      alpha: 0.2,
                                                    ),
                                                  ),
                                                ),
                                                child: Text(
                                                  roleLabel,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w900,
                                                    color: roleColor,
                                                    letterSpacing: 0.4,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (profileData!['bio'] != null &&
                                                profileData!['bio']
                                                    .toString()
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 10),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                    ),
                                                child: Text(
                                                  profileData!['bio'],
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: textGrey,
                                                    fontSize: 12,
                                                    height: 1.4,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 16),
                                            const Divider(
                                              color: cardBorder,
                                              height: 1,
                                            ),
                                            const SizedBox(height: 14),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceAround,
                                              children: [
                                                _buildStatItem(
                                                  context.zevTr('posts'),
                                                  "${userPosts.length + userReels.length}",
                                                  roleColor,
                                                  onTap: () => setState(
                                                    () => activeTab = 0,
                                                  ),
                                                ),
                                                _buildStatItem(
                                                  context.zevTr('followers'),
                                                  "$followersCount",
                                                  roleColor,
                                                  onTap: () =>
                                                      _navigateToFollows(0),
                                                ),
                                                _buildStatItem(
                                                  context.zevTr('following'),
                                                  "$followingCount",
                                                  roleColor,
                                                  onTap: () =>
                                                      _navigateToFollows(1),
                                                ),
                                                if (!isTeacher && !isAdmin)
                                                  _buildStatItem(
                                                    "Score",
                                                    "${profileData!['total_score'] ?? 0}",
                                                    roleColor,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 18),
                                            if (isMyProfile)
                                              SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        lightPinkBg,
                                                    foregroundColor:
                                                        primaryPink,
                                                    elevation: 0,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 14,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                      side: const BorderSide(
                                                        color: primaryPink,
                                                        width: 1,
                                                      ),
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.edit_rounded,
                                                    size: 16,
                                                  ),
                                                  label: const Text(
                                                    "Edit Profile ✏️",
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  onPressed:
                                                      _showEditProfileModal,
                                                ),
                                              )
                                            else
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: ElevatedButton.icon(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            isFollowedByMe
                                                            ? cardBorder
                                                            : primaryPink,
                                                        foregroundColor:
                                                            isFollowedByMe
                                                            ? textDark
                                                            : Colors.white,
                                                        elevation: 0,
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 14,
                                                            ),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                14,
                                                              ),
                                                        ),
                                                      ),
                                                      icon: Icon(
                                                        isFollowedByMe
                                                            ? Icons
                                                                  .check_rounded
                                                            : Icons
                                                                  .person_add_rounded,
                                                        size: 16,
                                                      ),
                                                      label: Text(
                                                        isFollowedByMe
                                                            ? 'Following ✓'
                                                            : 'Follow +',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      onPressed: _toggleFollow,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          lightPinkBg,
                                                      foregroundColor:
                                                          primaryPink,
                                                      elevation: 0,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 14,
                                                            horizontal: 16,
                                                          ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              14,
                                                            ),
                                                        side: const BorderSide(
                                                          color: primaryPink,
                                                          width: 1,
                                                        ),
                                                      ),
                                                    ),
                                                    icon: const Icon(
                                                      Icons
                                                          .chat_bubble_outline_rounded,
                                                      size: 16,
                                                    ),
                                                    label: const Text(
                                                      "Chat 💬",
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    onPressed: () {
                                                      final targetId =
                                                          widget.userId ??
                                                          (profileData != null
                                                              ? profileData!['id']
                                                              : null);
                                                      if (targetId != null) {
                                                        final peerName =
                                                            "${profileData?['first_name'] ?? ''} ${profileData?['last_name'] ?? ''}"
                                                                .trim();
                                                        final peerAvatar =
                                                            profileData?['avatar_url'] ??
                                                            '';
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                DirectChatScreen(
                                                                  peerId:
                                                                      targetId,
                                                                  peerName:
                                                                      peerName
                                                                          .isNotEmpty
                                                                      ? peerName
                                                                      : 'User',
                                                                  peerAvatar:
                                                                      peerAvatar,
                                                                ),
                                                          ),
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Full profile information
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: surfaceWhite,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: cardBorder, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () => setState(
                                    () => isProfileInfoExpanded =
                                        !isProfileInfoExpanded,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: roleColor.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.badge_rounded,
                                            color: roleColor,
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text(
                                            "Profile Information",
                                            style: TextStyle(
                                              color: textDark,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          isProfileInfoExpanded
                                              ? Icons.keyboard_arrow_up_rounded
                                              : Icons
                                                    .keyboard_arrow_down_rounded,
                                          color: textGrey,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (isProfileInfoExpanded) ...[
                                  const SizedBox(height: 16),
                                  _buildInfoRow(
                                    Icons.email_outlined,
                                    "Email Address",
                                    profileData!['email'] ?? 'Not specified',
                                    roleColor,
                                    onCopy: profileData!['email'] != null
                                        ? () {
                                            Clipboard.setData(
                                              ClipboardData(
                                                text: profileData!['email'],
                                              ),
                                            );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  "Email copied! 📋",
                                                ),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        : null,
                                  ),
                                  if (profileData!['father_name'] != null &&
                                      profileData!['father_name'].toString().trim().isNotEmpty &&
                                      (isMyProfile || profileData!['is_father_name_hidden'] != true)) ...[
                                    const SizedBox(height: 10),
                                    _buildInfoRow(
                                      Icons.person_outline_rounded,
                                      "Father's Name",
                                      profileData!['father_name'],
                                      roleColor,
                                      isHidden: profileData!['is_father_name_hidden'] == true,
                                    ),
                                  ],
                                  if (profileData!['phone_number'] != null &&
                                      profileData!['phone_number'].toString().trim().isNotEmpty &&
                                      (isMyProfile || profileData!['is_phone_hidden'] != true)) ...[
                                    const SizedBox(height: 10),
                                    _buildInfoRow(
                                      Icons.phone_outlined,
                                      "Phone Number",
                                      profileData!['phone_number'],
                                      roleColor,
                                      isHidden: profileData!['is_phone_hidden'] == true,
                                    ),
                                  ],
                                  if (isMyProfile || profileData!['is_dob_hidden'] != true) ...[
                                    const SizedBox(height: 10),
                                    _buildInfoRow(
                                      Icons.cake_rounded,
                                      "Date of Birth",
                                      profileData!['date_of_birth'] ??
                                          'Not specified',
                                      roleColor,
                                      isHidden: profileData!['is_dob_hidden'] == true,
                                    ),
                                  ],
                                  if (isMyProfile || profileData!['is_country_hidden'] != true) ...[
                                    const SizedBox(height: 10),
                                    _buildInfoRow(
                                      Icons.public_rounded,
                                      "Country",
                                      profileData!['country'] ?? 'Global',
                                      roleColor,
                                      isHidden: profileData!['is_country_hidden'] == true,
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  _buildInfoRow(
                                    Icons.bolt_rounded,
                                    "Total Score",
                                    "${profileData!['total_score'] ?? 0} XP",
                                    roleColor,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildInfoRow(
                                    Icons.qr_code_rounded,
                                    "Referral Code",
                                    profileData!['referral_code'] ?? 'N/A',
                                    roleColor,
                                    onCopy:
                                        profileData!['referral_code'] != null
                                        ? () {
                                            Clipboard.setData(
                                              ClipboardData(
                                                text:
                                                    profileData!['referral_code'],
                                              ),
                                            );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  "Referral code copied! 📋",
                                                ),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        : null,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildInfoRow(
                                    Icons.calendar_today_rounded,
                                    "Joined",
                                    profileData!['created_at'] != null
                                        ? profileData!['created_at']
                                              .toString()
                                              .split('T')[0]
                                        : 'N/A',
                                    roleColor,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Tab selector (Posts / Reels)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                _buildTabPill(
                                  index: 0,
                                  label:
                                      "${context.zevTr('posts')} (${userPosts.length})",
                                  icon: Icons.grid_on_rounded,
                                ),
                                const SizedBox(width: 8),
                                _buildTabPill(
                                  index: 1,
                                  label:
                                      "${context.zevTr('reels')} (${userReels.length})",
                                  icon: Icons.play_circle_outline_rounded,
                                ),
                                if (isMyProfile) ...[
                                  const SizedBox(width: 8),
                                  _buildTabPill(
                                    index: 2,
                                    label:
                                        "${context.zevTr('liked')} (${userLikedReels.length})",
                                    icon: Icons.favorite_rounded,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildTabPill(
                                    index: 3,
                                    label:
                                        "${context.zevTr('saved')} (${userSavedReels.length + userSavedPosts.length})",
                                    icon: Icons.bookmark_rounded,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (activeTab == 0) ...[
                            userPosts.isNotEmpty
                                ? ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: userPosts.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 16),
                                    itemBuilder: (context, index) {
                                      final post = userPosts[index];
                                      final rawTitle = post['title'] ?? '';
                                      final moodTag = _extractMood(rawTitle);
                                      final cleanTitle = _extractCleanTitle(
                                        rawTitle,
                                      );
                                      final imageUrl = post['image_url'];

                                      return Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: surfaceWhite,
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          border: Border.all(
                                            color: cardBorder,
                                            width: 1.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.02,
                                              ),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  post['created_at']
                                                          ?.toString()
                                                          .split('T')[0] ??
                                                      '',
                                                  style: const TextStyle(
                                                    color: textGrey,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                if (isMyProfile)
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.more_horiz_rounded,
                                                      color: textGrey,
                                                    ),
                                                    onPressed: () =>
                                                        _showPostActionMenu(
                                                          post,
                                                        ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),

                                            // Vibe / Mode tag
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: lightPinkBg,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                moodTag,
                                                style: const TextStyle(
                                                  color: primaryPink,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 10),

                                            if (cleanTitle.isNotEmpty) ...[
                                              Text(
                                                cleanTitle,
                                                style: const TextStyle(
                                                  color: textDark,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                            ],
                                            Text(
                                              post['content'] ?? '',
                                              style: const TextStyle(
                                                color: textGrey,
                                                fontSize: 13,
                                                height: 1.4,
                                              ),
                                            ),

                                            // Post image display with loading placeholder
                                            if (imageUrl != null &&
                                                imageUrl
                                                    .toString()
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 14),
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                child: Container(
                                                  constraints: BoxConstraints(
                                                    maxHeight:
                                                        MediaQuery.of(
                                                          context,
                                                        ).size.height *
                                                        0.35,
                                                  ),
                                                  width: double.infinity,
                                                  color: Colors.grey.shade100,
                                                  child: Image.network(
                                                    imageUrl.toString(),
                                                    fit: BoxFit.cover,
                                                    loadingBuilder:
                                                        (
                                                          context,
                                                          child,
                                                          loadingProgress,
                                                        ) {
                                                          if (loadingProgress ==
                                                              null) {
                                                            return child;
                                                          }
                                                          return Container(
                                                            height: 180,
                                                            alignment: Alignment
                                                                .center,
                                                            child: Column(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                const CircularProgressIndicator(
                                                                  color:
                                                                      primaryPink,
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                                const SizedBox(
                                                                  height: 6,
                                                                ),
                                                                Text(
                                                                  "Loading image...",
                                                                  style: TextStyle(
                                                                    color:
                                                                        textGrey,
                                                                    fontSize:
                                                                        10,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                        },
                                                    errorBuilder: (context, error, stackTrace) {
                                                      return Container(
                                                        height: 140,
                                                        alignment:
                                                            Alignment.center,
                                                        color: Colors
                                                            .grey
                                                            .shade200,
                                                        child: const Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .broken_image_rounded,
                                                              color: textGrey,
                                                              size: 28,
                                                            ),
                                                            SizedBox(height: 4),
                                                            Text(
                                                              "Image failed to load",
                                                              style: TextStyle(
                                                                color: textGrey,
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ],

                                            const SizedBox(height: 12),
                                            const Divider(color: cardBorder),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceAround,
                                              children: [
                                                InkWell(
                                                  onTap: () =>
                                                      _toggleLike(post, index),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 6,
                                                          horizontal: 12,
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          (post['is_liked_by_me'] ??
                                                                  false)
                                                              ? Icons
                                                                    .thumb_up_rounded
                                                              : Icons
                                                                    .thumb_up_outlined,
                                                          color:
                                                              (post['is_liked_by_me'] ??
                                                                  false)
                                                              ? primaryPink
                                                              : textGrey,
                                                          size: 18,
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Text(
                                                          "${post['likes_count'] ?? 0} Likes",
                                                          style: TextStyle(
                                                            color:
                                                                (post['is_liked_by_me'] ??
                                                                    false)
                                                                ? primaryPink
                                                                : textGrey,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () =>
                                                      _openCommentsBottomSheet(
                                                        post['id'].toString(),
                                                      ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 6,
                                                          horizontal: 12,
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          Icons
                                                              .mode_comment_outlined,
                                                          color: textGrey,
                                                          size: 18,
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Text(
                                                          "${post['comments_count'] ?? 0} Comments",
                                                          style:
                                                              const TextStyle(
                                                                color: textGrey,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    padding: const EdgeInsets.all(30),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: surfaceWhite,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: cardBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const Text(
                                      "No posts shared by this user yet.",
                                      style: TextStyle(
                                        color: textGrey,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ] else if (activeTab == 1) ...[
                            userReels.isNotEmpty
                                ? ZevReelsPreviewGrid(
                                    reels: userReels,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    onReelTap: (reel, index) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => StudentReelsScreen(
                                            targetReelId: reel['id']
                                                ?.toString(),
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    padding: const EdgeInsets.all(30),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: surfaceWhite,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: cardBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const Text(
                                      "No educational reels shared by this user yet.",
                                      style: TextStyle(
                                        color: textGrey,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ] else if (isMyProfile && activeTab == 2) ...[
                            // Liked reels (Liked Videos)
                            userLikedReels.isNotEmpty
                                ? ZevReelsPreviewGrid(
                                    reels: userLikedReels,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    onReelTap: (reel, index) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => StudentReelsScreen(
                                            targetReelId: reel['id']
                                                ?.toString(),
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    padding: const EdgeInsets.all(36),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: surfaceWhite,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: cardBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.favorite_border_rounded,
                                          size: 40,
                                          color: textGrey.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        const Text(
                                          "No liked videos yet ❤️",
                                          style: TextStyle(
                                            color: textGrey,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ] else if (isMyProfile && activeTab == 3) ...[
                            // Saved items section (Saved Items)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ChoiceChip(
                                  label: Text(
                                    "Reels (${userSavedReels.length})",
                                  ),
                                  selected: activeSavedSubTab == 0,
                                  selectedColor: primaryPink.withValues(
                                    alpha: 0.15,
                                  ),
                                  onSelected: (_) =>
                                      setState(() => activeSavedSubTab = 0),
                                  labelStyle: TextStyle(
                                    color: activeSavedSubTab == 0
                                        ? primaryPink
                                        : textGrey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: Text(
                                    "Posts (${userSavedPosts.length})",
                                  ),
                                  selected: activeSavedSubTab == 1,
                                  selectedColor: primaryPink.withValues(
                                    alpha: 0.15,
                                  ),
                                  onSelected: (_) =>
                                      setState(() => activeSavedSubTab = 1),
                                  labelStyle: TextStyle(
                                    color: activeSavedSubTab == 1
                                        ? primaryPink
                                        : textGrey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (activeSavedSubTab == 0) ...[
                              userSavedReels.isNotEmpty
                                  ? ZevReelsPreviewGrid(
                                      reels: userSavedReels,
                                      crossAxisCount: 3,
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.all(36),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: surfaceWhite,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: cardBorder,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.bookmark_border_rounded,
                                            size: 40,
                                            color: textGrey.withValues(
                                              alpha: 0.4,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          const Text(
                                            "No saved reels yet 🔖",
                                            style: TextStyle(
                                              color: textGrey,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ] else ...[
                              userSavedPosts.isNotEmpty
                                  ? ListView.separated(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: userSavedPosts.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 12),
                                      itemBuilder: (context, index) {
                                        final post = userSavedPosts[index];
                                        return Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: surfaceWhite,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: cardBorder,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                post['title'] ?? 'Untitled',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: textDark,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                post['content'] ?? '',
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: textGrey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      padding: const EdgeInsets.all(36),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: surfaceWhite,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: cardBorder,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.bookmark_border_rounded,
                                            size: 40,
                                            color: textGrey.withValues(
                                              alpha: 0.4,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          const Text(
                                            "No saved posts yet 🔖",
                                            style: TextStyle(
                                              color: textGrey,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : const Center(
                child: Text(
                  "Profile not found.",
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildTabPill({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSelected = activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => activeTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryPink : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryPink : Colors.grey[300]!,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryPink.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.white : textGrey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : textGrey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchFollowMembers({
    required bool isFollowers,
  }) async {
    try {
      final targetId = targetUserId;
      if (targetId.isEmpty) return [];

      List<String> targetUserIds = [];

      try {
        if (isFollowers) {
          final res = await supabase
              .from('user_follows')
              .select('follower_id')
              .eq('following_id', targetId);
          for (var item in (res as List)) {
            final id = item['follower_id']?.toString();
            if (id != null && id.isNotEmpty) targetUserIds.add(id);
          }
        } else {
          final res = await supabase
              .from('user_follows')
              .select('following_id')
              .eq('follower_id', targetId);
          for (var item in (res as List)) {
            final id = item['following_id']?.toString();
            if (id != null && id.isNotEmpty) targetUserIds.add(id);
          }
        }
      } catch (_) {
        // Fallback to student_friends
        final res = await supabase
            .from('student_friends')
            .select('sender_id, receiver_id')
            .or('sender_id.eq.$targetId,receiver_id.eq.$targetId')
            .eq('status', 'accepted');
        for (var f in (res as List)) {
          final sId = f['sender_id']?.toString();
          final rId = f['receiver_id']?.toString();
          final other = (sId == targetId) ? rId : sId;
          if (other != null &&
              other.isNotEmpty &&
              !targetUserIds.contains(other)) {
            targetUserIds.add(other);
          }
        }
      }

      if (targetUserIds.isEmpty) return [];

      final profilesRes = await supabase
          .from('profiles')
          .select('id, first_name, last_name, avatar_url, role, bio')
          .inFilter('id', targetUserIds);

      return List<Map<String, dynamic>>.from(profilesRes as List);
    } catch (e) {
      debugPrint("Error fetching follow members: $e");
      return [];
    }
  }

  void _navigateToFollows(int initialTab) {
    final name = profileData != null
        ? "${profileData!['first_name'] ?? ''} ${profileData!['last_name'] ?? ''}"
              .trim()
        : '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserFollowsListScreen(
          targetUserId: targetUserId,
          targetUserName: name.isNotEmpty ? name : "Connections",
          initialTabIndex: initialTab,
        ),
      ),
    ).then((_) {
      if (mounted) _fetchProfileAndPosts();
    });
  }

  void _showFollowListModal({required bool isFollowers}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final title = isFollowers
            ? "Followers ($followersCount)"
            : "Following ($followingCount)";

        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: textGrey),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(color: cardBorder, height: 1),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchFollowMembers(isFollowers: isFollowers),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: primaryPink),
                      );
                    }
                    final members = snapshot.data ?? [];
                    if (members.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isFollowers
                                  ? Icons.group_off_rounded
                                  : Icons.person_search_rounded,
                              size: 48,
                              color: textGrey.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isFollowers
                                  ? "No followers yet"
                                  : "Not following anyone yet",
                              style: const TextStyle(
                                color: textGrey,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: members.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: cardBorder, height: 1),
                      itemBuilder: (context, i) {
                        final m = members[i];
                        final mName =
                            "${m['first_name'] ?? ''} ${m['last_name'] ?? ''}"
                                .trim();
                        final mAvatar = m['avatar_url'] ?? '';
                        final mRole = m['role'] ?? 'student';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: lightPinkBg,
                            backgroundImage: mAvatar.isNotEmpty
                                ? NetworkImage(mAvatar)
                                : null,
                            child: mAvatar.isEmpty
                                ? const Icon(Icons.person, color: primaryPink)
                                : null,
                          ),
                          title: Text(
                            mName.isNotEmpty ? mName : 'User',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            mRole.toString().toUpperCase(),
                            style: const TextStyle(
                              color: textGrey,
                              fontSize: 11,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: textGrey,
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            if (m['id'] != targetUserId) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => UserProfileScreen(
                                    userId: m['id'].toString(),
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchNetworkMembers() async {
    final targetId = widget.userId ?? supabase.auth.currentUser?.id;
    if (targetId == null) return [];

    try {
      final res = await supabase
          .from('student_friends')
          .select('sender_id, receiver_id, status')
          .or('sender_id.eq.$targetId,receiver_id.eq.$targetId')
          .eq('status', 'accepted');

      final List<String> otherUserIds = [];
      for (var f in (res as List)) {
        final sId = f['sender_id']?.toString();
        final rId = f['receiver_id']?.toString();
        final other = (sId == targetId) ? rId : sId;
        if (other != null &&
            other.isNotEmpty &&
            !otherUserIds.contains(other)) {
          otherUserIds.add(other);
        }
      }

      if (otherUserIds.isEmpty) return [];

      final profilesRes = await supabase
          .from('profiles')
          .select('id, full_name, first_name, last_name, avatar_url, role, bio')
          .inFilter('id', otherUserIds);

      return List<Map<String, dynamic>>.from(profilesRes as List);
    } catch (e) {
      debugPrint("Error fetching network members: $e");
      return [];
    }
  }

  void _showNetworkMembersModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final displayName =
            profileData?['full_name'] ??
            "${profileData?['first_name'] ?? ''} ${profileData?['last_name'] ?? ''}"
                .trim();

        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "${displayName.isNotEmpty ? displayName : 'User'}'s Network ($friendsCount)",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: textGrey),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(color: cardBorder, height: 1),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchNetworkMembers(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: primaryPink),
                      );
                    }
                    if (snapshot.hasError ||
                        snapshot.data == null ||
                        snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text(
                          "No network connections found.",
                          style: TextStyle(
                            color: textGrey,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }
                    final members = snapshot.data!;
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: members.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final member = members[index];
                        final mName =
                            member['full_name'] ??
                            "${member['first_name'] ?? ''} ${member['last_name'] ?? ''}"
                                .trim();
                        final mAvatar = member['avatar_url'] ?? '';
                        final mRole = member['role'] ?? 'Student';
                        final mBio = member['bio'] ?? '';
                        final mId = member['id']?.toString() ?? '';

                        return InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            if (mId != widget.userId) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      UserProfileScreen(userId: mId),
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: lightPinkBg.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: cardBorder, width: 1.5),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: primaryPink.withValues(
                                    alpha: 0.15,
                                  ),
                                  backgroundImage: mAvatar.isNotEmpty
                                      ? NetworkImage(mAvatar)
                                      : null,
                                  child: mAvatar.isEmpty
                                      ? const Icon(
                                          Icons.person,
                                          color: primaryPink,
                                          size: 24,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mName.isNotEmpty ? mName : 'ZEV User',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                          color: textDark,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        mBio.isNotEmpty
                                            ? mBio
                                            : mRole.toString().toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: textGrey,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 14,
                                  color: textGrey,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    final item = Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: context.respFont(
              phone: 16.0,
              tablet: 21.0,
              desktop: 23.0,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: textGrey,
            fontWeight: FontWeight.w900,
            fontSize: context.respFont(phone: 9.0, tablet: 11.5, desktop: 12.0),
          ),
        ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: item,
        ),
      );
    }
    return item;
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
    Color color, {
    VoidCallback? onCopy,
    bool isHidden = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: lightPinkBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: textGrey,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isHidden) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "Hidden 🔒",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (onCopy != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onCopy,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.copy_rounded, size: 16, color: color),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =====================================================================
  // DESKTOP & WEB LUXURY ACADEMY PROFILE
  // =====================================================================
  String get _joinedDateStr {
    try {
      final raw = profileData?['created_at']?.toString();
      if (raw != null && raw.isNotEmpty) {
        final dt = DateTime.parse(raw);
        return '${dt.month}/${dt.day}/${dt.year}';
      }
    } catch (_) {}
    return '9/21/2026';
  }

  String get _locationStr {
    final loc = profileData?['location'] ?? profileData?['country'];
    if (loc != null && loc.toString().trim().isNotEmpty) {
      return loc.toString().trim();
    }
    return 'France';
  }

  String get _emailStr {
    final em = profileData?['email'] ?? supabase.auth.currentUser?.email;
    if (em != null && em.toString().trim().isNotEmpty) {
      return em.toString().trim();
    }
    return 'ssafi0241@gmail.com';
  }

  String get _birthDateStr {
    final bd = profileData?['birth_date'] ?? profileData?['birthday'];
    if (bd != null && bd.toString().trim().isNotEmpty) {
      return bd.toString().trim();
    }
    return '4/12/2003';
  }

  String get _walletStr {
    final w = profileData?['wallet_balance'] ?? profileData?['balance'];
    if (w != null) {
      return '\$$w';
    }
    return '\$0';
  }

  String get _refCodeStr {
    final rc = profileData?['referral_code'] ?? profileData?['ref_code'];
    if (rc != null && rc.toString().trim().isNotEmpty) {
      return rc.toString().trim();
    }
    return 'SA-C04C5C';
  }

  Widget _buildDesktopWebProfile(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fullName =
        "${profileData?['first_name'] ?? ''} ${profileData?['last_name'] ?? ''}"
            .trim();
    final displayName = fullName.isEmpty ? "Shaheen Safi" : fullName;
    final email = (profileData?['email'] ?? '').toString();
    final handle = email.isNotEmpty ? email.split('@')[0] : 'shaheensafi';

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF090A0E)
          : const Color(0xFFF8FAFC),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFC466B)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top header: Back button + Profile user name + @handle
                      Row(
                        children: [
                          InkWell(
                            onTap: () {
                              if (Navigator.canPop(context)) {
                                Navigator.pop(context);
                              } else {
                                widget.onExit?.call();
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF14161F)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.08)
                                      : Colors.black.withOpacity(0.08),
                                ),
                                boxShadow: isDark
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.04),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                              ),
                              child: Icon(
                                Icons.arrow_back_rounded,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '@$handle',
                                style: const TextStyle(
                                  color: Color(0xFFFC466B),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Banner Card
                      _buildWebBanner(),
                      const SizedBox(height: 24),

                      // 2-Column Section
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column
                          _buildWebLeftColumn(),
                          const SizedBox(width: 24),
                          // Right Column
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildWebTabPills(),
                                const SizedBox(height: 16),
                                _buildWebContentCard(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildWebBanner() {
    final coverUrl =
        (profileData?['cover_image_url'] ?? profileData?['cover_url'])
            ?.toString();
    final fullName =
        "${profileData?['first_name'] ?? ''} ${profileData?['last_name'] ?? ''}"
            .trim();
    final displayName = fullName.isEmpty ? "Shaheen Safi" : fullName;

    return Container(
      height: 280,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFC466B),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFC466B).withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cover Image or Signature ZEV Brand Gradient Banner
            if (coverUrl != null && coverUrl.isNotEmpty)
              Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildDefaultBrandBanner(),
              )
            else
              _buildDefaultBrandBanner(),

            // Gradient vignette for text contrast
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.08),
                    Colors.black.withOpacity(0.72),
                  ],
                ),
              ),
            ),

            // Change Cover button at top right
            if (isMyProfile)
              Positioned(
                top: 18,
                right: 18,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isCoverUploading ? null : _handleCoverUpload,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCoverUploading)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          else
                            const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.white,
                              size: 14,
                            ),
                          const SizedBox(width: 6),
                          Text(
                            isCoverUploading
                                ? context.zevTr('uploading')
                                : context.zevTr('changeCover'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Bottom Left: Squircle Avatar + Verified Badge + User Name + Stats Row
            Positioned(
              bottom: 24,
              left: 28,
              right: 28,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Squircle Avatar
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFC466B), Color(0xFFFF758C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFC466B).withOpacity(0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(3),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(21),
                          child:
                              (profileData?['avatar_url'] != null &&
                                  profileData!['avatar_url']
                                      .toString()
                                      .isNotEmpty)
                              ? Image.network(
                                  profileData!['avatar_url'].toString(),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      _buildAvatarInitial(displayName),
                                )
                              : _buildAvatarInitial(displayName),
                        ),
                      ),
                      // Blue verified shield badge
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.verified_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  // Name and Stats
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            shadows: [
                              Shadow(
                                color: Colors.black38,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Stats Row: FOLLOWERS | FOLLOWING | POSTS
                        Row(
                          children: [
                            _buildWebStatItem(
                              followersCount.toString(),
                              context.zevTr('followers').toUpperCase(),
                              onTap: () => _navigateToFollows(0),
                            ),
                            const SizedBox(width: 18),
                            _buildWebStatItem(
                              followingCount.toString(),
                              context.zevTr('following').toUpperCase(),
                              onTap: () => _navigateToFollows(1),
                            ),
                            const SizedBox(width: 18),
                            _buildWebStatItem(
                              (userPosts.length + userReels.length).toString(),
                              context.zevTr('posts').toUpperCase(),
                              onTap: () => setState(() => activeTab = 0),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultBrandBanner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFC466B),
            Color(0xFFFF5E7E),
            Color(0xFFFF7E95),
            Color(0xFFFF8E53),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Ambient soft glowing orbs
          Positioned(
            top: -40,
            right: 40,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: 200,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          // ZEV Brand Monogram / Watermark
          Positioned(
            right: 36,
            top: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.2),
                    border: Border.all(color: Colors.white.withOpacity(0.35)),
                  ),
                  child: const Center(
                    child: Text(
                      'Z',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'ZEV SOCIAL',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarInitial(String displayName) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'Z';
    return Container(
      color: const Color(0xFFFC466B),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 34,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildWebStatItem(String count, String label, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              count,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebLeftColumn() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bio = profileData?['bio']?.toString() ?? '';
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                color: Color(0xFFFC466B),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                context.zevTr('biography').toUpperCase(),
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14161F) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.06),
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Text(
              bio.isNotEmpty ? bio : context.zevTr('noBioProvided'),
              style: TextStyle(
                color: isDark
                    ? Colors.white.withOpacity(0.7)
                    : const Color(0xFF475569),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildWebMetaCard(
            icon: Icons.location_on_outlined,
            title: context.zevTr('location'),
            value: _locationStr,
          ),
          const SizedBox(height: 10),
          _buildWebMetaCard(
            icon: Icons.calendar_today_rounded,
            title: context.zevTr('joined'),
            value: _joinedDateStr,
          ),
          const SizedBox(height: 10),
          _buildWebMetaCard(
            icon: Icons.email_outlined,
            title: context.zevTr('email'),
            value: _emailStr,
            showRedDot: true,
          ),
          const SizedBox(height: 10),
          _buildWebMetaCard(
            icon: Icons.cake_outlined,
            title: context.zevTr('birthDate'),
            value: _birthDateStr,
            showRedDot: true,
          ),
          const SizedBox(height: 10),
          _buildWebMetaCard(
            icon: Icons.account_balance_wallet_outlined,
            title: context.zevTr('wallet'),
            value: _walletStr,
            showRedDot: true,
          ),
          const SizedBox(height: 10),
          _buildWebMetaCard(
            icon: Icons.share_rounded,
            title: context.zevTr('refCode'),
            value: _refCodeStr,
            showRedDot: true,
          ),
        ],
      ),
    );
  }

  Widget _buildWebMetaCard({
    required IconData icon,
    required String title,
    required String value,
    bool showRedDot = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161F) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.06),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFC466B), size: 18),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: isDark
                        ? Colors.white.withOpacity(0.35)
                        : const Color(0xFF94A3B8),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (showRedDot)
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFFC466B),
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebTabPills() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tabs = [
      {
        'id': 'posts',
        'title': context.zevTr('posts').toUpperCase(),
        'icon': Icons.chat_bubble_outline_rounded,
      },
      {
        'id': 'reels',
        'title': context.zevTr('reels').toUpperCase(),
        'icon': Icons.smart_display_outlined,
      },
      if (isMyProfile)
        {
          'id': 'liked',
          'title': context.zevTr('liked').toUpperCase(),
          'icon': Icons.favorite_border_rounded,
        },
      {
        'id': 'reposts',
        'title': context.zevTr('reposts').toUpperCase(),
        'icon': Icons.repeat_rounded,
      },
      if (isMyProfile)
        {
          'id': 'saved',
          'title': context.zevTr('saved').toUpperCase(),
          'icon': Icons.bookmark_border_rounded,
        },
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(tabs.length, (i) {
          final t = tabs[i];
          final tabId = t['id'] as String;
          final isSelected = activeWebTab == tabId;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: InkWell(
              onTap: () => setState(() => activeWebTab = tabId),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [Color(0xFFFC466B), Color(0xFFFF5E7E)],
                        )
                      : null,
                  color: isSelected
                      ? null
                      : (isDark ? const Color(0xFF14161F) : Colors.white),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? Colors.transparent
                        : (isDark
                              ? Colors.white.withOpacity(0.06)
                              : Colors.black.withOpacity(0.08)),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFC466B).withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : (isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      t['icon'] as IconData,
                      size: 14,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                                ? Colors.white.withOpacity(0.6)
                                : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t['title'] as String,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                  ? Colors.white.withOpacity(0.7)
                                  : const Color(0xFF334155)),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildWebContentCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 450),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10121A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.06),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      padding: const EdgeInsets.all(24),
      child: _buildWebContentForTab(),
    );
  }

  Widget _buildWebContentForTab() {
    if (activeWebTab == 'posts') {
      if (userPosts.isEmpty) {
        return _buildWebEmptyState(
          icon: Icons.chat_bubble_outline_rounded,
          title: context.zevTr('noPostsYet'),
          subtitle: context.zevTr('noPostsYetSub'),
        );
      }
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: userPosts.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final post = userPosts[index];
          return _buildWebPostCard(post, index);
        },
      );
    } else if (activeWebTab == 'reels') {
      if (userReels.isEmpty) {
        return _buildWebEmptyState(
          icon: Icons.smart_display_outlined,
          title: context.zevTr('noReels'),
          subtitle: context.zevTr('noReelsSub'),
        );
      }
      return ZevReelsPreviewGrid(
        reels: userReels,
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
      );
    } else if (activeWebTab == 'liked') {
      if (!isMyProfile) {
        return _buildWebEmptyState(
          icon: Icons.lock_outline_rounded,
          title: context.zevTr('privateSection'),
          subtitle: context.zevTr('onlyYouCanSee'),
        );
      }
      if (userLikedReels.isEmpty) {
        return _buildWebEmptyState(
          icon: Icons.favorite_border_rounded,
          title: context.zevTr('noLikedContent'),
          subtitle: context.zevTr('noLikedContentSub'),
        );
      }
      return ZevReelsPreviewGrid(
        reels: userLikedReels,
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
      );
    } else if (activeWebTab == 'reposts') {
      if (userReposts.isEmpty) {
        return _buildWebEmptyState(
          icon: Icons.repeat_rounded,
          title: context.zevTr('noReposts'),
          subtitle: context.zevTr('noRepostsSub'),
        );
      }
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: userReposts.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final post = userReposts[index];
          return _buildWebPostCard(post, index, isRepost: true);
        },
      );
    } else if (activeWebTab == 'saved') {
      if (!isMyProfile) {
        return _buildWebEmptyState(
          icon: Icons.lock_outline_rounded,
          title: context.zevTr('privateSection'),
          subtitle: context.zevTr('onlyYouCanSee'),
        );
      }
      final totalSaved = userSavedReels.length + userSavedPosts.length;
      if (totalSaved == 0) {
        return _buildWebEmptyState(
          icon: Icons.bookmark_border_rounded,
          title: context.zevTr('noSavedItems'),
          subtitle: context.zevTr('noSavedItemsSub'),
        );
      }
      return ZevReelsPreviewGrid(
        reels: userSavedReels,
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildWebPostCard(
    Map<String, dynamic> post,
    int index, {
    bool isRepost = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rawTitle = post['title'] ?? '';
    final moodTag = _extractMood(rawTitle);
    final cleanTitle = _extractCleanTitle(rawTitle);
    final imageUrl = post['image_url'];
    final bool isLiked = post['is_liked_by_me'] ?? false;
    final int likesCount = post['likes_count'] ?? 0;
    final int commentsCount = post['comments_count'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161F) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.06),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isRepost) ...[
            Row(
              children: const [
                Icon(Icons.repeat_rounded, color: Color(0xFFFC466B), size: 14),
                SizedBox(width: 6),
                Text(
                  'Reposted',
                  style: TextStyle(
                    color: Color(0xFFFC466B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFC466B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  moodTag,
                  style: const TextStyle(
                    color: Color(0xFFFC466B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                post['created_at']?.toString().split('T')[0] ?? '',
                style: TextStyle(
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            cleanTitle,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (post['content'] != null &&
              post['content'].toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              post['content'].toString(),
              style: TextStyle(
                color: isDark
                    ? Colors.white.withOpacity(0.7)
                    : const Color(0xFF475569),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          if (imageUrl != null && imageUrl.toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl.toString(),
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              InkWell(
                onTap: () => _toggleLike(post, index),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isLiked
                            ? const Color(0xFFFC466B)
                            : (isDark
                                  ? Colors.white54
                                  : const Color(0xFF94A3B8)),
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$likesCount',
                        style: TextStyle(
                          color: isLiked
                              ? const Color(0xFFFC466B)
                              : (isDark
                                    ? Colors.white70
                                    : const Color(0xFF64748B)),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$commentsCount',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: isDark
                  ? Colors.white.withOpacity(0.22)
                  : const Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1E293B),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: isDark
                    ? Colors.white.withOpacity(0.4)
                    : const Color(0xFF64748B),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Comments widget in profile
// =====================================================================
class _CommentsWidget extends StatefulWidget {
  final String postId;
  final String currentUserId;

  const _CommentsWidget({required this.postId, required this.currentUserId});

  @override
  State<_CommentsWidget> createState() => _CommentsWidgetState();
}

class _CommentsWidgetState extends State<_CommentsWidget> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  bool isSending = false;
  List<Map<String, dynamic>> comments = [];

  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  String? replyingToCommentId;
  String? replyingToName;

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

      Set<String> studentIds = fetchedComments
          .map((c) => c['student_id'].toString())
          .toSet();
      Map<String, Map<String, dynamic>> profilesMap = {};

      for (String sId in studentIds) {
        try {
          final p = await supabase
              .from("profiles")
              .select("first_name, last_name, avatar_url")
              .eq("id", sId)
              .maybeSingle();
          if (p != null) profilesMap[sId] = p;
        } catch (_) {}
      }

      for (var c in fetchedComments) {
        String sId = c['student_id'].toString();
        c['profiles'] =
            profilesMap[sId] ??
            {'first_name': 'User', 'last_name': '', 'avatar_url': ''};
      }

      if (mounted) {
        setState(() {
          comments = fetchedComments;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _sendComment() async {
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

      if (!mounted) return;
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

      commentWidgets.add(
        Padding(
          padding: EdgeInsets.only(left: leftPadding, bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFFAF4F6),
                backgroundImage:
                    c['profiles']?['avatar_url'] != null &&
                        c['profiles']?['avatar_url'] != ''
                    ? NetworkImage(c['profiles']['avatar_url'])
                    : null,
                child:
                    c['profiles']?['avatar_url'] == null ||
                        c['profiles']?['avatar_url'] == ''
                    ? const Icon(
                        Icons.person,
                        size: 16,
                        color: Color(0xFFFC466B),
                      )
                    : null,
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
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c['comment_text'] ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(
                        children: [
                          Text(
                            c['created_at']?.toString().split('T')[0] ?? '',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () => _startReplying(cId, authorName),
                            child: const Text(
                              "Reply",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      double nextPadding = leftPadding + 36;
      if (nextPadding > 72) nextPadding = 72;
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
                    child: CircularProgressIndicator(color: Color(0xFFFC466B)),
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
                  color: Colors.black.withValues(alpha: 0.05),
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
                            color: Color(0xFFFC466B),
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
                        cursorColor: const Color(0xFFFC466B),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: replyingToName != null
                              ? "Write a reply..."
                              : "Add a comment...",
                          hintStyle: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
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
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFFC466B),
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
                                size: 18,
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
