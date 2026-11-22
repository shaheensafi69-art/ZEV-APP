import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _isLoading = true;
  bool _isMember = false;
  String _userRole = 'none';

  @override
  void initState() {
    super.initState();
    _community = widget.initialData;
    _tabController = TabController(length: 4, vsync: this);
    _loadCommunityData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCommunityData() async {
    final userId = _client.auth.currentUser?.id;

    try {
      // 1. Fetch community details
      final commRes = await _client
          .from('communities')
          .select()
          .eq('id', widget.communityId)
          .single();

      _community = Map<String, dynamic>.from(commRes);

      // 2. Check membership
      if (userId != null) {
        final memRes = await _client
            .from('community_members')
            .select('role')
            .eq('community_id', widget.communityId)
            .eq('user_id', userId)
            .maybeSingle();

        if (memRes != null) {
          _isMember = true;
          _userRole = memRes['role'] ?? 'member';
        } else {
          _isMember = false;
          _userRole = 'none';
        }
      }

      // 3. Fetch community posts & reels
      final postsRes = await _client
          .from('community_posts')
          .select('*, profiles(username, full_name, avatar_url, is_verified)')
          .eq('community_id', widget.communityId)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(50);

      setState(() {
        _posts = List<Map<String, dynamic>>.from(postsRes);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[CommunityDetailScreen] error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleMembership() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    HapticFeedback.lightImpact();

    try {
      if (_isMember) {
        // Leave
        await _client
            .from('community_members')
            .delete()
            .eq('community_id', widget.communityId)
            .eq('user_id', userId);

        setState(() {
          _isMember = false;
          _userRole = 'none';
          if (_community != null) {
            _community!['members_count'] = ((_community!['members_count'] as num?) ?? 1) - 1;
          }
        });
      } else {
        // Join
        await _client.from('community_members').insert({
          'community_id': widget.communityId,
          'user_id': userId,
          'role': 'member',
        });

        setState(() {
          _isMember = true;
          _userRole = 'member';
          if (_community != null) {
            _community!['members_count'] = ((_community!['members_count'] as num?) ?? 0) + 1;
          }
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

  @override
  Widget build(BuildContext context) {
    if (_community == null && _isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0284C7))),
      );
    }

    final c = _community ?? {};
    final name = c['name'] ?? 'Community';
    final desc = c['description'] ?? '';
    final coverUrl = c['cover_url'];
    final avatarUrl = c['avatar_url'];
    final category = c['category'] ?? 'education';
    final members = c['members_count'] ?? 1;
    final posts = c['posts_count'] ?? 0;
    final rules = (c['rules'] as List?)?.cast<String>() ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, innerBoxScrolled) => [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                  ],
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 16),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                    ],
                  ),
                  child: const Icon(Icons.share_rounded, color: Color(0xFF0F172A), size: 18),
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
                              colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.white.withValues(alpha: 0.95)],
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
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF0284C7).withValues(alpha: 0.2), blurRadius: 16),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 36,
                            backgroundColor: const Color(0xFF0284C7),
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
                                  color: Color(0xFF0F172A),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "${category.toString().toUpperCase()} GROUP",
                                style: const TextStyle(
                                  color: Color(0xFF0284C7),
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

          // Community Info & Action Bar
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (desc.isNotEmpty) ...[
                    Text(
                      desc,
                      style: const TextStyle(color: Color(0xFF475569), fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Stats Row
                  Row(
                    children: [
                      _buildStatChip(Icons.people_alt_rounded, "$members Members"),
                      const SizedBox(width: 8),
                      _buildStatChip(Icons.forum_rounded, "$posts Posts & Q&A"),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _toggleMembership,
                        icon: Icon(_isMember ? Icons.check_circle_rounded : Icons.group_add_rounded, size: 16),
                        label: Text(_isMember ? "Joined" : "Join Group"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isMember ? const Color(0xFFF1F5F9) : const Color(0xFF0284C7),
                          foregroundColor: _isMember ? const Color(0xFF0F172A) : Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Sliver TabBar Header
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabBarDelegate(
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF0284C7),
                indicatorWeight: 3,
                labelColor: const Color(0xFF0284C7),
                unselectedLabelColor: const Color(0xFF64748B),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(text: "Posts"),
                  Tab(text: "Q&A"),
                  Tab(text: "Reels"),
                  Tab(text: "Rules"),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            // 1. Regular Feed Posts
            _buildPostList(
              _posts.where((p) => p['post_type'] == 'post').toList(),
              emptyLabel: "No community feed posts yet. Be the first to share an update!",
            ),

            // 2. Q&A Forum (Reddit / StackOverflow style)
            _buildPostList(
              _posts.where((p) => p['post_type'] == 'question').toList(),
              isQnATab: true,
              emptyLabel: "No open questions yet. Ask something to the community!",
            ),

            // 3. Reels & Short Videos
            _buildReelsGrid(
              _posts.where((p) => p['post_type'] == 'reel').toList(),
            ),

            // 4. About & Guidelines
            _buildRulesTab(rules),
          ],
        ),
      ),
      floatingActionButton: _isMember
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await CreateCommunityPostScreen.open(
                  context,
                  communityId: widget.communityId,
                  communityName: name,
                );
                if (created == true) _loadCommunityData();
              },
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text("Post / Ask", style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
    );
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF0284C7), size: 14),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Color(0xFF475569), fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPostList(List<Map<String, dynamic>> items, {bool isQnATab = false, required String emptyLabel}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7)));
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isQnATab ? Icons.question_answer_outlined : Icons.dynamic_feed_outlined, color: const Color(0xFF94A3B8), size: 48),
              const SizedBox(height: 12),
              Text(emptyLabel, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSolved ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
          width: isSolved ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
                    backgroundColor: const Color(0xFF0284C7),
                    backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                    child: avatar == null ? Text(authorName[0], style: const TextStyle(color: Colors.white, fontSize: 12)) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(authorName, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(created, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                      ],
                    ),
                  ),
                  if (isSolved)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
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
                  style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 6),
              ],

              // Content
              Text(
                content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF475569), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),

              // Footer: Upvotes & Comments
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_upward_rounded, color: Color(0xFF0284C7), size: 14),
                        const SizedBox(width: 4),
                        Text("$upvotes", style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    children: [
                      const Icon(Icons.comment_outlined, color: Color(0xFF64748B), size: 14),
                      const SizedBox(width: 4),
                      Text("$comments answers", style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5)),
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
          style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.1),
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
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), shape: BoxShape.circle),
                    child: Center(
                      child: Text("${entry.key + 1}", style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(entry.value, style: const TextStyle(color: Color(0xFF475569), fontSize: 13, height: 1.4)),
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
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) => false;
}
