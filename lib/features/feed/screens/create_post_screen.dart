import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/hashtag_service.dart';
import '../../../core/utils/app_media_picker.dart';

class CreatePostScreen extends StatefulWidget {
  final VoidCallback? onPostSuccess;
  final VoidCallback? onCancel;
  const CreatePostScreen({super.key, this.onPostSuccess, this.onCancel});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final supabase = Supabase.instance.client;
  bool isLoadingProfile = true;
  bool isPosting = false;
  AppPickedMedia? _selectedMedia;
  Map<String, dynamic>? userProfile;
  String userName = "";
  String userAvatar = "";
  String userRole = "Student";

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  List<HashtagItem> _trendingHashtags = [];
  List<HashtagItem> _hashtagSuggestions = [];
  bool _showHashtagDropdown = false;
  String _activeTagQuery = '';

  String selectedMood = "🚀 Excited";
  final List<String> moods = [
    "🚀 Excited",
    "🌟 Explore",
    "💡 Learning",
    "📊 Analysis",
    "🔥 Motivated",
    "📢 Announcement",
  ];

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  bool _isRtlText(String text) {
    if (text.isEmpty) return false;
    final rtlRegex = RegExp(
      r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
    );
    return rtlRegex.hasMatch(text);
  }

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserProfile();
    _loadTrendingHashtags();
    _contentController.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    _contentController.removeListener(_onContentChanged);
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadTrendingHashtags() async {
    try {
      final tags = await HashtagService.instance.getTrendingHashtags(limit: 12);
      if (mounted) {
        setState(() {
          _trendingHashtags = tags;
        });
      }
    } catch (_) {}
  }

  void _onContentChanged() {
    final text = _contentController.text;
    final sel = _contentController.selection;
    if (sel.baseOffset < 0 || sel.baseOffset > text.length) {
      if (_showHashtagDropdown) setState(() => _showHashtagDropdown = false);
      return;
    }

    final beforeCursor = text.substring(0, sel.baseOffset);
    final lastHashIndex = beforeCursor.lastIndexOf('#');

    if (lastHashIndex != -1) {
      final tagSub = beforeCursor.substring(lastHashIndex + 1);
      // Only search if there are no spaces or newlines after '#'
      if (!tagSub.contains(' ') && !tagSub.contains('\n')) {
        _activeTagQuery = tagSub.trim().toLowerCase();
        _queryHashtags(_activeTagQuery);
        return;
      }
    }

    if (_showHashtagDropdown) {
      setState(() => _showHashtagDropdown = false);
    }
  }

  Future<void> _queryHashtags(String query) async {
    final results = await HashtagService.instance.searchHashtags(query, limit: 8);
    if (!mounted) return;
    setState(() {
      _hashtagSuggestions = results;
      _showHashtagDropdown = results.isNotEmpty;
    });
  }

  void _insertHashtag(String tag) {
    final cleanTag = tag.replaceAll('#', '').trim();
    final text = _contentController.text;
    final sel = _contentController.selection;
    int cursor = sel.baseOffset >= 0 && sel.baseOffset <= text.length
        ? sel.baseOffset
        : text.length;

    final before = text.substring(0, cursor);
    final after = text.substring(cursor);
    final lastHash = before.lastIndexOf('#');

    String newText;
    int newCursor;

    if (lastHash != -1 && !before.substring(lastHash).contains(' ')) {
      // Replace the active query starting with '#'
      final prefix = before.substring(0, lastHash);
      newText = '$prefix#$cleanTag $after';
      newCursor = (prefix.length + cleanTag.length + 2);
    } else {
      // Append tag with space
      final space = (before.isEmpty || before.endsWith(' ') || before.endsWith('\n')) ? '' : ' ';
      newText = '$before$space#$cleanTag $after';
      newCursor = (before.length + space.length + cleanTag.length + 2);
    }

    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor.clamp(0, newText.length)),
    );

    setState(() {
      _showHashtagDropdown = false;
      _hashtagSuggestions = [];
    });
  }

  Future<void> _fetchCurrentUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final profile = await supabase
            .from('profiles')
            .select('full_name, first_name, last_name, avatar_url, role')
            .eq('id', user.id)
            .maybeSingle();

        if (profile != null && mounted) {
          setState(() {
            userProfile = profile;
            userName =
                profile['full_name'] ??
                '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
                    .trim();
            userAvatar = profile['avatar_url'] ?? '';
            userRole = profile['role'] ?? 'Student';
            isLoadingProfile = false;
          });
          return;
        }
      }
      if (mounted) setState(() => isLoadingProfile = false);
    } catch (e) {
      if (mounted) setState(() => isLoadingProfile = false);
    }
  }

  Future<void> _pickUniversalMedia({required bool allowImages, required bool allowVideos}) async {
    final media = await AppMediaPicker.instance.pickUniversalMedia(
      allowImages: allowImages,
      allowVideos: allowVideos,
    );
    if (media != null && mounted) {
      setState(() {
        _selectedMedia = media;
      });
    }
  }

  Future<void> _publishPost() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill in both title and content fields."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => isPosting = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception("You must be logged in to publish a post.");
      }

      String? uploadedImageUrl;
      if (_selectedMedia != null) {
        final ext = _selectedMedia!.name.split('.').last.toLowerCase();
        final fileName = "post_${DateTime.now().millisecondsSinceEpoch}_${user.id}.$ext";
        
        uploadedImageUrl = await CloudflareStorageService.instance.upload(
          bucket: "safiacademy-media",
          path: "feed/$fileName",
          bytes: _selectedMedia!.bytes,
          file: _selectedMedia!.file,
          contentType: _selectedMedia!.mimeType,
        );

        if (uploadedImageUrl.isEmpty) {
          throw Exception("Media upload failed. Please verify your connection.");
        }
      }

      Map<String, dynamic> insertData = {
        'student_id': user.id,
        'title': "[$selectedMood] $title",
        'content': content,
      };
      if (uploadedImageUrl != null) insertData['image_url'] = uploadedImageUrl;

      final res = await supabase
          .from("discussion_posts")
          .insert(insertData)
          .select('id')
          .maybeSingle();

      if (res != null) {
        final newPostId = res['id']?.toString();
        if (newPostId != null) {
          HashtagService.instance.syncPostHashtags(newPostId, "$title $content");
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Post published successfully! 🎉"),
            backgroundColor: Colors.green,
          ),
        );

        _titleController.clear();
        _contentController.clear();
        setState(() => _selectedMedia = null);

        if (widget.onPostSuccess != null) {
          widget.onPostSuccess!();
        } else if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to publish post: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String authorName = "ZEV User";
    String roleLabel = "Public Post 🌍";
    Color roleColor = primaryPink;

    if (userProfile != null) {
      authorName =
          "${userProfile!['first_name'] ?? ''} ${userProfile!['last_name'] ?? ''}"
              .trim();
      if (userProfile!['role'] == 'admin' ||
          userProfile!['role'] == 'super_admin') {
        roleLabel = "Official Announcement 🛡️";
        roleColor = Colors.deepPurple;
      } else {
        roleLabel = "Public Post 🌍";
        roleColor = primaryPink;
      }
    }
    String avatarUrl = userProfile?['avatar_url'] ?? '';

    return ZevLoadingOverlay(
      isLoading: isPosting,
      message: "PUBLISHING POST...",
      child: Scaffold(
        backgroundColor: surfaceWhite,
        appBar: AppBar(
          backgroundColor: surfaceWhite,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: textDark,
            ),
            tooltip: "Back",
            onPressed: () {
              if (widget.onCancel != null) {
                widget.onCancel!();
              } else if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
          ),
          iconTheme: const IconThemeData(color: textDark),
          title: const Text(
            "Create New Post ✍️",
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              letterSpacing: -0.5,
            ),
          ),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryPink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: primaryPink.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                onPressed: isPosting ? null : _publishPost,
                child: const Text(
                  "Publish",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFFFFF0F5).withOpacity(0.4), surfaceWhite],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 750),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        physics: const BouncingScrollPhysics(),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: surfaceWhite,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: cardBorder, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // User profile
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundColor: lightPinkBg,
                                    backgroundImage: avatarUrl.isNotEmpty
                                        ? NetworkImage(avatarUrl)
                                        : null,
                                    child: avatarUrl.isEmpty
                                        ? Text(
                                            authorName.isNotEmpty
                                                ? authorName[0]
                                                : 'U',
                                            style: const TextStyle(
                                              color: primaryPink,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        authorName,
                                        style: const TextStyle(
                                          color: textDark,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: roleColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          roleLabel,
                                          style: TextStyle(
                                            color: roleColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // Select Vibe / Topic
                              const Text(
                                "SELECT VIBE / TOPIC",
                                style: TextStyle(
                                  color: textGrey,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 44,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: moods.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final m = moods[index];
                                    bool isSelected = selectedMood == m;
                                    return ChoiceChip(
                                      label: Text(
                                        m,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: isSelected
                                              ? Colors.white
                                              : textDark,
                                        ),
                                      ),
                                      selected: isSelected,
                                      selectedColor: primaryPink,
                                      backgroundColor: cardBorder,
                                      onSelected: (selected) =>
                                          setState(() => selectedMood = m),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      side: BorderSide.none,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Title input field
                              TextField(
                                controller: _titleController,
                                cursorColor: primaryPink,
                                textDirection: _isRtlText(_titleController.text)
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                                textAlign: _isRtlText(_titleController.text)
                                    ? TextAlign.right
                                    : TextAlign.left,
                                onChanged: (_) => setState(() {}),
                                style: const TextStyle(
                                  color: textDark,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                                decoration: const InputDecoration(
                                  hintText:
                                      "Give your post a catching title...",
                                  hintStyle: TextStyle(
                                    color: textGrey,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                              const Divider(
                                color: cardBorder,
                                height: 32,
                                thickness: 1.5,
                              ),

                              // Main text input field
                              TextField(
                                controller: _contentController,
                                cursorColor: primaryPink,
                                textDirection: _isRtlText(_contentController.text)
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                                textAlign: _isRtlText(_contentController.text)
                                    ? TextAlign.right
                                    : TextAlign.left,
                                maxLines: null,
                                minLines: 6,
                                onChanged: (_) => setState(() {}),
                                style: const TextStyle(
                                  color: textDark,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 1.6,
                                ),
                                decoration: const InputDecoration(
                                  hintText:
                                      "What's on your mind? Share thoughts, media, or stories with ZEV (Type # for hashtags)...",
                                  hintStyle: TextStyle(
                                    color: textGrey,
                                    fontSize: 14,
                                    height: 1.6,
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Live Hashtag Autocomplete Suggestions Dropdown
                              if (_showHashtagDropdown && _hashtagSuggestions.isNotEmpty) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: lightPinkBg,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: primaryPink.withOpacity(0.3),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryPink.withOpacity(0.06),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.auto_awesome_rounded,
                                            size: 14,
                                            color: primaryPink,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            "HASHTAG SUGGESTIONS (${_hashtagSuggestions.length})",
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: textGrey,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: _hashtagSuggestions.map((tagItem) {
                                          return InkWell(
                                            onTap: () => _insertHashtag(tagItem.tag),
                                            borderRadius: BorderRadius.circular(12),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: primaryPink.withOpacity(0.2),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    "#${tagItem.tag}",
                                                    style: const TextStyle(
                                                      color: primaryPink,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  if (tagItem.postsCount > 0) ...[
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      "${tagItem.postsCount}",
                                                      style: const TextStyle(
                                                        color: textGrey,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // Selected Media Preview (Universal for Mobile & Web)
                              if (_selectedMedia != null) ...[
                                if (!_selectedMedia!.isVideo) ...[
                                  Stack(
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        constraints: const BoxConstraints(maxHeight: 380),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F172A),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: cardBorder,
                                            width: 1.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.08),
                                              blurRadius: 15,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(20),
                                          child: Image.memory(
                                            _selectedMedia!.bytes,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 10,
                                        right: 10,
                                        child: GestureDetector(
                                          onTap: () => setState(
                                            () => _selectedMedia = null,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: const BoxDecoration(
                                              color: Colors.black87,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close_rounded,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Stack(
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(18),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: primaryPink.withOpacity(0.3),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: primaryPink.withOpacity(0.2),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.videocam_rounded,
                                                color: primaryPink,
                                                size: 26,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _selectedMedia!.name,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    "${(_selectedMedia!.bytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(1)} MB • Video Ready",
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: GestureDetector(
                                          onTap: () => setState(
                                            () => _selectedMedia = null,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close_rounded,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 20),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Trending Hashtag Quick Pick Bar
                    if (_trendingHashtags.isNotEmpty)
                      Container(
                        height: 38,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _trendingHashtags.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final tag = _trendingHashtags[index];
                            return ActionChip(
                              backgroundColor: lightPinkBg,
                              side: BorderSide(color: primaryPink.withOpacity(0.2)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              label: Text(
                                "#${tag.tag}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: primaryPink,
                                ),
                              ),
                              onPressed: () => _insertHashtag(tag.tag),
                            );
                          },
                        ),
                      ),

                    // Bottom action bar for media and tags
                    Container(
                      padding: EdgeInsets.only(
                        left: 20,
                        right: 20,
                        top: 14,
                        bottom: 16 + MediaQuery.of(context).padding.bottom,
                      ),
                      decoration: BoxDecoration(
                        color: surfaceWhite,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        border: const Border(
                          top: BorderSide(color: cardBorder, width: 1.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 16,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Add Photo button
                          InkWell(
                            onTap: () => _pickUniversalMedia(
                              allowImages: true,
                              allowVideos: false,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: lightPinkBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: primaryPink.withOpacity(0.2),
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.add_photo_alternate_rounded,
                                    color: primaryPink,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _selectedMedia != null && !_selectedMedia!.isVideo
                                        ? "Change Photo"
                                        : "Photo",
                                    style: const TextStyle(
                                      color: primaryPink,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Add Video button
                          InkWell(
                            onTap: () => _pickUniversalMedia(
                              allowImages: false,
                              allowVideos: true,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF22C55E).withOpacity(0.3),
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.video_library_rounded,
                                    color: Color(0xFF16A34A),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _selectedMedia != null && _selectedMedia!.isVideo
                                        ? "Change Video"
                                        : "Video",
                                    style: const TextStyle(
                                      color: Color(0xFF16A34A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),

                          // Quick Hashtag button
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.tag_rounded,
                                color: Colors.blueAccent,
                                size: 22,
                              ),
                            ),
                            onPressed: () {
                              _insertHashtag("ZEV");
                            },
                            tooltip: "Insert #ZEV",
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ZevLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final String message;
  final Widget child;

  const ZevLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message = "LOADING...",
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.white.withOpacity(0.95),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  color: Color(0xFFFC466B),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 20),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
