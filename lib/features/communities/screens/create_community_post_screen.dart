import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';

class CreateCommunityPostScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String initialType;

  const CreateCommunityPostScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.initialType = 'post',
  });

  static Future<bool?> open(
    BuildContext context, {
    required String communityId,
    required String communityName,
    String initialType = 'post',
  }) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateCommunityPostScreen(
          communityId: communityId,
          communityName: communityName,
          initialType: initialType,
        ),
      ),
    );
  }

  @override
  State<CreateCommunityPostScreen> createState() => _CreateCommunityPostScreenState();
}

class _CreateCommunityPostScreenState extends State<CreateCommunityPostScreen> {
  final _client = Supabase.instance.client;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _picker = ImagePicker();

  late String _postType; // 'post', 'question', 'reel'
  File? _selectedMediaFile;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _postType = widget.initialType;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    try {
      if (_postType == 'reel') {
        final video = await _picker.pickVideo(source: ImageSource.gallery);
        if (video != null) {
          setState(() => _selectedMediaFile = File(video.path));
        }
      } else {
        final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (image != null) {
          setState(() => _selectedMediaFile = File(image.path));
        }
      }
    } catch (e) {
      debugPrint("Error picking media: $e");
    }
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedMediaFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please write some content or attach media.")),
      );
      return;
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSubmitting = true);

    try {
      String? uploadedMediaUrl;
      if (_selectedMediaFile != null) {
        final ext = _postType == 'reel' ? 'mp4' : 'jpg';
        final fileName = '${_postType}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        uploadedMediaUrl = await CloudflareStorageService.instance.upload(
          bucket: _postType == 'reel' ? 'reels' : 'posts',
          path: fileName,
          file: _selectedMediaFile,
        );
      }

      await _client.from('community_posts').insert({
        'community_id': widget.communityId,
        'user_id': userId,
        'post_type': _postType,
        'title': _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : null,
        'content': content.isNotEmpty ? content : (_postType == 'reel' ? 'Community Reel' : 'Community Post'),
        'media_url': ?uploadedMediaUrl,
        if (uploadedMediaUrl != null && _postType == 'reel') 'thumbnail_url': uploadedMediaUrl,
      });

      // Update posts_count on community
      try {
        final c = await _client.from('communities').select('posts_count').eq('id', widget.communityId).single();
        final currentCount = (c['posts_count'] as num?) ?? 0;
        await _client.from('communities').update({'posts_count': currentCount + 1}).eq('id', widget.communityId);
      } catch (_) {}

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error publishing post: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isQ = _postType == 'question';
    final isReel = _postType == 'reel';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isReel
              ? "Publish Community Reel"
              : isQ
                  ? "Ask a Question"
                  : "Create Community Post",
          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 17),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _isSubmitting ? null : _submit,
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      isQ ? "Ask" : "Publish",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                    ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          // Post Type Switcher
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTypeChip('post', 'Feed Post', Icons.notes_rounded),
                const SizedBox(width: 8),
                _buildTypeChip('reel', 'Community Reel', Icons.videocam_rounded),
                const SizedBox(width: 8),
                _buildTypeChip('question', 'Q&A Question', Icons.help_outline_rounded),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Title
          TextField(
            controller: _titleController,
            style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16),
            decoration: InputDecoration(
              hintText: isQ
                  ? "What is your question? (e.g. Best practices for state management?)"
                  : isReel
                      ? "Reel Title / Caption..."
                      : "Post Title (optional)",
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
            ),
          ),
          const SizedBox(height: 14),

          // Content Box
          TextField(
            controller: _contentController,
            maxLines: isReel ? 3 : 8,
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, height: 1.4),
            decoration: InputDecoration(
              hintText: isQ
                  ? "Describe your question in detail..."
                  : isReel
                      ? "Write a description or tags for this community reel..."
                      : "Share knowledge, insights, or start a discussion with fellow community members...",
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),

          // Media Attachment Selector
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isReel ? Icons.video_file_rounded : Icons.photo_library_rounded,
                      color: const Color(0xFF0284C7),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isReel ? "Attach Reel Video" : "Attach Photo / Media",
                      style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _pickMedia,
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: Text(_selectedMediaFile != null ? "Change" : "Select"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0284C7),
                        side: const BorderSide(color: Color(0xFF0284C7)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
                if (_selectedMediaFile != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(isReel ? Icons.movie_rounded : Icons.image_rounded, color: const Color(0xFF0284C7), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedMediaFile!.path.split('/').last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel_rounded, color: Color(0xFF94A3B8), size: 18),
                          onPressed: () => setState(() => _selectedMediaFile = null),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String type, String label, IconData icon) {
    final selected = _postType == type;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: selected ? Colors.white : const Color(0xFF64748B)),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
      selected: selected,
      selectedColor: const Color(0xFF0284C7),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF64748B),
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      side: BorderSide(color: selected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0)),
      onSelected: (_) => setState(() {
        _postType = type;
        _selectedMediaFile = null;
      }),
    );
  }
}
