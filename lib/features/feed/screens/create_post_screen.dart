import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/media_processing_service.dart';
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
  File? _selectedImageFile;
  Map<String, dynamic>? userProfile;
  String userName = "";
  String userAvatar = "";
  String userRole = "Student";

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

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

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserProfile();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
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

  Future<void> _pickImage(ImageSource source) async {
    final file = await AppMediaPicker.instance.pickImage(source: source);
    if (file != null && mounted) {
      setState(() {
        _selectedImageFile = file;
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
      if (user == null) return;

      String? uploadedImageUrl;
      if (_selectedImageFile != null) {
        // 🖼️ Compress photo without watermark for fast feed load
        final compressedImage = await MediaProcessingService.instance
            .compressFeedImage(_selectedImageFile!);

        final fileName = "post_${DateTime.now().millisecondsSinceEpoch}.jpg";
        uploadedImageUrl = await CloudflareStorageService.instance.upload(
          bucket: "safiacademy-media",
          path: "feed/$fileName",
          file: compressedImage,
          contentType: "image/jpeg",
        );
      }

      Map<String, dynamic> insertData = {
        'student_id': user.id,
        'title': "[$selectedMood] $title",
        'content': content,
      };
      if (uploadedImageUrl != null) insertData['image_url'] = uploadedImageUrl;

      await supabase.from("discussion_posts").insert(insertData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Post published successfully! 🎉"),
            backgroundColor: Colors.green,
          ),
        );

        _titleController.clear();
        _contentController.clear();
        setState(() => _selectedImageFile = null);

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
                                maxLines: null,
                                minLines: 6,
                                style: const TextStyle(
                                  color: textDark,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 1.6,
                                ),
                                decoration: const InputDecoration(
                                  hintText:
                                      "What's on your mind? Share thoughts, media, or stories with ZEV...",
                                  hintStyle: TextStyle(
                                    color: textGrey,
                                    fontSize: 14,
                                    height: 1.6,
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Selected image preview
                              if (_selectedImageFile != null) ...[
                                Stack(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.08,
                                            ),
                                            blurRadius: 15,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: Image.file(
                                          _selectedImageFile!,
                                          height: 240,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: GestureDetector(
                                        onTap: () => setState(
                                          () => _selectedImageFile = null,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(
                                              0.75,
                                            ),
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
                                const SizedBox(height: 20),
                              ],
                            ],
                          ),
                        ),
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Pick image button via FilePicker
                          InkWell(
                            onTap: () => _pickImage(ImageSource.gallery),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
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
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _selectedImageFile != null
                                        ? "Change Image"
                                        : "Add Image (File)",
                                    style: const TextStyle(
                                      color: primaryPink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Tag selection button
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
                              if (!_contentController.text.contains("#ZEV")) {
                                _contentController.text += " #ZEV #Trending ";
                              }
                            },
                            tooltip: "Add Tags",
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
