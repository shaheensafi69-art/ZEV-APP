import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/media_processing_service.dart';
import '../../../core/utils/app_media_picker.dart';

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _mediaUrlController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();

  String mediaType = 'image';
  bool isUploadingFile = false;
  bool isPublishing = false;

  final List<String> backgroundOptions = [
    "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=800&q=80",
    "https://images.unsplash.com/photo-1579546929518-9e396f3cc809?w=800&q=80",
    "https://images.unsplash.com/photo-1557683316-973673baf926?w=800&q=80",
    "https://images.unsplash.com/photo-1531482615713-2afd69097998?w=800&q=80",
    "https://images.unsplash.com/photo-1524178232363-1fb2b075b655?w=800&q=80",
  ];

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  @override
  void dispose() {
    _mediaUrlController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadMedia() async {
    final File? file;
    if (mediaType == 'image') {
      file = await AppMediaPicker.instance.pickImage();
    } else {
      file = await AppMediaPicker.instance.pickVideo();
    }

    if (file == null) return;
    final pickedPath = file.path;

    if (pickedPath.isNotEmpty) {
      setState(() => isUploadingFile = true);
      try {
        File processedFile;
        if (mediaType == 'video') {
          // 🎬 Video: Hardware-accelerated compression
          processedFile = await MediaProcessingService.instance
              .compressVideo(pickedPath);
        } else {
          // 🖼️ Photo: compression without watermark
          processedFile = await MediaProcessingService.instance
              .compressFeedImage(File(pickedPath));
        }

        final bytes = await processedFile.readAsBytes();
        final ext = mediaType == 'image' ? 'jpg' : 'mp4';
        final fileName = "story_${DateTime.now().millisecondsSinceEpoch}.$ext";

        final publicUrl = await CloudflareStorageService.instance.upload(
          bucket: "safiacademy-media",
          path: "story/$fileName",
          bytes: bytes,
          contentType: mediaType == 'image' ? 'image/jpeg' : 'video/mp4',
        );
        setState(() {
          _mediaUrlController.text = publicUrl;
          isUploadingFile = false;
        });
      } catch (e) {
        setState(() => isUploadingFile = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${context.l10n.error}: $e")),
          );
        }
      }
    }
  }

  Future<void> _publishStory() async {
    final mediaUrl = _mediaUrlController.text.trim();
    if (mediaUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${context.l10n.fillRequiredFields} 📸"),
        ),
      );
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => isPublishing = true);

    try {
      // Automatic 24-hour expiration
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 24)).toIso8601String();

      await supabase.from("user_stories").insert({
        'user_id': user.id,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'caption': _captionController.text.trim(),
        'expires_at': expiresAt,
        'created_at': now.toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.storyPublishedSuccess),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Error publishing story: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("${context.l10n.error}: $e")));
        setState(() => isPublishing = false);
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
          icon: const Icon(Icons.close_rounded, color: textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Create 24h Story 📸",
          style: TextStyle(
            color: textDark,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPink,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: (isPublishing || isUploadingFile)
                  ? null
                  : _publishStory,
              child: isPublishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "SHARE",
                      style: TextStyle(
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
            // 24-hour guidance card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: lightPinkBg.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primaryPink.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: primaryPink, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.story24hNotice,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Media type (image or video)
            const Text(
              "Media Type",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text("📷 Image")),
                    selected: mediaType == 'image',
                    selectedColor: primaryPink,
                    labelStyle: TextStyle(
                      color: mediaType == 'image' ? Colors.white : textDark,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => mediaType = 'image');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text("🎥 Video")),
                    selected: mediaType == 'video',
                    selectedColor: primaryPink,
                    labelStyle: TextStyle(
                      color: mediaType == 'video' ? Colors.white : textDark,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => mediaType = 'video');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Select from gallery button
            GestureDetector(
              onTap: isUploadingFile ? null : _pickAndUploadMedia,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: primaryPink.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: primaryPink.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      mediaType == 'image'
                          ? Icons.photo_library_rounded
                          : Icons.video_library_rounded,
                      color: primaryPink,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isUploadingFile
                            ? "${context.l10n.uploading} ⏳"
                            : (_mediaUrlController.text.isNotEmpty
                                  ? context.l10n.mediaUploaded
                                  : context.l10n.chooseMediaFromGallery),
                        style: const TextStyle(
                          color: primaryPink,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (isUploadingFile)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: primaryPink,
                          strokeWidth: 2,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // URL input field
            const Text(
              "Media URL",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mediaUrlController,
              style: const TextStyle(fontSize: 13, color: textDark),
              decoration: InputDecoration(
                hintText: "https://example.com/story.jpg",
                hintStyle: const TextStyle(color: textGrey, fontSize: 12),
                filled: true,
                fillColor: cardBorder,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: primaryPink, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Default test images
            const Text(
              "Or Select Quick Media Sample:",
              style: TextStyle(
                fontSize: 12,
                color: textGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: backgroundOptions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final url = backgroundOptions[index];
                  return GestureDetector(
                    onTap: () {
                      _mediaUrlController.text = url;
                      setState(() {});
                    },
                    child: Container(
                      width: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        image: DecorationImage(
                          image: NetworkImage(url),
                          fit: BoxFit.cover,
                        ),
                        border: Border.all(
                          color: _mediaUrlController.text == url
                              ? primaryPink
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Caption input
            const Text(
              "Caption / Text Overlay",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _captionController,
              maxLines: 3,
              style: const TextStyle(fontSize: 13, color: textDark),
              decoration: InputDecoration(
                hintText: "Write a message for your peers...",
                hintStyle: const TextStyle(color: textGrey, fontSize: 12),
                filled: true,
                fillColor: cardBorder,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: primaryPink, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Story preview
            if (_mediaUrlController.text.isNotEmpty) ...[
              const Text(
                "Story Preview",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 280,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  image: DecorationImage(
                    image: NetworkImage(_mediaUrlController.text),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      _captionController.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
