import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../models/feed_post_item.dart';
import '../widgets/feed_post_card.dart';

/// Flagship Instagram-Grade Post Creation Studio for ZEV.
/// Features dual-mode [Editor | Live Preview], real-time Feed replica preview,
/// topic taxonomy tags, Cloudflare R2 media upload, and smart dynamic RTL/LTR.
class CreatePostScreen extends StatefulWidget {
  final VoidCallback onPostCreated;

  const CreatePostScreen({super.key, required this.onPostCreated});

  static Future<void> open(
    BuildContext context, {
    required VoidCallback onPostCreated,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            CreatePostScreen(onPostCreated: onPostCreated),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          final tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Mode: 0 = Editor, 1 = Live Preview
  int _activeMode = 0;

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();

  File? _selectedImage;
  bool _isPublishing = false;
  String? _errorMessage;

  // Author Profile
  String _authorUsername = 'user';
  String _authorFullName = 'ZEV Creator';
  String _authorAvatar = '';
  bool _isVerified = false;

  // Category tags
  String _selectedCategory = "Explore";
  final List<String> _categories = [
    "Analysis",
    "Education",
    "Explore",
    "Tech",
    "Trading",
    "Community",
    "Design",
  ];

  // Quick Hashtags
  final List<String> _quickTags = [
    "#zev",
    "#tech",
    "#education",
    "#analysis",
    "#crypto",
    "#coding",
    "#community",
  ];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _contentCtrl.addListener(() => setState(() {}));
    _titleCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('username, first_name, last_name, avatar_url, is_verified')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        final fn = res['first_name'] ?? '';
        final ln = res['last_name'] ?? '';
        final full = "$fn $ln".trim();
        setState(() {
          _authorUsername = res['username'] ?? (full.isNotEmpty ? full : 'user');
          _authorFullName = full.isNotEmpty ? full : 'ZEV Creator';
          _authorAvatar = res['avatar_url'] ?? '';
          _isVerified = res['is_verified'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1920,
      );
      if (picked != null) {
        setState(() => _selectedImage = File(picked.path));
      }
    } catch (e) {
      debugPrint("Image pick notice: $e");
    }
  }

  void _insertHashtag(String tag) {
    HapticFeedback.selectionClick();
    final currentText = _contentCtrl.text;
    final space = currentText.isNotEmpty && !currentText.endsWith(' ') ? ' ' : '';
    _contentCtrl.text = "$currentText$space$tag ";
    _contentCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _contentCtrl.text.length),
    );
  }

  Future<void> _publishPost() async {
    final content = _contentCtrl.text.trim();
    final title = _titleCtrl.text.trim();

    if (content.isEmpty && _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please write text or attach a photo.")),
      );
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to publish.")),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isPublishing = true;
      _errorMessage = null;
    });

    try {
      String imageUrl = "";
      if (_selectedImage != null) {
        final ext = _selectedImage!.path.split('.').last;
        final fileName =
            'feed_${user.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        imageUrl = await CloudflareStorageService.instance.upload(
          bucket: 'feed',
          path: fileName,
          file: _selectedImage,
        );
      }

      final formattedTitle = title.startsWith('[')
          ? title
          : "[$_selectedCategory] ${title.isNotEmpty ? title : (content.length > 30 ? content.substring(0, 30) : content)}";

      await supabase.from('discussion_posts').insert({
        'student_id': user.id,
        'title': formattedTitle,
        'content': content,
        'image_url': imageUrl,
        'created_at': DateTime.now().toIso8601String(),
      });

      HapticFeedback.lightImpact();
      widget.onPostCreated();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Post published successfully!"),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  bool get _canPublish =>
      _contentCtrl.text.trim().isNotEmpty || _selectedImage != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZevColors.white,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: ZevColors.deepNavy, size: 26),
          onPressed: () {
            if (_canPublish) {
              _showDiscardDialog();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        centerTitle: true,
        // Center Segmented Toggle: [ Editor | Live Preview ]
        title: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: ZevColors.softSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ZevColors.border, width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSegmentTab(index: 0, label: "Editor", icon: Icons.edit_note_rounded),
              _buildSegmentTab(index: 1, label: "Live Preview", icon: Icons.visibility_outlined),
            ],
          ),
        ),
        actions: [
          // Share / Publish Button
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: _isPublishing
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ZevColors.primaryBlue,
                      ),
                    ),
                  )
                : ElevatedButton(
                    onPressed: _canPublish ? _publishPost : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canPublish
                          ? ZevColors.primaryBlue
                          : ZevColors.softSurface,
                      foregroundColor: _canPublish
                          ? ZevColors.deepNavy
                          : ZevColors.textMuted,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      "Share",
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _activeMode == 0
              ? _buildEditorView()
              : _buildLivePreviewView(),
        ),
      ),
    );
  }

  Widget _buildSegmentTab({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _activeMode == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _activeMode = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? ZevColors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? ZevColors.deepNavy : ZevColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? ZevColors.deepNavy : ZevColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1. Editor View
  Widget _buildEditorView() {
    final isRtl = TextDirectionHelper.isRtl(_contentCtrl.text);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Header
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: ZevColors.softSurface,
                backgroundImage: _authorAvatar.isNotEmpty
                    ? NetworkImage(_authorAvatar)
                    : null,
                child: _authorAvatar.isEmpty
                    ? const Icon(Icons.person_rounded, color: ZevColors.textMuted)
                    : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _authorUsername,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                      if (_isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 15,
                          color: ZevColors.primaryBlue,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ZevColors.border, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.public_rounded, size: 12, color: ZevColors.textMuted),
                        SizedBox(width: 4),
                        Text(
                          "Public Feed",
                          style: TextStyle(fontSize: 11, color: ZevColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Category Pills
          const Text(
            "SELECT TOPIC CATEGORY",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ZevColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final cat = _categories[i];
                final isSelected = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategory = cat);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: isSelected ? ZevColors.brandGradientHorizontal : null,
                      color: isSelected ? null : ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: isSelected
                          ? null
                          : Border.all(color: ZevColors.border, width: 1.0),
                    ),
                    child: Center(
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? ZevColors.deepNavy : ZevColors.deepNavy,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),

          // Optional Title Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: ZevColors.softSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ZevColors.border, width: 1.0),
            ),
            child: TextField(
              controller: _titleCtrl,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: ZevColors.deepNavy,
              ),
              decoration: const InputDecoration(
                hintText: "Title / Headline (optional)",
                hintStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ZevColors.textMuted,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Caption Field
          Container(
            constraints: const BoxConstraints(minHeight: 130),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: ZevColors.softSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ZevColors.border, width: 1.0),
            ),
            child: TextField(
              controller: _contentCtrl,
              maxLines: null,
              minLines: 5,
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              style: const TextStyle(
                fontSize: 14.5,
                color: ZevColors.deepNavy,
                height: 1.4,
              ),
              decoration: const InputDecoration(
                hintText:
                    "What's on your mind? Share thoughts, insights, or tutorials with the ZEV community...",
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: ZevColors.textMuted,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Quick Hashtags Strip
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _quickTags.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final tag = _quickTags[i];
                return GestureDetector(
                  onTap: () => _insertHashtag(tag),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: ZevColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ZevColors.border, width: 0.8),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ZevColors.secondaryBlue,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Media Attachment Section
          const Text(
            "MEDIA ATTACHMENT",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ZevColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),

          if (_selectedImage != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 420),
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      border: Border.all(color: ZevColors.border),
                    ),
                    child: Image.file(
                      _selectedImage!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
                ),
                // Remove photo button
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _selectedImage = null);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
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
                // Change photo button
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: GestureDetector(
                    onTap: () => _pickImage(ImageSource.gallery),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            "Change photo",
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildMediaPickerCard(
                    icon: Icons.photo_library_outlined,
                    title: "Gallery",
                    subtitle: "Choose from device",
                    onTap: () => _pickImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMediaPickerCard(
                    icon: Icons.camera_alt_outlined,
                    title: "Camera",
                    subtitle: "Take a photo now",
                    onTap: () => _pickImage(ImageSource.camera),
                  ),
                ),
              ],
            ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildMediaPickerCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: ZevColors.softSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZevColors.border, width: 1.2),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ZevColors.primaryBlue.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: ZevColors.primaryBlue, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: ZevColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2. THE SHOWSTOPPER: Live Real-Time Feed Preview
  Widget _buildLivePreviewView() {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    final previewPost = FeedPostItem(
      id: 'preview_post',
      authorId: supabase.auth.currentUser?.id ?? 'preview_author',
      authorUsername: _authorUsername,
      authorFullName: _authorFullName,
      authorAvatar: _authorAvatar,
      isVerified: _isVerified,
      title: title.startsWith('[')
          ? title
          : "[$_selectedCategory] ${title.isNotEmpty ? title : (content.length > 30 ? content.substring(0, 30) : content)}",
      content: content.isNotEmpty
          ? content
          : "Your caption text will appear here with dynamic RTL/LTR support.",
      imageUrl: _selectedImage?.path ?? '',
      createdAt: DateTime.now(),
      likesCount: 0,
      isLikedByMe: false,
      commentsCount: 0,
      categoryTag: _selectedCategory,
      isAuthorFollowed: true, // Don't show follow button on own post
    );

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Informative Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: ZevColors.primaryBlue.withValues(alpha: 0.1),
              border: const Border(
                bottom: BorderSide(color: ZevColors.border, width: 0.8),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: ZevColors.primaryBlue,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Live Feed Preview: Exactly how your post appears to followers.",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Render Real FeedPostCard
          FeedPostCard(
            key: const ValueKey('preview_card'),
            post: previewPost,
            onCommentsUpdated: null,
          ),

          const SizedBox(height: 24),

          // Bottom Action to Publish directly from Preview
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _canPublish ? _publishPost : null,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text(
                  "Looks Great! Publish Now",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.primaryBlue,
                  foregroundColor: ZevColors.deepNavy,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showDiscardDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Discard post?"),
        content: const Text(
          "If you leave now, you will lose the content you've entered.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text(
              "Discard",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}
