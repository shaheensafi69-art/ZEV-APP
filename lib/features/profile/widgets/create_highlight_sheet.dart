import 'dart:io';
import 'package:easy_compressor/easy_compressor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/content_safety_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../stories/widgets/video_trimmer_sheet.dart';
import '../models/story_highlight_model.dart';
import '../services/story_highlight_service.dart';

/// Minimal, Instagram-Grade Bottom Sheet to create a Story Highlight.
/// Allows selecting from historical user_stories archive OR adding new photo/video/text.
class CreateHighlightSheet extends StatefulWidget {
  final String userId;
  final ValueChanged<StoryHighlight> onHighlightCreated;

  const CreateHighlightSheet({
    super.key,
    required this.userId,
    required this.onHighlightCreated,
  });

  static Future<void> show(
    BuildContext context, {
    required String userId,
    required ValueChanged<StoryHighlight> onHighlightCreated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateHighlightSheet(
        userId: userId,
        onHighlightCreated: onHighlightCreated,
      ),
    );
  }

  @override
  State<CreateHighlightSheet> createState() => _CreateHighlightSheetState();
}

class _CreateHighlightSheetState extends State<CreateHighlightSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _titleCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  late final TabController _tabCtrl;
  bool _isLoadingArchive = true;
  List<Map<String, dynamic>> _archivedStories = [];
  final List<Map<String, dynamic>> _selectedArchiveStories = [];
  final List<StoryHighlightItem> _newlyAddedItems = [];

  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadArchiveStories();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadArchiveStories() async {
    final list = await StoryHighlightService().fetchUserStoriesArchive(widget.userId);
    if (mounted) {
      setState(() {
        _archivedStories = list;
        _isLoadingArchive = false;
      });
    }
  }

  void _toggleSelectArchiveStory(Map<String, dynamic> story) {
    HapticFeedback.selectionClick();
    setState(() {
      final id = story['id']?.toString() ?? '';
      final exists = _selectedArchiveStories.any((s) => s['id']?.toString() == id);
      if (exists) {
        _selectedArchiveStories.removeWhere((s) => s['id']?.toString() == id);
      } else {
        _selectedArchiveStories.add(story);
      }
    });
  }

  Future<void> _pickPhoto() async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1080,
      );
      if (picked == null) return;

      setState(() => _isCreating = true);

      final photoFile = File(picked.path);
      final safetyResult = await ContentSafetyService.instance.checkImageSafety(
        file: photoFile,
      );
      if (!safetyResult.isSafe) {
        if (mounted) {
          setState(() => _isCreating = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                safetyResult.errorMessage ??
                    "Photo flagged as inappropriate (+18).",
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final ext = picked.path.split('.').last;
      final fileName =
          'highlight_${widget.userId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final url = await CloudflareStorageService.instance.upload(
        bucket: 'stories',
        path: fileName,
        file: photoFile,
      );

      final item = StoryHighlightItem(
        id: 'new_${DateTime.now().millisecondsSinceEpoch}',
        mediaUrl: url,
        mediaType: 'image',
        caption: '',
        createdAt: DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _newlyAddedItems.add(item);
          _isCreating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Photo added to highlight!")),
        );
      }
    } catch (e) {
      debugPrint("Upload highlight photo error: $e");
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _pickVideo() async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickVideo(
        source: ImageSource.gallery,
      );
      if (picked == null) return;

      File videoFile = File(picked.path);

      // Check duration
      Duration? videoDuration;
      try {
        final ctrl = VideoPlayerController.file(videoFile);
        await ctrl.initialize();
        videoDuration = ctrl.value.duration;
        await ctrl.dispose();
      } catch (_) {}

      // Enforce 1:30 (90 seconds) limit with WhatsApp-style trimmer
      if (videoDuration != null && videoDuration > const Duration(seconds: 90)) {
        if (!mounted) return;
        final trimmed = await VideoTrimmerSheet.show(
          context,
          videoFile: videoFile,
          maxDuration: const Duration(seconds: 90),
        );
        if (trimmed == null) return; // user cancelled
        videoFile = trimmed;
      }

      setState(() => _isCreating = true);

      final safetyResult = await ContentSafetyService.instance.checkVideoSafety(
        videoFile,
      );
      if (!safetyResult.isSafe) {
        if (mounted) {
          setState(() => _isCreating = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                safetyResult.errorMessage ??
                    "Video flagged as inappropriate (+18).",
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final ext = videoFile.path.split('.').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName =
          'highlight_vid_${widget.userId}_$timestamp.$ext';

      final url = await CloudflareStorageService.instance.upload(
        bucket: 'stories',
        path: fileName,
        file: videoFile,
      );

      // Generate real JPEG thumbnail for highlight cover
      String? thumbUrl;
      try {
        final thumbBytes = await EasyCompressor().getThumbnail(
          videoFile.path,
          position: const Duration(milliseconds: 500),
          quality: 80,
          maxHeight: 720,
        );
        if (thumbBytes != null && thumbBytes.isNotEmpty) {
          thumbUrl = await CloudflareStorageService.instance.upload(
            bucket: 'stories',
            path: 'thumb_${widget.userId}_$timestamp.jpg',
            bytes: thumbBytes,
            contentType: 'image/jpeg',
          );
        }
      } catch (thumbErr) {
        debugPrint("Highlight thumbnail generation notice: $thumbErr");
      }

      final item = StoryHighlightItem(
        id: 'new_vid_$timestamp',
        mediaUrl: url,
        mediaType: 'video',
        caption: '',
        createdAt: DateTime.now(),
        thumbnailUrl: thumbUrl,
      );

      if (mounted) {
        setState(() {
          _newlyAddedItems.add(item);
          _isCreating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Video added to highlight!")),
        );
      }
    } catch (e) {
      debugPrint("Upload highlight video error: $e");
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showAddTextDialog() {
    HapticFeedback.lightImpact();
    final textCtrl = TextEditingController();
    int selectedGradientIdx = 0;

    final gradients = [
      [0xFF00D4FF, 0xFF536DFE],
      [0xFFFF0080, 0xFF7928CA],
      [0xFFFBAA47, 0xFFD91A46],
      [0xFF10B981, 0xFF059669],
      [0xFF1E293B, 0xFF0F172A],
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            backgroundColor: ZevColors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              "New Text Story",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ZevColors.deepNavy,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 140,
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradients[selectedGradientIdx]
                            .map((c) => Color(c))
                            .toList(),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: textCtrl,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: "Type your text...",
                        hintStyle: TextStyle(color: Colors.white70),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(gradients.length, (idx) {
                      final isSel = selectedGradientIdx == idx;
                      return GestureDetector(
                        onTap: () => setDlgState(() => selectedGradientIdx = idx),
                        child: Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: gradients[idx].map((c) => Color(c)).toList(),
                            ),
                            border: isSel
                                ? Border.all(color: ZevColors.deepNavy, width: 2.5)
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel", style: TextStyle(color: ZevColors.textMuted)),
              ),
              ElevatedButton(
                onPressed: () {
                  final text = textCtrl.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(ctx);
                  setState(() {
                    _newlyAddedItems.add(
                      StoryHighlightItem(
                        id: 'text_${DateTime.now().millisecondsSinceEpoch}',
                        mediaUrl: '',
                        mediaType: 'text',
                        caption: text,
                        createdAt: DateTime.now(),
                        bgGradientColors: gradients[selectedGradientIdx],
                      ),
                    );
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.primaryBlue,
                  foregroundColor: ZevColors.deepNavy,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text("Add", style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleCreate() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _errorMessage = "Please enter a highlight title.");
      return;
    }

    final totalCount = _selectedArchiveStories.length + _newlyAddedItems.length;
    if (totalCount == 0) {
      setState(() => _errorMessage = "Select at least 1 story or add media.");
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final items = <StoryHighlightItem>[];

      // Convert selected archive stories to items
      for (var s in _selectedArchiveStories) {
        items.add(
          StoryHighlightItem(
            id: s['id']?.toString() ?? 'story_${DateTime.now().millisecondsSinceEpoch}',
            mediaUrl: s['media_url']?.toString() ?? '',
            mediaType: s['media_type']?.toString() ?? 'image',
            caption: s['caption']?.toString() ?? '',
            createdAt: s['created_at'] != null
                ? DateTime.tryParse(s['created_at'].toString()) ?? DateTime.now()
                : DateTime.now(),
          ),
        );
      }

      // Add newly uploaded/created items
      items.addAll(_newlyAddedItems);

      // Determine cover URL (prefer real thumbnail if item is a video)
      String coverUrl = '';
      for (var it in items) {
        if (it.thumbnailUrl != null && it.thumbnailUrl!.isNotEmpty) {
          coverUrl = it.thumbnailUrl!;
          break;
        } else if (it.mediaUrl.isNotEmpty && it.mediaType != 'video') {
          coverUrl = it.mediaUrl;
          break;
        }
      }
      if (coverUrl.isEmpty) {
        for (var it in items) {
          if (it.mediaUrl.isNotEmpty) {
            coverUrl = it.mediaUrl;
            break;
          }
        }
      }
      if (coverUrl.isEmpty) {
        coverUrl =
            'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=600&auto=format&fit=crop&q=80';
      }

      final highlight = StoryHighlight(
        id: 'highlight_${DateTime.now().millisecondsSinceEpoch}',
        userId: widget.userId,
        title: title,
        coverUrl: coverUrl,
        createdAt: DateTime.now(),
        items: items,
      );

      await StoryHighlightService().saveHighlight(widget.userId, highlight);

      widget.onHighlightCreated(highlight);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Highlight '$title' created!"),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint("Create highlight error: $e");
      if (mounted) {
        setState(() {
          _isCreating = false;
          _errorMessage = "Failed to create highlight: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final totalSelected = _selectedArchiveStories.length + _newlyAddedItems.length;

    return Container(
      height: mediaQuery.size.height * 0.88,
      decoration: const BoxDecoration(
        color: ZevColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
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

          // Header: Cancel - New Highlight - Create
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(
                      fontSize: 14,
                      color: ZevColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Text(
                  "New Highlight",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                  ),
                ),
                GestureDetector(
                  onTap: _isCreating ? null : _handleCreate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: totalCountButtonColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _isCreating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ZevColors.deepNavy,
                            ),
                          )
                        : Text(
                            totalSelected > 0 ? "Create ($totalSelected)" : "Create",
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: ZevColors.border),

          // Title Input & Cover Preview Row
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Highlight circle preview
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZevColors.softSurface,
                    border: Border.all(color: ZevColors.primaryBlue, width: 2),
                  ),
                  child: ClipOval(
                    child: _selectedArchiveStories.isNotEmpty &&
                            (_selectedArchiveStories.first['media_url'] ?? '')
                                .toString()
                                .isNotEmpty
                        ? ZevCachedImage.grid(
                            imageUrl: _selectedArchiveStories.first['media_url'],
                          )
                        : _newlyAddedItems.isNotEmpty &&
                                _newlyAddedItems.first.mediaUrl.isNotEmpty
                            ? ZevCachedImage.grid(
                                imageUrl: _newlyAddedItems.first.mediaUrl,
                              )
                            : const Icon(
                                Icons.star_rounded,
                                color: ZevColors.primaryBlue,
                                size: 28,
                              ),
                  ),
                ),
                const SizedBox(width: 14),

                // Name TextField
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _titleCtrl,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ZevColors.deepNavy,
                        ),
                        decoration: const InputDecoration(
                          hintText: "Highlight name (e.g. Memories)",
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: ZevColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                      const Divider(height: 1, color: ZevColors.border),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),

          // TabBar: Stories Archive vs Add New Media
          TabBar(
            controller: _tabCtrl,
            indicatorColor: ZevColors.primaryBlue,
            indicatorWeight: 2.5,
            labelColor: ZevColors.deepNavy,
            unselectedLabelColor: ZevColors.textMuted,
            labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
            tabs: [
              Tab(
                text: "Stories Archive (${_archivedStories.length})",
              ),
              Tab(
                text: "Add New Media (${_newlyAddedItems.length})",
              ),
            ],
          ),
          const Divider(height: 1, color: ZevColors.border),

          // TabBarView Content
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // 1. Stories Archive Grid
                _buildArchiveTab(),

                // 2. Add New Media Tab
                _buildAddNewTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color get totalCountButtonColor {
    final total = _selectedArchiveStories.length + _newlyAddedItems.length;
    return total > 0 ? ZevColors.primaryBlue : ZevColors.softSurface;
  }

  Widget _buildArchiveTab() {
    if (_isLoadingArchive) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: ZevColors.primaryBlue,
        ),
      );
    }

    if (_archivedStories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.history_rounded,
                size: 44,
                color: ZevColors.textMuted,
              ),
              const SizedBox(height: 12),
              const Text(
                "No past stories found",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "You can add fresh photos, videos, or text in the 'Add New Media' tab!",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: ZevColors.textMuted),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _tabCtrl.animateTo(1),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: ZevColors.primaryBlue),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text("Go to Add New", style: TextStyle(color: ZevColors.deepNavy)),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
        childAspectRatio: 0.72,
      ),
      itemCount: _archivedStories.length,
      itemBuilder: (context, index) {
        final story = _archivedStories[index];
        final id = story['id']?.toString() ?? '';
        final mediaUrl = story['media_url']?.toString() ?? '';
        final mediaType = story['media_type']?.toString() ?? 'image';
        final isSelected = _selectedArchiveStories.any((s) => s['id']?.toString() == id);

        return GestureDetector(
          onTap: () => _toggleSelectArchiveStory(story),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: ZevColors.softSurface,
                child: mediaUrl.isNotEmpty
                    ? ZevCachedImage.grid(
                        imageUrl: mediaUrl,
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
                          ),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          story['caption'] ?? '',
                          maxLines: 4,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),

              // Video indicator icon
              if (mediaType == 'video')
                const Positioned(
                  top: 6,
                  left: 6,
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),

              // Dark overlay when selected
              if (isSelected)
                Container(
                  color: Colors.black.withValues(alpha: 0.35),
                ),

              // Checkbox bubble (Top-Right)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? ZevColors.primaryBlue : Colors.black45,
                    border: Border.all(
                      color: Colors.white,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Center(
                          child: Icon(
                            Icons.check_rounded,
                            color: ZevColors.deepNavy,
                            size: 14,
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAddNewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Add Content Directly",
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: ZevColors.deepNavy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Upload brand new photos, short clips, or styled text to this highlight.",
            style: TextStyle(fontSize: 12, color: ZevColors.textMuted),
          ),
          const SizedBox(height: 16),

          // Upload Photo Card
          _buildActionCard(
            icon: Icons.photo_library_rounded,
            title: "Upload Photo",
            subtitle: "Select high-res image from gallery or camera",
            gradient: const LinearGradient(
              colors: [Color(0xFF00D4FF), Color(0xFF0095F6)],
            ),
            onTap: _pickPhoto,
          ),
          const SizedBox(height: 12),

          // Upload Video Card
          _buildActionCard(
            icon: Icons.video_collection_rounded,
            title: "Upload Video",
            subtitle: "Select video clip (up to 60s) from device",
            gradient: const LinearGradient(
              colors: [Color(0xFF7928CA), Color(0xFFFF0080)],
            ),
            onTap: _pickVideo,
          ),
          const SizedBox(height: 12),

          // Create Text Card
          _buildActionCard(
            icon: Icons.text_fields_rounded,
            title: "Write Text Story",
            subtitle: "Create aesthetic quote or announcement",
            gradient: const LinearGradient(
              colors: [Color(0xFFFBAA47), Color(0xFFD91A46)],
            ),
            onTap: _showAddTextDialog,
          ),

          if (_newlyAddedItems.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Added Items (${_newlyAddedItems.length})",
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _newlyAddedItems.clear()),
                  child: const Text(
                    "Clear all",
                    style: TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _newlyAddedItems.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final it = _newlyAddedItems[idx];
                  return Stack(
                    children: [
                      Container(
                        width: 76,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: ZevColors.softSurface,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: it.mediaUrl.isNotEmpty
                              ? ZevCachedImage.grid(imageUrl: it.mediaUrl)
                              : Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: (it.bgGradientColors ??
                                              [0xFF00D4FF, 0xFF536DFE])
                                          .map((c) => Color(c))
                                          .toList(),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    it.caption,
                                    maxLines: 3,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => _newlyAddedItems.removeAt(idx)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.white,
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
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZevColors.border, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      fontSize: 11.5,
                      color: ZevColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: ZevColors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

