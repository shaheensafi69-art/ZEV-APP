import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
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
  final TextEditingController _searchCtrl = TextEditingController();

  String _selectedCategory = 'all';
  List<Map<String, dynamic>> _communities = [];
  List<Map<String, dynamic>> _myJoined = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Timer? _debounceTimer;

  final List<Map<String, dynamic>> _categories = [
    {'id': 'all', 'label': 'Explore All', 'icon': Icons.explore_rounded},
    {'id': 'education', 'label': 'Education & Academy', 'icon': Icons.school_rounded},
    {'id': 'trading', 'label': 'Trading & Crypto', 'icon': Icons.trending_up_rounded},
    {'id': 'programming', 'label': 'Coding & Dev', 'icon': Icons.code_rounded},
    {'id': 'technology', 'label': 'Technology & AI', 'icon': Icons.memory_rounded},
    {'id': 'business', 'label': 'Business & Startup', 'icon': Icons.business_center_rounded},
    {'id': 'general', 'label': 'General Discussion', 'icon': Icons.chat_bubble_outline_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _loadCommunities();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() => _searchQuery = val.trim().toLowerCase());
    });
  }

  Future<void> _loadCommunities() async {
    final userId = _client.auth.currentUser?.id;
    setState(() => _isLoading = true);

    try {
      // 1. Load user's joined communities
      if (userId != null) {
        final myMemberships = await _client
            .from('community_members')
            .select('community_id, communities(*)')
            .eq('user_id', userId);

        _myJoined = (myMemberships as List)
            .map((m) => m['communities'] as Map<String, dynamic>?)
            .whereType<Map<String, dynamic>>()
            .toList();
      }

      // 2. Load feed communities
      var query = _client.from('communities').select();
      if (_selectedCategory != 'all') {
        query = query.eq('category', _selectedCategory);
      }

      final res = await query.order('members_count', ascending: false).limit(40);

      setState(() {
        _communities = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[CommunitiesListScreen] error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredCommunities {
    if (_searchQuery.isEmpty) return _communities;
    return _communities.where((c) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      final desc = (c['description'] ?? '').toString().toLowerCase();
      final cat = (c['category'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) || desc.contains(_searchQuery) || cat.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final displayList = _filteredCommunities;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          children: [
            Text(
              "Communities & Groups",
              style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 17),
            ),
            Text(
              "Verified Groups, Discussion & Q&A Forums",
              style: TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF0284C7)),
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
        color: const Color(0xFF0284C7),
        backgroundColor: Colors.white,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: [
            // Top Live Search Box
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF0284C7), size: 22),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.cancel_rounded, color: Color(0xFF94A3B8), size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    hintText: "Search communities, topics, or clubs...",
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 6),

            // Category Chips
            _buildCategoryBar(),

            const SizedBox(height: 12),

            // My Joined Groups (if any and not in search mode)
            if (_myJoined.isNotEmpty && _selectedCategory == 'all' && _searchQuery.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.group_rounded, color: Color(0xFF0284C7), size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      "MY COMMUNITIES",
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                    ),
                    const Spacer(),
                    Text("${_myJoined.length} Joined", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
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
              const SizedBox(height: 14),
              const Divider(color: Color(0xFFE2E8F0), thickness: 1, indent: 16, endIndent: 16),
              const SizedBox(height: 10),
            ],

            // Section Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.travel_explore_rounded, color: Color(0xFF0284C7), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _searchQuery.isNotEmpty
                        ? "SEARCH RESULTS (${displayList.length})"
                        : _selectedCategory == 'all'
                            ? "POPULAR COMMUNITIES"
                            : "${_selectedCategory.toUpperCase()} GROUPS",
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Communities List
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF0284C7))),
              )
            else if (displayList.isEmpty)
              _buildEmptyState()
            else
              ...displayList.map((c) => _buildCommunityFeedCard(c)),
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
                  Icon(cat['icon'] as IconData, size: 14, color: isSelected ? Colors.white : const Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  Text(cat['label'] as String),
                ],
              ),
              selected: isSelected,
              selectedColor: const Color(0xFF0284C7),
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF64748B),
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide(color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0)),
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
    final isVerified = c['is_verified'] == true;

    return InkWell(
      onTap: () => CommunityDetailScreen.open(context, communityId: c['id'], initialData: c),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: coverUrl != null
                  ? CachedNetworkImage(imageUrl: coverUrl, height: 60, width: double.infinity, fit: BoxFit.cover)
                  : Container(
                      height: 60,
                      color: const Color(0xFFF1F5F9),
                      child: const Center(
                        child: Icon(Icons.groups_rounded, color: Color(0xFF0284C7), size: 28),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 3),
                        const Icon(Icons.verified_rounded, color: Color(0xFF00D4FF), size: 13),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "$members members",
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
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
    final isVerified = c['is_verified'] == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
                      ? CachedNetworkImage(imageUrl: coverUrl, height: 110, width: double.infinity, fit: BoxFit.cover)
                      : Container(
                          height: 110,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.groups_rounded, color: Color(0xFF0284C7), size: 40),
                          ),
                        ),
                ),
                Positioned(
                  top: 10,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isPrivate ? Icons.lock_rounded : Icons.public_rounded, size: 12, color: Colors.white),
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
                    backgroundColor: const Color(0xFF0284C7),
                    backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15.5, fontWeight: FontWeight.w900),
                              ),
                            ),
                            if (isVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified_rounded, color: Color(0xFF00D4FF), size: 16),
                            ],
                          ],
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 1.3),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.people_alt_rounded, color: Color(0xFF0284C7), size: 14),
                            const SizedBox(width: 4),
                            Text("$members members", style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5)),
                            const SizedBox(width: 12),
                            const Icon(Icons.forum_rounded, color: Color(0xFF10B981), size: 14),
                            const SizedBox(width: 4),
                            Text("$posts posts", style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5)),
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
            const Icon(Icons.group_work_outlined, color: Color(0xFF94A3B8), size: 56),
            const SizedBox(height: 14),
            Text(
              _searchQuery.isNotEmpty ? "No matching communities found" : "No Communities in this category yet",
              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty ? "Try a different keyword or create this group!" : "Be the first to create a discussion community!",
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => CreateCommunityScreen.open(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text("Create Group"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
