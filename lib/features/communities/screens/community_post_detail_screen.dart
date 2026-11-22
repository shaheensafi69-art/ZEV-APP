import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/zev_theme.dart';

class CommunityPostDetailScreen extends StatefulWidget {
  final String postId;
  final Map<String, dynamic>? initialPost;

  const CommunityPostDetailScreen({
    super.key,
    required this.postId,
    this.initialPost,
  });

  static Future<void> open(BuildContext context, {required String postId, Map<String, dynamic>? initialPost}) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityPostDetailScreen(postId: postId, initialPost: initialPost),
      ),
    );
  }

  @override
  State<CommunityPostDetailScreen> createState() => _CommunityPostDetailScreenState();
}

class _CommunityPostDetailScreenState extends State<CommunityPostDetailScreen> {
  final _client = Supabase.instance.client;
  final _commentController = TextEditingController();

  Map<String, dynamic>? _post;
  List<Map<String, dynamic>> _comments = [];
  int _userVote = 0; // -1, 0, 1
  bool _isLoading = true;
  bool _isPostingComment = false;

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    _loadPostAndComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadPostAndComments() async {
    final userId = _client.auth.currentUser?.id;

    try {
      // 1. Fetch post details
      final pRes = await _client
          .from('community_posts')
          .select('*, profiles:user_id(id, full_name, username, avatar_url, is_verified)')
          .eq('id', widget.postId)
          .single();

      _post = Map<String, dynamic>.from(pRes);

      // 2. Fetch user's existing vote
      if (userId != null) {
        final voteRes = await _client
            .from('community_post_votes')
            .select('vote_type')
            .eq('post_id', widget.postId)
            .eq('user_id', userId)
            .maybeSingle();

        _userVote = voteRes?['vote_type'] ?? 0;
      }

      // 3. Fetch comments / answers
      final commentsRes = await _client
          .from('community_comments')
          .select('*, profiles:user_id(id, full_name, username, avatar_url, is_verified)')
          .eq('post_id', widget.postId)
          .order('is_best_answer', ascending: false)
          .order('upvotes_count', ascending: false)
          .order('created_at', ascending: true);

      _comments = List<Map<String, dynamic>>.from(commentsRes);

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[CommunityPostDetailScreen] load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _vote(int direction) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final res = await _client.rpc('vote_community_post', params: {
        'p_post_id': widget.postId,
        'p_vote_type': direction,
      });

      if (res is Map) {
        setState(() {
          _userVote = res['current_vote'] ?? 0;
          _post?['upvotes_count'] = res['upvotes_count'] ?? (_post?['upvotes_count'] ?? 0);
        });
      }
    } catch (e) {
      debugPrint('[CommunityPostDetailScreen] vote error: $e');
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isPostingComment = true);
    _commentController.clear();

    try {
      final insertRes = await _client.from('community_comments').insert({
        'post_id': widget.postId,
        'user_id': userId,
        'content': text,
      }).select('*, profiles:user_id(id, full_name, username, avatar_url, is_verified)').single();

      setState(() {
        _comments.add(Map<String, dynamic>.from(insertRes));
        _post?['comments_count'] = (_post?['comments_count'] ?? 0) + 1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error submitting answer: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPostingComment = false);
    }
  }

  Future<void> _markBestAnswer(String commentId) async {
    try {
      final res = await _client.rpc('mark_best_community_answer', params: {
        'p_post_id': widget.postId,
        'p_comment_id': commentId,
      });

      if (res is Map && res['success'] == true) {
        setState(() {
          _post?['is_solved'] = true;
          _post?['best_answer_id'] = commentId;
          for (var c in _comments) {
            c['is_best_answer'] = c['id'] == commentId;
          }
          // Sort best answer to top
          _comments.sort((a, b) {
            if (a['is_best_answer'] == true) return -1;
            if (b['is_best_answer'] == true) return 1;
            return 0;
          });
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Marked as Best Answer!"),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _client.auth.currentUser?.id;
    final isAuthor = _post != null && currentUserId != null && _post!['user_id'] == currentUserId;
    final isQnA = _post?['post_type'] == 'question';

    final prof = _post?['profiles'] as Map<String, dynamic>? ?? {};
    final authorName = prof['full_name'] ?? prof['username'] ?? 'Author';
    final avatar = prof['avatar_url'];
    final title = _post?['title'];
    final content = _post?['content'] ?? '';
    final upvotes = _post?['upvotes_count'] ?? 0;
    final isSolved = _post?['is_solved'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF0B101B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B101B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isQnA ? "Question & Answers" : "Community Post",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Post Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161F30),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSolved ? const Color(0xFF10B981).withOpacity(0.3) : Colors.white.withOpacity(0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Author Row
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFF00B2FF),
                            backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                            child: avatar == null ? Text(authorName[0], style: const TextStyle(color: Colors.white)) : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(authorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                                Text(
                                  isQnA ? "Asked a question" : "Shared a post",
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          if (isSolved)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                                  SizedBox(width: 4),
                                  Text("Solved", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      if (title != null && title.isNotEmpty) ...[
                        Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16.5),
                        ),
                        const SizedBox(height: 8),
                      ],

                      SelectableText(
                        content,
                        style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14, height: 1.5),
                      ),
                      const SizedBox(height: 16),

                      // Voting Bar
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.arrow_upward_rounded,
                                    color: _userVote == 1 ? const Color(0xFF00B2FF) : const Color(0xFF94A3B8),
                                    size: 20,
                                  ),
                                  onPressed: () => _vote(1),
                                ),
                                Text(
                                  "$upvotes",
                                  style: TextStyle(
                                    color: _userVote != 0 ? const Color(0xFF00B2FF) : Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.arrow_downward_rounded,
                                    color: _userVote == -1 ? Colors.redAccent : const Color(0xFF94A3B8),
                                    size: 20,
                                  ),
                                  onPressed: () => _vote(-1),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            "${_comments.length} ${isQnA ? 'Answers' : 'Comments'}",
                            style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Text(
                  isQnA ? "ANSWERS & DISCUSSIONS" : "COMMENTS",
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                ),
                const SizedBox(height: 12),

                if (_isLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFF00B2FF))))
                else if (_comments.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        isQnA ? "No answers yet. Share your knowledge!" : "No comments yet.",
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                    ),
                  )
                else
                  ..._comments.map((comment) => _buildCommentCard(comment, isAuthor: isAuthor, isQnA: isQnA)),
              ],
            ),
          ),

          // Bottom Answer / Comment Box
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF161F30),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B101B),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _commentController,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: isQnA ? "Write an answer or helpful solution..." : "Write a comment...",
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(color: Color(0xFF00B2FF), shape: BoxShape.circle),
                    child: IconButton(
                      icon: _isPostingComment
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      onPressed: _isPostingComment ? null : _sendComment,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentCard(Map<String, dynamic> comment, {required bool isAuthor, required bool isQnA}) {
    final cProf = comment['profiles'] as Map<String, dynamic>? ?? {};
    final cAuthor = cProf['full_name'] ?? cProf['username'] ?? 'User';
    final cAvatar = cProf['avatar_url'];
    final cContent = comment['content'] ?? '';
    final isBest = comment['is_best_answer'] == true;
    final commentId = comment['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isBest ? const Color(0xFF064E3B).withOpacity(0.3) : const Color(0xFF161F30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBest ? const Color(0xFF10B981) : Colors.white.withOpacity(0.06),
          width: isBest ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF00B2FF),
                backgroundImage: cAvatar != null ? NetworkImage(cAvatar) : null,
                child: cAvatar == null ? Text(cAuthor[0], style: const TextStyle(color: Colors.white, fontSize: 11)) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(cAuthor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              if (isBest)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    children: [
                      Icon(Icons.star_rounded, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text("Best Answer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10.5)),
                    ],
                  ),
                )
              else if (isAuthor && isQnA)
                TextButton.icon(
                  onPressed: () => _markBestAnswer(commentId),
                  icon: const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 14),
                  label: const Text("Select as Best", style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            cContent,
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}
