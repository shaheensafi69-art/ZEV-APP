import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/hashtag_service.dart';
import '../../../core/utils/app_media_picker.dart';
import 'reels_viewer_screen.dart';

class UploadReelScreen extends StatefulWidget {
  const UploadReelScreen({super.key});

  @override
  State<UploadReelScreen> createState() => _UploadReelScreenState();
}

class _UploadReelScreenState extends State<UploadReelScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  VideoPlayerController? _previewController;
  List<HashtagItem> _trendingHashtags = [];

  String selectedCategory = 'Explore';
  final List<String> categories = [
    'Explore',
    'Educational',
    'Trading',
    'Coding',
    'Motivation',
  ];

  bool isUploadingFile = false;
  bool isPublishing = false;
  String? uploadedPublicUrl;

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
    _loadTrendingHashtags();
  }

  Future<void> _loadTrendingHashtags() async {
    try {
      final tags = await HashtagService.instance.getTrendingHashtags(limit: 10);
      if (mounted) setState(() => _trendingHashtags = tags);
    } catch (_) {}
  }

  @override
  void dispose() {
    _previewController?.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadVideo() async {
    final media = await AppMediaPicker.instance.pickUniversalMedia(
      allowImages: false,
      allowVideos: true,
    );
    if (media == null) return;

    setState(() => isUploadingFile = true);

    try {
      final user = supabase.auth.currentUser;
      final uId = user?.id ?? 'guest';
      final ext = media.name.split('.').last.toLowerCase();
      final fileName = "reel_${DateTime.now().millisecondsSinceEpoch}_$uId.$ext";

      final publicUrl = await CloudflareStorageService.instance.upload(
        bucket: "safiacademy-media",
        path: "reels/$fileName",
        bytes: media.bytes,
        file: media.file,
        contentType: media.mimeType,
      );

      if (publicUrl.isEmpty) {
        throw Exception("Failed to upload video file.");
      }

      // Initialize live preview controller
      _previewController?.dispose();
      final controller = VideoPlayerController.networkUrl(Uri.parse(publicUrl));
      await controller.initialize();
      controller.setLooping(true);
      controller.play();

      if (mounted) {
        setState(() {
          uploadedPublicUrl = publicUrl;
          _urlController.text = publicUrl;
          _previewController = controller;
          isUploadingFile = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isUploadingFile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error uploading video: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _publishReel() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final title = _titleController.text.trim();
    final videoUrl = _urlController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${context.l10n.fillRequiredFields} 🎬")),
      );
      return;
    }

    if (videoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${context.l10n.selectVideo} 📹"),
        ),
      );
      return;
    }

    setState(() => isPublishing = true);

    try {
      final desc = _descriptionController.text.trim();
      final reelRes = await supabase.from("reels").insert({
        'user_id': user.id,
        'title': title,
        'description': desc,
        'video_url': videoUrl,
        'category': selectedCategory,
        'is_published': true,
        'views_count': 0,
        'likes_count': 0,
        'comments_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      }).select('id').maybeSingle();

      if (reelRes != null) {
        final newReelId = reelRes['id']?.toString();
        if (newReelId != null) {
          HashtagService.instance.syncReelHashtags(newReelId, "$title $desc");
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.reelPublishedSuccess),
            backgroundColor: Colors.green,
          ),
        );

        // Redirect directly to StudentReelsScreen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StudentReelsScreen()),
        );
      }
    } catch (e) {
      setState(() => isPublishing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${context.l10n.error}: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
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
        title: Text(
          "${context.l10n.reels} 🎬",
          style: const TextStyle(
            color: textDark,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPink,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: (isUploadingFile || isPublishing)
                  ? null
                  : _publishReel,
              child: isPublishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      context.l10n.publish,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview card or video pick button
            if (isUploadingFile)
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: lightPinkBg.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: primaryPink.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      color: primaryPink,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "${context.l10n.uploading}... ⏳",
                      style: const TextStyle(
                        color: primaryPink,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            else if (_previewController != null && _previewController!.value.isInitialized)
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      color: Colors.black,
                      constraints: const BoxConstraints(maxHeight: 280),
                      width: double.infinity,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _previewController!.value.aspectRatio,
                          child: VideoPlayer(_previewController!),
                        ),
                      ),
                    ),
                  ),
                  // Play / Pause toggle overlay button
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_previewController!.value.isPlaying) {
                          _previewController!.pause();
                        } else {
                          _previewController!.play();
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _previewController!.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  // Change Video button
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: isUploadingFile ? null : _pickAndUploadVideo,
                      icon: const Icon(Icons.sync_rounded, size: 16),
                      label: const Text(
                        "Change Video",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              )
            else if (uploadedPublicUrl != null)
              GestureDetector(
                onTap: isUploadingFile ? null : _pickAndUploadVideo,
                child: Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: lightPinkBg.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: primaryPink.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.videoReadyToPublish,
                        style: const TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Tap to change video",
                        style: TextStyle(color: textGrey, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: isUploadingFile ? null : _pickAndUploadVideo,
                child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: lightPinkBg.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: primaryPink.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: primaryPink,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.video_library_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        context.l10n.selectVideo,
                        style: const TextStyle(
                          color: primaryPink,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Tap to pick MP4, MOV, WebM or any video",
                        style: TextStyle(color: textGrey, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),

            // Reel title
            Text(
              "${context.l10n.reelTitle} *",
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              textDirection: _isRtlText(_titleController.text)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              textAlign: _isRtlText(_titleController.text)
                  ? TextAlign.right
                  : TextAlign.left,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontSize: 14,
                color: textDark,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText:
                    "Enter a title (e.g. Master Support & Resistance in 60s)",
                hintStyle: const TextStyle(color: textGrey, fontSize: 13),
                filled: true,
                fillColor: cardBorder.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: primaryPink, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Category
            Text(
              context.l10n.categories,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: categories.map((cat) {
                final isSel = selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
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
                    if (val) setState(() => selectedCategory = cat);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Description (optional)
            Text(
              context.l10n.descriptionOptional,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              textDirection: _isRtlText(_descriptionController.text)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              textAlign: _isRtlText(_descriptionController.text)
                  ? TextAlign.right
                  : TextAlign.left,
              onChanged: (_) => setState(() {}),
              maxLines: 3,
              style: const TextStyle(fontSize: 13, color: textDark),
              decoration: InputDecoration(
                hintText: "Add key notes or hashtags #Trading #Coding...",
                hintStyle: const TextStyle(color: textGrey, fontSize: 12),
                filled: true,
                fillColor: cardBorder.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: primaryPink, width: 1.5),
                ),
              ),
            ),
            if (_trendingHashtags.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _trendingHashtags.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final h = _trendingHashtags[index];
                    return ActionChip(
                      backgroundColor: lightPinkBg,
                      side: BorderSide(color: primaryPink.withValues(alpha: 0.2)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      label: Text(
                        "#${h.tag}",
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: primaryPink,
                        ),
                      ),
                      onPressed: () {
                        final cur = _descriptionController.text.trim();
                        final sep = cur.isEmpty ? '' : ' ';
                        setState(() {
                          _descriptionController.text = "$cur$sep#${h.tag} ";
                        });
                      },
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Direct video URL (optional)
            const Text(
              "Video URL (Direct or Auto-filled)",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              style: const TextStyle(fontSize: 12, color: textDark),
              decoration: InputDecoration(
                hintText: "https://...",
                hintStyle: const TextStyle(color: textGrey, fontSize: 12),
                filled: true,
                fillColor: cardBorder.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: primaryPink, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
