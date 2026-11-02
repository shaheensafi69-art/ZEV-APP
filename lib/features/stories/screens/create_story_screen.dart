import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/text_direction_helper.dart';

/// Flagship Instagram-Grade Story Creation Studio for ZEV.
/// Features 9:16 fullscreen canvas, dual-mode [Studio | Live Preview],
/// draggable text overlay, color filters, Cloudflare R2 upload, and 24h expiration.
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
  bool _isPublishing = false;
  String? _errorMessage;

  // Text overlay state
  final TextEditingController _captionCtrl = TextEditingController();
  bool _isEditingText = false;
  int _textStyleIndex = 0; // 0: White text on dark pill, 1: Cyan neon, 2: Bold white shadow
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
        setState(() {
          _selectedImage = File(picked.path);
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint("Story media picker notice: $e");
    }
  }

  Future<void> _publishStory() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a photo for your story.")),
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
      final ext = _selectedImage!.path.split('.').last;
      final fileName =
          'story_${user.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      // 1. Upload to Cloudflare R2
      final mediaUrl = await CloudflareStorageService.instance.upload(
        bucket: 'feed',
        path: fileName,
        file: _selectedImage,
      );

      // 2. Insert into user_stories table with 24-hour expiration
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 24)).toIso8601String();

      await supabase.from('user_stories').insert({
        'user_id': user.id,
        'media_url': mediaUrl,
        'media_type': 'image',
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
        backgroundColor: const Color(0xFF1E232F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Discard story?",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          "If you exit now, any edits and photos will be discarded.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Keep Editing", style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text(
              "Discard",
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
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

            // 2. Top Navigation Bar (Floating Overlay)
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Discard / Close Button
                  GestureDetector(
                    onTap: _showDiscardDialog,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),

                  // Center Segmented Toggle: [ Studio | Preview ]
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white24,
                        width: 0.8,
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
                                  : Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.title_rounded,
                              color: _isEditingText ? Colors.black : Colors.white,
                              size: 22,
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
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                              border: _filterColors[_activeFilterIndex] != null
                                  ? Border.all(
                                      color: ZevColors.primaryBlue,
                                      width: 1.5,
                                    )
                                  : null,
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 20,
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
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.black : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1. Studio Editor View
  Widget _buildStudioEditorView() {
    if (_selectedImage == null) {
      return _buildEmptyStudioCanvas();
    }

    final isRtl = TextDirectionHelper.isRtl(_captionCtrl.text);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 60, 10, 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Selected Image
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
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              _captionCtrl.text.trim(),
                              textAlign: isRtl ? TextAlign.right : TextAlign.center,
                              textDirection:
                                  isRtl ? TextDirection.rtl : TextDirection.ltr,
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
                            Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text(
                              "Change",
                              style: TextStyle(color: Colors.white, fontSize: 12),
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

        // Bottom Story Action Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            children: [
              // 24H Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_toggle_drop_rounded,
                        color: ZevColors.primaryBlue, size: 16),
                    SizedBox(width: 6),
                    Text(
                      "24 Hours",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
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
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                            blurRadius: 16,
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

  // Empty canvas with Gallery & Camera Pickers
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
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Share photos and daily updates that automatically vanish after 24 hours.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.white60,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: _buildPickerCard(
                    icon: Icons.photo_library_rounded,
                    title: "Gallery",
                    subtitle: "Choose photo",
                    onTap: () => _pickImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 14),
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
          color: const Color(0xFF131927),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12, width: 1.0),
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
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2. THE SHOWSTOPPER: Live 1:1 Instagram Story Player Replica
  Widget _buildLiveStoryPreviewView() {
    if (_selectedImage == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported_outlined,
                color: Colors.white54, size: 44),
            const SizedBox(height: 12),
            const Text(
              "Select a photo first to preview your story.",
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _pickImage(ImageSource.gallery),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: ZevColors.deepNavy,
              ),
              child: const Text("Pick Photo"),
            ),
          ],
        ),
      );
    }

    final isRtl = TextDirectionHelper.isRtl(_captionCtrl.text);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Story Canvas Image
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
          height: 140,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.8),
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
          top: 60,
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
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 2.5,
                );
              },
            ),
          ),
        ),

        // Top Story Author Header
        Positioned(
          top: 72,
          left: 16,
          right: 16,
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white24,
                backgroundImage: _authorAvatar.isNotEmpty
                    ? NetworkImage(_authorAvatar)
                    : null,
                child: _authorAvatar.isEmpty
                    ? const Icon(Icons.person, size: 18, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _authorUsername,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        "Just now",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
            ],
          ),
        ),

        // Caption Text on Preview
        if (_captionCtrl.text.trim().isNotEmpty)
          Positioned(
            bottom: 120 + _textPosition.dy,
            left: 24,
            right: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _getTextBgColor(),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _captionCtrl.text.trim(),
                  textAlign: isRtl ? TextAlign.right : TextAlign.center,
                  textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _getTextColor(),
                  ),
                ),
              ),
            ),
          ),

        // Bottom Simulated Story Reply Bar & Instant Publish Action
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bottom Action Button
              SizedBox(
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
            ],
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
                child: const Text("Done", style: TextStyle(fontWeight: FontWeight.w800)),
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
