import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_compressor/easy_compressor.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/content_safety_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../models/reel_item.dart';
import '../widgets/reel_player_item.dart';

/// Flagship Instagram/TikTok-Grade Reel Creation Studio for ZEV.
/// Fully designed in serene Light Mode matching official ZEV branding (#00D4FF / #080D1A).
/// Features dual-mode [Editor | Live Preview], local video playback preview,
/// custom audio track selector, topic taxonomy, Cloudflare R2 upload, and Supabase integration.
class CreateReelScreen extends StatefulWidget {
  final VoidCallback onReelCreated;

  const CreateReelScreen({super.key, required this.onReelCreated});

  static Future<void> open(
    BuildContext context, {
    required VoidCallback onReelCreated,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            CreateReelScreen(onReelCreated: onReelCreated),
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
  State<CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends State<CreateReelScreen> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Mode: 0 = Editor, 1 = Live Preview
  int _activeMode = 0;

  File? _selectedVideo;
  VideoPlayerController? _videoPreviewCtrl;
  bool _isVideoInitialized = false;
  Duration _videoDuration = Duration.zero;

  bool _isPublishing = false;
  String? _errorMessage;

  // Author details
  String _authorUsername = 'user';
  String _authorFullName = 'ZEV Creator';
  String _authorAvatar = '';
  bool _isVerified = false;

  // Metadata Controllers
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _captionCtrl = TextEditingController();
  final TextEditingController _audioCtrl = TextEditingController();

  // Categories
  String _selectedCategory = "Explore";
  final List<String> _categories = [
    "Analysis",
    "Education",
    "Explore",
    "Trading",
    "Tech",
    "Community",
    "Design",
  ];

  // Quick Trending Hashtags
  final List<String> _quickTags = [
    "#reels",
    "#zev",
    "#viral",
    "#trending",
    "#crypto",
    "#tech",
    "#education",
  ];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _captionCtrl.addListener(() => setState(() {}));
    _titleCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _captionCtrl.dispose();
    _audioCtrl.dispose();
    _videoPreviewCtrl?.dispose();
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
          _audioCtrl.text = "Original Audio - $_authorUsername";
        });
      }
    } catch (_) {}
  }

  Future<void> _pickVideo(ImageSource source) async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 120),
      );
      if (picked != null) {
        final file = File(picked.path);
        _initializePickedVideo(file);
      }
    } catch (e) {
      debugPrint("Reel video pick notice: $e");
    }
  }

  Future<void> _initializePickedVideo(File file) async {
    _videoPreviewCtrl?.dispose();
    setState(() {
      _selectedVideo = file;
      _isVideoInitialized = false;
      _errorMessage = null;
    });

    try {
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(1.0);
      ctrl.play();

      if (mounted) {
        setState(() {
          _videoPreviewCtrl = ctrl;
          _isVideoInitialized = true;
          _videoDuration = ctrl.value.duration;
        });
      }
    } catch (e) {
      debugPrint("Video preview init warning: $e");
    }
  }

  void _insertHashtag(String tag) {
    HapticFeedback.selectionClick();
    final currentText = _captionCtrl.text;
    final space = currentText.isNotEmpty && !currentText.endsWith(' ') ? ' ' : '';
    _captionCtrl.text = "$currentText$space$tag ";
    _captionCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _captionCtrl.text.length),
    );
  }

  Future<void> _publishReel() async {
    if (_selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a video for your Reel.")),
      );
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to publish reels.")),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isPublishing = true;
      _errorMessage = null;
    });

    try {
      // Pre-upload +18 and Violence Safety Check on Video Frames
      final safetyResult = await ContentSafetyService.instance.checkVideoSafety(
        _selectedVideo!,
      );
      if (!safetyResult.isSafe) {
        if (mounted) {
          setState(() {
            _isPublishing = false;
            _errorMessage = safetyResult.errorMessage ??
                "This video was flagged as inappropriate (+18) and cannot be posted.";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                safetyResult.errorMessage ??
                    "Content flagged as inappropriate (+18).",
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final ext = _selectedVideo!.path.split('.').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'reel_${user.id}_$timestamp.$ext';

      // 1. Upload video to Cloudflare R2
      final videoUrl = await CloudflareStorageService.instance.upload(
        bucket: 'reels',
        path: fileName,
        file: _selectedVideo,
      );

      // 2. Generate and upload real thumbnail
      String thumbnailUrl = '';
      try {
        final thumbBytes = await EasyCompressor().getThumbnail(
          _selectedVideo!.path,
          position: const Duration(milliseconds: 500),
          quality: 80,
          maxHeight: 720,
        );
        if (thumbBytes != null && thumbBytes.isNotEmpty) {
          thumbnailUrl = await CloudflareStorageService.instance.upload(
            bucket: 'reels',
            path: 'thumb_${user.id}_$timestamp.jpg',
            bytes: thumbBytes,
            contentType: 'image/jpeg',
          );
        }
      } catch (thumbErr) {
        debugPrint("Reel thumbnail generation notice: $thumbErr");
      }

      final caption = _captionCtrl.text.trim();
      final title = _titleCtrl.text.trim().isNotEmpty
          ? _titleCtrl.text.trim()
          : (caption.isNotEmpty
              ? (caption.length > 40 ? caption.substring(0, 40) : caption)
              : "Reel by @$_authorUsername");

      // 3. Insert into reels table
      await supabase.from('reels').insert({
        'user_id': user.id,
        'title': title,
        'description': caption,
        'video_url': videoUrl,
        'thumbnail_url': thumbnailUrl,
        'category': _selectedCategory,
        'duration_seconds': _videoDuration.inSeconds > 0
            ? _videoDuration.inSeconds
            : 30,
        'is_published': true,
        'views_count': 0,
        'likes_count': 0,
        'comments_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      });

      HapticFeedback.lightImpact();
      widget.onReelCreated();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Reel published successfully!"),
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

  void _showDiscardDialog() {
    if (_selectedVideo == null && _captionCtrl.text.isEmpty) {
      Navigator.pop(context);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZevColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Discard Reel?",
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          "If you leave now, your selected video and edits will be lost.",
          style: TextStyle(color: ZevColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Keep Editing",
              style: TextStyle(color: ZevColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text(
              "Discard",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _canPublish => _selectedVideo != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZevColors.white, // Pristine ZEV Light Mode
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: ZevColors.deepNavy, size: 26),
          onPressed: _showDiscardDialog,
        ),
        centerTitle: true,
        // Segmented Toggle: [ Editor | Preview ] (Responsive Scaledown)
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: ZevColors.softSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ZevColors.border, width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSegmentTab(index: 0, label: "Editor", icon: Icons.tune_rounded),
                _buildSegmentTab(index: 1, label: "Preview", icon: Icons.remove_red_eye_rounded),
              ],
            ),
          ),
        ),
        actions: [
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
                    onPressed: _canPublish ? _publishReel : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canPublish
                          ? ZevColors.primaryBlue
                          : ZevColors.softSurface,
                      foregroundColor: _canPublish
                          ? ZevColors.deepNavy
                          : ZevColors.textMuted,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
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
              : _buildLiveReelPreviewView(),
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
              size: 15,
              color: isSelected ? ZevColors.deepNavy : ZevColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? ZevColors.deepNavy : ZevColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1. Editor View (Light Mode)
  Widget _buildEditorView() {
    final isRtl = TextDirectionHelper.isRtl(_captionCtrl.text);

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
                    ? const Icon(Icons.person, color: ZevColors.textMuted)
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ZevColors.border, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.public_rounded,
                            size: 12, color: ZevColors.primaryBlue),
                        SizedBox(width: 4),
                        Text(
                          "Public Reel",
                          style: TextStyle(fontSize: 11, color: ZevColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Video Selection Box
          const Text(
            "REEL VIDEO ATTACHMENT",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ZevColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),

          if (_selectedVideo != null)
            Container(
              width: double.infinity,
              height: 260,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ZevColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isVideoInitialized && _videoPreviewCtrl != null)
                      SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _videoPreviewCtrl!.value.size.width,
                            height: _videoPreviewCtrl!.value.size.height,
                            child: VideoPlayer(_videoPreviewCtrl!),
                          ),
                        ),
                      )
                    else
                      const Center(
                        child: CircularProgressIndicator(
                          color: ZevColors.primaryBlue,
                          strokeWidth: 2,
                        ),
                      ),

                    // Duration Badge
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.timer_outlined,
                                color: ZevColors.primaryBlue, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              "${_videoDuration.inMinutes.toString().padLeft(2, '0')}:${(_videoDuration.inSeconds % 60).toString().padLeft(2, '0')}",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Remove video button
                    Positioned(
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _videoPreviewCtrl?.dispose();
                          setState(() {
                            _selectedVideo = null;
                            _videoPreviewCtrl = null;
                            _isVideoInitialized = false;
                          });
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

                    // Change video button
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: GestureDetector(
                        onTap: () => _pickVideo(ImageSource.gallery),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.swap_horiz_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text(
                                "Change video",
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildMediaPickerCard(
                    icon: Icons.video_library_rounded,
                    title: "Gallery Video",
                    subtitle: "Choose from device",
                    onTap: () => _pickVideo(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMediaPickerCard(
                    icon: Icons.videocam_rounded,
                    title: "Record Reel",
                    subtitle: "Camera recorder",
                    onTap: () => _pickVideo(ImageSource.camera),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 20),

          // Audio Track Input (Light Mode)
          const Text(
            "AUDIO TRACK",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ZevColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: ZevColors.softSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ZevColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.music_note_rounded,
                    color: ZevColors.primaryBlue, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _audioCtrl,
                    style: const TextStyle(
                      color: ZevColors.deepNavy,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      hintText: "Audio track name...",
                      hintStyle: TextStyle(color: ZevColors.textMuted, fontSize: 13.5),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Category Pills (Light Mode)
          const Text(
            "SELECT REEL CATEGORY",
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
                final isSelected = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedCategory = cat);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? ZevColors.primaryBlue
                          : ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected
                            ? ZevColors.primaryBlue
                            : ZevColors.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected
                              ? ZevColors.deepNavy
                              : ZevColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Caption (Light Mode)
          const Text(
            "CAPTION & HASHTAGS",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ZevColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ZevColors.softSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ZevColors.border),
            ),
            child: TextField(
              controller: _captionCtrl,
              maxLines: 4,
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                fontSize: 14.5,
                color: ZevColors.deepNavy,
                height: 1.4,
              ),
              decoration: const InputDecoration(
                hintText: "Write a captivating caption for your Reel...",
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: ZevColors.textMuted,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Quick Hashtags Strip (Light Mode)
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: ZevColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ZevColors.border),
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

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.redAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 60),
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
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: ZevColors.softSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ZevColors.border, width: 1.2),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
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
                fontWeight: FontWeight.w800,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11.5,
                color: ZevColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2. THE SHOWSTOPPER: Live Full-Screen Reel Preview
  Widget _buildLiveReelPreviewView() {
    if (_selectedVideo == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.video_camera_back_outlined,
              color: ZevColors.textMuted,
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              "Select a video first to preview your Reel.",
              style: TextStyle(color: ZevColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _pickVideo(ImageSource.gallery),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: ZevColors.deepNavy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text("Select Video"),
            ),
          ],
        ),
      );
    }

    final previewReel = ReelItem(
      id: 'preview_reel',
      userId: supabase.auth.currentUser?.id ?? 'preview_user',
      authorUsername: _authorUsername,
      authorFullName: _authorFullName,
      authorAvatar: _authorAvatar,
      isVerified: _isVerified,
      videoUrl: _selectedVideo!.path,
      title: _titleCtrl.text.trim().isNotEmpty
          ? _titleCtrl.text.trim()
          : "Preview Reel",
      description: _captionCtrl.text.trim().isNotEmpty
          ? _captionCtrl.text.trim()
          : "Your reel description and hashtags will appear here.",
      category: _selectedCategory,
      durationSeconds: _videoDuration.inSeconds > 0
          ? _videoDuration.inSeconds
          : 30,
      viewsCount: 0,
      likesCount: 0,
      isLikedByMe: false,
      commentsCount: 0,
      isBookmarkedByMe: false,
      isAuthorFollowed: true, // Don't show follow on own reel
      createdAt: DateTime.now(),
    );

    return Stack(
      children: [
        // Real ReelPlayerItem
        Positioned.fill(
          child: ReelPlayerItem(
            reel: previewReel,
            isActive: true,
            isGlobalMuted: false,
            onToggleMute: () {},
          ),
        ),

        // Floating Top Live Banner
        Positioned(
          top: 10,
          left: 14,
          right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: ZevColors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ZevColors.border, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: ZevColors.primaryBlue, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Live Reel Preview: Exactly how viewers will watch and interact.",
                    style: TextStyle(
                      color: ZevColors.deepNavy,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Instant Bottom Publish Action Button
        Positioned(
          bottom: 20,
          left: 16,
          right: 76, // Leaves room for the right column actions
          child: SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isPublishing ? null : _publishReel,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text(
                "Looks Amazing! Publish Reel",
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: ZevColors.deepNavy,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(23),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
