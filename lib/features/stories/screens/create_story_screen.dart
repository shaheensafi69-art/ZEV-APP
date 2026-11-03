import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/content_safety_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';
import '../widgets/video_trimmer_sheet.dart';

/// Flagship Instagram-Grade Story Creation Studio for ZEV.
/// Fully designed in serene Light Mode matching official ZEV branding (#00D4FF / #080D1A).
/// Features 9:16 canvas, dual-mode [Studio | Live Preview], draggable text overlay,
/// color filters, Cloudflare R2 upload, and 24h expiration.
class CreateStoryScreen extends StatefulWidget {
  final VoidCallback onStoryCreated;

  const CreateStoryScreen({super.key, required this.onStoryCreated});

  static Future<void> open(
    BuildContext context, {
    required VoidCallback onStoryCreated,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            CreateStoryScreen(onStoryCreated: onStoryCreated),
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
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Mode: 0 = Studio Editor, 1 = Live Story Preview
  int _activeMode = 0;

  File? _selectedImage;
  bool _isVideo = false;
  VideoPlayerController? _videoCtrl;
  bool _isVideoInitialized = false;
  bool _isPublishing = false;
  String? _errorMessage;

  // Text overlay state
  final TextEditingController _captionCtrl = TextEditingController();
  bool _isEditingText = false;
  int _textStyleIndex = 0; // 0: Dark pill, 1: Cyan neon, 2: Bold white shadow
  Offset _textPosition = const Offset(0.0, 0.0);

  // Filter tints
  int _activeFilterIndex = 0;
  final List<Color?> _filterColors = [
    null,
    const Color(0xFF00D4FF).withValues(alpha: 0.18), // Electric Cyan
    const Color(0xFFFF9E00).withValues(alpha: 0.18), // Sunset Warm
    const Color(0xFF8B5CF6).withValues(alpha: 0.20), // Purple Haze
    Colors.black.withValues(alpha: 0.25), // Moody Contrast
  ];

  // Author details
  String _authorUsername = 'Your Story';
  String _authorAvatar = '';

  // Timer animation for simulated Live Preview progress bar
  late final AnimationController _previewTimerAnim;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _previewTimerAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _previewTimerAnim.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('username, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _authorUsername = res['username'] ?? 'Your Story';
          _authorAvatar = res['avatar_url'] ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 92,
        maxWidth: 1440,
      );
      if (picked != null) {
        await _videoCtrl?.dispose();
        setState(() {
          _selectedImage = File(picked.path);
          _isVideo = false;
          _videoCtrl = null;
          _isVideoInitialized = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint("Story media picker notice: $e");
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 10),
      );
      if (picked == null) return;

      File videoFile = File(picked.path);

      // Verify duration
      final tempCtrl = VideoPlayerController.file(videoFile);
      await tempCtrl.initialize();
      final duration = tempCtrl.value.duration;
      await tempCtrl.dispose();

      // Enforce 1:30 (90 seconds) limit with WhatsApp-style trimmer
      if (duration.inSeconds > 90) {
        if (!mounted) return;
        final trimmedFile = await VideoTrimmerSheet.show(
          context,
          videoFile: videoFile,
          maxDuration: const Duration(seconds: 90),
        );
        if (trimmedFile == null) return;
        videoFile = trimmedFile;
      }

      await _videoCtrl?.dispose();
      final newCtrl = VideoPlayerController.file(videoFile);
      await newCtrl.initialize();
      newCtrl.setLooping(true);
      newCtrl.play();

      if (mounted) {
        setState(() {
          _selectedImage = videoFile;
          _isVideo = true;
          _videoCtrl = newCtrl;
          _isVideoInitialized = true;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint("Story video picker error: $e");
    }
  }

  Future<void> _publishStory() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a photo or video for your story.")),
      );
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to publish stories.")),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isPublishing = true;
      _errorMessage = null;
    });

    try {
      if (!_isVideo) {
        // Pre-upload +18 and Violence Safety Check for photos
        final safetyResult = await ContentSafetyService.instance.checkImageSafety(
          file: _selectedImage,
        );
        if (!safetyResult.isSafe) {
          if (mounted) {
            setState(() {
              _isPublishing = false;
              _errorMessage = safetyResult.errorMessage ??
                  "This story was flagged as inappropriate (+18) and cannot be posted.";
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
      }

      final ext = _selectedImage!.path.split('.').last.toLowerCase();
      final fileName =
          'story_${user.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      // 1. Upload to Cloudflare R2 bucket 'stories'
      final mediaUrl = await CloudflareStorageService.instance.upload(
        bucket: 'stories',
        path: fileName,
        file: _selectedImage,
      );

      // 2. Insert into user_stories table with 24-hour expiration
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 24)).toIso8601String();

      await supabase.from('user_stories').insert({
        'user_id': user.id,
        'media_url': mediaUrl,
        'media_type': _isVideo ? 'video' : 'image',
        'caption': _captionCtrl.text.trim(),
        'created_at': now.toIso8601String(),
        'expires_at': expiresAt,
      });

      HapticFeedback.lightImpact();
      widget.onStoryCreated();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Added to your story for 24 hours!"),
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
    if (_selectedImage == null && _captionCtrl.text.isEmpty) {
      Navigator.pop(context);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZevColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Discard story?",
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          "If you exit now, any edits and photos will be discarded.",
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZevColors.white, // Pristine ZEV Light Mode
      body: SafeArea(
        child: Stack(
          children: [
            // 1. Main View Switcher
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _activeMode == 0
                    ? _buildStudioEditorView()
                    : _buildLiveStoryPreviewView(),
              ),
            ),

            // 2. Top Navigation Bar (Light Mode)
            Positioned(
              top: 8,
              left: 14,
              right: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Discard / Close Button
                  GestureDetector(
                    onTap: _showDiscardDialog,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: ZevColors.softSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: ZevColors.border, width: 1.0),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: ZevColors.deepNavy,
                        size: 22,
                      ),
                    ),
                  ),

                  // Center Segmented Toggle: [ Studio | Preview ] (Light Mode)
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: ZevColors.border,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSegmentTab(
                          index: 0,
                          label: "Studio",
                          icon: Icons.brush_rounded,
                        ),
                        _buildSegmentTab(
                          index: 1,
                          label: "Preview",
                          icon: Icons.remove_red_eye_rounded,
                        ),
                      ],
                    ),
                  ),

                  // Top Tools (Only in Studio mode with media selected)
                  if (_activeMode == 0 && _selectedImage != null)
                    Row(
                      children: [
                        // Text Overlay Toggle
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _isEditingText = !_isEditingText);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _isEditingText
                                  ? ZevColors.primaryBlue
                                  : ZevColors.softSurface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isEditingText
                                    ? ZevColors.primaryBlue
                                    : ZevColors.border,
                                width: 1.0,
                              ),
                            ),
                            child: Icon(
                              Icons.title_rounded,
                              color: ZevColors.deepNavy,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Filter Tint Cycle
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _activeFilterIndex =
                                  (_activeFilterIndex + 1) % _filterColors.length;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: ZevColors.softSurface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _filterColors[_activeFilterIndex] != null
                                    ? ZevColors.primaryBlue
                                    : ZevColors.border,
                                width: 1.2,
                              ),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: ZevColors.deepNavy,
                              size: 19,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox(width: 44),
                ],
              ),
            ),

            // 3. Floating Text Overlay Editor Dialog
            if (_isEditingText) _buildTextEditingOverlay(),
          ],
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

  // 1. Studio Editor View (Light Mode)
  Widget _buildStudioEditorView() {
    if (_selectedImage == null) {
      return _buildEmptyStudioCanvas();
    }

    final isRtl = TextDirectionHelper.isRtl(_captionCtrl.text);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 60, 14, 12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ZevColors.border, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(23),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Selected Media (Image or Video)
                    if (_isVideo && _isVideoInitialized && _videoCtrl != null)
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: _videoCtrl!.value.size.width,
                          height: _videoCtrl!.value.size.height,
                          child: VideoPlayer(_videoCtrl!),
                        ),
                      )
                    else
                      Image.file(
                        _selectedImage!,
                        fit: BoxFit.cover,
                      ),

                    // Active Color Tint Filter
                    if (_filterColors[_activeFilterIndex] != null)
                      Container(color: _filterColors[_activeFilterIndex]),

                    // Draggable / Styled Caption Overlay on canvas
                    if (_captionCtrl.text.trim().isNotEmpty)
                      Positioned(
                        bottom: 80 + _textPosition.dy,
                        left: 20,
                        right: 20,
                        child: GestureDetector(
                          onTap: () => setState(() => _isEditingText = true),
                          onPanUpdate: (details) {
                            setState(() {
                              _textPosition += Offset(0, details.delta.dy);
                            });
                          },
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: _getTextBgColor(),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                _captionCtrl.text.trim(),
                                textAlign:
                                    isRtl ? TextAlign.right : TextAlign.center,
                                textDirection: isRtl
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: _getTextColor(),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Change photo small action pill
                    Positioned(
                      top: 14,
                      right: 14,
                      child: GestureDetector(
                        onTap: () => _pickImage(ImageSource.gallery),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.swap_horiz_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                "Change",
                                style:
                                    TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Bottom Story Action Bar (Light Mode)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            children: [
              // 24H Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: ZevColors.softSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ZevColors.border, width: 1.0),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: ZevColors.primaryBlue,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      "24 Hours",
                      style: TextStyle(
                        color: ZevColors.deepNavy,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Radiant "Share to Your Story" Main Button
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isPublishing ? null : _publishStory,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        child: _isPublishing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: Colors.white24,
                                    backgroundImage: _authorAvatar.isNotEmpty
                                        ? NetworkImage(_authorAvatar)
                                        : null,
                                    child: _authorAvatar.isEmpty
                                        ? const Icon(Icons.person,
                                            size: 14, color: Colors.white)
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "Share to Your Story",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }

  // Empty canvas with Gallery & Camera Pickers (Light Mode)
  Widget _buildEmptyStudioCanvas() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_stories_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Create a Story",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Share photos and daily updates that automatically vanish after 24 hours.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: ZevColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: _buildPickerCard(
                    icon: Icons.photo_library_rounded,
                    title: "Photo",
                    subtitle: "Choose photo",
                    onTap: () => _pickImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildPickerCard(
                    icon: Icons.video_library_rounded,
                    title: "Video",
                    subtitle: "Max 1:30",
                    onTap: () => _pickVideo(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildPickerCard(
                    icon: Icons.camera_alt_rounded,
                    title: "Camera",
                    subtitle: "Snap right now",
                    onTap: () => _pickImage(ImageSource.camera),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: ZevColors.softSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ZevColors.border, width: 1.2),
        ),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: ZevColors.primaryBlue.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: ZevColors.primaryBlue, size: 26),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: ZevColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2. THE SHOWSTOPPER: Live 1:1 Instagram Story Player Replica (Surrounded by Light Theme)
  Widget _buildLiveStoryPreviewView() {
    if (_selectedImage == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.image_not_supported_outlined,
              color: ZevColors.textMuted,
              size: 44,
            ),
            const SizedBox(height: 12),
            const Text(
              "Select a photo first to preview your story.",
              style: TextStyle(color: ZevColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _pickImage(ImageSource.gallery),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: ZevColors.deepNavy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text("Pick Photo"),
            ),
          ],
        ),
      );
    }

    final isRtl = TextDirectionHelper.isRtl(_captionCtrl.text);

    return Column(
      children: [
        // Top Informative Pill
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 56, 16, 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: ZevColors.softSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ZevColors.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  color: ZevColors.primaryBlue, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Live Story Preview: Exactly how followers will watch your 24h Story.",
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.deepNavy,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Live Story Phone Frame
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ZevColors.border, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(23),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Story Canvas Media (Image or Video)
                    if (_isVideo && _isVideoInitialized && _videoCtrl != null)
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: _videoCtrl!.value.size.width,
                          height: _videoCtrl!.value.size.height,
                          child: VideoPlayer(_videoCtrl!),
                        ),
                      )
                    else
                      Image.file(
                        _selectedImage!,
                        fit: BoxFit.cover,
                      ),

                    // Color Filter
                    if (_filterColors[_activeFilterIndex] != null)
                      Container(color: _filterColors[_activeFilterIndex]),

                    // Top Subtle Dark Gradient
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 120,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.7),
                              Colors.transparent,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),

                    // Top Simulated Story Progress Line
                    Positioned(
                      top: 14,
                      left: 14,
                      right: 14,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: AnimatedBuilder(
                          animation: _previewTimerAnim,
                          builder: (context, _) {
                            return LinearProgressIndicator(
                              value: _previewTimerAnim.value,
                              backgroundColor: Colors.white30,
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 2.5,
                            );
                          },
                        ),
                      ),
                    ),

                    // Top Story Author Header
                    Positioned(
                      top: 24,
                      left: 14,
                      right: 14,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.white24,
                            backgroundImage: _authorAvatar.isNotEmpty
                                ? NetworkImage(_authorAvatar)
                                : null,
                            child: _authorAvatar.isEmpty
                                ? const Icon(Icons.person,
                                    size: 16, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _authorUsername,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            "Just now",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.more_vert_rounded,
                              color: Colors.white, size: 20),
                        ],
                      ),
                    ),

                    // Caption Text on Preview
                    if (_captionCtrl.text.trim().isNotEmpty)
                      Positioned(
                        bottom: 40 + _textPosition.dy,
                        left: 20,
                        right: 20,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _getTextBgColor(),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _captionCtrl.text.trim(),
                              textAlign:
                                  isRtl ? TextAlign.right : TextAlign.center,
                              textDirection: isRtl
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _getTextColor(),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Bottom Action Button to Publish directly from Preview (Light Mode)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isPublishing ? null : _publishStory,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text(
                "Looks Awesome! Share Story Now",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: ZevColors.deepNavy,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Floating text edit modal
  Widget _buildTextEditingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.palette_outlined, color: Colors.white),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _textStyleIndex = (_textStyleIndex + 1) % 3);
                },
              ),
              ElevatedButton(
                onPressed: () => setState(() => _isEditingText = false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text("Done",
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // Text Field
          TextField(
            controller: _captionCtrl,
            autofocus: true,
            maxLines: 4,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _getTextColor(),
            ),
            decoration: const InputDecoration(
              hintText: "Type something for your story...",
              hintStyle: TextStyle(color: Colors.white38),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Color _getTextBgColor() {
    switch (_textStyleIndex) {
      case 0:
        return Colors.black.withValues(alpha: 0.7);
      case 1:
        return const Color(0xFF00D4FF).withValues(alpha: 0.85);
      case 2:
        return Colors.white.withValues(alpha: 0.9);
      default:
        return Colors.black54;
    }
  }

  Color _getTextColor() {
    switch (_textStyleIndex) {
      case 0:
        return Colors.white;
      case 1:
        return const Color(0xFF080D1A);
      case 2:
        return Colors.black;
      default:
        return Colors.white;
    }
  }
}
