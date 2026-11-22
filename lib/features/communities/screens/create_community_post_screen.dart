import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateCommunityPostScreen extends StatefulWidget {
  final String communityId;
  final String communityName;

  const CreateCommunityPostScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  static Future<bool?> open(
    BuildContext context, {
    required String communityId,
    required String communityName,
  }) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateCommunityPostScreen(
          communityId: communityId,
          communityName: communityName,
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

  String _postType = 'post'; // 'post', 'question', 'reel'
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please write some content")),
      );
      return;
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSubmitting = true);

    try {
      await _client.from('community_posts').insert({
        'community_id': widget.communityId,
        'user_id': userId,
        'post_type': _postType,
        'title': _titleController.text.trim().isNotEmpty ? _titleController.text.trim() : null,
        'content': content,
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error posting: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isQ = _postType == 'question';

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
          isQ ? "Ask a Question" : "Create Post",
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
                      isQ ? "Ask" : "Post",
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
          Row(
            children: [
              _buildTypeChip('post', 'Feed Post', Icons.notes_rounded),
              const SizedBox(width: 8),
              _buildTypeChip('question', 'Q&A Question', Icons.help_outline_rounded),
              const SizedBox(width: 8),
              _buildTypeChip('reel', 'Reel Video', Icons.videocam_rounded),
            ],
          ),
          const SizedBox(height: 20),

          // Title (Always good for questions or articles)
          TextField(
            controller: _titleController,
            style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16),
            decoration: InputDecoration(
              hintText: isQ ? "What is your question? (e.g. How to use Riverpod with Supabase?)" : "Title (optional)",
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
            maxLines: 10,
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, height: 1.4),
            decoration: InputDecoration(
              hintText: isQ
                  ? "Describe your problem in detail. You can include error messages, code snippets, or what you've tried..."
                  : "Share knowledge, insights, or start a discussion with fellow community members...",
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
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
      onSelected: (_) => setState(() => _postType = type),
    );
  }
}
