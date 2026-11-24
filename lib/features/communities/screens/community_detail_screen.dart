import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../profile/screens/profile_screen.dart';
import 'community_post_detail_screen.dart';
import 'create_community_post_screen.dart';
import '../widgets/community_join_requests_sheet.dart';

class CommunityDetailScreen extends StatefulWidget {
  final String communityId;
  final Map<String, dynamic>? initialData;

  const CommunityDetailScreen({
    super.key,
    required this.communityId,
    this.initialData,
  });

  static Future<void> open(
    BuildContext context, {
    required String communityId,
    Map<String, dynamic>? initialData,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityDetailScreen(
          communityId: communityId,
          initialData: initialData,
        ),
      ),
    );
  }

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late TabController _tabController;

  Map<String, dynamic>? _community;
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  bool _isLoadingMembers = false;
  bool _isMember = false;
  String _userRole = 'member'; // 'owner', 'admin', 'moderator', 'member'

  bool get _isCreator {
    final uid = _client.auth.currentUser?.id;
    return uid != null && _community != null && _community!['creator_id'] == uid;
  }

  bool get _isAdminOrOwner =>
      _isCreator || _userRole == 'owner' || _userRole == 'admin';

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

      // 2. Check membership & role
      if (userId != null) {
        if (_community!['creator_id'] == userId) {
          _isMember = true;
          _userRole = 'owner';
        } else {
          final memRes = await _client
              .from('community_members')
              .select('role')
              .eq('community_id', widget.communityId)
              .eq('user_id', userId)
              .maybeSingle();

          if (memRes != null) {
            _isMember = true;
            _userRole = (memRes['role'] ?? 'member').toString().toLowerCase();
          } else {
            _isMember = false;
            _userRole = 'none';
          }
        }
      }

      // 3. Fetch community posts & reels
      final postsRes = await _client
          .from('community_posts')
          .select('*, profiles(username, full_name, avatar_url, is_verified)')
          .eq('community_id', widget.communityId)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(60);

      setState(() {
        _posts = List<Map<String, dynamic>>.from(postsRes);
        _isLoading = false;
      });

      _loadMembers();
    } catch (e) {
      debugPrint('[CommunityDetailScreen] error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoadingMembers = true);
    try {
      final membersRes = await _client
          .from('community_members')
          .select('id, user_id, role, created_at')
          .eq('community_id', widget.communityId)
          .limit(100);

      final List<Map<String, dynamic>> rawMembers =
          List<Map<String, dynamic>>.from(membersRes);

      if (rawMembers.isEmpty) {
        if (mounted) setState(() => _isLoadingMembers = false);
        return;
      }

      final userIds = rawMembers
          .map((m) => m['user_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      final profilesRes = await _client
          .from('profiles')
          .select('id, username, full_name, avatar_url, is_verified')
          .inFilter('id', userIds);

      final Map<String, Map<String, dynamic>> profileMap = {
        for (var p in (profilesRes as List))
          p['id'].toString(): Map<String, dynamic>.from(p)
      };

      final List<Map<String, dynamic>> enriched = [];
      for (var m in rawMembers) {
        final uid = m['user_id']?.toString() ?? '';
        final profile = profileMap[uid] ?? {};
        enriched.add({
          ...m,
          'profile': profile,
          'is_owner': _community != null && _community!['creator_id'] == uid,
        });
      }

      // Sort: owner first, then admins, then moderators, then members
      enriched.sort((a, b) {
        int roleWeight(Map<String, dynamic> item) {
          if (item['is_owner'] == true) return 0;
          final r = item['role']?.toString().toLowerCase();
          if (r == 'owner') return 0;
          if (r == 'admin') return 1;
          if (r == 'moderator') return 2;
          return 3;
        }
        return roleWeight(a).compareTo(roleWeight(b));
      });

      if (mounted) {
        setState(() {
          _members = enriched;
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      debugPrint('[CommunityDetailScreen] error loading members: $e');
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  Future<void> _toggleMembership() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    if (_isCreator) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("As the group creator, you cannot leave your own community.")),
      );
      return;
    }

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
            _community!['members_count'] =
                ((_community!['members_count'] as num?) ?? 1) - 1;
          }
        });
        _loadMembers();
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
            _community!['members_count'] =
                ((_community!['members_count'] as num?) ?? 0) + 1;
          }
        });
        _loadMembers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Admin: Remove member from community
  Future<void> _removeMember(String memberUserId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Remove @$username?"),
        content: const Text("Are you sure you want to remove this member from the community?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _client
          .from('community_members')
          .delete()
          .eq('community_id', widget.communityId)
          .eq('user_id', memberUserId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Removed @$username from community.")),
        );
        setState(() {
          _members.removeWhere((m) => m['user_id'] == memberUserId);
          if (_community != null) {
            _community!['members_count'] =
                ((_community!['members_count'] as num?) ?? 1) - 1;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to remove member: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Admin: Change member role
  Future<void> _changeMemberRole(String memberUserId, String newRole, String username) async {
    try {
      await _client
          .from('community_members')
          .update({'role': newRole})
          .eq('community_id', widget.communityId)
          .eq('user_id', memberUserId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("@$username is now $newRole.")),
        );
        _loadMembers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update role: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Share & Invite Bottom Sheet
  void _openInviteSheet() {
    final slug = _community?['slug'] ?? widget.communityId;
    final inviteUrl = "https://zevapp.com/c/$slug";
    final TextEditingController searchUserCtrl = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearchingUsers = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> searchUsers(String query) async {
            final q = query.trim();
            if (q.isEmpty) {
              setSheetState(() => searchResults = []);
              return;
            }
            setSheetState(() => isSearchingUsers = true);
            try {
              final users = await _client
                  .from('profiles')
                  .select('id, username, full_name, avatar_url, is_verified')
                  .or('username.ilike.%$q%,full_name.ilike.%$q%')
                  .limit(10);
              setSheetState(() {
                searchResults = List<Map<String, dynamic>>.from(users);
                isSearchingUsers = false;
              });
            } catch (_) {
              setSheetState(() => isSearchingUsers = false);
            }
          }

          Future<void> inviteUser(Map<String, dynamic> user) async {
            final targetId = user['id'];
            try {
              // Check if already in group
              final existing = await _client
                  .from('community_members')
                  .select('id')
                  .eq('community_id', widget.communityId)
                  .eq('user_id', targetId)
                  .maybeSingle();

              if (existing != null) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("@${user['username']} is already a member.")),
                  );
                }
                return;
              }

              await _client.from('community_members').insert({
                'community_id': widget.communityId,
                'user_id': targetId,
                'role': 'member',
              });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("@${user['username']} added to community!")),
                );
                setState(() {
                  if (_community != null) {
                    _community!['members_count'] =
                        ((_community!['members_count'] as num?) ?? 0) + 1;
                  }
                });
                _loadMembers();
              }
              if (sheetCtx.mounted) {
                Navigator.pop(sheetCtx);
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error inviting user: $e"), backgroundColor: Colors.red),
                );
              }
            }
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.72,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Invite Members to Community",
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Share the direct link or search and add friends instantly.",
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
                const SizedBox(height: 16),

                // Copy Link Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded, color: Color(0xFF0284C7), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          inviteUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: inviteUrl));
                          HapticFeedback.selectionClick();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Community link copied to clipboard!")),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("Copy", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.share_rounded, color: Color(0xFF64748B), size: 20),
                        onPressed: () {
                          Share.share("Join ${_community?['name'] ?? 'our community'} on ZEV: $inviteUrl");
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Search Users Bar
                TextField(
                  controller: searchUserCtrl,
                  onChanged: (val) => searchUsers(val),
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
                    hintText: "Search user by username or name...",
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 12),

                // Users Search Results List
                Expanded(
                  child: isSearchingUsers
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7)))
                      : searchResults.isEmpty
                          ? Center(
                              child: Text(
                                searchUserCtrl.text.isEmpty
                                    ? "Type a username above to invite."
                                    : "No users found.",
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                              ),
                            )
                          : ListView.builder(
                              itemCount: searchResults.length,
                              itemBuilder: (c, idx) {
                                final u = searchResults[idx];
                                final uname = u['username'] ?? '';
                                final fname = u['full_name'] ?? uname;
                                final avatar = u['avatar_url'];
                                final verified = u['is_verified'] == true;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  leading: CircleAvatar(
                                    radius: 20,
                                    backgroundColor: const Color(0xFF0284C7),
                                    backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
                                    child: avatar == null
                                        ? Text(fname.isNotEmpty ? fname[0].toUpperCase() : 'U',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                        : null,
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          fname,
                                          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (verified) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.verified_rounded, color: Color(0xFF00D4FF), size: 14),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text("@$uname", style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                  trailing: ElevatedButton(
                                    onPressed: () => inviteUser(u),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0284C7),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: const Text("Add / Invite", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Admin: Community Settings & Profile Edit Modal
  void _openCommunitySettings() {
    final c = _community ?? {};
    final nameCtrl = TextEditingController(text: c['name'] ?? '');
    final descCtrl = TextEditingController(text: c['description'] ?? '');
    String selectedCat = c['category'] ?? 'education';

    File? newAvatarFile;
    File? newCoverFile;
    bool isSaving = false;

    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> pickAvatar() async {
            final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
            if (picked != null) {
              setModalState(() => newAvatarFile = File(picked.path));
            }
          }

          Future<void> pickCover() async {
            final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
            if (picked != null) {
              setModalState(() => newCoverFile = File(picked.path));
            }
          }

          Future<void> saveSettings() async {
            final newName = nameCtrl.text.trim();
            if (newName.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Community name cannot be empty.")),
              );
              return;
            }

            setModalState(() => isSaving = true);
            try {
              String? avatarUrl = c['avatar_url'];
              String? coverUrl = c['cover_url'];

              if (newAvatarFile != null) {
                final fn = 'comm_avatar_${widget.communityId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                avatarUrl = await CloudflareStorageService.instance.upload(
                  bucket: 'avatars',
                  path: fn,
                  file: newAvatarFile,
                );
              }

              if (newCoverFile != null) {
                final fn = 'comm_cover_${widget.communityId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                coverUrl = await CloudflareStorageService.instance.upload(
                  bucket: 'covers',
                  path: fn,
                  file: newCoverFile,
                );
              }

              await _client.from('communities').update({
                'name': newName,
                'description': descCtrl.text.trim(),
                'category': selectedCat,
                'avatar_url': ?avatarUrl,
                'cover_url': ?coverUrl,
              }).eq('id', widget.communityId);

              if (mounted) {
                setState(() {
                  _community!['name'] = newName;
                  _community!['description'] = descCtrl.text.trim();
                  _community!['category'] = selectedCat;
                  if (avatarUrl != null) _community!['avatar_url'] = avatarUrl;
                  if (coverUrl != null) _community!['cover_url'] = coverUrl;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Community profile updated successfully!")),
                );
              }
              if (modalCtx.mounted) {
                Navigator.pop(modalCtx);
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Failed to update: $e"), backgroundColor: Colors.red),
                );
              }
            } finally {
              if (modalCtx.mounted) setModalState(() => isSaving = false);
            }
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.88,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: ListView(
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Edit Community Profile",
                  style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Manage community branding, photos, and general information.",
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
                ),
                const SizedBox(height: 20),

                // Cover Photo Preview & Change Button
                const Text("COVER PHOTO", style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: pickCover,
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      image: newCoverFile != null
                          ? DecorationImage(image: FileImage(newCoverFile!), fit: BoxFit.cover)
                          : c['cover_url'] != null
                              ? DecorationImage(image: CachedNetworkImageProvider(c['cover_url']), fit: BoxFit.cover)
                              : null,
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text("Change Cover", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Avatar Preview & Change Button
                const Text("PROFILE AVATAR", style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: const Color(0xFF0284C7),
                      backgroundImage: newAvatarFile != null
                          ? FileImage(newAvatarFile!) as ImageProvider
                          : c['avatar_url'] != null
                              ? CachedNetworkImageProvider(c['avatar_url'])
                              : null,
                      child: (newAvatarFile == null && c['avatar_url'] == null)
                          ? Text(
                              (c['name'] ?? 'C').toString().isNotEmpty ? c['name'][0].toUpperCase() : 'C',
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: pickAvatar,
                      icon: const Icon(Icons.photo_library_rounded, size: 16),
                      label: const Text("Upload Avatar"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0284C7),
                        side: const BorderSide(color: Color(0xFF0284C7)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Name
                const Text("COMMUNITY NAME", style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
                  ),
                ),
                const SizedBox(height: 18),

                // Description
                const Text("DESCRIPTION", style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  maxLines: 4,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
                  decoration: InputDecoration(
                    hintText: "What is this community about? Share mission and guidelines...",
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
                  ),
                ),
                const SizedBox(height: 24),

                // Save Button
                ElevatedButton(
                  onPressed: isSaving ? null : saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Save Community Changes", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ],
            ),
          );
        },
      ),
    );
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
    final posts = c['posts_count'] ?? _posts.length;
    final isVerified = c['is_verified'] == true;
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
              // Invite / Share Button
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
                  child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF0284C7), size: 18),
                ),
                tooltip: "Invite Members",
                onPressed: _openInviteSheet,
              ),

              // Admin Settings Gear
              if (_isAdminOrOwner)
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
                    child: const Icon(Icons.settings_suggest_rounded, color: Color(0xFF0F172A), size: 18),
                  ),
                  tooltip: "Community Settings",
                  onPressed: _openCommunitySettings,
                ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  coverUrl != null
                      ? CachedNetworkImage(imageUrl: coverUrl, fit: BoxFit.cover)
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
                            backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
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
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (isVerified) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.verified_rounded,
                                      color: Color(0xFF00D4FF),
                                      size: 18,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    "${category.toString().toUpperCase()} GROUP",
                                    style: const TextStyle(
                                      color: Color(0xFF0284C7),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  if (_isAdminOrOwner) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _isCreator ? "CREATOR" : _userRole.toUpperCase(),
                                        style: const TextStyle(
                                          color: Color(0xFF0284C7),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
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

                  // Stats Row & Join Button
                  Row(
                    children: [
                      _buildStatChip(Icons.people_alt_rounded, "$members Members"),
                      const SizedBox(width: 8),
                      _buildStatChip(Icons.forum_rounded, "$posts Posts"),
                      if (_isCreator || _userRole == 'admin') ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            CommunityJoinRequestsSheet.show(
                              context,
                              communityId: widget.communityId,
                              communityName: _community?['name'] ?? 'Community',
                              onUpdated: () {
                                _loadCommunityData();
                                _loadMembers();
                              },
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF0284C7)
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person_add_rounded,
                                  color: Color(0xFF0284C7),
                                  size: 14,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Requests',
                                  style: TextStyle(
                                    color: Color(0xFF0284C7),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _isCreator ? null : _toggleMembership,
                        icon: Icon(
                          _isCreator
                              ? Icons.admin_panel_settings_rounded
                              : _isMember
                                  ? Icons.check_circle_rounded
                                  : Icons.group_add_rounded,
                          size: 16,
                        ),
                        label: Text(_isCreator ? "Owner" : _isMember ? "Joined" : "Join Group"),
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
                  Tab(text: "Reels"),
                  Tab(text: "Members"),
                  Tab(text: "Rules & Info"),
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
              _posts.where((p) => p['post_type'] != 'reel').toList(),
              emptyLabel: "No community feed posts yet. Be the first to share an update!",
            ),

            // 2. Reels & Short Videos
            _buildReelsGrid(
              _posts.where((p) => p['post_type'] == 'reel').toList(),
            ),

            // 3. Members List & Management Tab
            _buildMembersTab(),

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
              label: const Text("Post / Reel", style: TextStyle(fontWeight: FontWeight.w800)),
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

  Widget _buildPostList(List<Map<String, dynamic>> items, {required String emptyLabel}) {
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
              const Icon(Icons.dynamic_feed_outlined, color: Color(0xFF94A3B8), size: 48),
              const SizedBox(height: 12),
              Text(emptyLabel, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final pinned = items.where((p) => p['is_pinned'] == true).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        if (pinned.isNotEmpty) ...[
          _buildPinnedAnnouncementBanner(pinned.first),
          const SizedBox(height: 12),
        ],
        ...items.map((p) => _buildPostCard(p)),
      ],
    );
  }

  Widget _buildPinnedAnnouncementBanner(Map<String, dynamic> post) {
    final prof = post['profiles'] as Map<String, dynamic>? ?? {};
    final authorName = prof['full_name'] ?? prof['username'] ?? 'Admin';
    final title = post['title'] ?? 'Community Announcement';
    final content = post['content'] ?? '';

    return GestureDetector(
      onTap: () => CommunityPostDetailScreen.open(
        context,
        postId: post['id'],
        initialPost: post,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEFF6FF), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0284C7).withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.push_pin_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'PINNED ANNOUNCEMENT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  'by @$authorName',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    final prof = post['profiles'] as Map<String, dynamic>? ?? {};
    final authorName = prof['full_name'] ?? prof['username'] ?? 'Member';
    final avatar = prof['avatar_url'];
    final authorVerified = prof['is_verified'] == true;
    final title = post['title'];
    final content = post['content'] ?? '';
    final mediaUrl = post['media_url'];
    final upvotes = post['upvotes_count'] ?? 0;
    final comments = post['comments_count'] ?? 0;
    final created = post['created_at'] != null
        ? DateTime.parse(post['created_at']).toLocal().toString().substring(0, 16)
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
                    backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
                    child: avatar == null ? Text(authorName[0], style: const TextStyle(color: Colors.white, fontSize: 12)) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                authorName,
                                style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (authorVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified_rounded, color: Color(0xFF00D4FF), size: 14),
                            ],
                          ],
                        ),
                        Text(created, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
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

              // Attached Media (if any)
              if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: mediaUrl,
                    fit: BoxFit.cover,
                    height: 180,
                    width: double.infinity,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Footer: Likes & Comments
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
                      const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF64748B), size: 14),
                      const SizedBox(width: 4),
                      Text("$comments comments", style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5)),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.video_collection_outlined, color: Color(0xFF94A3B8), size: 48),
              const SizedBox(height: 12),
              const Text("No community reels yet.", style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
              const SizedBox(height: 16),
              if (_isMember)
                ElevatedButton.icon(
                  onPressed: () async {
                    final created = await CreateCommunityPostScreen.open(
                      context,
                      communityId: widget.communityId,
                      communityName: _community?['name'] ?? 'Community',
                      initialType: 'reel',
                    );
                    if (created == true) _loadCommunityData();
                  },
                  icon: const Icon(Icons.video_call_rounded, size: 16),
                  label: const Text("Post a Reel"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
        ),
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
        final thumb = r['thumbnail_url'] ?? r['media_url'];
        final title = r['title'] ?? r['content'] ?? 'Reel';

        return GestureDetector(
          onTap: () => CommunityPostDetailScreen.open(context, postId: r['id'], initialPost: r),
          child: Container(
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
                  if (thumb != null)
                    CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(color: const Color(0xFF0F172A)),
                    )
                  else
                    Container(color: const Color(0xFF0F172A)),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 44)),
                  Positioned(
                    bottom: 10,
                    left: 10,
                    right: 10,
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Members Tab with Role Badges & Admin Controls
  Widget _buildMembersTab() {
    if (_isLoadingMembers) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7)));
    }

    if (_members.isEmpty) {
      return const Center(
        child: Text("No members found.", style: TextStyle(color: Color(0xFF64748B))),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _members.length,
      itemBuilder: (ctx, idx) {
        final m = _members[idx];
        final memberUid = m['user_id']?.toString() ?? '';
        final profile = m['profile'] as Map<String, dynamic>? ?? {};
        final username = profile['username'] ?? 'User';
        final fullName = profile['full_name'] ?? username;
        final avatarUrl = profile['avatar_url'];
        final isVerified = profile['is_verified'] == true;
        final role = (m['role'] ?? 'member').toString().toLowerCase();
        final isOwner = m['is_owner'] == true;

        Color roleColor;
        String roleLabel;
        if (isOwner) {
          roleColor = const Color(0xFFEAB308); // Gold
          roleLabel = "OWNER";
        } else if (role == 'admin') {
          roleColor = const Color(0xFF0284C7); // Blue
          roleLabel = "ADMIN";
        } else if (role == 'moderator') {
          roleColor = const Color(0xFF10B981); // Emerald
          roleLabel = "MODERATOR";
        } else {
          roleColor = const Color(0xFF64748B);
          roleLabel = "MEMBER";
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => ProfileScreen.open(context, userId: memberUid),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF0284C7),
                  backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                  child: avatarUrl == null
                      ? Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => ProfileScreen.open(context, userId: memberUid),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified_rounded, color: Color(0xFF00D4FF), size: 14),
                          ],
                        ],
                      ),
                      Text("@$username", style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                    ],
                  ),
                ),
              ),

              // Role Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  roleLabel,
                  style: TextStyle(color: roleColor, fontWeight: FontWeight.w900, fontSize: 10),
                ),
              ),

              // Admin 3-dots Menu for non-owner members
              if (_isAdminOrOwner && !isOwner && memberUid != _client.auth.currentUser?.id) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B), size: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onSelected: (val) {
                    if (val == 'remove') {
                      _removeMember(memberUid, username);
                    } else if (val == 'admin' || val == 'moderator' || val == 'member') {
                      _changeMemberRole(memberUid, val, username);
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (role != 'admin')
                      const PopupMenuItem(
                        value: 'admin',
                        child: Row(
                          children: [
                            Icon(Icons.shield_rounded, color: Color(0xFF0284C7), size: 18),
                            SizedBox(width: 8),
                            Text("Make Admin"),
                          ],
                        ),
                      ),
                    if (role != 'moderator')
                      const PopupMenuItem(
                        value: 'moderator',
                        child: Row(
                          children: [
                            Icon(Icons.security_rounded, color: Color(0xFF10B981), size: 18),
                            SizedBox(width: 8),
                            Text("Make Moderator"),
                          ],
                        ),
                      ),
                    if (role != 'member')
                      const PopupMenuItem(
                        value: 'member',
                        child: Row(
                          children: [
                            Icon(Icons.person_rounded, color: Color(0xFF64748B), size: 18),
                            SizedBox(width: 8),
                            Text("Demote to Member"),
                          ],
                        ),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          Icon(Icons.person_remove_rounded, color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Text("Remove from Community", style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
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
          const Text("Standard ZEV community etiquette applies: respect fellow members, no spam, and keep discussions constructive.",
              style: TextStyle(color: Color(0xFF64748B), height: 1.5))
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
                    decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
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
