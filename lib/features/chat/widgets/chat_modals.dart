import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/social_graph_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_video_thumbnail.dart';
import '../../feed/screens/post_detail_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../reels/models/reel_item.dart';
import '../../reels/widgets/reel_player_item.dart';
import '../models/chat_conversation_item.dart';
import '../models/direct_message_model.dart';
import '../services/chat_cache_service.dart';
import '../services/chat_service.dart';
import 'new_chat_sheet.dart';

/// Forward Message Picker Sheet (recent conversations + user search).
class ForwardPickerSheet extends StatefulWidget {
  final DirectMessageModel message;

  const ForwardPickerSheet({super.key, required this.message});

  static Future<void> show(
    BuildContext context, {
    required DirectMessageModel message,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ForwardPickerSheet(message: message),
    );
  }

  @override
  State<ForwardPickerSheet> createState() => _ForwardPickerSheetState();
}

class _ForwardPickerSheetState extends State<ForwardPickerSheet> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _forwardedTargets = {};
  final Set<String> _sendingTargets = {};
  List<ChatConversationItem> _threads = [];
  List<Map<String, dynamic>> _searchUsers = [];
  Set<String> _blockedIds = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _threads = ChatCacheService.instance.cachedInbox
        .where((c) => !c.isRequest)
        .toList();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final safety = await SocialGraphService.instance.fetchSafetyFilters();
      _blockedIds = safety.blockedUserIds;
      if (_threads.isEmpty) {
        final inbox = await ChatService.instance.fetchInbox();
        if (mounted) {
          setState(() {
            _threads = inbox.conversations.where((c) => !c.isRequest).toList();
          });
        }
      }
    } catch (_) {}
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() => _searchUsers = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final myId = _supabase.auth.currentUser?.id ?? '';
      try {
        final res = await _supabase
            .from('profiles')
            .select(
              'id, username, first_name, last_name, avatar_url, is_verified',
            )
            .neq('id', myId)
            .or(
              'username.ilike.%$trimmed%,first_name.ilike.%$trimmed%,last_name.ilike.%$trimmed%',
            )
            .limit(20);
        if (mounted) {
          setState(() {
            _searchUsers = (res as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .where(
                  (u) => !_blockedIds.contains(u['id']?.toString() ?? ''),
                )
                .toList();
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _forwardToThread(ChatConversationItem item) async {
    final key = item.threadKey;
    if (_sendingTargets.contains(key) || _forwardedTargets.contains(key)) return;
    setState(() => _sendingTargets.add(key));
    try {
      String convId = item.conversationId;
      if (convId.isEmpty && !item.isGroup) {
        convId =
            (await ChatService.instance.ensureDirectConversation(item.peerId)) ??
                '';
      }
      if (convId.isEmpty) throw Exception('Conversation unavailable');

      final res = await ChatService.instance.forwardMessage(
        source: widget.message,
        targetConversationId: convId,
        isTargetGroup: item.isGroup,
        targetPeerId: item.peerId,
      );
      if (mounted) {
        setState(() {
          _sendingTargets.remove(key);
          if (!res.isFailed) _forwardedTargets.add(key);
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingTargets.remove(key));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Forward failed: $e')),
        );
      }
    }
  }

  Future<void> _forwardToUser(Map<String, dynamic> user) async {
    final uid = user['id']?.toString() ?? '';
    if (uid.isEmpty ||
        _sendingTargets.contains(uid) ||
        _forwardedTargets.contains(uid)) {
      return;
    }
    setState(() => _sendingTargets.add(uid));
    try {
      final convId = await ChatService.instance.ensureDirectConversation(uid);
      if (convId == null) throw Exception('Cannot open conversation');
      final res = await ChatService.instance.forwardMessage(
        source: widget.message,
        targetConversationId: convId,
        isTargetGroup: false,
        targetPeerId: uid,
      );
      if (mounted) {
        setState(() {
          _sendingTargets.remove(uid);
          if (!res.isFailed) _forwardedTargets.add(uid);
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingTargets.remove(uid));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filteredThreads = q.isEmpty
        ? _threads
        : _threads.where((t) {
            return t.displayTitle.toLowerCase().contains(q) ||
                t.peerUsername.toLowerCase().contains(q);
          }).toList();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.72,
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
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Forward Message',
                      style: TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: ZevColors.border),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      icon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: ZevColors.textMuted,
                      ),
                      hintText: 'Search chats or people...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    ...filteredThreads.map((item) {
                      final sent = _forwardedTargets.contains(item.threadKey);
                      final sending = _sendingTargets.contains(item.threadKey);
                      return _buildTargetRow(
                        title: item.displayTitle,
                        subtitle: item.displayHandle,
                        avatar: item.displayAvatar,
                        isGroup: item.isGroup,
                        isVerified: !item.isGroup && item.isPeerVerified,
                        sent: sent,
                        sending: sending,
                        onSend: () => _forwardToThread(item),
                      );
                    }),
                    if (_searchUsers.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'People',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: ZevColors.textMuted,
                          ),
                        ),
                      ),
                      ..._searchUsers.map((u) {
                        final uid = u['id']?.toString() ?? '';
                        final uname = u['username']?.toString() ?? 'user';
                        final fn = u['first_name']?.toString() ?? '';
                        final ln = u['last_name']?.toString() ?? '';
                        final full = '$fn $ln'.trim();
                        return _buildTargetRow(
                          title: full.isNotEmpty ? full : '@$uname',
                          subtitle: '@$uname',
                          avatar: u['avatar_url']?.toString() ?? '',
                          isGroup: false,
                          isVerified: u['is_verified'] == true,
                          sent: _forwardedTargets.contains(uid),
                          sending: _sendingTargets.contains(uid),
                          onSend: () => _forwardToUser(u),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetRow({
    required String title,
    required String subtitle,
    required String avatar,
    required bool isGroup,
    required bool isVerified,
    required bool sent,
    required bool sending,
    required VoidCallback onSend,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: ZevColors.border,
            backgroundImage:
                avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
            child: avatar.isEmpty
                ? Icon(
                    isGroup ? Icons.groups_rounded : Icons.person_rounded,
                    color: ZevColors.textMuted,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified_rounded,
                        size: 13,
                        color: ZevColors.primaryBlue,
                      ),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: ZevColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: (sent || sending) ? null : onSend,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  sent ? ZevColors.successGreen : ZevColors.primaryBlue,
              foregroundColor: sent ? Colors.white : ZevColors.deepNavy,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: sending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    sent ? 'Sent' : 'Send',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Light Clearmorphic Group Info, Admin & Members Sheet.
class GroupInfoSheet extends StatefulWidget {
  final String conversationId;
  final VoidCallback? onGroupUpdated;
  final VoidCallback? onLeftGroup;

  const GroupInfoSheet({
    super.key,
    required this.conversationId,
    this.onGroupUpdated,
    this.onLeftGroup,
  });

  static Future<void> show(
    BuildContext context, {
    required String conversationId,
    VoidCallback? onGroupUpdated,
    VoidCallback? onLeftGroup,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupInfoSheet(
        conversationId: conversationId,
        onGroupUpdated: onGroupUpdated,
        onLeftGroup: onLeftGroup,
      ),
    );
  }

  @override
  State<GroupInfoSheet> createState() => _GroupInfoSheetState();
}

class _GroupInfoSheetState extends State<GroupInfoSheet> {
  GroupConversationDetails? _details;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res =
        await ChatService.instance.fetchGroupDetails(widget.conversationId);
    if (mounted) {
      setState(() {
        _details = res;
        _loading = false;
      });
    }
  }

  bool get _amIAdmin {
    final myId = ChatService.instance.currentUserId;
    if (myId == null || _details == null) return false;
    return _details!.members.any((m) => m.userId == myId && m.isAdmin);
  }

  Future<void> _editTitle() async {
    if (_details == null) return;
    final ctrl = TextEditingController(text: _details!.title);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Rename Group',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: ctrl,
          maxLength: 80,
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (saved != null && saved.isNotEmpty && saved != _details!.title) {
      await ChatService.instance.updateGroupTitle(widget.conversationId, saved);
      widget.onGroupUpdated?.call();
      await _load();
    }
  }

  void _addMembers() {
    if (_details == null) return;
    final existingIds = _details!.members.map((m) => m.userId).toSet();
    NewChatSheet.showMemberPicker(
      context,
      excludeUserIds: existingIds,
      onConfirm: (selectedIds) async {
        await ChatService.instance
            .addGroupMembers(widget.conversationId, selectedIds);
        widget.onGroupUpdated?.call();
        await _load();
      },
    );
  }

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Leave Group?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'You will no longer receive messages from this group unless re-added.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ZevColors.errorRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ChatService.instance.leaveGroup(widget.conversationId);
      if (mounted) {
        Navigator.pop(context);
        widget.onLeftGroup?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = ChatService.instance.currentUserId ?? '';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.78,
          decoration: BoxDecoration(
            color: ZevColors.softSurface.withValues(alpha: 0.96),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: ZevColors.primaryBlue,
                  ),
                )
              : _details == null
                  ? const Center(child: Text('Group details unavailable'))
                  : Column(
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
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: ZevColors.border),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: ZevColors.primaryBlue
                                      .withValues(alpha: 0.14),
                                  backgroundImage: _details!.avatarUrl.isNotEmpty
                                      ? CachedNetworkImageProvider(
                                          _details!.avatarUrl,
                                        )
                                      : null,
                                  child: _details!.avatarUrl.isEmpty
                                      ? const Icon(
                                          Icons.groups_rounded,
                                          size: 28,
                                          color: ZevColors.secondaryBlue,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _details!.title,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w900,
                                          color: ZevColors.deepNavy,
                                        ),
                                      ),
                                      Text(
                                        '${_details!.members.length} members',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: ZevColors.textMuted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_amIAdmin)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_rounded,
                                      color: ZevColors.secondaryBlue,
                                    ),
                                    onPressed: _editTitle,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Members',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: ZevColors.textSecondary,
                                ),
                              ),
                              if (_amIAdmin)
                                TextButton.icon(
                                  onPressed: _addMembers,
                                  icon: const Icon(
                                    Icons.person_add_alt_1_rounded,
                                    size: 17,
                                  ),
                                  label: const Text(
                                    'Add Members',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: _details!.members.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, idx) {
                              final member = _details!.members[idx];
                              final isMe = member.userId == myId;
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: ZevColors.border,
                                  ),
                                ),
                                child: ListTile(
                                  onTap: () {
                                    Navigator.pop(context);
                                    ProfileScreen.open(
                                      context,
                                      userId: member.userId,
                                    );
                                  },
                                  leading: CircleAvatar(
                                    backgroundColor: ZevColors.softSurface,
                                    backgroundImage: member.avatarUrl.isNotEmpty
                                        ? CachedNetworkImageProvider(
                                            member.avatarUrl,
                                          )
                                        : null,
                                    child: member.avatarUrl.isEmpty
                                        ? const Icon(
                                            Icons.person_rounded,
                                            color: ZevColors.textMuted,
                                          )
                                        : null,
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          isMe
                                              ? '@${member.username} (You)'
                                              : '@${member.username}',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: ZevColors.deepNavy,
                                          ),
                                        ),
                                      ),
                                      if (member.isVerified) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.verified_rounded,
                                          size: 14,
                                          color: ZevColors.primaryBlue,
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: member.fullName.isNotEmpty
                                      ? Text(
                                          member.fullName,
                                          style: const TextStyle(fontSize: 12),
                                        )
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (member.isAdmin)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: ZevColors.primaryBlue
                                                .withValues(alpha: 0.14),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            'Admin',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: ZevColors.secondaryBlue,
                                            ),
                                          ),
                                        ),
                                      if (_amIAdmin && !isMe)
                                        PopupMenuButton<String>(
                                          icon: const Icon(
                                            Icons.more_vert_rounded,
                                            size: 19,
                                          ),
                                          onSelected: (val) async {
                                            if (val == 'toggle_admin') {
                                              await ChatService.instance
                                                  .setGroupMemberRole(
                                                conversationId:
                                                    widget.conversationId,
                                                userId: member.userId,
                                                role: member.isAdmin
                                                    ? 'member'
                                                    : 'admin',
                                              );
                                            } else if (val == 'remove') {
                                              await ChatService.instance
                                                  .removeGroupMember(
                                                widget.conversationId,
                                                member.userId,
                                              );
                                            }
                                            widget.onGroupUpdated?.call();
                                            await _load();
                                          },
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'toggle_admin',
                                              child: Text(
                                                member.isAdmin
                                                    ? 'Dismiss as Admin'
                                                    : 'Make Group Admin',
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'remove',
                                              child: Text(
                                                'Remove from Group',
                                                style: TextStyle(
                                                  color: ZevColors.errorRed,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _confirmLeave,
                                icon: const Icon(Icons.logout_rounded),
                                label: const Text('Leave Group'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: ZevColors.errorRed,
                                  side: BorderSide(
                                    color: ZevColors.errorRed
                                        .withValues(alpha: 0.45),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
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
}

/// File / Document Message Card inside a chat bubble.
class FileMessageCard extends StatelessWidget {
  final String fileName;
  final int? fileSize;
  final String? url;
  final bool isMine;

  const FileMessageCard({
    super.key,
    required this.fileName,
    this.fileSize,
    required this.url,
    required this.isMine,
  });

  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Document';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _extBadge() {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : 'FILE';
    return ext.length > 5 ? ext.substring(0, 5) : ext;
  }

  Future<void> _openFile(BuildContext context) async {
    final raw = url?.trim() ?? '';
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFile(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isMine
              ? Colors.white.withValues(alpha: 0.18)
              : ZevColors.softSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMine
                ? Colors.white.withValues(alpha: 0.3)
                : ZevColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isMine ? Colors.white : ZevColors.primaryBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  _extBadge(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: isMine ? ZevColors.secondaryBlue : Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName.isNotEmpty ? fileName : 'Attachment',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: isMine ? Colors.white : ZevColors.deepNavy,
                    ),
                  ),
                  Text(
                    _formatSize(fileSize),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.85)
                          : ZevColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.open_in_new_rounded,
              size: 17,
              color: isMine ? Colors.white : ZevColors.secondaryBlue,
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline Video Attachment Preview + Fullscreen Player for chat messages.
/// Uses [ZevVideoThumbnail] instead of holding live hardware decoders per bubble.
class VideoMessageBubblePlayer extends StatelessWidget {
  final String videoUrl;
  final bool isMine;

  const VideoMessageBubblePlayer({
    super.key,
    required this.videoUrl,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FullScreenVideoViewer(videoUrl: videoUrl),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 195,
          width: 230,
          decoration: BoxDecoration(
            color: ZevColors.softSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ZevColors.border),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: ZevVideoThumbnail(
                  videoUrl: videoUrl,
                  showPlayBadge: false,
                  showViews: false,
                  fit: BoxFit.cover,
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.deepNavy.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: ZevColors.deepNavy,
                  size: 30,
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.videocam_rounded,
                        size: 12,
                        color: ZevColors.secondaryBlue,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Video',
                        style: TextStyle(
                          color: ZevColors.deepNavy,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FullScreenVideoViewer extends StatefulWidget {
  final String videoUrl;

  const FullScreenVideoViewer({super.key, required this.videoUrl});

  @override
  State<FullScreenVideoViewer> createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<FullScreenVideoViewer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    VideoPlayerController? c;
    try {
      c = VideoPlayerController.networkUrl(uri);
      _controller = c;
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.play();
      await c.setLooping(true);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('[FullScreenVideoViewer] init error: $e');
      try {
        await c?.dispose();
      } catch (_) {}
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: _failed
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.white70, size: 40),
                  SizedBox(height: 10),
                  Text(
                    'Unable to play video.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              )
            : !_ready || _controller == null
                ? const CircularProgressIndicator(color: ZevColors.primaryBlue)
                : GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_controller!.value.isPlaying) {
                          _controller!.pause();
                        } else {
                          _controller!.play();
                        }
                      });
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio > 0
                              ? _controller!.value.aspectRatio
                              : 9 / 16,
                          child: VideoPlayer(_controller!),
                        ),
                        if (!_controller!.value.isPlaying)
                          const Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white70,
                            size: 64,
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// Shared Post / Reel Card inside a chat message bubble.
class SharedContentMessageCard extends StatelessWidget {
  final DirectMessageModel message;
  final bool isMine;

  const SharedContentMessageCard({
    super.key,
    required this.message,
    required this.isMine,
  });

  Future<void> _openSharedTarget(BuildContext context) async {
    final targetId = (message.fileName ?? '').trim();
    if (targetId.isEmpty) return;
    final isReel = message.effectiveType == 'reel_share';

    if (!isReel) {
      PostDetailScreen.open(context, postId: targetId);
      return;
    }

    try {
      final res = await Supabase.instance.client
          .from('reels')
          .select(
            'id, user_id, title, description, video_url, thumbnail_url, views_count, likes_count, comments_count, created_at',
          )
          .eq('id', targetId)
          .maybeSingle();

      if (res != null && context.mounted) {
        final reel = ReelItem(
          id: res['id'].toString(),
          userId: res['user_id']?.toString() ?? '',
          authorUsername: message.mimeType ?? 'creator',
          authorFullName: '',
          authorAvatar: '',
          isVerified: false,
          videoUrl: res['video_url']?.toString() ?? '',
          thumbnailUrl: res['thumbnail_url']?.toString(),
          title: res['title']?.toString() ?? '',
          description: res['description']?.toString() ?? '',
          viewsCount: (res['views_count'] as num?)?.toInt() ?? 0,
          likesCount: (res['likes_count'] as num?)?.toInt() ?? 0,
          commentsCount: (res['comments_count'] as num?)?.toInt() ?? 0,
          createdAt: DateTime.tryParse(res['created_at']?.toString() ?? '') ??
              DateTime.now(),
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(reel.title.isNotEmpty ? reel.title : 'Reel'),
              ),
              body: ReelPlayerItem(
                reel: reel,
                isActive: true,
                isGlobalMuted: false,
                onToggleMute: () {},
              ),
            ),
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isReel = message.effectiveType == 'reel_share';
    final author = (message.mimeType ?? '').trim();

    return GestureDetector(
      onTap: () => _openSharedTarget(context),
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: isMine
              ? Colors.white.withValues(alpha: 0.16)
              : ZevColors.softSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMine
                ? Colors.white.withValues(alpha: 0.35)
                : ZevColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((message.attachmentUrl ?? '').isNotEmpty)
              SizedBox(
                height: 120,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: message.attachmentUrl!,
                  fit: BoxFit.cover,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isReel
                            ? Icons.video_collection_rounded
                            : Icons.article_rounded,
                        size: 14,
                        color:
                            isMine ? Colors.white : ZevColors.secondaryBlue,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          author.isNotEmpty
                              ? '@$author • ${isReel ? 'Reel' : 'Post'}'
                              : (isReel ? 'Shared Reel' : 'Shared Post'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isMine
                                ? Colors.white.withValues(alpha: 0.9)
                                : ZevColors.secondaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (message.messageText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      message.messageText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isMine ? Colors.white : ZevColors.deepNavy,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
