import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/services/user_presence_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/time_ago.dart';
import '../models/chat_conversation_item.dart';
import '../services/chat_cache_service.dart';
import '../widgets/new_chat_sheet.dart';
import 'chat_conversation_screen.dart';

/// Flagship Claymorphic & Glassmorphic Direct Messages Inbox Screen for ZEV.
/// Features:
/// - Instant 0ms cache-backed rendering via ChatCacheService
/// - Real-time Supabase direct_messages & profiles presence synchronization
/// - Top Active Friends & Notes Carousel with floating 3D speech bubble pills
/// - Primary, General, and Requests filter tabs with claymorphic active indicator
/// - Outgoing tick lifecycle: 1 grey tick (sent), 2 grey ticks (delivered), 2 blue ticks (seen/read)
/// - Unread message counter badges with bold typography & 3D gradient bubble
/// - Auto-suggested friends fallback so the inbox is never blank or empty
/// - Strictly preserves the elegant, clean Light aesthetic with buttery-smooth 120 FPS performance
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
  List<Map<String, dynamic>> _suggestedFriends = [];
  String _selectedTab = "Primary"; // "Primary", "General", "Requests"
  String _searchQuery = "";

  RealtimeChannel? _directMessagesChannel;

  final List<String> _tabs = ["Primary", "General", "Requests"];

  @override
  void initState() {
    super.initState();
    _loadFromCacheFirst();
    _loadCurrentUserProfile();
    _fetchInbox(isBackgroundUpdate: _conversations.isNotEmpty);
    _subscribeToLiveMessages();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _directMessagesChannel?.unsubscribe();
    super.dispose();
  }

  /// Instantly renders previously cached conversations and friends in 0ms
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

  /// Fetches real direct messages, peer profiles, and active friends with fault-tolerance
  Future<void> _fetchInbox({bool isBackgroundUpdate = false}) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (!isBackgroundUpdate && _conversations.isEmpty) {
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
          .limit(300);

      // 2. Group messages by peer user id
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final m in (msgsRes as List)) {
        final sId = m['sender_id']?.toString() ?? '';
        final rId = m['receiver_id']?.toString() ?? '';
        final peerId = (sId == currentUserId) ? rId : sId;
        if (peerId.isEmpty || peerId == currentUserId) continue;

        grouped.putIfAbsent(peerId, () => []).add(m);
      }

      final allPeerIds = grouped.keys.toSet();

      // 3. Fetch user's friends & following contacts so the tray is always active
      final Set<String> friendUserIds = {};
      try {
        final followingRes = await supabase
            .from('user_follows')
            .select('following_id')
            .eq('follower_id', currentUserId)
            .limit(25);
        for (final f in (followingRes as List)) {
          final id = f['following_id']?.toString() ?? '';
          if (id.isNotEmpty && id != currentUserId) friendUserIds.add(id);
        }

        final followersRes = await supabase
            .from('user_follows')
            .select('follower_id')
            .eq('following_id', currentUserId)
            .limit(25);
        for (final f in (followersRes as List)) {
          final id = f['follower_id']?.toString() ?? '';
          if (id.isNotEmpty && id != currentUserId) friendUserIds.add(id);
        }
      } catch (e) {
        debugPrint("user_follows fetch notice: $e");
      }

      // 4. Combine all IDs to fetch their full profiles
      final combinedIds = {...allPeerIds, ...friendUserIds};

      // If still very few users, discover other active platform users
      if (combinedIds.length < 8) {
        try {
          final suggestions = await supabase
              .from('profiles')
              .select('id')
              .neq('id', currentUserId)
              .limit(15);
          for (final s in (suggestions as List)) {
            final id = s['id']?.toString() ?? '';
            if (id.isNotEmpty) combinedIds.add(id);
          }
        } catch (_) {}
      }

      Map<String, Map<String, dynamic>> profilesMap = {};
      if (combinedIds.isNotEmpty) {
        try {
          // Primary query with presence fields
          final profsRes = await supabase
              .from('profiles')
              .select(
                'id, username, first_name, last_name, avatar_url, is_verified, bio, last_seen, last_seen_at, is_online, updated_at',
              )
              .inFilter('id', combinedIds.toList());

          for (final p in (profsRes as List)) {
            profilesMap[p['id'].toString()] = p;
            ChatCacheService.instance.cacheProfile(p['id'].toString(), p);
          }
        } catch (colErr) {
          debugPrint("Presence columns query fallback notice: $colErr");
          // Resilient fallback query with standard columns
          final fallbackProfs = await supabase
              .from('profiles')
              .select('id, username, first_name, last_name, avatar_url, is_verified, bio')
              .inFilter('id', combinedIds.toList());

          for (final p in (fallbackProfs as List)) {
            profilesMap[p['id'].toString()] = p;
            ChatCacheService.instance.cacheProfile(p['id'].toString(), p);
          }
        }
      }

      // 5. Construct Conversation Items for users who have messages
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
            lastMessageAt: DateTime.tryParse(lastMsg['created_at']?.toString() ?? '') ??
                DateTime.now(),
            unreadCount: unreadCount,
            peerNote: presence.statusText,
          ),
        );
      }

      // Sort conversations with newest last message first
      convList.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

      // 6. Populate Active Friends Notes Carousel (Top bar)
      final List<Map<String, dynamic>> notesList = [];
      for (final pId in combinedIds) {
        final p = profilesMap[pId];
        if (p != null) {
          final pPresence = UserPresenceService.computePresence(p);
          notesList.add({
            'id': p['id'],
            'username': p['username'] ?? 'user',
            'first_name': p['first_name'] ?? '',
            'avatar_url': p['avatar_url'] ?? '',
            'is_verified': p['is_verified'] == true,
            'is_online': pPresence.isOnline,
            'note': (p['bio'] != null && p['bio'].toString().isNotEmpty)
                ? p['bio'].toString()
                : pPresence.statusText,
          });
        }
      }

      // 7. Suggested friends list (contacts user hasn't messaged yet)
      final List<Map<String, dynamic>> suggested = [];
      for (final pId in combinedIds) {
        if (!grouped.containsKey(pId) && profilesMap.containsKey(pId)) {
          suggested.add(profilesMap[pId]!);
        }
      }

      // Store in high-performance in-memory cache
      ChatCacheService.instance.setInbox(convList);
      ChatCacheService.instance.setActiveFriends(notesList);

      if (mounted) {
        setState(() {
          _conversations = convList;
          _activeFriendsNotes = notesList;
          _suggestedFriends = suggested;
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

    // Reset unread count locally for instant UI update
    final idx = _conversations.indexWhere((c) => c.peerId == peerId);
    if (idx != -1 && _conversations[idx].unreadCount > 0) {
      setState(() {
        _conversations[idx] = _conversations[idx].copyWith(unreadCount: 0);
      });
      ChatCacheService.instance.markThreadRead(peerId);
    }

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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.06),
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
          onTap: () => HapticFeedback.selectionClick(),
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
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.edit_square,
                color: Color(0xFF0F172A),
                size: 18,
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
          const SizedBox(width: 8),
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
              // 1. Claymorphic Search Bar
              SliverToBoxAdapter(
                child: _buildSearchBar(),
              ),

              // 2. Active Friends & Notes Horizontal Carousel
              SliverToBoxAdapter(
                child: _buildNotesAndActiveFriendsTray(),
              ),

              // 3. Filter Tabs (Primary | General | Requests)
              SliverToBoxAdapter(
                child: _buildFilterTabs(),
              ),

              // 4. Conversation List View or Empty State with Suggested Contacts
              if (_isLoading && _conversations.isEmpty)
                SliverFillRemaining(
                  child: _buildShimmerLoading(),
                )
              else if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: _buildEmptyInbox(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = filtered[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildConversationCard(item),
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Claymorphic 3D Search Bar with soft inset feel
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.8),
              blurRadius: 4,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 21),
            const SizedBox(width: 10),
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
                  hintText: "Search messages or friends...",
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
                icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
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
      height: 108,
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: 1 + _activeFriendsNotes.length,
        separatorBuilder: (context, index) => const SizedBox(width: 15),
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
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 27,
                          backgroundColor: const Color(0xFFE2E8F0),
                          backgroundImage: _myAvatarUrl.isNotEmpty
                              ? CachedNetworkImageProvider(_myAvatarUrl)
                              : null,
                          child: _myAvatarUrl.isEmpty
                              ? const Icon(Icons.person, color: Color(0xFF94A3B8), size: 26)
                              : null,
                        ),
                      ),

                      // Floating Claymorphic Note Bubble
                      Positioned(
                        top: -7,
                        left: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, size: 11, color: ZevColors.primaryBlue),
                              SizedBox(width: 2),
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
                      fontSize: 11.5,
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
          final isOnline = friend['is_online'] == true;

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
              width: 68,
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
                                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 27,
                          backgroundColor: const Color(0xFFE2E8F0),
                          backgroundImage: fAvatar.isNotEmpty
                              ? CachedNetworkImageProvider(fAvatar)
                              : null,
                          child: fAvatar.isEmpty
                              ? const Icon(Icons.person, color: Color(0xFF94A3B8), size: 26)
                              : null,
                        ),
                      ),

                      // Online Green Indicator Dot
                      if (isOnline)
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Floating 3D Note Bubble
                      if (fNote.isNotEmpty)
                        Positioned(
                          top: -7,
                          left: -8,
                          right: -8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.14),
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
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isOnline ? FontWeight.w700 : FontWeight.w600,
                      color: isOnline ? const Color(0xFF0F172A) : const Color(0xFF64748B),
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

  /// Claymorphic Segmented Filter Tabs (Primary, General, Requests)
  Widget _buildFilterTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: _tabs.map((tab) {
          final isSelected = tab == _selectedTab;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedTab = tab);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 1.2,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  tab,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Flagship Claymorphic Conversation Card with Outgoing Ticks & Unread Badge
  Widget _buildConversationCard(ChatConversationItem item) {
    final hasUnread = item.unreadCount > 0 && !item.isLastMessageMine;

    // Subtitle message preview text
    String previewText = item.lastMessageText;
    if (item.lastAttachmentType == 'audio') {
      previewText = "🎙️ Voice message${item.lastMessageText.isNotEmpty ? ' (${item.lastMessageText})' : ''}";
    } else if (previewText.isEmpty && item.lastAttachmentUrl != null) {
      previewText = item.lastAttachmentType == 'video' ? "Sent a video" : "Sent a photo";
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: hasUnread ? Colors.white : Colors.white,
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
                  : const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.9),
              blurRadius: 2,
              offset: const Offset(0, -1),
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
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 13),

            // Content Column: Username + Message Preview + Time
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
                            letterSpacing: -0.2,
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
                      const Spacer(),
                      Text(
                        TimeAgo.format(item.lastMessageAt),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w500,
                          color: hasUnread
                              ? ZevColors.primaryBlue
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3.5),
                  Row(
                    children: [
                      // Outgoing delivery status tick indicator:
                      // 1 grey tick = sent, 2 grey ticks = delivered, 2 blue ticks = read
                      if (item.isLastMessageMine) ...[
                        _buildStatusTick(item.deliveryStatus),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          item.isLastMessageMine ? "You: $previewText" : previewText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w500,
                            color: hasUnread
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF64748B),
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

            // Right side: 3D Unread Badge Counter or Quick Camera Shortcut
            if (hasUnread)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.5, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00D4FF), Color(0xFF0284C7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
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

  /// Renders accurate ticks based on status:
  /// - 'sent': 1 grey tick
  /// - 'delivered': 2 grey ticks
  /// - 'read': 2 blue ticks
  Widget _buildStatusTick(String status) {
    if (status == 'read') {
      return const Icon(
        Icons.done_all_rounded,
        size: 15,
        color: Color(0xFF0284C7), // 2 blue ticks
      );
    } else if (status == 'delivered') {
      return const Icon(
        Icons.done_all_rounded,
        size: 15,
        color: Color(0xFF94A3B8), // 2 grey ticks
      );
    } else {
      return const Icon(
        Icons.done_rounded,
        size: 15,
        color: Color(0xFF94A3B8), // 1 grey tick
      );
    }
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Share a Thought...",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLength: 60,
                decoration: InputDecoration(
                  hintText: "What's on your mind? (60 chars)",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
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
      itemCount: 6,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) => Container(
        height: 74,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }

  /// Empty inbox state that smartly provides quick suggestions so the screen is never dead
  Widget _buildEmptyInbox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        children: [
          // Claymorphic Hero Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.05),
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
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 34,
                    color: ZevColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 14),
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
                  "Direct message your friends or start a chat with suggested people below.",
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
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
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Text("New Message"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZevColors.primaryBlue,
                    foregroundColor: ZevColors.deepNavy,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          // Suggested Friends to Chat With
          if (_suggestedFriends.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Text(
                  "Suggested Friends",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                TextButton(
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
                  child: const Text("See all", style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _suggestedFriends.take(4).length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final friend = _suggestedFriends[index];
                final fId = friend['id']?.toString() ?? '';
                final fUsername = friend['username']?.toString() ?? 'user';
                final fAvatar = friend['avatar_url']?.toString() ?? '';
                final fVerified = friend['is_verified'] == true;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFE2E8F0),
                        backgroundImage: fAvatar.isNotEmpty
                            ? CachedNetworkImageProvider(fAvatar)
                            : null,
                        child: fAvatar.isEmpty
                            ? const Icon(Icons.person, color: Color(0xFF94A3B8), size: 22)
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
                                  "@$fUsername",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
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
                              "Tap to start chatting",
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          _openChatWithUser(
                            peerId: fId,
                            peerUsername: fUsername,
                            peerAvatar: fAvatar,
                            peerFullName: fUsername,
                            isVerified: fVerified,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF1F5F9),
                          foregroundColor: const Color(0xFF0F172A),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        child: const Text(
                          "Chat",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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
