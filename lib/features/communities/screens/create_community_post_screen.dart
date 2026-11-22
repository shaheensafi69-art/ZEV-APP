import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/zev_theme.dart';

class CreateCommunityPostScreen extends StatefulWidget {
  final String communityId;
  final String initialType; // 'post', 'reel', 'question'

  const CreateCommunityPostScreen({
    super.key,
    required this.communityId,
    this.initialType = 'post',
  });

  static Future<bool?> open(BuildContext context, {required String communityId, String initialType = 'post'}) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateCommunityPostScreen(communityId: communityId, initialType: initialType),
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
  late String _postType;
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

  Future<void> _submit() async {
    final title = _titleController.text.trim();
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
        'title': title.isNotEmpty ? title : null,
        'content': content,
      });

      if (mounted) Navigator.pop(context, true);
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
      backgroundColor: const Color(0xFF0B101B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B101B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isQ ? "Ask a Question" : "Create Post",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _isSubmitting ? null : _submit,
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF00B2FF),
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
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            decoration: InputDecoration(
              hintText: isQ ? "What is your question? (e.g. How to use Riverpod with Supabase?)" : "Title (optional)",
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
              filled: true,
              fillColor: const Color(0xFF161F30),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),

          // Content Box
          TextField(
            controller: _contentController,
            maxLines: 10,
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            decoration: InputDecoration(
              hintText: isQ
                  ? "Describe your problem in detail. You can include error messages, code snippets, or what you've tried..."
                  : "Share knowledge, insights, or start a discussion with fellow community members...",
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF161F30),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
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
          Icon(icon, size: 14, color: selected ? Colors.white : const Color(0xFF94A3B8)),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
      selected: selected,
      selectedColor: const Color(0xFF00B2FF),
      backgroundColor: const Color(0xFF161F30),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF94A3B8),
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      side: BorderSide(color: selected ? const Color(0xFF00B2FF) : Colors.white.withOpacity(0.06)),
      onSelected: (_) => setState(() => _postType = type),
    );
  }
}
