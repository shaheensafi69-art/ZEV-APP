import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/media_processing_service.dart';
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

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadVideo() async {
    final file = await AppMediaPicker.instance.pickVideo();
    if (file == null) return;
    final pickedFilePath = file.path;

    setState(() => isUploadingFile = true);

    try {
      // 🎬 Hardware-accelerated mobile compression (Media3 / AVFoundation)
      final processedFile = await MediaProcessingService.instance
          .compressVideo(pickedFilePath);

      final user = supabase.auth.currentUser;
      final uId = user?.id ?? 'guest';
      final fileName = "reel_${DateTime.now().millisecondsSinceEpoch}_$uId.mp4";

      final publicUrl = await CloudflareStorageService.instance.upload(
        bucket: "safiacademy-media",
        path: "reels/$fileName",
        file: processedFile,
        contentType: 'video/mp4',
      );

      setState(() {
        uploadedPublicUrl = publicUrl;
        _urlController.text = publicUrl;
        isUploadingFile = false;
      });
    } catch (e) {
      setState(() => isUploadingFile = false);
      if (mounted) {
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
      await supabase.from("reels").insert({
        'user_id': user.id,
        'title': title,
        'description': _descriptionController.text.trim(),
        'video_url': videoUrl,
        'category': selectedCategory,
        'is_published': true,
        'views_count': 0,
        'likes_count': 0,
        'comments_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      });

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
                child: isUploadingFile
                    ? Column(
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
                      )
                    : uploadedPublicUrl != null
                    ? Column(
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
                      )
                    : Column(
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
                            "Tap to open gallery and pick MP4 video",
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
