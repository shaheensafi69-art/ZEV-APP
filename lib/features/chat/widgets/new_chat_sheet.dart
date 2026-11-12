import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../services/chat_service.dart';

/// Light Clearmorphic "New Message" & "New Group" Bottom Sheet for ZEV.
/// Filters out blocked accounts via [SocialGraphService] and supports:
/// - 1:1 Direct Messaging
/// - Multi-select Group Chat creation (`create_group_conversation` RPC)
/// - Multi-select Member Picker for existing groups
class NewChatSheet extends StatefulWidget {
  final Function(
    String userId,
    String username,
    String avatarUrl,
    String fullName,
    bool isVerified,
  )? onSelectUser;

  final void Function(String conversationId, String title)? onCreateGroup;
  final void Function(List<String> userIds)? onSelectMemberIds;
  final Set<String> excludeUserIds;
  final bool initialGroupMode;
  final bool pickerOnly;

  const NewChatSheet({
    super.key,
    this.onSelectUser,
    this.onCreateGroup,
    this.onSelectMemberIds,
    this.excludeUserIds = const {},
    this.initialGroupMode = false,
    this.pickerOnly = false,
  });

  static Future<void> show(
    BuildContext context, {
    required Function(
      String userId,
      String username,
      String avatarUrl,
      String fullName,
      bool isVerified,
    ) onSelectUser,
    void Function(String conversationId, String title)? onCreateGroup,
    bool initialGroupMode = false,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewChatSheet(
        onSelectUser: onSelectUser,
        onCreateGroup: onCreateGroup,
        initialGroupMode: initialGroupMode,
      ),
    );
  }

  static Future<void> showMemberPicker(
    BuildContext context, {
    required Set<String> excludeUserIds,
    required void Function(List<String> userIds) onConfirm,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewChatSheet(
        excludeUserIds: excludeUserIds,
        onSelectMemberIds: onConfirm,
        initialGroupMode: true,
        pickerOnly: true,
      ),
    );
  }

  @override
  State<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<NewChatSheet> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _groupTitleCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSearching = false;
  bool _isGroupMode = false;
  bool _isSubmitting = false;

  Set<String> _blockedIds = {};
  List<Map<String, dynamic>> _suggestedUsers = [];
  List<Map<String, dynamic>> _searchResults = [];
  final Map<String, Map<String, dynamic>> _selectedMembers = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _isGroupMode = widget.initialGroupMode || widget.pickerOnly;
    _fetchSuggestedUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _groupTitleCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchSuggestedUsers() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final safety = await SocialGraphService.instance.fetchSafetyFilters();
      _blockedIds = safety.blockedUserIds;

      final followsRes = await _supabase
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', currentUserId)
          .limit(30);

      final followingIds = (followsRes as List)
          .map((f) => f['following_id']?.toString() ?? '')
          .where((id) => _isEligibleId(id, currentUserId))
          .toList();

      List<Map<String, dynamic>> users = [];

      if (followingIds.isNotEmpty) {
        final profsRes = await _supabase
            .from('profiles')
            .select(
              'id, username, first_name, last_name, avatar_url, is_verified',
            )
            .inFilter('id', followingIds)
            .limit(25);
        users = List<Map<String, dynamic>>.from(profsRes as List);
      }

      final followersRes = await _supabase
          .from('user_follows')
          .select('follower_id')
          .eq('following_id', currentUserId)
          .limit(25);

      final followerIds = (followersRes as List)
          .map((f) => f['follower_id']?.toString() ?? '')
          .where(
            (id) =>
                _isEligibleId(id, currentUserId) && !followingIds.contains(id),
          )
          .toList();

      if (followerIds.isNotEmpty) {
        final fProfs = await _supabase
            .from('profiles')
            .select(
              'id, username, first_name, last_name, avatar_url, is_verified',
            )
            .inFilter('id', followerIds)
            .limit(20);
        users.addAll(List<Map<String, dynamic>>.from(fProfs as List));
      }

      if (users.length < 10) {
        final othersRes = await _supabase
            .from('profiles')
            .select(
              'id, username, first_name, last_name, avatar_url, is_verified',
            )
            .neq('id', currentUserId)
            .limit(25);

        final existingIds = users.map((u) => u['id'].toString()).toSet();
        for (final o in (othersRes as List)) {
          final id = o['id']?.toString() ?? '';
          if (_isEligibleId(id, currentUserId) && !existingIds.contains(id)) {
            users.add(Map<String, dynamic>.from(o as Map));
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
      debugPrint('Error fetching suggested chat users: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isEligibleId(String id, String currentUserId) {
    if (id.isEmpty || id == currentUserId) return false;
    if (_blockedIds.contains(id)) return false;
    if (widget.excludeUserIds.contains(id)) return false;
    return true;
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
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final currentUserId = _supabase.auth.currentUser?.id ?? '';
      try {
        final res = await _supabase
            .from('profiles')
            .select(
              'id, username, first_name, last_name, avatar_url, is_verified',
            )
            .neq('id', currentUserId)
            .or(
              'username.ilike.%$trimmed%,first_name.ilike.%$trimmed%,last_name.ilike.%$trimmed%',
            )
            .limit(30);

        final filtered = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((u) => _isEligibleId(u['id']?.toString() ?? '', currentUserId))
            .toList();

        if (mounted) {
          setState(() => _searchResults = filtered);
        }
      } catch (e) {
        debugPrint('Error searching users for chat: $e');
      }
    });
  }

  void _toggleSelectMember(Map<String, dynamic> user) {
    final uid = user['id']?.toString() ?? '';
    if (uid.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedMembers.containsKey(uid)) {
        _selectedMembers.remove(uid);
      } else {
        _selectedMembers[uid] = user;
      }
    });
  }

  Future<void> _submitGroupAction() async {
    if (_selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least 1 member to continue.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (widget.pickerOnly) {
      Navigator.pop(context);
      widget.onSelectMemberIds?.call(_selectedMembers.keys.toList());
      return;
    }

    final titleText = _groupTitleCtrl.text.trim().isNotEmpty
        ? _groupTitleCtrl.text.trim()
        : _selectedMembers.values
            .take(3)
            .map((m) => '@${m['username'] ?? 'user'}')
            .join(', ');

    setState(() => _isSubmitting = true);
    try {
      final convId = await ChatService.instance.createGroupConversation(
        title: titleText,
        memberIds: _selectedMembers.keys.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreateGroup?.call(convId, titleText);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not create group: $e'),
            backgroundColor: ZevColors.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final displayList = _isSearching ? _searchResults : _suggestedUsers;
    final canToggleGroup =
        !widget.pickerOnly && widget.onCreateGroup != null;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.84,
          padding: EdgeInsets.only(bottom: bottomInset),
          decoration: BoxDecoration(
            color: ZevColors.softSurface.withValues(alpha: 0.96),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(
                  color: ZevColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 10),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.pickerOnly
                          ? 'Add Group Members'
                          : (_isGroupMode ? 'New Group Chat' : 'New Message'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                        letterSpacing: -0.3,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: ZevColors.textMuted,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Direct / Group Mode Switcher
              if (canToggleGroup)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: ZevColors.border),
                    ),
                    child: Row(
                      children: [
                        _buildModePill(
                          label: 'Direct Message',
                          icon: Icons.person_outline_rounded,
                          selected: !_isGroupMode,
                          onTap: () => setState(() => _isGroupMode = false),
                        ),
                        _buildModePill(
                          label: 'Create Group',
                          icon: Icons.group_add_outlined,
                          selected: _isGroupMode,
                          onTap: () => setState(() => _isGroupMode = true),
                        ),
                      ],
                    ),
                  ),
                ),

              // Group Name Input
              if (_isGroupMode && !widget.pickerOnly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: ZevColors.border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.deepNavy.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _groupTitleCtrl,
                      maxLength: 80,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ZevColors.deepNavy,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        icon: Icon(
                          Icons.groups_rounded,
                          color: ZevColors.secondaryBlue,
                          size: 20,
                        ),
                        hintText: 'Group name (e.g. Weekend Squad)...',
                        hintStyle: TextStyle(
                          color: ZevColors.textMuted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),

              // Selected Members Horizontal Strip
              if (_isGroupMode && _selectedMembers.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedMembers.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final entry = _selectedMembers.entries.elementAt(idx);
                      final uname =
                          entry.value['username']?.toString() ?? 'user';
                      return Chip(
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.45),
                        ),
                        label: Text(
                          '@$uname',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 15),
                        onDeleted: () => setState(
                          () => _selectedMembers.remove(entry.key),
                        ),
                      );
                    },
                  ),
                ),

              // Light Clearmorphic Search Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: ZevColors.deepNavy.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: ZevColors.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: _onSearchChanged,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: ZevColors.deepNavy,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search people...',
                            hintStyle: TextStyle(
                              color: ZevColors.textMuted,
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
                          icon: const Icon(
                            Icons.clear_rounded,
                            size: 16,
                            color: ZevColors.textMuted,
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearchChanged('');
                          },
                        ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _isSearching ? 'Search Results' : 'Suggested Contacts',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.textSecondary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),

              // Contacts List
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
                              _isSearching
                                  ? 'No users found'
                                  : 'No suggestions available',
                              style: const TextStyle(
                                color: ZevColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                            itemCount: displayList.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final user = displayList[index];
                              final uId = user['id']?.toString() ?? '';
                              final uName =
                                  user['username']?.toString() ?? 'user';
                              final avatar =
                                  user['avatar_url']?.toString() ?? '';
                              final fn = user['first_name']?.toString() ?? '';
                              final ln = user['last_name']?.toString() ?? '';
                              final full = '$fn $ln'.trim();
                              final isVerified = user['is_verified'] == true;
                              final isSelected =
                                  _selectedMembers.containsKey(uId);

                              return GestureDetector(
                                onTap: () {
                                  if (_isGroupMode) {
                                    _toggleSelectMember(user);
                                  } else {
                                    HapticFeedback.lightImpact();
                                    Navigator.pop(context);
                                    widget.onSelectUser?.call(
                                      uId,
                                      uName,
                                      avatar,
                                      full,
                                      isVerified,
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? ZevColors.primaryBlue
                                            .withValues(alpha: 0.1)
                                        : Colors.white.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                          ? ZevColors.primaryBlue
                                          : Colors.white,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: ZevColors.deepNavy
                                            .withValues(alpha: 0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: ZevColors.border,
                                        backgroundImage: avatar.isNotEmpty
                                            ? CachedNetworkImageProvider(avatar)
                                            : null,
                                        child: avatar.isEmpty
                                            ? const Icon(
                                                Icons.person_rounded,
                                                color: ZevColors.textMuted,
                                                size: 20,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    '@$uName',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: ZevColors.deepNavy,
                                                    ),
                                                  ),
                                                ),
                                                if (isVerified) ...[
                                                  const SizedBox(width: 4),
                                                  const Icon(
                                                    Icons.verified_rounded,
                                                    size: 14,
                                                    color:
                                                        ZevColors.primaryBlue,
                                                  ),
                                                ],
                                              ],
                                            ),
                                            if (full.isNotEmpty)
                                              Text(
                                                full,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      ZevColors.textSecondary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (_isGroupMode)
                                        Container(
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: isSelected
                                                ? ZevColors.brandGradient
                                                : null,
                                            color: isSelected
                                                ? null
                                                : ZevColors.softSurface,
                                            border: Border.all(
                                              color: isSelected
                                                  ? Colors.transparent
                                                  : ZevColors.border,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: isSelected
                                              ? const Icon(
                                                  Icons.check_rounded,
                                                  color: Colors.white,
                                                  size: 16,
                                                )
                                              : null,
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: ZevColors.brandGradient,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            boxShadow: [
                                              BoxShadow(
                                                color: ZevColors.secondaryBlue
                                                    .withValues(alpha: 0.25),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Text(
                                            'Chat',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
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

              if (_isGroupMode)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: ZevColors.brandGradient,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: ZevColors.secondaryBlue
                                  .withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submitGroupAction,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  widget.pickerOnly
                                      ? 'Add ${_selectedMembers.length} Member${_selectedMembers.length == 1 ? '' : 's'}'
                                      : 'Create Group (${_selectedMembers.length})',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModePill({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: ZevColors.deepNavy.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? ZevColors.deepNavy : ZevColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? ZevColors.deepNavy : ZevColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
