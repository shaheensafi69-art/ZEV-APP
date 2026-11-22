import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'community_detail_screen.dart';
import 'create_community_screen.dart';

class CommunitiesListScreen extends StatefulWidget {
  const CommunitiesListScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CommunitiesListScreen()),
    );
  }

  @override
  State<CommunitiesListScreen> createState() => _CommunitiesListScreenState();
}

class _CommunitiesListScreenState extends State<CommunitiesListScreen> {
  final _client = Supabase.instance.client;
  String _selectedCategory = 'all';
  List<Map<String, dynamic>> _communities = [];
  List<Map<String, dynamic>> _myJoined = [];
  bool _isLoading = true;

  final _categories = [
    {'id': 'all', 'label': 'All Groups', 'icon': Icons.public_rounded},
    {'id': 'education', 'label': 'Safi Academy & Education', 'icon': Icons.school_rounded},
    {'id': 'programming', 'label': 'Programming & Dev', 'icon': Icons.code_rounded},
    {'id': 'trading', 'label': 'Crypto & Trading', 'icon': Icons.trending_up_rounded},
    {'id': 'technology', 'label': 'Tech & AI', 'icon': Icons.memory_rounded},
    {'id': 'design', 'label': 'UI/UX & Design', 'icon': Icons.palette_rounded},
    {'id': 'business', 'label': 'Business & Startup', 'icon': Icons.business_center_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _loadCommunities();
  }

  Future<void> _loadCommunities() async {
    final userId = _client.auth.currentUser?.id;
    try {
      setState(() => _isLoading = true);

      // 1. Fetch joined communities
      if (userId != null) {
        final joinedRes = await _client
            .from('community_members')
            .select('community_id, communities(*)')
            .eq('user_id', userId);

        _myJoined = List<Map<String, dynamic>>.from(
          (joinedRes as List).map((j) => j['communities']).where((c) => c != null),
        );
      }

      // 2. Fetch all public communities
      var query = _client.from('communities').select();
      if (_selectedCategory != 'all') {
        query = query.eq('category', _selectedCategory);
      }

      final res = await query.order('members_count', ascending: false).limit(50);
      _communities = List<Map<String, dynamic>>.from(res);

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[CommunitiesListScreen] error: $e');
      if (mounted) setState(() => _isLoading = false);
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
        title: const Column(
          children: [
            Text(
              "Communities & Groups",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
            ),
            Text(
              "Facebook Groups & Q&A Forums",
              style: TextStyle(color: Color(0xFF00B2FF), fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF00B2FF)),
            tooltip: "Create Group",
            onPressed: () async {
              final created = await CreateCommunityScreen.open(context);
              if (created == true) _loadCommunities();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCommunities,
        color: const Color(0xFF00B2FF),
        backgroundColor: const Color(0xFF161F30),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: [
            // Category Chips
            _buildCategoryBar(),

            const SizedBox(height: 12),

            // My Joined Groups (if any)
            if (_myJoined.isNotEmpty && _selectedCategory == 'all') ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.group_rounded, color: Color(0xFF00B2FF), size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      "MY COMMUNITIES",
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                    ),
                    const Spacer(),
                    Text("${_myJoined.length} Joined", style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _myJoined.length,
                  itemBuilder: (ctx, idx) => _buildJoinedGroupCard(_myJoined[idx]),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Explore All Groups Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.explore_rounded, color: Color(0xFFF59E0B), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    "EXPLORE COMMUNITIES",
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: Color(0xFF00B2FF)),
                ),
              )
            else if (_communities.isEmpty)
              _buildEmptyState()
            else
              ..._communities.map((c) => _buildCommunityFeedCard(c)),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBar() {
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (ctx, idx) {
          final cat = _categories[idx];
          final isSelected = _selectedCategory == cat['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(cat['icon'] as IconData, size: 14, color: isSelected ? Colors.white : const Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Text(cat['label'] as String),
                ],
              ),
              selected: isSelected,
              selectedColor: const Color(0xFF00B2FF),
              backgroundColor: const Color(0xFF161F30),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide(color: isSelected ? const Color(0xFF00B2FF) : Colors.white.withOpacity(0.06)),
              onSelected: (_) {
                setState(() => _selectedCategory = cat['id'] as String);
                _loadCommunities();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildJoinedGroupCard(Map<String, dynamic> c) {
    final name = c['name'] ?? 'Community';
    final coverUrl = c['cover_url'];
    final members = c['members_count'] ?? 1;

    return InkWell(
      onTap: () => CommunityDetailScreen.open(context, communityId: c['id'], initialData: c),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF161F30),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: coverUrl != null
                  ? Image.network(coverUrl, height: 60, width: double.infinity, fit: BoxFit.cover)
                  : Container(
                      height: 60,
                      color: const Color(0xFF1E293B),
                      child: const Center(
                        child: Icon(Icons.groups_rounded, color: Color(0xFF00B2FF), size: 28),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "$members members",
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityFeedCard(Map<String, dynamic> c) {
    final name = c['name'] ?? 'Community';
    final desc = c['description'] ?? '';
    final coverUrl = c['cover_url'];
    final avatarUrl = c['avatar_url'];
    final members = c['members_count'] ?? 1;
    final posts = c['posts_count'] ?? 0;
    final isPrivate = c['is_private'] == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161F30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: InkWell(
        onTap: () => CommunityDetailScreen.open(context, communityId: c['id'], initialData: c),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image with Gradient
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: coverUrl != null
                      ? Image.network(coverUrl, height: 110, width: double.infinity, fit: BoxFit.cover)
                      : Container(
                          height: 110,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.groups_rounded, color: Color(0xFF00B2FF), size: 40),
                          ),
                        ),
                ),
                Positioned(
                  top: 10,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isPrivate ? Icons.lock_rounded : Icons.public_rounded, size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          isPrivate ? "Private Group" : "Public Group",
                          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Info Body
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF00B2FF),
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'C',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w900),
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.3),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.people_alt_rounded, color: Color(0xFF00B2FF), size: 14),
                            const SizedBox(width: 4),
                            Text("$members members", style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5)),
                            const SizedBox(width: 12),
                            const Icon(Icons.forum_rounded, color: Color(0xFF10B981), size: 14),
                            const SizedBox(width: 4),
                            Text("$posts posts", style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Icon(Icons.group_work_outlined, color: Color(0xFF475569), size: 56),
            const SizedBox(height: 14),
            const Text(
              "No Communities in this category yet",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              "Be the first to create a discussion community!",
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => CreateCommunityScreen.open(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text("Create Group"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B2FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
