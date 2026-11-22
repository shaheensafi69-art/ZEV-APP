import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    _loadPostDetails();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadPostDetails() async {
    final userId = _client.auth.currentUser?.id;

    try {
      // 1. Fetch fresh post data
      final postRes = await _client
          .from('community_posts')
          .select('*, profiles(username, full_name, avatar_url, is_verified)')
          .eq('id', widget.postId)
          .single();

      _post = Map<String, dynamic>.from(postRes);

      // 2. Fetch comments / answers
      final commentsRes = await _client
          .from('community_comments')
          .select('*, profiles(username, full_name, avatar_url, is_verified)')
          .eq('post_id', widget.postId)
          .order('is_best_answer', ascending: false)
          .order('upvotes_count', ascending: false)
          .order('created_at', ascending: true);

      _comments = List<Map<String, dynamic>>.from(commentsRes);

      // 3. Fetch user's current vote
      if (userId != null) {
        final voteRes = await _client
            .from('community_post_votes')
            .select('vote_type')
            .eq('post_id', widget.postId)
            .eq('user_id', userId)
            .maybeSingle();

        if (voteRes != null) {
          _userVote = (voteRes['vote_type'] as num?)?.toInt() ?? 0;
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[CommunityPostDetailScreen] error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _vote(int type) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    HapticFeedback.selectionClick();

    try {
      final res = await _client.rpc('vote_community_post', params: {
        'p_post_id': widget.postId,
        'p_vote_type': type,
      });

      if (res is Map && mounted) {
        setState(() {
          _userVote = (res['current_vote'] as num?)?.toInt() ?? 0;
          if (_post != null) {
            _post!['upvotes_count'] = res['upvotes_count'];
          }
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

    try {
      final insertRes = await _client.from('community_comments').insert({
        'post_id': widget.postId,
        'user_id': userId,
        'content': text,
      }).select('*, profiles(username, full_name, avatar_url, is_verified)').single();

      _commentController.clear();

      setState(() {
        _comments.add(Map<String, dynamic>.from(insertRes));
        if (_post != null) {
          _post!['comments_count'] = ((_post!['comments_count'] as num?) ?? 0) + 1;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error posting answer: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPostingComment = false);
    }
  }

  Future<void> _markBestAnswer(String commentId) async {
    HapticFeedback.mediumImpact();

    try {
      await _client.rpc('mark_best_community_answer', params: {
        'p_post_id': widget.postId,
        'p_comment_id': commentId,
      });

      setState(() {
        if (_post != null) {
          _post!['is_solved'] = true;
          _post!['best_answer_id'] = commentId;
        }
        for (var c in _comments) {
          c['is_best_answer'] = (c['id'] == commentId);
        }
      });
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
    if (_post == null && _isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0284C7))),
      );
    }

    final prof = _post?['profiles'] as Map<String, dynamic>? ?? {};
    final authorName = prof['full_name'] ?? prof['username'] ?? 'Member';
    final avatar = prof['avatar_url'];
    final title = _post?['title'];
    final content = _post?['content'] ?? '';
    final upvotes = _post?['upvotes_count'] ?? 0;
    final isQnA = _post?['post_type'] == 'question';
    final currentUserId = _client.auth.currentUser?.id;
    final isAuthor = currentUserId != null && currentUserId == _post?['user_id'];
    final isSolved = _post?['is_solved'] == true;

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
        title: Text(
          isQnA ? "Question & Answers" : "Community Post",
          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 17),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Author Row
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFF0284C7),
                            backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                            child: avatar == null ? Text(authorName[0], style: const TextStyle(color: Colors.white)) : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(authorName, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 14)),
                                Text(
                                  isQnA ? "Asked a question" : "Shared a post",
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          if (isSolved)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
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
                          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 16.5),
                        ),
                        const SizedBox(height: 8),
                      ],

                      SelectableText(
                        content,
                        style: const TextStyle(color: Color(0xFF334155), fontSize: 14, height: 1.5),
                      ),
                      const SizedBox(height: 16),

                      // Voting Bar
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.arrow_upward_rounded,
                                    color: _userVote == 1 ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                    size: 20,
                                  ),
                                  onPressed: () => _vote(1),
                                ),
                                Text(
                                  "$upvotes",
                                  style: TextStyle(
                                    color: _userVote != 0 ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.arrow_downward_rounded,
                                    color: _userVote == -1 ? Colors.redAccent : const Color(0xFF64748B),
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
                            style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Text(
                  isQnA ? "ANSWERS & DISCUSSIONS" : "COMMENTS",
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                ),
                const SizedBox(height: 12),

                if (_isLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFF0284C7))))
                else if (_comments.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        isQnA ? "No answers yet. Share your knowledge!" : "No comments yet.",
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
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
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: _commentController,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: isQnA ? "Write an answer or helpful solution..." : "Write a comment...",
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(color: Color(0xFF0284C7), shape: BoxShape.circle),
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
        color: isBest ? const Color(0xFFECFDF5) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBest ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
          width: isBest ? 1.5 : 1,
        ),
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
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF0284C7),
                backgroundImage: cAvatar != null ? NetworkImage(cAvatar) : null,
                child: cAvatar == null ? Text(cAuthor[0], style: const TextStyle(color: Colors.white, fontSize: 11)) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(cAuthor, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13)),
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
                ),
              if (isAuthor && isQnA && !isBest)
                TextButton.icon(
                  onPressed: () => _markBestAnswer(commentId),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF10B981)),
                  label: const Text(
                    "Mark Best",
                    style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            cContent,
            style: const TextStyle(color: Color(0xFF334155), fontSize: 13.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}
