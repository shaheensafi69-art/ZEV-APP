import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/services/user_presence_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/time_ago.dart';
import '../models/chat_conversation_item.dart';
import '../widgets/new_chat_sheet.dart';
import 'chat_conversation_screen.dart';

/// Flagship Instagram-Caliber Direct Messages Inbox Screen for ZEV.
/// Features:
/// - Real-time Supabase direct_messages & profiles synchronization
/// - Top Instagram Notes & Active Friends Carousel with floating speech bubbles
/// - Primary, General, and Requests filter tabs
/// - Live instant conversation search & new user discovery
/// - Unread message counter badges & online activity status
/// - Claymorphic design language with 120 FPS buttery-smooth performance
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  /// Opens the chat inbox screen with smooth navigation transition
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
  final supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  String _myUsername = 'user';
  String _myAvatarUrl = '';
  bool _isMyVerified = false;

  List<ChatConversationItem> _conversations = [];
  List<Map<String, dynamic>> _activeFriendsNotes = [];
  String _selectedTab = "Primary"; // "Primary", "General", "Requests"
  String _searchQuery = "";

  RealtimeChannel? _directMessagesChannel;

  final List<String> _tabs = ["Primary", "General", "Requests"];

  @override
  void initState() {
    super.initState();
    _loadCurrentUserProfile();
    _fetchInbox();
    _subscribeToLiveMessages();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _directMessagesChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadCurrentUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('username, avatar_url, is_verified')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _myUsername = res['username'] ?? 'user';
          _myAvatarUrl = res['avatar_url'] ?? '';
          _isMyVerified = res['is_verified'] == true;
        });
      }
    } catch (_) {}
  }

  /// Sets up real-time listener for incoming & outgoing direct messages
  void _subscribeToLiveMessages() {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      _directMessagesChannel = supabase
          .channel('public:direct_messages:$currentUserId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'direct_messages',
            callback: (payload) {
              final newRec = payload.newRecord;
              if (newRec.isNotEmpty) {
                final sId = newRec['sender_id']?.toString() ?? '';
                final rId = newRec['receiver_id']?.toString() ?? '';
                if (sId == currentUserId || rId == currentUserId) {
                  _fetchInbox(isBackgroundUpdate: true);
                }
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint("Direct messages realtime subscription notice: $e");
    }
  }

  /// Fetches real direct messages and derives unique 1-on-1 conversations
  Future<void> _fetchInbox({bool isBackgroundUpdate = false}) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (!isBackgroundUpdate) {
      setState(() => _isLoading = true);
    }

    try {
      // 1. Fetch recent direct messages involving current user
      final msgsRes = await supabase
          .from('direct_messages')
          .select(
            'id, sender_id, receiver_id, message_text, attachment_url, attachment_type, is_delivered, is_read, created_at',
          )
          .or('sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId')
          .order('created_at', ascending: false)
          .limit(250);

      // 2. Group messages by peer user id
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final m in msgsRes) {
        final sId = m['sender_id']?.toString() ?? '';
        final rId = m['receiver_id']?.toString() ?? '';
        final peerId = (sId == currentUserId) ? rId : sId;
        if (peerId.isEmpty || peerId == currentUserId) continue;

        if (!grouped.containsKey(peerId)) {
          grouped[peerId] = [];
        }
        grouped[peerId]!.add(m);
      }

      // 3. Batch fetch peer profiles
      final allPeerIds = grouped.keys.toSet();

      // If user has few conversations, also fetch suggested contacts so inbox is active
      final followsRes = await supabase
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', currentUserId)
          .limit(15);

      final followingIds = (followsRes as List)
          .map((f) => f['following_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final combinedIds = {...allPeerIds, ...followingIds};

      Map<String, Map<String, dynamic>> profilesMap = {};
      if (combinedIds.isNotEmpty) {
        final profsRes = await supabase
            .from('profiles')
            .select('id, username, first_name, last_name, avatar_url, is_verified, bio, last_seen, is_online, updated_at')
            .inFilter('id', combinedIds.toList());

        for (final p in profsRes) {
          profilesMap[p['id'].toString()] = p;
        }
      }

      // 4. Construct Conversation Items
      final List<ChatConversationItem> convList = [];

      for (final peerId in grouped.keys) {
        final peerMessages = grouped[peerId]!;
        if (peerMessages.isEmpty) continue;

        final lastMsg = peerMessages.first;
        final profile = profilesMap[peerId] ?? {};

        final unreadCount = peerMessages.where((m) {
          return m['sender_id'] == peerId && m['is_read'] != true;
        }).length;

        final isMine = lastMsg['sender_id'] == currentUserId;
        final fn = profile['first_name'] ?? '';
        final ln = profile['last_name'] ?? '';
        final full = "$fn $ln".trim();

        final presence = UserPresenceService.computePresence(profile);

        convList.add(
          ChatConversationItem(
            peerId: peerId,
            peerUsername: profile['username'] ?? 'user',
            peerFullName: full,
            peerAvatar: profile['avatar_url'] ?? '',
            isPeerVerified: profile['is_verified'] == true,
            isPeerOnline: presence.isOnline,
            lastMessageId: lastMsg['id']?.toString() ?? '',
            lastMessageText: (lastMsg['message_text']?.toString() ?? '').trim(),
            lastAttachmentUrl: lastMsg['attachment_url']?.toString(),
            lastAttachmentType: lastMsg['attachment_type']?.toString(),
            isLastMessageMine: isMine,
            isLastMessageDelivered: lastMsg['is_delivered'] == true,
            isLastMessageRead: lastMsg['is_read'] == true,
            lastMessageAt: DateTime.tryParse(lastMsg['created_at']?.toString() ?? '') ?? DateTime.now(),
            unreadCount: unreadCount,
            peerNote: presence.statusText,
          ),
        );
      }

      // Sort conversations with newest last message first
      convList.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

      // 5. Populate Active Friends Notes Carousel (Top bar)
      final List<Map<String, dynamic>> notesList = [];
      for (final pId in combinedIds) {
        final p = profilesMap[pId];
        if (p != null) {
          final pPresence = UserPresenceService.computePresence(p);
          notesList.add({
            'id': p['id'],
            'username': p['username'] ?? 'user',
            'avatar_url': p['avatar_url'] ?? '',
            'is_verified': p['is_verified'] == true,
            'is_online': pPresence.isOnline,
            'note': (p['bio'] != null && p['bio'].toString().isNotEmpty)
                ? p['bio'].toString()
                : pPresence.statusText,
          });
        }
      }

      if (mounted) {
        setState(() {
          _conversations = convList;
          _activeFriendsNotes = notesList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Inbox fetch error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Filters conversations by search text and active tab
  List<ChatConversationItem> get _filteredConversations {
    List<ChatConversationItem> list = _conversations;

    // Filter by tab
    if (_selectedTab == "Requests") {
      // In Instagram, requests are messages from people not followed
      list = list.where((c) => c.unreadCount > 0 && !c.isLastMessageMine).toList();
    }

    // Filter by search query
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      list = list.where((c) {
        return c.peerUsername.toLowerCase().contains(q) ||
            c.peerFullName.toLowerCase().contains(q) ||
            c.lastMessageText.toLowerCase().contains(q);
      }).toList();
    }

    return list;
  }

  void _openChatWithUser({
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredConversations;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF0F172A),
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "@$_myUsername",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
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
                color: Color(0xFF64748B),
              ),
            ],
          ),
        ),
        actions: [
          // Compose / New Message Button
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: const Icon(
                Icons.edit_square,
                color: Color(0xFF0F172A),
                size: 19,
              ),
            ),
            tooltip: "New Message",
            onPressed: () {
              HapticFeedback.lightImpact();
              NewChatSheet.show(
                context,
                onSelectUser: (uId, uName, avatar, full, isVer) {
                  _openChatWithUser(
                    peerId: uId,
                    peerUsername: uName,
                    peerAvatar: avatar,
                    peerFullName: full,
                    isVerified: isVer,
                  );
                },
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: ZevColors.primaryBlue,
          onRefresh: _fetchInbox,
          child: Column(
            children: [
              // 1. Search Bar
              _buildSearchBar(),

              // 2. Instagram Notes & Active Friends Carousel (Horizontal Tray)
              _buildNotesAndActiveFriendsTray(),

              // 3. Filter Tabs (Primary | General | Requests)
              _buildFilterTabs(),

              // 4. Conversation List View
              Expanded(
                child: _isLoading
                    ? _buildShimmerLoading()
                    : filtered.isEmpty
                        ? _buildEmptyInbox()
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 40),
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 7),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              return _buildConversationCard(item);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Claymorphic Search Bar
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
                decoration: const InputDecoration(
                  hintText: "Search messages or accounts...",
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
                icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = "");
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Signature Instagram Notes & Active Friends Horizontal Carousel
  Widget _buildNotesAndActiveFriendsTray() {
    return Container(
      height: 105,
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: 1 + _activeFriendsNotes.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          // Index 0: Current User's "Your Note"
          if (index == 0) {
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showAddNoteModal();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // User Avatar
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFFE2E8F0),
                        backgroundImage: _myAvatarUrl.isNotEmpty
                            ? CachedNetworkImageProvider(_myAvatarUrl)
                            : null,
                        child: _myAvatarUrl.isEmpty
                            ? const Icon(Icons.person, color: Color(0xFF94A3B8), size: 26)
                            : null,
                      ),

                      // Floating Note Bubble
                      Positioned(
                        top: -6,
                        left: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.1),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, size: 10, color: ZevColors.primaryBlue),
                              Text(
                                "Note",
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
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
                    "Your note",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }

          // Friends Notes
          final friend = _activeFriendsNotes[index - 1];
          final fId = friend['id']?.toString() ?? '';
          final fUsername = friend['username']?.toString() ?? 'friend';
          final fAvatar = friend['avatar_url']?.toString() ?? '';
          final fVerified = friend['is_verified'] == true;
          final fNote = friend['note']?.toString() ?? '';

          return GestureDetector(
            onTap: () {
              _openChatWithUser(
                peerId: fId,
                peerUsername: fUsername,
                peerAvatar: fAvatar,
                peerFullName: fUsername,
                isVerified: fVerified,
              );
            },
            child: SizedBox(
              width: 66,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFFE2E8F0),
                        backgroundImage: fAvatar.isNotEmpty
                            ? CachedNetworkImageProvider(fAvatar)
                            : null,
                        child: fAvatar.isEmpty
                            ? const Icon(Icons.person, color: Color(0xFF94A3B8), size: 26)
                            : null,
                      ),

                      // Online Green Indicator Dot (Only when genuinely online)
                      if (friend['is_online'] == true)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),

                      // Floating Note Bubble (if exists)
                      if (fNote.isNotEmpty)
                        Positioned(
                          top: -6,
                          left: -8,
                          right: -8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              fNote,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
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
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
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

  /// Filter Tabs (Primary, General, Requests)
  Widget _buildFilterTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: _tabs.map((tab) {
          final isSelected = tab == _selectedTab;
          return Padding(
            padding: const EdgeInsets.only(right: 18),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedTab = tab);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tab,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                      color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 2.5,
                    width: 28,
                    decoration: BoxDecoration(
                      color: isSelected ? ZevColors.primaryBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Individual Instagram Direct conversation card
  Widget _buildConversationCard(ChatConversationItem item) {
    final hasUnread = item.unreadCount > 0 && !item.isLastMessageMine;

    // Build subtitle message preview text
    String previewText = item.lastMessageText;
    if (item.lastAttachmentType == 'audio') {
      previewText = "🎙️ Voice message${item.lastMessageText.isNotEmpty ? ' (${item.lastMessageText})' : ''}";
    } else if (previewText.isEmpty && item.lastAttachmentUrl != null) {
      previewText = item.lastAttachmentType == 'video' ? "Sent a video" : "Sent a photo";
    }
    if (item.isLastMessageMine) {
      previewText = "You: $previewText";
    }

    return GestureDetector(
      onTap: () {
        _openChatWithUser(
          peerId: item.peerId,
          peerUsername: item.peerUsername,
          peerAvatar: item.peerAvatar,
          peerFullName: item.peerFullName,
          isVerified: item.isPeerVerified,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasUnread ? const Color(0xFFF0FDF4).withValues(alpha: 0.6) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasUnread
                ? ZevColors.primaryBlue.withValues(alpha: 0.4)
                : Colors.white,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // User Avatar with Online Dot
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFFE2E8F0),
                  backgroundImage: item.peerAvatar.isNotEmpty
                      ? CachedNetworkImageProvider(item.peerAvatar)
                      : null,
                  child: item.peerAvatar.isEmpty
                      ? const Icon(Icons.person, color: Color(0xFF94A3B8), size: 26)
                      : null,
                ),
                if (item.isPeerOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Content Column: Username + Message Preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          "@${item.peerUsername}",
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: hasUnread ? FontWeight.w900 : FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.isPeerVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: ZevColors.primaryBlue,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (item.isLastMessageMine) ...[
                        Icon(
                          item.isLastMessageRead
                              ? Icons.done_all_rounded
                              : (item.isLastMessageDelivered
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded),
                          size: 14,
                          color: item.isLastMessageRead
                              ? const Color(0xFF00D4FF)
                              : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          previewText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                            color: hasUnread
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "• ${TimeAgo.format(item.lastMessageAt)}",
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                          color: hasUnread
                              ? ZevColors.primaryBlue
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Right side: Unread Badge or Camera Quick-Send Shortcut
            if (hasUnread)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00D4FF), Color(0xFF0284C7)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
              IconButton(
                icon: const Icon(
                  Icons.camera_alt_outlined,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _openChatWithUser(
                    peerId: item.peerId,
                    peerUsername: item.peerUsername,
                    peerAvatar: item.peerAvatar,
                    peerFullName: item.peerFullName,
                    isVerified: item.isPeerVerified,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showAddNoteModal() {
    final noteCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Share a thought...",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLength: 60,
                decoration: InputDecoration(
                  hintText: "What's on your mind? (60 chars)",
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel"),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final text = noteCtrl.text.trim();
                      if (text.isNotEmpty) {
                        final user = supabase.auth.currentUser;
                        if (user != null) {
                          try {
                            await supabase
                                .from('profiles')
                                .update({'bio': text})
                                .eq('id', user.id);
                          } catch (_) {}
                        }
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _fetchInbox(isBackgroundUpdate: true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZevColors.primaryBlue,
                      foregroundColor: ZevColors.deepNavy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text("Share Note", style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
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
      itemCount: 7,
      separatorBuilder: (context, index) => const SizedBox(height: 7),
      itemBuilder: (context, index) => Container(
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  Widget _buildEmptyInbox() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 38,
                color: ZevColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "No Messages Yet",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Direct message your friends or search anyone on ZEV to start a conversation.",
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.35),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                NewChatSheet.show(
                  context,
                  onSelectUser: (uId, uName, avatar, full, isVer) {
                    _openChatWithUser(
                      peerId: uId,
                      peerUsername: uName,
                      peerAvatar: avatar,
                      peerFullName: full,
                      isVerified: isVer,
                    );
                  },
                );
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text("Send Message"),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: ZevColors.deepNavy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

