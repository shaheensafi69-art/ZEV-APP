import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/theme/zev_theme.dart';

/// Instagram-Grade "New Message" Bottom Sheet to search users and start a direct conversation.
class NewChatSheet extends StatefulWidget {
  final Function(
    String userId,
    String username,
    String avatarUrl,
    String fullName,
    bool isVerified,
  ) onSelectUser;

  const NewChatSheet({super.key, required this.onSelectUser});

  static Future<void> show(
    BuildContext context, {
    required Function(
      String userId,
      String username,
      String avatarUrl,
      String fullName,
      bool isVerified,
    ) onSelectUser,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewChatSheet(onSelectUser: onSelectUser),
    );
  }

  @override
  State<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<NewChatSheet> {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  List<Map<String, dynamic>> _suggestedUsers = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchSuggestedUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchSuggestedUsers() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch users currently followed by the user
      final followsRes = await supabase
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', currentUserId)
          .limit(30);

      final followingIds = (followsRes as List)
          .map((f) => f['following_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      List<Map<String, dynamic>> users = [];

      if (followingIds.isNotEmpty) {
        final profsRes = await supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .inFilter('id', followingIds)
            .limit(20);

        users = List<Map<String, dynamic>>.from(profsRes);
      }

      // 2. If following is small, fetch other active users
      if (users.length < 10) {
        final othersRes = await supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .neq('id', currentUserId)
            .limit(20);

        final existingIds = users.map((u) => u['id'].toString()).toSet();
        for (final o in othersRes) {
          if (!existingIds.contains(o['id'].toString())) {
            users.add(o);
          }
        }
      }

      if (mounted) {
        setState(() {
          _suggestedUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching suggested chat users: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final currentUserId = supabase.auth.currentUser?.id;
      try {
        final res = await supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified')
            .neq('id', currentUserId ?? '')
            .or('username.ilike.%$trimmed%,first_name.ilike.%$trimmed%,last_name.ilike.%$trimmed%')
            .limit(20);

        if (mounted) {
          setState(() {
            _searchResults = List<Map<String, dynamic>>.from(res);
          });
        }
      } catch (e) {
        debugPrint("Error searching users for chat: $e");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final displayList = _isSearching ? _searchResults : _suggestedUsers;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4.5,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "New Message",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                      decoration: const InputDecoration(
                        hintText: "Search people...",
                        hintStyle: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF94A3B8)),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchChanged("");
                      },
                    ),
                ],
              ),
            ),
          ),

          // Subtitle
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isSearching ? "Search Results" : "Suggested Contacts",
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),

          // User List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: ZevColors.primaryBlue,
                    ),
                  )
                : displayList.isEmpty
                    ? Center(
                        child: Text(
                          _isSearching ? "No users found" : "No suggestions available",
                          style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        itemCount: displayList.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final user = displayList[index];
                          final uId = user['id']?.toString() ?? '';
                          final uName = user['username']?.toString() ?? 'user';
                          final avatar = user['avatar_url']?.toString() ?? '';
                          final fn = user['first_name']?.toString() ?? '';
                          final ln = user['last_name']?.toString() ?? '';
                          final full = "$fn $ln".trim();
                          final isVerified = user['is_verified'] == true;

                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.pop(context);
                              widget.onSelectUser(uId, uName, avatar, full, isVerified);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFF1F5F9)),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFFE2E8F0),
                                    backgroundImage: avatar.isNotEmpty
                                        ? CachedNetworkImageProvider(avatar)
                                        : null,
                                    child: avatar.isEmpty
                                        ? const Icon(Icons.person, color: Color(0xFF94A3B8), size: 20)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              "@$uName",
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            if (isVerified) ...[
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.verified_rounded,
                                                size: 14,
                                                color: ZevColors.primaryBlue,
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (full.isNotEmpty)
                                          Text(
                                            full,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF64748B),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: ZevColors.primaryBlue.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      "Chat",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: ZevColors.primaryBlue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

