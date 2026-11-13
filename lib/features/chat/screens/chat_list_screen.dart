import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/multi_account_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/time_ago.dart';
import '../../profile/screens/profile_screen.dart';
import '../models/chat_conversation_item.dart';
import '../services/chat_cache_service.dart';
import '../services/chat_service.dart';
import '../widgets/chat_modals.dart';
import '../widgets/new_chat_sheet.dart';
import 'chat_conversation_screen.dart';

/// Light Clearmorphic Direct & Group Messages Inbox Screen for ZEV.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  static Future<void> open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ChatListScreen(),
      ),
    );
  }

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  String _myUsername = 'user';
  String _myAvatarUrl = '';
  bool _isMyVerified = false;
  String _myNote = '';

  List<ChatConversationItem> _conversations = [];
  List<Map<String, dynamic>> _activeFriendsNotes = [];
  List<Map<String, dynamic>> _suggestedFriends = [];
  List<MessageSearchHit> _messageHits = [];
  bool _isSearchingMessages = false;

  String _selectedTab = 'Primary'; // 'Primary', 'Groups', 'Requests'
  String _searchQuery = '';

  RealtimeChannel? _inboxChannel;
  Timer? _realtimeDebounce;
  Timer? _searchDebounce;

  static const List<String> _tabs = ['Primary', 'Groups', 'Requests'];

  @override
  void initState() {
    super.initState();
    _loadFromCacheFirst();
    _loadCurrentUserProfile();
    _fetchInbox(isBackgroundUpdate: _conversations.isNotEmpty);
    _subscribeToInboxRealtime();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _realtimeDebounce?.cancel();
    _searchDebounce?.cancel();
    _inboxChannel?.unsubscribe();
    super.dispose();
  }

  void _loadFromCacheFirst() {
    final cached = ChatCacheService.instance.cachedInbox;
    final cachedFriends = ChatCacheService.instance.cachedActiveFriends;
    if (cached.isNotEmpty || cachedFriends.isNotEmpty) {
      _conversations = List.from(cached);
      _activeFriendsNotes = List.from(cachedFriends);
      _isLoading = false;
    }
  }

  Future<void> _loadCurrentUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await _supabase
          .from('profiles')
          .select('username, avatar_url, is_verified')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        final prof = Map<String, dynamic>.from(res);
        ChatCacheService.instance.cacheProfile(user.id, prof);
        setState(() {
          _myUsername = prof['username']?.toString() ?? 'user';
          _myAvatarUrl = prof['avatar_url']?.toString() ?? '';
          _isMyVerified = prof['is_verified'] == true;
        });
      }
    } catch (_) {}
  }

  void _scheduleInboxRefresh() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _fetchInbox(isBackgroundUpdate: true);
    });
  }

  void _subscribeToInboxRealtime() {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      _inboxChannel = _supabase
          .channel('inbox:$myId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'direct_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'receiver_id',
              value: myId,
            ),
            callback: (_) => _scheduleInboxRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'direct_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'sender_id',
              value: myId,
            ),
            callback: (_) => _scheduleInboxRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'conversation_members',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: myId,
            ),
            callback: (_) => _scheduleInboxRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'message_requests',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'recipient_id',
              value: myId,
            ),
            callback: (_) => _scheduleInboxRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'conversations',
            callback: (_) => _scheduleInboxRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'user_notes',
            callback: (_) => _scheduleInboxRefresh(),
          )
          .subscribe();
    } catch (e) {
      debugPrint('[ChatListScreen] Realtime subscription notice: $e');
    }
  }

  Future<void> _fetchInbox({bool isBackgroundUpdate = false}) async {
    if (!isBackgroundUpdate && _conversations.isEmpty && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final snapshot = await ChatService.instance.fetchInbox();
      if (mounted) {
        setState(() {
          _conversations = snapshot.conversations;
          _activeFriendsNotes = snapshot.activeFriendsNotes;
          _suggestedFriends = snapshot.suggestedFriends;
          _myNote = snapshot.myNote;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ChatListScreen] Inbox fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    _searchDebounce?.cancel();

    final trimmed = val.trim();
    if (trimmed.length < 2) {
      setState(() {
        _messageHits = [];
        _isSearchingMessages = false;
      });
      return;
    }

    setState(() => _isSearchingMessages = true);
    _searchDebounce = Timer(const Duration(milliseconds: 320), () async {
      final hits = await ChatService.instance.searchAllMessages(trimmed);
      if (mounted) {
        setState(() {
          _messageHits = hits;
          _isSearchingMessages = false;
        });
      }
    });
  }

  List<ChatConversationItem> get _filteredConversations {
    List<ChatConversationItem> list;
    if (_selectedTab == 'Requests') {
      list = _conversations.where((c) => c.isRequest).toList();
    } else if (_selectedTab == 'Groups') {
      list = _conversations.where((c) => c.isGroup && !c.isRequest).toList();
    } else {
      list = _conversations.where((c) => !c.isRequest).toList();
    }

    final q = _searchQuery.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list.where((c) {
        return c.displayTitle.toLowerCase().contains(q) ||
            c.peerUsername.toLowerCase().contains(q) ||
            c.lastMessageText.toLowerCase().contains(q);
      }).toList();
    }

    return list;
  }

  void _openConversation(ChatConversationItem item) {
    HapticFeedback.lightImpact();

    final idx = _conversations.indexWhere((c) => c.threadKey == item.threadKey);
    if (idx != -1 && _conversations[idx].unreadCount > 0) {
      setState(() {
        _conversations[idx] = _conversations[idx].copyWith(unreadCount: 0);
      });
      ChatCacheService.instance.markThreadRead(
        item.threadKey,
        currentUserId: ChatService.instance.currentUserId,
      );
    }

    ChatConversationScreen.open(
      context,
      conversationId: item.conversationId,
      isGroup: item.isGroup,
      groupTitle: item.groupTitle,
      groupAvatar: item.groupAvatar,
      peerId: item.peerId,
      peerUsername: item.peerUsername,
      peerAvatar: item.peerAvatar,
      peerFullName: item.peerFullName,
      isPeerVerified: item.isPeerVerified,
    ).then((_) {
      if (mounted) _fetchInbox(isBackgroundUpdate: true);
    });
  }

  void _openDirectUser({
    required String peerId,
    required String peerUsername,
    required String peerAvatar,
    required String peerFullName,
    required bool isVerified,
  }) {
    HapticFeedback.lightImpact();
    ChatConversationScreen.open(
      context,
      peerId: peerId,
      peerUsername: peerUsername,
      peerAvatar: peerAvatar,
      peerFullName: peerFullName,
      isPeerVerified: isVerified,
    ).then((_) {
      if (mounted) _fetchInbox(isBackgroundUpdate: true);
    });
  }

  void _openNewChatSheet({bool initialGroupMode = false}) {
    HapticFeedback.lightImpact();
    NewChatSheet.show(
      context,
      initialGroupMode: initialGroupMode,
      onSelectUser: (uId, uName, avatar, full, isVer) {
        _openDirectUser(
          peerId: uId,
          peerUsername: uName,
          peerAvatar: avatar,
          peerFullName: full,
          isVerified: isVer,
        );
      },
      onCreateGroup: (conversationId, title) {
        ChatConversationScreen.open(
          context,
          conversationId: conversationId,
          isGroup: true,
          groupTitle: title,
        ).then((_) {
          if (mounted) _fetchInbox(isBackgroundUpdate: true);
        });
      },
    );
  }

  void _showConversationOptionsMenu(ChatConversationItem item) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.84,
              ),
              decoration: BoxDecoration(
                color: ZevColors.softSurface.withValues(alpha: 0.96),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(30)),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: ZevColors.border,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: ZevColors.border,
                              backgroundImage: item.displayAvatar.isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      item.displayAvatar,
                                    )
                                  : null,
                              child: item.displayAvatar.isEmpty
                                  ? Icon(
                                      item.isGroup
                                          ? Icons.groups_rounded
                                          : Icons.person_rounded,
                                      color: ZevColors.textMuted,
                                      size: 24,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.displayTitle,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: ZevColors.deepNavy,
                                    ),
                                  ),
                                  Text(
                                    item.displayHandle,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: ZevColors.textMuted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (item.conversationId.isNotEmpty) ...[
                        _buildOptionTile(
                          icon: item.isPinned
                              ? Icons.push_pin_outlined
                              : Icons.push_pin_rounded,
                          title: item.isPinned
                              ? 'Unpin Conversation'
                              : 'Pin Conversation',
                          subtitle: item.isPinned
                              ? 'Remove from pinned top slot'
                              : 'Keep this chat pinned at the top',
                          onTap: () async {
                            Navigator.pop(ctx);
                            await ChatService.instance.togglePinConversation(
                              item.conversationId,
                              !item.isPinned,
                            );
                            await _fetchInbox(isBackgroundUpdate: true);
                          },
                        ),
                        const SizedBox(height: 8),
                      ],

                      _buildOptionTile(
                        icon: item.unreadCount > 0
                            ? Icons.mark_email_read_rounded
                            : Icons.mark_email_unread_rounded,
                        title: item.unreadCount > 0
                            ? 'Mark as Read'
                            : 'Mark as Unread',
                        subtitle: item.unreadCount > 0
                            ? 'Clear unread counter'
                            : 'Highlight as unread in inbox',
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _toggleReadState(item);
                        },
                      ),
                      const SizedBox(height: 8),

                      if (item.conversationId.isNotEmpty) ...[
                        _buildOptionTile(
                          icon: item.isMuted
                              ? Icons.notifications_active_outlined
                              : Icons.notifications_off_outlined,
                          title: item.isMuted
                              ? 'Unmute Notifications'
                              : 'Mute Notifications',
                          subtitle: item.isMuted
                              ? 'Resume push alerts for this chat'
                              : 'Silence alerts for 8h, 1w, or forever',
                          onTap: () {
                            Navigator.pop(ctx);
                            _handleMuteAction(item);
                          },
                        ),
                        const SizedBox(height: 8),
                      ],

                      _buildOptionTile(
                        icon: item.isGroup
                            ? Icons.group_outlined
                            : Icons.person_outline_rounded,
                        title:
                            item.isGroup ? 'Group Info & Members' : 'View Profile',
                        subtitle: item.isGroup
                            ? 'Manage members, admins & group title'
                            : 'See @${item.peerUsername}\'s profile',
                        onTap: () {
                          Navigator.pop(ctx);
                          if (item.isGroup) {
                            GroupInfoSheet.show(
                              context,
                              conversationId: item.conversationId,
                              onGroupUpdated: () =>
                                  _fetchInbox(isBackgroundUpdate: true),
                              onLeftGroup: () =>
                                  _fetchInbox(isBackgroundUpdate: true),
                            );
                          } else {
                            ProfileScreen.open(context, userId: item.peerId);
                          }
                        },
                      ),
                      const SizedBox(height: 8),

                      _buildOptionTile(
                        icon: Icons.delete_outline_rounded,
                        title: 'Delete Conversation',
                        subtitle:
                            'Remove this chat from your inbox (keeps peer copy)',
                        isDestructive: true,
                        onTap: () {
                          Navigator.pop(ctx);
                          _confirmDeleteConversation(item);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleReadState(ChatConversationItem item) async {
    HapticFeedback.lightImpact();
    if (item.unreadCount > 0 && item.conversationId.isNotEmpty) {
      await ChatService.instance.markConversationRead(
        conversationId: item.conversationId,
        peerId: item.peerId,
      );
    }
    final idx = _conversations.indexWhere((c) => c.threadKey == item.threadKey);
    if (idx != -1 && mounted) {
      final nextUnread = item.unreadCount > 0 ? 0 : 1;
      setState(() {
        _conversations[idx] =
            _conversations[idx].copyWith(unreadCount: nextUnread);
      });
      ChatCacheService.instance.setInbox(_conversations);
    }
  }

  Future<void> _handleMuteAction(ChatConversationItem item) async {
    if (item.isMuted) {
      await ChatService.instance.unmuteConversation(item.conversationId);
      await _fetchInbox(isBackgroundUpdate: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unmuted ${item.displayTitle}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              'Mute ${item.displayTitle}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('For 8 hours'),
              onTap: () => Navigator.pop(ctx, '8h'),
            ),
            ListTile(
              leading: const Icon(Icons.date_range_rounded),
              title: const Text('For 1 week'),
              onTap: () => Navigator.pop(ctx, '1w'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off_rounded),
              title: const Text('Always'),
              onTap: () => Navigator.pop(ctx, 'always'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;

    Duration? dur;
    if (choice == '8h') dur = const Duration(hours: 8);
    if (choice == '1w') dur = const Duration(days: 7);

    await ChatService.instance
        .muteConversation(item.conversationId, duration: dur);
    await _fetchInbox(isBackgroundUpdate: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Muted ${item.displayTitle}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmDeleteConversation(ChatConversationItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          'Delete chat with ${item.displayTitle}?',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            fontSize: 17,
          ),
        ),
        content: const Text(
          'This removes existing messages from your inbox only. Other participants keep their copy.',
          style: TextStyle(color: ZevColors.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: ZevColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              HapticFeedback.mediumImpact();
              setState(() {
                _conversations
                    .removeWhere((c) => c.threadKey == item.threadKey);
              });
              ChatCacheService.instance.setInbox(_conversations);
              if (item.conversationId.isNotEmpty) {
                await ChatService.instance
                    .deleteConversationForMe(item.conversationId);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFEF2F2),
              foregroundColor: ZevColors.errorRed,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
              ),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDestructive ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDestructive
              ? const Color(0xFFFCA5A5).withValues(alpha: 0.6)
              : Colors.white,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDestructive
                        ? const Color(0xFFFEE2E2)
                        : ZevColors.softSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isDestructive
                        ? ZevColors.errorRed
                        : ZevColors.deepNavy,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: isDestructive
                              ? ZevColors.errorRed
                              : ZevColors.deepNavy,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDestructive
                              ? ZevColors.errorRed.withValues(alpha: 0.8)
                              : ZevColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: ZevColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredConversations;

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.94),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop()
            ? Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: ZevColors.softSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: ZevColors.deepNavy,
                        size: 17,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        title: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            MultiAccountService.showAccountSwitcherSheet(context);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '@$_myUsername',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (_isMyVerified) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: ZevColors.primaryBlue,
                ),
              ],
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: ZevColors.textMuted,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'New Group',
            onPressed: () => _openNewChatSheet(initialGroupMode: true),
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: ZevColors.softSurface,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(
                Icons.group_add_outlined,
                color: ZevColors.deepNavy,
                size: 18,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _openNewChatSheet(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ZevColors.softSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Icon(
                  Icons.edit_square,
                  color: ZevColors.deepNavy,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: ZevColors.primaryBlue,
          onRefresh: () => _fetchInbox(isBackgroundUpdate: false),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: _buildSearchBar()),
              SliverToBoxAdapter(child: _buildNotesAndActiveFriendsTray()),
              SliverToBoxAdapter(child: _buildFilterTabs()),

              if (_isLoading && _conversations.isEmpty)
                SliverFillRemaining(child: _buildShimmerLoading())
              else if (filtered.isEmpty && _messageHits.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyInbox())
              else ...[
                if (filtered.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildConversationCard(filtered[index]),
                        ),
                        childCount: filtered.length,
                      ),
                    ),
                  ),
                if (_searchQuery.trim().length >= 2)
                  SliverToBoxAdapter(child: _buildMessageSearchResults()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: ZevColors.deepNavy.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: ZevColors.textMuted,
              size: 21,
            ),
            const SizedBox(width: 10),
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
                  hintText: 'Search chats or message text...',
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
                  Icons.close_rounded,
                  size: 18,
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
    );
  }

  Widget _buildMessageSearchResults() {
    if (_isSearchingMessages) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: ZevColors.primaryBlue,
            ),
          ),
        ),
      );
    }
    if (_messageHits.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Messages (${_messageHits.length})',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: ZevColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ..._messageHits.map((hit) {
            return Container(
              margin: const EdgeInsets.only(bottom: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: ZevColors.border),
              ),
              child: ListTile(
                onTap: () {
                  ChatConversationScreen.open(
                    context,
                    conversationId: hit.message.conversationId ?? '',
                    isGroup: hit.isGroup,
                    groupTitle: hit.isGroup ? hit.conversationTitle : '',
                    peerId: hit.peerId,
                    peerUsername: hit.peerUsername,
                    peerAvatar: hit.peerAvatar,
                  );
                },
                leading: CircleAvatar(
                  backgroundColor: ZevColors.softSurface,
                  backgroundImage: hit.peerAvatar.isNotEmpty
                      ? CachedNetworkImageProvider(hit.peerAvatar)
                      : null,
                  child: hit.peerAvatar.isEmpty
                      ? Icon(
                          hit.isGroup
                              ? Icons.groups_rounded
                              : Icons.person_rounded,
                          color: ZevColors.textMuted,
                        )
                      : null,
                ),
                title: Text(
                  hit.conversationTitle,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                  ),
                ),
                subtitle: Text(
                  hit.message.messageText.isNotEmpty
                      ? hit.message.messageText
                      : (hit.message.fileName ?? 'Attachment'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: ZevColors.textSecondary,
                  ),
                ),
                trailing: Text(
                  TimeAgo.format(hit.message.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: ZevColors.textMuted,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNotesAndActiveFriendsTray() {
    final hasMyNote = _myNote.isNotEmpty;

    return Container(
      height: 112,
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: 1 + _activeFriendsNotes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == 0) {
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showAddNoteModal();
              },
              child: SizedBox(
                width: 72,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    ZevColors.deepNavy.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 27,
                            backgroundColor: ZevColors.border,
                            backgroundImage: _myAvatarUrl.isNotEmpty
                                ? CachedNetworkImageProvider(_myAvatarUrl)
                                : null,
                            child: _myAvatarUrl.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: ZevColors.textMuted,
                                    size: 26,
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          top: -8,
                          left: -6,
                          right: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: Colors.white, width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: ZevColors.deepNavy
                                      .withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (!hasMyNote) ...[
                                  const Icon(
                                    Icons.add_rounded,
                                    size: 12,
                                    color: ZevColors.primaryBlue,
                                  ),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Note',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: ZevColors.deepNavy,
                                    ),
                                  ),
                                ] else
                                  Flexible(
                                    child: Text(
                                      _myNote,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: ZevColors.deepNavy,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Your note',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: ZevColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          }

          final friend = _activeFriendsNotes[index - 1];
          final fId = friend['id']?.toString() ?? '';
          final fUsername = friend['username']?.toString() ?? 'friend';
          final fAvatar = friend['avatar_url']?.toString() ?? '';
          final fVerified = friend['is_verified'] == true;
          final fNote = friend['note']?.toString() ?? '';
          final isOnline = friend['is_online'] == true;

          return GestureDetector(
            onTap: () {
              _openDirectUser(
                peerId: fId,
                peerUsername: fUsername,
                peerAvatar: fAvatar,
                peerFullName: fUsername,
                isVerified: fVerified,
              );
            },
            child: SizedBox(
              width: 72,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: isOnline
                                ? ZevColors.successGreen.withValues(alpha: 0.55)
                                : Colors.transparent,
                            width: 1.6,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  ZevColors.deepNavy.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 27,
                          backgroundColor: ZevColors.border,
                          backgroundImage: fAvatar.isNotEmpty
                              ? CachedNetworkImageProvider(fAvatar)
                              : null,
                          child: fAvatar.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  color: ZevColors.textMuted,
                                  size: 26,
                                )
                              : null,
                        ),
                      ),
                      if (isOnline)
                        Positioned(
                          bottom: 1,
                          right: 1,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: ZevColors.successGreen,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      if (fNote.isNotEmpty)
                        Positioned(
                          top: -8,
                          left: -6,
                          right: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: Colors.white, width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: ZevColors.deepNavy
                                      .withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              fNote,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: ZevColors.deepNavy,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fUsername,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isOnline ? FontWeight.w700 : FontWeight.w600,
                      color: isOnline
                          ? ZevColors.deepNavy
                          : ZevColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterTabs() {
    final requestsCount = _conversations.where((c) => c.isRequest).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ZevColors.border.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: _tabs.map((tab) {
            final isSelected = tab == _selectedTab;
            final isRequests = tab == 'Requests';

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedTab = tab);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 7.5),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color:
                                  ZevColors.deepNavy.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        tab,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w900 : FontWeight.w600,
                          color: isSelected
                              ? ZevColors.deepNavy
                              : ZevColors.textMuted,
                        ),
                      ),
                      if (isRequests && requestsCount > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5.5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            gradient: ZevColors.brandGradient,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            requestsCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildConversationCard(ChatConversationItem item) {
    final hasUnread = item.unreadCount > 0 && !item.isLastMessageMine;

    String previewText = item.lastMessageText;
    IconData? previewIcon;
    switch (item.lastMessageType) {
      case 'audio':
        previewText =
            'Voice message${item.lastMessageText.isNotEmpty ? ' (${item.lastMessageText})' : ''}';
        previewIcon = Icons.mic_rounded;
        break;
      case 'video':
        if (previewText.isEmpty) previewText = 'Video';
        previewIcon = Icons.videocam_rounded;
        break;
      case 'image':
        if (previewText.isEmpty) previewText = 'Photo';
        previewIcon = Icons.photo_rounded;
        break;
      case 'file':
        if (previewText.isEmpty) previewText = 'Document';
        previewIcon = Icons.attach_file_rounded;
        break;
      case 'post_share':
        previewIcon = Icons.article_outlined;
        if (previewText.isEmpty) previewText = 'Shared a post';
        break;
      case 'reel_share':
        previewIcon = Icons.video_collection_outlined;
        if (previewText.isEmpty) previewText = 'Shared a reel';
        break;
      case 'deleted':
        previewText = 'Message deleted';
        previewIcon = Icons.block_rounded;
        break;
      case 'call_log':
      case 'call':
        final isVideo = previewText.toLowerCase().contains('video');
        final isMissed = previewText.toLowerCase().contains('missed') ||
            previewText.toLowerCase().contains('no answer');
        if (isMissed) {
          previewIcon = isVideo
              ? Icons.missed_video_call_rounded
              : Icons.phone_missed_rounded;
        } else {
          previewIcon = isVideo ? Icons.videocam_rounded : Icons.phone_rounded;
        }
        if (previewText.isEmpty) {
          previewText = isVideo ? 'Video call' : 'Audio call';
        }
        break;
    }

    String senderPrefix = '';
    if (item.isLastMessageMine) {
      senderPrefix = 'You: ';
    } else if (item.isGroup && (item.lastSenderName ?? '').isNotEmpty) {
      senderPrefix = '${item.lastSenderName}: ';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: hasUnread
              ? ZevColors.primaryBlue.withValues(alpha: 0.4)
              : Colors.white,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: hasUnread
                ? ZevColors.primaryBlue.withValues(alpha: 0.08)
                : ZevColors.deepNavy.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openConversation(item),
          onLongPress: () => _showConversationOptionsMenu(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: item.isGroup
                              ? ZevColors.primaryBlue.withValues(alpha: 0.14)
                              : ZevColors.border,
                          backgroundImage: item.displayAvatar.isNotEmpty
                              ? CachedNetworkImageProvider(item.displayAvatar)
                              : null,
                          child: item.displayAvatar.isEmpty
                              ? Icon(
                                  item.isGroup
                                      ? Icons.groups_rounded
                                      : Icons.person_rounded,
                                  color: item.isGroup
                                      ? ZevColors.secondaryBlue
                                      : ZevColors.textMuted,
                                  size: 26,
                                )
                              : null,
                        ),
                        if (!item.isGroup && item.isPeerOnline)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                color: ZevColors.successGreen,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.isGroup
                                      ? item.displayTitle
                                      : '@${item.peerUsername}',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: hasUnread
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                    color: ZevColors.deepNavy,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!item.isGroup && item.isPeerVerified) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 14,
                                  color: ZevColors.primaryBlue,
                                ),
                              ],
                              if (item.isPinned) ...[
                                const SizedBox(width: 5),
                                const Icon(
                                  Icons.push_pin_rounded,
                                  size: 13,
                                  color: ZevColors.secondaryBlue,
                                ),
                              ],
                              if (item.isMuted) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.notifications_off_rounded,
                                  size: 13,
                                  color: ZevColors.textMuted,
                                ),
                              ],
                              const Spacer(),
                              Text(
                                TimeAgo.format(item.lastMessageAt),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: hasUnread
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: hasUnread
                                      ? ZevColors.primaryBlue
                                      : ZevColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3.5),
                          Row(
                            children: [
                              if (item.isLastMessageMine) ...[
                                _buildStatusTick(item.deliveryStatus),
                                const SizedBox(width: 4),
                              ],
                              if (previewIcon != null) ...[
                                Icon(
                                  previewIcon,
                                  size: 14,
                                  color: hasUnread
                                      ? ZevColors.primaryBlue
                                      : ZevColors.textMuted,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  '$senderPrefix$previewText',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: hasUnread
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: hasUnread
                                        ? ZevColors.deepNavy
                                        : ZevColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (hasUnread)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.5,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: ZevColors.brandGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          item.unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      )
                    else
                      Icon(
                        item.isGroup
                            ? Icons.chevron_right_rounded
                            : Icons.camera_alt_outlined,
                        color: ZevColors.textMuted,
                        size: 20,
                      ),
                  ],
                ),
                if (item.isRequest && _selectedTab == 'Requests') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await ChatService.instance.respondMessageRequest(
                              conversationId: item.conversationId,
                              accept: false,
                            );
                            await _fetchInbox(isBackgroundUpdate: true);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ZevColors.errorRed,
                            side: BorderSide(
                              color: ZevColors.errorRed.withValues(alpha: 0.4),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Decline',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            await ChatService.instance.respondMessageRequest(
                              conversationId: item.conversationId,
                              accept: true,
                            );
                            await _fetchInbox(isBackgroundUpdate: true);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ZevColors.primaryBlue,
                            foregroundColor: ZevColors.deepNavy,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Accept',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTick(String status) {
    if (status == 'read') {
      return const Icon(
        Icons.done_all_rounded,
        size: 15,
        color: Color(0xFF0284C7),
      );
    } else if (status == 'delivered') {
      return const Icon(
        Icons.done_all_rounded,
        size: 15,
        color: ZevColors.textMuted,
      );
    }
    return const Icon(
      Icons.done_rounded,
      size: 15,
      color: ZevColors.textMuted,
    );
  }

  void _showAddNoteModal() {
    final noteCtrl = TextEditingController(text: _myNote);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: ZevColors.softSurface.withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: ZevColors.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Share a 24h Note...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Text(
                    'Visible above your avatar in chat for 24 hours.',
                    style: TextStyle(fontSize: 12.5, color: ZevColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildEmojiPill('💭', 'Thinking', noteCtrl),
                        _buildEmojiPill('🔥', 'Vibing', noteCtrl),
                        _buildEmojiPill('🎧', 'Music', noteCtrl),
                        _buildEmojiPill('⚡', 'Energy', noteCtrl),
                        _buildEmojiPill('☕', 'Coffee', noteCtrl),
                        _buildEmojiPill('💻', 'Working', noteCtrl),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: ZevColors.border),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: TextField(
                      controller: noteCtrl,
                      maxLength: 60,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ZevColors.deepNavy,
                      ),
                      decoration: const InputDecoration(
                        hintText: "What's on your mind? (60 chars)",
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_myNote.isNotEmpty) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await ChatService.instance.deleteUserNote();
                              if (mounted) setState(() => _myNote = '');
                              if (ctx.mounted) Navigator.pop(ctx);
                              _fetchInbox(isBackgroundUpdate: true);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ZevColors.errorRed,
                              side: const BorderSide(color: Color(0xFFFCA5A5)),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Delete Note',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: ZevColors.brandGradient,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ElevatedButton(
                            onPressed: () async {
                              final text = noteCtrl.text.trim();
                              if (text.isEmpty) {
                                await ChatService.instance.deleteUserNote();
                              } else {
                                await ChatService.instance.saveUserNote(text);
                              }
                              if (mounted) setState(() => _myNote = text);
                              if (ctx.mounted) Navigator.pop(ctx);
                              _fetchInbox(isBackgroundUpdate: true);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              _myNote.isNotEmpty ? 'Update Note' : 'Share Note',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(noteCtrl.dispose);
  }

  Widget _buildEmojiPill(
    String emoji,
    String label,
    TextEditingController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          final current = controller.text;
          if (!current.startsWith(emoji)) {
            controller.text = '$emoji $current'.trim();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ZevColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.deepNavy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _PulsingShimmer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: ZevColors.border,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: ZevColors.border,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 200,
                      height: 11,
                      decoration: BoxDecoration(
                        color: ZevColors.softSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyInbox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: ZevColors.deepNavy.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: ZevColors.softSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _selectedTab == 'Groups'
                        ? Icons.groups_outlined
                        : (_selectedTab == 'Requests'
                            ? Icons.mark_chat_unread_outlined
                            : Icons.chat_bubble_outline_rounded),
                    size: 34,
                    color: ZevColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _selectedTab == 'Requests'
                      ? 'No Message Requests'
                      : (_selectedTab == 'Groups'
                          ? 'No Group Chats Yet'
                          : 'No Messages Yet'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _selectedTab == 'Requests'
                      ? 'Message requests from people you do not follow appear here.'
                      : 'Start a direct chat or create a group with your friends.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: ZevColors.textMuted,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_selectedTab != 'Requests') ...[
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () => _openNewChatSheet(
                      initialGroupMode: _selectedTab == 'Groups',
                    ),
                    icon: Icon(
                      _selectedTab == 'Groups'
                          ? Icons.group_add_rounded
                          : Icons.send_rounded,
                      size: 17,
                    ),
                    label: Text(
                      _selectedTab == 'Groups'
                          ? 'Create Group'
                          : 'New Message',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZevColors.primaryBlue,
                      foregroundColor: ZevColors.deepNavy,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_selectedTab == 'Primary' && _suggestedFriends.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Text(
                  'Suggested Friends',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _openNewChatSheet(),
                  child: const Text('See all', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _suggestedFriends.take(4).length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final friend = _suggestedFriends[index];
                final fId = friend['id']?.toString() ?? '';
                final fUsername = friend['username']?.toString() ?? 'user';
                final fAvatar = friend['avatar_url']?.toString() ?? '';
                final fVerified = friend['is_verified'] == true;

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: ZevColors.border,
                        backgroundImage: fAvatar.isNotEmpty
                            ? CachedNetworkImageProvider(fAvatar)
                            : null,
                        child: fAvatar.isEmpty
                            ? const Icon(
                                Icons.person,
                                color: ZevColors.textMuted,
                                size: 22,
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
                                    '@$fUsername',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: ZevColors.deepNavy,
                                    ),
                                  ),
                                ),
                                if (fVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.verified_rounded,
                                    size: 13,
                                    color: ZevColors.primaryBlue,
                                  ),
                                ],
                              ],
                            ),
                            const Text(
                              'Tap to start chatting',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: ZevColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          _openDirectUser(
                            peerId: fId,
                            peerUsername: fUsername,
                            peerAvatar: fAvatar,
                            peerFullName: fUsername,
                            isVerified: fVerified,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZevColors.softSurface,
                          foregroundColor: ZevColors.deepNavy,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        child: const Text(
                          'Chat',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _PulsingShimmer extends StatefulWidget {
  final Widget child;
  const _PulsingShimmer({required this.child});

  @override
  State<_PulsingShimmer> createState() => _PulsingShimmerState();
}

class _PulsingShimmerState extends State<_PulsingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
      lowerBound: 0.45,
      upperBound: 0.9,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _anim, child: widget.child);
  }
}
