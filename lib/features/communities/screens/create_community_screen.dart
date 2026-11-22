import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/zev_theme.dart';

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});

  static Future<bool?> open(BuildContext context) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateCommunityScreen()),
    );
  }

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _client = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _category = 'education';
  bool _isPrivate = false;
  bool _isSubmitting = false;

  final _categories = [
    {'id': 'education', 'name': 'Safi Academy & Education'},
    {'id': 'programming', 'name': 'Programming & Dev'},
    {'id': 'trading', 'name': 'Crypto & Forex Trading'},
    {'id': 'technology', 'name': 'Tech & AI'},
    {'id': 'design', 'name': 'UI/UX & Creative Design'},
    {'id': 'business', 'name': 'Business & Startup'},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _createCommunity() async {
    final name = _nameController.text.trim();
    final desc = _descController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a community name")),
      );
      return;
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final slug = '${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${DateTime.now().millisecondsSinceEpoch % 10000}';

    setState(() => _isSubmitting = true);

    try {
      final commRes = await _client.from('communities').insert({
        'creator_id': userId,
        'name': name,
        'slug': slug,
        'description': desc,
        'category': _category,
        'is_private': _isPrivate,
        'members_count': 1,
      }).select().single();

      // Automatically add creator as admin member
      await _client.from('community_members').insert({
        'community_id': commRes['id'],
        'user_id': userId,
        'role': 'admin',
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error creating community: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B101B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B101B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Create Community",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "COMMUNITY NAME",
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "e.g. Flutter Masterclass Afghan, Crypto Pro Traders",
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF161F30),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            "CATEGORY",
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF161F30),
              borderRadius: BorderRadius.circular(14),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _category,
                isExpanded: true,
                dropdownColor: const Color(0xFF161F30),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                items: _categories.map((c) {
                  return DropdownMenuItem<String>(
                    value: c['id'],
                    child: Text(c['name']!),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _category = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            "DESCRIPTION",
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descController,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "What is this group about? Who should join?",
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF161F30),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),

          // Privacy Switch
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF161F30),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(_isPrivate ? Icons.lock_rounded : Icons.public_rounded, color: const Color(0xFF00B2FF), size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPrivate ? "Private Community" : "Public Community",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      Text(
                        _isPrivate ? "Only approved members can view and post" : "Anyone on ZEV can find and view posts",
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isPrivate,
                  activeColor: const Color(0xFF00B2FF),
                  onChanged: (val) => setState(() => _isPrivate = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _createCommunity,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B2FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("Create Group", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
