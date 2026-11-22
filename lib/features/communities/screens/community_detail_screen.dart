import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'community_post_detail_screen.dart';
import 'create_community_post_screen.dart';

class CommunityDetailScreen extends StatefulWidget {
  final String communityId;
  final Map<String, dynamic>? initialData;

  const CommunityDetailScreen({
    super.key,
    required this.communityId,
    this.initialData,
  });

  static Future<void> open(BuildContext context, {required String communityId, Map<String, dynamic>? initialData}) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityDetailScreen(communityId: communityId, initialData: initialData),
      ),
    );
  }

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late TabController _tabController;

  Map<String, dynamic>? _community;
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _reels = [];
  List<Map<String, dynamic>> _questions = [];
  bool _isMember = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _community = widget.initialData;
    _fetchCommunityData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchCommunityData() async {
    final userId = _client.auth.currentUser?.id;

    try {
      // 1. Fetch community details
      final commRes = await _client
          .from('communities')
          .select()
          .eq('id', widget.communityId)
          .single();

      _community = Map<String, dynamic>.from(commRes);

      // 2. Check if current user is member
      if (userId != null) {
        final memberCheck = await _client
            .from('community_members')
            .select('role')
            .eq('community_id', widget.communityId)
            .eq('user_id', userId)
            .maybeSingle();

        _isMember = memberCheck != null;
      }

      // 3. Fetch community posts
      final postsRes = await _client
          .from('community_posts')
          .select('*, profiles:user_id(id, full_name, username, avatar_url, is_verified)')
          .eq('community_id', widget.communityId)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);

      final allPosts = List<Map<String, dynamic>>.from(postsRes);
      _posts = allPosts.where((p) => p['post_type'] == 'post').toList();
      _reels = allPosts.where((p) => p['post_type'] == 'reel').toList();
      _questions = allPosts.where((p) => p['post_type'] == 'question').toList();

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[CommunityDetailScreen] fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleJoin() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      if (_isMember) {
        await _client
            .from('community_members')
            .delete()
            .eq('community_id', widget.communityId)
            .eq('user_id', userId);
        setState(() {
          _isMember = false;
          _community?['members_count'] = ((_community?['members_count'] ?? 1) - 1).clamp(0, 999999);
        });
      } else {
        await _client.from('community_members').insert({
          'community_id': widget.communityId,
          'user_id': userId,
          'role': 'member',
        });
        setState(() {
          _isMember = true;
          _community?['members_count'] = (_community?['members_count'] ?? 0) + 1;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPostTypeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161F30),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Text(
                "Create in Community",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
              ),
              const SizedBox(height: 16),
              _buildActionTile(
                icon: Icons.edit_note_rounded,
                color: const Color(0xFF00B2FF),
                title: "Share Feed Post",
                subtitle: "Post ideas, discussions, photos with community members",
                onTap: () {
                  Navigator.pop(ctx);
                  _openCreatePost('post');
                },
              ),
              const SizedBox(height: 10),
              _buildActionTile(
                icon: Icons.live_tv_rounded,
                color: const Color(0xFF10B981),
                title: "Post Community Reel",
                subtitle: "Upload a short video or tutorial inside this group",
                onTap: () {
                  Navigator.pop(ctx);
                  _openCreatePost('reel');
                },
              ),
              const SizedBox(height: 10),
              _buildActionTile(
                icon: Icons.help_outline_rounded,
                color: const Color(0xFFF59E0B),
                title: "Ask a Question (Q&A)",
                subtitle: "Ask coding, trading, or course questions to get verified answers",
                onTap: () {
                  Navigator.pop(ctx);
                  _openCreatePost('question');
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCreatePost(String postType) async {
    final res = await CreateCommunityPostScreen.open(
      context,
      communityId: widget.communityId,
      initialType: postType,
    );
    if (res == true) _fetchCommunityData();
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF64748B), size: 14),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _community ?? widget.initialData ?? {};
    final name = c['name'] ?? 'Community';
    final desc = c['description'] ?? '';
    final coverUrl = c['cover_url'];
    final avatarUrl = c['avatar_url'];
    final category = c['category'] ?? 'education';
    final members = c['members_count'] ?? 1;
    final posts = c['posts_count'] ?? 0;
    final rules = (c['rules'] as List?)?.cast<String>() ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF0B101B),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, innerBoxScrolled) => [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: const Color(0xFF0B101B),
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                ),
                onPressed: () {},
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  coverUrl != null
                      ? Image.network(coverUrl, fit: BoxFit.cover)
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0284C7), Color(0xFF0F172A)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, const Color(0xFF0B101B).withOpacity(0.95)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 20,
                    right: 20,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00B2FF),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF00B2FF).withOpacity(0.4), blurRadius: 16),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 36,
                            backgroundColor: const Color(0xFF161F30),
                            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                            child: avatarUrl == null
                                ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'C',
                                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900))
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "${category.toString().toUpperCase()} GROUP",
                                style: const TextStyle(
                                  color: Color(0xFF00B2FF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
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
          ),

          // Community Summary & Join Button
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (desc.isNotEmpty) ...[
                    Text(
                      desc,
                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Stats Row
                  Row(
                    children: [
                      _buildStatChip(Icons.people_rounded, "$members Members"),
                      const SizedBox(width: 8),
                      _buildStatChip(Icons.dynamic_feed_rounded, "$posts Posts"),
                      const SizedBox(width: 8),
                      _buildStatChip(Icons.help_center_rounded, "${_questions.length} Questions"),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Join / Joined Button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _toggleJoin,
                      icon: Icon(_isMember ? Icons.check_circle_rounded : Icons.group_add_rounded, size: 18),
                      label: Text(
                        _isMember ? "Joined (Member)" : "Join Community",
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isMember ? const Color(0xFF1E293B) : const Color(0xFF00B2FF),
                        foregroundColor: Colors.white,
                        elevation: _isMember ? 0 : 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: _isMember ? Colors.white24 : Colors.transparent),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Persistent TabBar
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabBarDelegate(
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF00B2FF),
                indicatorWeight: 3,
                labelColor: const Color(0xFF00B2FF),
                unselectedLabelColor: const Color(0xFF94A3B8),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                tabs: [
                  Tab(text: "Feed (${_posts.length})"),
                  Tab(text: "Reels (${_reels.length})"),
                  Tab(text: "Q&A (${_questions.length})"),
                  const Tab(text: "Rules"),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Feed Posts
            _buildPostList(_posts, emptyLabel: "No community feed posts yet. Be the first to post!"),

            // Tab 2: Community Reels
            _buildReelsGrid(_reels),

            // Tab 3: Q&A Discussions
            _buildPostList(_questions, isQnATab: true, emptyLabel: "No open questions. Ask a question to get answers!"),

            // Tab 4: Rules & About
            _buildRulesTab(rules),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showPostTypeSelector,
        backgroundColor: const Color(0xFF00B2FF),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text("Post / Ask", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161F30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF00B2FF), size: 14),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPostList(List<Map<String, dynamic>> items, {bool isQnATab = false, required String emptyLabel}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00B2FF)));
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isQnATab ? Icons.question_answer_outlined : Icons.dynamic_feed_outlined, color: const Color(0xFF475569), size: 48),
              const SizedBox(height: 12),
              Text(emptyLabel, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length,
      itemBuilder: (ctx, idx) => _buildPostCard(items[idx], isQnA: isQnATab),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, {bool isQnA = false}) {
    final prof = post['profiles'] as Map<String, dynamic>? ?? {};
    final authorName = prof['full_name'] ?? prof['username'] ?? 'Member';
    final avatar = prof['avatar_url'];
    final title = post['title'];
    final content = post['content'] ?? '';
    final upvotes = post['upvotes_count'] ?? 0;
    final comments = post['comments_count'] ?? 0;
    final isSolved = post['is_solved'] == true;
    final created = post['created_at'] != null ? DateTime.parse(post['created_at']).toLocal().toString().substring(0, 16) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161F30),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSolved ? const Color(0xFF10B981).withOpacity(0.4) : Colors.white.withOpacity(0.06),
        ),
      ),
      child: InkWell(
        onTap: () => CommunityPostDetailScreen.open(context, postId: post['id'], initialPost: post),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author Row
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF00B2FF),
                    backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                    child: avatar == null ? Text(authorName[0], style: const TextStyle(color: Colors.white, fontSize: 12)) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(authorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(created, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5)),
                      ],
                    ),
                  ),
                  if (isSolved)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 12),
                          SizedBox(width: 4),
                          Text("Solved", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 10.5)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // Title if present
              if (title != null && title.isNotEmpty) ...[
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 6),
              ],

              // Content
              Text(
                content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),

              // Footer: Upvotes & Comments
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_upward_rounded, color: Color(0xFF00B2FF), size: 14),
                        const SizedBox(width: 4),
                        Text("$upvotes", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    children: [
                      const Icon(Icons.comment_outlined, color: Color(0xFF94A3B8), size: 14),
                      const SizedBox(width: 4),
                      Text("$comments answers", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReelsGrid(List<Map<String, dynamic>> reels) {
    if (reels.isEmpty) {
      return const Center(
        child: Text("No community reels yet.", style: TextStyle(color: Color(0xFF94A3B8))),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: reels.length,
      itemBuilder: (ctx, idx) {
        final r = reels[idx];
        final thumb = r['thumbnail_url'];
        final title = r['title'] ?? 'Reel';

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161F30),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumb != null) Image.network(thumb, fit: BoxFit.cover),
                Container(color: Colors.black26),
                const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 40)),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRulesTab(List<String> rules) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          "COMMUNITY GUIDELINES & RULES",
          style: TextStyle(color: Color(0xFF00B2FF), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.1),
        ),
        const SizedBox(height: 12),
        if (rules.isEmpty)
          const Text("Standard ZEV community etiquette applies.", style: TextStyle(color: Color(0xFF94A3B8)))
        else
          ...rules.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: const Color(0xFF161F30), shape: BoxShape.circle),
                    child: Center(
                      child: Text("${entry.key + 1}", style: const TextStyle(color: Color(0xFF00B2FF), fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(entry.value, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4)),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  _SliverTabBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: const Color(0xFF0B101B), child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) => false;
}
