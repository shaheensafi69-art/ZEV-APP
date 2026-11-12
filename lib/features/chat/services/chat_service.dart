import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/services/user_presence_service.dart';
import '../models/chat_conversation_item.dart';
import '../models/direct_message_model.dart';
import 'chat_cache_service.dart';

/// Summarized reaction chip for a single emoji on a message.
class MessageReactionSummary {
  final String emoji;
  final int count;
  final bool reactedByMe;

  const MessageReactionSummary({
    required this.emoji,
    required this.count,
    required this.reactedByMe,
  });
}

/// Group conversation member record with role & profile details.
class GroupMemberInfo {
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final bool isVerified;
  final String role; // 'admin' | 'member'
  final DateTime joinedAt;

  const GroupMemberInfo({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.isVerified,
    required this.role,
    required this.joinedAt,
  });

  bool get isAdmin => role == 'admin';
}

class GroupConversationDetails {
  final String conversationId;
  final String title;
  final String avatarUrl;
  final String createdBy;
  final List<GroupMemberInfo> members;

  const GroupConversationDetails({
    required this.conversationId,
    required this.title,
    required this.avatarUrl,
    required this.createdBy,
    required this.members,
  });
}

class InboxSnapshot {
  final List<ChatConversationItem> conversations;
  final List<Map<String, dynamic>> activeFriendsNotes;
  final List<Map<String, dynamic>> suggestedFriends;
  final String myNote;

  const InboxSnapshot({
    required this.conversations,
    required this.activeFriendsNotes,
    required this.suggestedFriends,
    required this.myNote,
  });
}

class MessageSearchHit {
  final DirectMessageModel message;
  final String conversationTitle;
  final String peerId;
  final String peerUsername;
  final String peerAvatar;
  final bool isGroup;

  const MessageSearchHit({
    required this.message,
    required this.conversationTitle,
    required this.peerId,
    required this.peerUsername,
    required this.peerAvatar,
    required this.isGroup,
  });
}

/// Centralized Real-Time Messaging Repository for ZEV.
/// Uses normalized `conversations`, `conversation_members`, `direct_messages`,
/// `message_reactions`, `message_deliveries`, `message_reads`, `message_edits`,
/// `message_deletions`, `conversation_pins`, `conversation_mutes`,
/// `message_requests`, and `user_notes`.
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  SupabaseClient get _supabase => Supabase.instance.client;
  String? get currentUserId => _supabase.auth.currentUser?.id;

  // ===========================================================================
  // INBOX, CONVERSATIONS, PINS, MUTES, REQUESTS & NOTES
  // ===========================================================================

  Future<String?> ensureDirectConversation(String peerId) async {
    if (peerId.isEmpty || peerId == currentUserId) return null;
    try {
      final res = await _supabase.rpc(
        'get_or_create_direct_conversation',
        params: {'p_peer_id': peerId},
      );
      final convId = res?.toString() ?? '';
      if (convId.isNotEmpty) {
        ChatCacheService.instance.linkPeerConversation(peerId, convId);
        return convId;
      }
    } catch (e) {
      debugPrint('[ChatService] ensureDirectConversation notice: $e');
    }
    return null;
  }

  Future<String> createGroupConversation({
    required String title,
    required List<String> memberIds,
    String? avatarUrl,
  }) async {
    final res = await _supabase.rpc(
      'create_group_conversation',
      params: {
        'p_title': title.trim(),
        'p_member_ids': memberIds,
        'p_avatar_url': avatarUrl,
      },
    );
    final convId = res?.toString() ?? '';
    if (convId.isEmpty) {
      throw Exception('Unable to create group conversation.');
    }
    return convId;
  }

  Future<InboxSnapshot> fetchInbox() async {
    final myId = currentUserId;
    if (myId == null) {
      return const InboxSnapshot(
        conversations: [],
        activeFriendsNotes: [],
        suggestedFriends: [],
        myNote: '',
      );
    }

    // Load safety filters, my memberships, pins, mutes, pending requests in parallel
    final initialResults = await Future.wait<dynamic>([
      SocialGraphService.instance.fetchSafetyFilters(),
      _supabase
          .from('conversation_members')
          .select('conversation_id, role, last_read_at')
          .eq('user_id', myId),
      _supabase
          .from('conversation_pins')
          .select('conversation_id')
          .eq('user_id', myId),
      _supabase
          .from('conversation_mutes')
          .select('conversation_id, muted_until')
          .eq('user_id', myId),
      _supabase
          .from('message_requests')
          .select('conversation_id, sender_id, status')
          .eq('recipient_id', myId)
          .eq('status', 'pending'),
      _supabase
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', myId)
          .limit(30),
      _supabase
          .from('user_follows')
          .select('follower_id')
          .eq('following_id', myId)
          .limit(25),
      _supabase
          .from('user_notes')
          .select('user_id, content, expires_at')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String()),
    ]);

    final safety = initialResults[0] as UserSafetyFilters;
    final myMemberships = List<Map<String, dynamic>>.from(
      initialResults[1] as List,
    );
    final pinRows = List<Map<String, dynamic>>.from(initialResults[2] as List);
    final muteRows = List<Map<String, dynamic>>.from(initialResults[3] as List);
    final reqRows = List<Map<String, dynamic>>.from(initialResults[4] as List);
    final followingRows = List<Map<String, dynamic>>.from(
      initialResults[5] as List,
    );
    final followerRows = List<Map<String, dynamic>>.from(
      initialResults[6] as List,
    );
    final noteRows = List<Map<String, dynamic>>.from(initialResults[7] as List);

    final pinnedIds = pinRows
        .map((r) => r['conversation_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final nowUtc = DateTime.now().toUtc();
    final Map<String, DateTime?> mutedMap = {};
    for (final r in muteRows) {
      final cid = r['conversation_id']?.toString() ?? '';
      if (cid.isEmpty) continue;
      final untilStr = r['muted_until']?.toString();
      final until = untilStr != null ? DateTime.tryParse(untilStr) : null;
      if (until == null || until.toUtc().isAfter(nowUtc)) {
        mutedMap[cid] = until;
      }
    }

    final pendingReqConvIds = reqRows
        .map((r) => r['conversation_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final Map<String, String> activeNotesByUser = {};
    String myNote = '';
    for (final r in noteRows) {
      final uid = r['user_id']?.toString() ?? '';
      final content = (r['content'] ?? '').toString().trim();
      if (uid.isEmpty || content.isEmpty) continue;
      if (uid == myId) {
        myNote = content;
      } else {
        activeNotesByUser[uid] = content;
      }
    }

    final convIds = myMemberships
        .map((m) => m['conversation_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    List<Map<String, dynamic>> convRows = [];
    List<Map<String, dynamic>> allMembersRows = [];
    List<Map<String, dynamic>> recentDmRows = [];

    if (convIds.isNotEmpty) {
      final detailResults = await Future.wait<dynamic>([
        _supabase
            .from('conversations')
            .select(
              'id, is_group, title, avatar_url, last_message_text, last_message_type, last_message_at, last_sender_id, created_at',
            )
            .inFilter('id', convIds)
            .order('last_message_at', ascending: false),
        _supabase
            .from('conversation_members')
            .select('conversation_id, user_id, role, last_read_at')
            .inFilter('conversation_id', convIds),
        _supabase
            .from('direct_messages')
            .select(
              'id, conversation_id, sender_id, receiver_id, message_text, message_type, attachment_url, attachment_type, file_name, is_delivered, is_read, deleted_at, deleted_for_user_ids, created_at',
            )
            .inFilter('conversation_id', convIds)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .limit(400),
      ]);

      convRows = List<Map<String, dynamic>>.from(detailResults[0] as List);
      allMembersRows = List<Map<String, dynamic>>.from(detailResults[1] as List);
      recentDmRows = List<Map<String, dynamic>>.from(detailResults[2] as List);
    }

    // Group conversation members and recent non-deleted DMs per conversation
    final Map<String, List<Map<String, dynamic>>> membersByConv = {};
    for (final m in allMembersRows) {
      final cid = m['conversation_id']?.toString() ?? '';
      if (cid.isNotEmpty) {
        membersByConv.putIfAbsent(cid, () => []).add(m);
      }
    }

    final Map<String, Map<String, dynamic>> myMembershipByConv = {};
    for (final m in myMemberships) {
      final cid = m['conversation_id']?.toString() ?? '';
      if (cid.isNotEmpty) myMembershipByConv[cid] = m;
    }

    final Map<String, List<Map<String, dynamic>>> visibleMsgsByConv = {};
    for (final dm in recentDmRows) {
      final cid = dm['conversation_id']?.toString() ?? '';
      if (cid.isEmpty) continue;
      final delFor = dm['deleted_for_user_ids'];
      if (delFor is List && delFor.map((e) => e.toString()).contains(myId)) {
        continue;
      }
      visibleMsgsByConv.putIfAbsent(cid, () => []).add(dm);
    }

    final Set<String> friendIds = {};
    for (final r in followingRows) {
      final id = r['following_id']?.toString() ?? '';
      if (id.isNotEmpty && id != myId && !safety.blockedUserIds.contains(id)) {
        friendIds.add(id);
      }
    }
    for (final r in followerRows) {
      final id = r['follower_id']?.toString() ?? '';
      if (id.isNotEmpty && id != myId && !safety.blockedUserIds.contains(id)) {
        friendIds.add(id);
      }
    }

    final Set<String> neededUserIds = {...friendIds};
    for (final cid in convIds) {
      for (final m in (membersByConv[cid] ?? const [])) {
        final uid = m['user_id']?.toString() ?? '';
        if (uid.isNotEmpty && uid != myId) neededUserIds.add(uid);
      }
      for (final dm in (visibleMsgsByConv[cid] ?? const []).take(1)) {
        final sid = dm['sender_id']?.toString() ?? '';
        if (sid.isNotEmpty && sid != myId) neededUserIds.add(sid);
      }
    }

    if (neededUserIds.length < 8) {
      try {
        final fallback = await _supabase
            .from('profiles')
            .select('id')
            .neq('id', myId)
            .limit(12);
        for (final row in (fallback as List)) {
          final id = row['id']?.toString() ?? '';
          if (id.isNotEmpty && !safety.blockedUserIds.contains(id)) {
            neededUserIds.add(id);
          }
        }
      } catch (_) {}
    }

    final Map<String, Map<String, dynamic>> profilesMap = {};
    Map<String, UserPresenceInfo> presenceMap = {};
    if (neededUserIds.isNotEmpty) {
      final idList = neededUserIds.toList();
      final profFuture = _supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified')
          .inFilter('id', idList);
      final presFuture = UserPresenceService.instance.fetchPresenceMap(idList);
      final metaResults = await Future.wait<dynamic>([profFuture, presFuture]);

      for (final p in (metaResults[0] as List)) {
        final map = Map<String, dynamic>.from(p as Map);
        final id = map['id'].toString();
        profilesMap[id] = map;
        ChatCacheService.instance.cacheProfile(id, map);
      }
      presenceMap = metaResults[1] as Map<String, UserPresenceInfo>;
    }

    final List<ChatConversationItem> items = [];
    final Set<String> messagedPeerIds = {};

    for (final c in convRows) {
      final cid = c['id']?.toString() ?? '';
      if (cid.isEmpty) continue;
      final isGroup = c['is_group'] == true;
      final convMembers = membersByConv[cid] ?? const [];
      final convMsgs = visibleMsgsByConv[cid] ?? const [];

      if (!isGroup && convMsgs.isEmpty) {
        // Hide empty 1:1 conversations unless there are pending local outbox messages
        final localPending = await ChatCacheService.instance.getOutboxForThread(
          userId: myId,
          conversationId: cid,
        );
        if (localPending.isEmpty) continue;
      }

      String peerId = '';
      if (!isGroup) {
        final otherMember = convMembers.firstWhere(
          (m) => (m['user_id']?.toString() ?? '') != myId,
          orElse: () => const <String, dynamic>{},
        );
        peerId = otherMember['user_id']?.toString() ?? '';
        if (peerId.isEmpty && convMsgs.isNotEmpty) {
          final firstMsg = convMsgs.first;
          peerId = firstMsg['sender_id'] == myId
              ? (firstMsg['receiver_id']?.toString() ?? '')
              : (firstMsg['sender_id']?.toString() ?? '');
        }
        if (peerId.isEmpty || safety.blockedUserIds.contains(peerId)) continue;
        messagedPeerIds.add(peerId);
      }

      final peerProfile = peerId.isNotEmpty ? (profilesMap[peerId] ?? {}) : {};
      final peerPresence = peerId.isNotEmpty
          ? (presenceMap[peerId] ?? UserPresenceInfo.offline)
          : UserPresenceInfo.offline;

      final latestMsg = convMsgs.isNotEmpty ? convMsgs.first : null;
      final String lastMsgId = latestMsg?['id']?.toString() ?? '';
      final String? lastSenderId =
          latestMsg?['sender_id']?.toString() ?? c['last_sender_id']?.toString();
      final bool isLastMine = lastSenderId == myId;

      final myLastReadStr = myMembershipByConv[cid]?['last_read_at']?.toString();
      final myLastReadAt =
          myLastReadStr != null ? DateTime.tryParse(myLastReadStr) : null;

      final int unreadCount = convMsgs.where((m) {
        if (m['sender_id'] == myId) return false;
        if (isGroup && myLastReadAt != null) {
          final created = DateTime.tryParse(m['created_at']?.toString() ?? '');
          return created != null && created.isAfter(myLastReadAt);
        }
        return m['is_read'] != true;
      }).length;

      final fn = (peerProfile['first_name'] ?? '').toString().trim();
      final ln = (peerProfile['last_name'] ?? '').toString().trim();
      final peerFull = '$fn $ln'.trim();

      String lastSenderName = '';
      if (isGroup && lastSenderId != null && lastSenderId != myId) {
        final sp = profilesMap[lastSenderId];
        if (sp != null) {
          lastSenderName = (sp['username'] ?? '').toString();
        }
      }

      final String previewText = latestMsg != null
          ? (latestMsg['message_text']?.toString() ?? '').trim()
          : (c['last_message_text']?.toString() ?? '').trim();
      final String previewType = latestMsg != null
          ? (latestMsg['attachment_type']?.toString() ??
              latestMsg['message_type']?.toString() ??
              'text')
          : (c['last_message_type']?.toString() ?? 'text');

      items.add(
        ChatConversationItem(
          conversationId: cid,
          isGroup: isGroup,
          groupTitle: (c['title'] ?? '').toString(),
          groupAvatar: (c['avatar_url'] ?? '').toString(),
          memberCount: convMembers.length,
          peerId: peerId,
          peerUsername: (peerProfile['username'] ?? 'user').toString(),
          peerFullName: peerFull,
          peerAvatar: (peerProfile['avatar_url'] ?? '').toString(),
          isPeerVerified: peerProfile['is_verified'] == true,
          isPeerOnline: peerPresence.isOnline,
          peerNote: activeNotesByUser[peerId] ?? peerPresence.statusText,
          lastMessageId: lastMsgId,
          lastMessageText: previewText,
          lastMessageType: previewType,
          lastAttachmentUrl: latestMsg?['attachment_url']?.toString(),
          lastAttachmentType: latestMsg?['attachment_type']?.toString(),
          lastSenderId: lastSenderId,
          lastSenderName: lastSenderName,
          isLastMessageMine: isLastMine,
          isLastMessageDelivered: latestMsg?['is_delivered'] == true,
          isLastMessageRead: latestMsg?['is_read'] == true,
          lastMessageAt:
              DateTime.tryParse(
                latestMsg?['created_at']?.toString() ??
                    c['last_message_at']?.toString() ??
                    c['created_at']?.toString() ??
                    '',
              ) ??
              DateTime.now(),
          unreadCount: unreadCount,
          isPinned: pinnedIds.contains(cid),
          isMuted: mutedMap.containsKey(cid),
          mutedUntil: mutedMap[cid],
          isRequest: !isGroup && pendingReqConvIds.contains(cid),
        ),
      );
    }

    // Sort: Pinned conversations first, then newest message first
    items.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastMessageAt.compareTo(a.lastMessageAt);
    });

    // Active Friends + Notes tray (prioritize friends with active 24h notes or online)
    final List<Map<String, dynamic>> activeNotesTray = [];
    for (final uid in neededUserIds) {
      if (safety.blockedUserIds.contains(uid)) continue;
      final p = profilesMap[uid];
      if (p == null) continue;
      final pres = presenceMap[uid] ?? UserPresenceInfo.offline;
      final noteText = activeNotesByUser[uid];
      activeNotesTray.add({
        'id': uid,
        'username': p['username'] ?? 'user',
        'first_name': p['first_name'] ?? '',
        'avatar_url': p['avatar_url'] ?? '',
        'is_verified': p['is_verified'] == true,
        'is_online': pres.isOnline,
        'has_note': noteText != null && noteText.isNotEmpty,
        'note': (noteText != null && noteText.isNotEmpty)
            ? noteText
            : pres.statusText,
      });
    }
    activeNotesTray.sort((a, b) {
      final aNote = a['has_note'] == true ? 1 : 0;
      final bNote = b['has_note'] == true ? 1 : 0;
      if (aNote != bNote) return bNote.compareTo(aNote);
      final aOn = a['is_online'] == true ? 1 : 0;
      final bOn = b['is_online'] == true ? 1 : 0;
      return bOn.compareTo(aOn);
    });

    // Suggested friends not yet in active DMs
    final List<Map<String, dynamic>> suggested = [];
    for (final uid in neededUserIds) {
      if (!messagedPeerIds.contains(uid) &&
          !safety.blockedUserIds.contains(uid) &&
          profilesMap.containsKey(uid)) {
        suggested.add(profilesMap[uid]!);
      }
    }

    ChatCacheService.instance.setInbox(items);
    ChatCacheService.instance.setActiveFriends(activeNotesTray);

    return InboxSnapshot(
      conversations: items,
      activeFriendsNotes: activeNotesTray,
      suggestedFriends: suggested,
      myNote: myNote,
    );
  }

  // ===========================================================================
  // MESSAGES FETCH, SEND, OFFLINE QUEUE, EDIT, DELETE, FORWARD, SEARCH
  // ===========================================================================

  Future<List<DirectMessageModel>> fetchMessages({
    required String conversationId,
    int limit = 80,
    DateTime? before,
  }) async {
    final myId = currentUserId;
    if (myId == null || conversationId.isEmpty) return [];

    var query = _supabase
        .from('direct_messages')
        .select(
          'id, conversation_id, sender_id, receiver_id, message_text, message_type, attachment_url, attachment_type, file_name, file_size, mime_type, reply_to_message_id, forwarded_from_id, is_delivered, is_read, delivered_at, read_at, edited_at, deleted_at, deleted_for_user_ids, created_at',
        )
        .eq('conversation_id', conversationId);

    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }

    final res = await query
        .order('created_at', ascending: false)
        .limit(limit);

    final List<DirectMessageModel> serverMsgs = [];
    for (final row in (res as List)) {
      final msg = DirectMessageModel.fromMap(Map<String, dynamic>.from(row as Map));
      if (!msg.isDeletedForUser(myId)) {
        serverMsgs.add(msg);
      }
    }

    // Prepend pending / failed offline outbox messages for this thread
    if (before == null) {
      final queued = await ChatCacheService.instance.getOutboxForThread(
        userId: myId,
        conversationId: conversationId,
      );
      final serverIds = serverMsgs.map((m) => m.id).toSet();
      final merged = [
        ...queued.where((q) => !serverIds.contains(q.id)),
        ...serverMsgs,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      ChatCacheService.instance.setThread(conversationId, merged);
      return merged;
    }

    return serverMsgs;
  }

  Future<Map<String, List<MessageReactionSummary>>> fetchReactionsSummary(
    List<String> messageIds,
  ) async {
    final myId = currentUserId;
    if (myId == null || messageIds.isEmpty) return {};

    final cleanIds = messageIds
        .where((id) => id.isNotEmpty && !id.startsWith('temp_'))
        .toList();
    if (cleanIds.isEmpty) return {};

    try {
      final res = await _supabase
          .from('message_reactions')
          .select('message_id, user_id, emoji')
          .inFilter('message_id', cleanIds);

      final Map<String, Map<String, int>> counts = {};
      final Map<String, Set<String>> mine = {};

      for (final r in (res as List)) {
        final mId = r['message_id']?.toString() ?? '';
        final uId = r['user_id']?.toString() ?? '';
        final em = r['emoji']?.toString() ?? '';
        if (mId.isEmpty || em.isEmpty) continue;

        counts.putIfAbsent(mId, () => {});
        counts[mId]![em] = (counts[mId]![em] ?? 0) + 1;
        if (uId == myId) {
          mine.putIfAbsent(mId, () => <String>{}).add(em);
        }
      }

      final Map<String, List<MessageReactionSummary>> out = {};
      for (final entry in counts.entries) {
        final mId = entry.key;
        final mySet = mine[mId] ?? const <String>{};
        out[mId] = entry.value.entries
            .map(
              (e) => MessageReactionSummary(
                emoji: e.key,
                count: e.value,
                reactedByMe: mySet.contains(e.key),
              ),
            )
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));
      }
      return out;
    } catch (e) {
      debugPrint('[ChatService] fetchReactionsSummary notice: $e');
      return {};
    }
  }

  Future<void> toggleReaction({
    required String messageId,
    required String emoji,
    required bool currentlyReacted,
  }) async {
    final myId = currentUserId;
    if (myId == null || messageId.startsWith('temp_')) return;

    if (currentlyReacted) {
      await _supabase
          .from('message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', myId)
          .eq('emoji', emoji);
    } else {
      await _supabase.from('message_reactions').upsert(
        {
          'message_id': messageId,
          'user_id': myId,
          'emoji': emoji,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'message_id,user_id,emoji',
      );
    }
  }

  /// Sends a text or media message. If offline or server fails, persists cleanly
  /// in the SharedPreferences offline outbox so user can auto-flush or tap Retry.
  Future<DirectMessageModel> sendMessage({
    required String conversationId,
    required bool isGroup,
    String peerId = '',
    String messageText = '',
    String messageType = 'text',
    String? attachmentUrl,
    String? attachmentType,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? replyToMessageId,
    String? forwardedFromId,
    String? localFilePath,
    String? existingTempId,
    bool isPeerOnline = false,
  }) async {
    final myId = currentUserId;
    if (myId == null) {
      throw Exception('You must be signed in to send messages.');
    }

    final tempId =
        existingTempId ?? 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().toUtc();

    final pendingMsg = DirectMessageModel(
      id: tempId,
      conversationId: conversationId,
      senderId: myId,
      receiverId: isGroup ? '' : peerId,
      messageText: messageText,
      messageType: messageType,
      attachmentUrl: attachmentUrl,
      attachmentType: attachmentType,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      replyToMessageId: replyToMessageId,
      forwardedFromId: forwardedFromId,
      isDelivered: false,
      isRead: false,
      createdAt: now,
      localSendState: 'sending',
      localFilePath: localFilePath,
    );

    ChatCacheService.instance.addMessage(conversationId, pendingMsg);
    await ChatCacheService.instance.upsertOutboxMessage(myId, pendingMsg);

    try {
      String? finalUrl = attachmentUrl;

      // Upload local file on demand (also works smoothly during Retry!)
      if ((finalUrl == null || finalUrl.isEmpty) &&
          localFilePath != null &&
          localFilePath.isNotEmpty) {
        final localFile = File(localFilePath);
        if (!await localFile.exists()) {
          throw Exception('Original attachment file is no longer on device.');
        }
        final resolvedMime =
            mimeType ?? CloudflareStorageService.inferMimeType(localFilePath);
        final resolvedName =
            fileName ?? localFilePath.split('/').last;
        final subFolder = attachmentType == 'audio'
            ? 'voice/$resolvedName'
            : (attachmentType == 'video'
                ? 'video/$resolvedName'
                : (attachmentType == 'file'
                    ? 'files/$resolvedName'
                    : resolvedName));

        finalUrl = await CloudflareStorageService.instance.upload(
          bucket: 'direct_messages',
          path: 'zev/chat/$subFolder',
          file: localFile,
          contentType: resolvedMime,
        );
      }

      final Map<String, dynamic> payload = {
        'conversation_id': conversationId,
        'sender_id': myId,
        'receiver_id': isGroup ? null : peerId,
        'message_text': messageText,
        'message_type': messageType,
        'attachment_url': finalUrl,
        'attachment_type': attachmentType,
        'file_name': fileName,
        'file_size': fileSize,
        'mime_type': mimeType,
        'reply_to_message_id': replyToMessageId,
        'forwarded_from_id': forwardedFromId,
        'is_delivered': isGroup ? true : isPeerOnline,
        'is_read': false,
        'created_at': now.toIso8601String(),
      };
      if (!isGroup && isPeerOnline) {
        payload['delivered_at'] = now.toIso8601String();
      }

      final inserted = await _supabase
          .from('direct_messages')
          .insert(payload)
          .select()
          .single();

      final confirmed = DirectMessageModel.fromMap(inserted)
          .copyWith(localSendState: 'sent');

      await ChatCacheService.instance.removeOutboxMessage(myId, tempId);
      ChatCacheService.instance.replaceTempMessage(
        conversationId,
        tempId,
        confirmed,
      );

      // Dispatch Push via backend API without creating duplicate DB notifications
      // (trigger `tr_direct_message_inserted` handles `user_notifications` row).
      unawaited(_dispatchChatPush(
        conversationId: conversationId,
        isGroup: isGroup,
        peerId: peerId,
        message: confirmed,
      ));

      return confirmed;
    } catch (e) {
      debugPrint('[ChatService] sendMessage failed (queued for retry): $e');
      final failedMsg = pendingMsg.copyWith(
        localSendState: 'failed',
        localError: e.toString(),
      );
      await ChatCacheService.instance.upsertOutboxMessage(myId, failedMsg);
      ChatCacheService.instance.updateMessage(conversationId, failedMsg);
      return failedMsg;
    }
  }

  /// Sends a shared post or reel directly from `FeedShareSheet` to a 1:1 user.
  Future<bool> sendSharedContentToUser({
    required String peerId,
    required String contentId,
    required bool isReel,
    required String authorUsername,
    required String previewText,
    String? thumbnailUrl,
  }) async {
    try {
      final convId = await ensureDirectConversation(peerId);
      if (convId == null) return false;
      return await sendSharedContentToConversation(
        conversationId: convId,
        isGroup: false,
        peerId: peerId,
        contentId: contentId,
        isReel: isReel,
        authorUsername: authorUsername,
        previewText: previewText,
        thumbnailUrl: thumbnailUrl,
      );
    } catch (e) {
      debugPrint('[ChatService] sendSharedContentToUser notice: $e');
      return false;
    }
  }

  /// Sends a shared post or reel into an existing 1:1 or group conversation.
  Future<bool> sendSharedContentToConversation({
    required String conversationId,
    required bool isGroup,
    String peerId = '',
    required String contentId,
    required bool isReel,
    required String authorUsername,
    required String previewText,
    String? thumbnailUrl,
  }) async {
    try {
      final res = await sendMessage(
        conversationId: conversationId,
        isGroup: isGroup,
        peerId: isGroup ? '' : peerId,
        messageText: previewText.trim().isNotEmpty
            ? previewText.trim()
            : 'Shared a ${isReel ? 'reel' : 'post'} by @$authorUsername',
        messageType: isReel ? 'reel_share' : 'post_share',
        attachmentUrl: thumbnailUrl,
        attachmentType: isReel ? 'reel_share' : 'post_share',
        fileName: contentId,
        mimeType: authorUsername,
      );
      return !res.isFailed;
    } catch (e) {
      debugPrint('[ChatService] sendSharedContentToConversation notice: $e');
      return false;
    }
  }

  /// Retries all failed/pending outbox messages for a given conversation.
  Future<List<DirectMessageModel>> flushOutboxForThread({
    required String conversationId,
    required bool isGroup,
    String peerId = '',
  }) async {
    final myId = currentUserId;
    if (myId == null) return [];
    final queued = await ChatCacheService.instance.getOutboxForThread(
      userId: myId,
      conversationId: conversationId,
      peerId: peerId,
    );
    final List<DirectMessageModel> results = [];
    for (final msg in queued) {
      final retried = await sendMessage(
        conversationId: conversationId,
        isGroup: isGroup,
        peerId: peerId.isNotEmpty ? peerId : msg.receiverId,
        messageText: msg.messageText,
        messageType: msg.messageType,
        attachmentUrl: msg.attachmentUrl,
        attachmentType: msg.attachmentType,
        fileName: msg.fileName,
        fileSize: msg.fileSize,
        mimeType: msg.mimeType,
        replyToMessageId: msg.replyToMessageId,
        forwardedFromId: msg.forwardedFromId,
        localFilePath: msg.localFilePath,
        existingTempId: msg.id,
      );
      results.add(retried);
    }
    return results;
  }

  Future<DirectMessageModel> editMessage({
    required String conversationId,
    required String messageId,
    required String newText,
  }) async {
    final raw = await _supabase.rpc(
      'edit_direct_message',
      params: {'p_message_id': messageId, 'p_new_text': newText.trim()},
    );
    final updated = DirectMessageModel.fromMap(
      Map<String, dynamic>.from(raw as Map),
    );
    ChatCacheService.instance.updateMessage(conversationId, updated);
    return updated;
  }

  Future<void> deleteMessageForMe({
    required String conversationId,
    required String messageId,
  }) async {
    final myId = currentUserId;
    if (myId != null && messageId.startsWith('temp_')) {
      await ChatCacheService.instance.removeOutboxMessage(myId, messageId);
      ChatCacheService.instance.removeMessage(conversationId, messageId);
      return;
    }
    await _supabase.rpc(
      'delete_message_for_me',
      params: {'p_message_id': messageId},
    );
    ChatCacheService.instance.removeMessage(conversationId, messageId);
  }

  Future<void> deleteMessageForEveryone({
    required String conversationId,
    required DirectMessageModel message,
  }) async {
    final myId = currentUserId;
    if (myId != null && message.id.startsWith('temp_')) {
      await ChatCacheService.instance.removeOutboxMessage(myId, message.id);
      ChatCacheService.instance.removeMessage(conversationId, message.id);
      return;
    }
    final attachmentUrl = message.attachmentUrl;
    await _supabase.rpc(
      'delete_message_for_everyone',
      params: {'p_message_id': message.id},
    );
    if (attachmentUrl != null &&
        attachmentUrl.isNotEmpty &&
        message.messageType != 'post_share' &&
        message.messageType != 'reel_share') {
      unawaited(CloudflareStorageService.instance.deleteByUrl(attachmentUrl));
    }
    final tombstone = message.copyWith(
      deletedAt: DateTime.now().toUtc(),
      messageText: '',
      attachmentUrl: null,
    );
    ChatCacheService.instance.updateMessage(conversationId, tombstone);
  }

  Future<void> deleteConversationForMe(String conversationId) async {
    await _supabase.rpc(
      'delete_conversation_for_me',
      params: {'p_conversation_id': conversationId},
    );
  }

  Future<DirectMessageModel> forwardMessage({
    required DirectMessageModel source,
    required String targetConversationId,
    required bool isTargetGroup,
    String targetPeerId = '',
  }) async {
    return sendMessage(
      conversationId: targetConversationId,
      isGroup: isTargetGroup,
      peerId: targetPeerId,
      messageText: source.messageText,
      messageType: source.messageType,
      attachmentUrl: source.attachmentUrl,
      attachmentType: source.attachmentType,
      fileName: source.fileName,
      fileSize: source.fileSize,
      mimeType: source.mimeType,
      forwardedFromId: source.id,
    );
  }

  Future<void> markConversationRead({
    required String conversationId,
    String? peerId,
  }) async {
    final myId = currentUserId;
    if (myId == null) return;

    ChatCacheService.instance.markThreadRead(
      conversationId,
      currentUserId: myId,
    );

    try {
      await _supabase.rpc(
        'mark_conversation_read',
        params: {'p_conversation_id': conversationId},
      );
    } catch (e) {
      debugPrint('[ChatService] mark_conversation_read notice: $e');
      if (peerId != null && peerId.isNotEmpty) {
        try {
          await _supabase.rpc(
            'mark_messages_read',
            params: {'p_sender_id': peerId},
          );
        } catch (_) {}
      }
    }
  }

  // ===========================================================================
  // PIN, MUTE, REQUESTS, SEARCH & EPHEMERAL 24H NOTES
  // ===========================================================================

  Future<void> togglePinConversation(String conversationId, bool pin) async {
    final myId = currentUserId;
    if (myId == null) return;
    if (pin) {
      await _supabase.from('conversation_pins').upsert(
        {
          'conversation_id': conversationId,
          'user_id': myId,
        },
        onConflict: 'conversation_id,user_id',
      );
    } else {
      await _supabase
          .from('conversation_pins')
          .delete()
          .eq('conversation_id', conversationId)
          .eq('user_id', myId);
    }
  }

  Future<void> muteConversation(
    String conversationId, {
    Duration? duration,
  }) async {
    final myId = currentUserId;
    if (myId == null) return;
    final until = duration != null
        ? DateTime.now().toUtc().add(duration).toIso8601String()
        : null;
    await _supabase.from('conversation_mutes').upsert(
      {
        'conversation_id': conversationId,
        'user_id': myId,
        'muted_until': until,
      },
      onConflict: 'conversation_id,user_id',
    );
  }

  Future<void> unmuteConversation(String conversationId) async {
    final myId = currentUserId;
    if (myId == null) return;
    await _supabase
        .from('conversation_mutes')
        .delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', myId);
  }

  Future<void> respondMessageRequest({
    required String conversationId,
    required bool accept,
  }) async {
    await _supabase.rpc(
      'respond_message_request',
      params: {
        'p_conversation_id': conversationId,
        'p_action': accept ? 'accepted' : 'declined',
      },
    );
  }

  Future<List<DirectMessageModel>> searchInConversation({
    required String conversationId,
    required String query,
  }) async {
    final myId = currentUserId;
    final clean = query.trim();
    if (myId == null || clean.isEmpty) return [];

    final res = await _supabase
        .from('direct_messages')
        .select(
          'id, conversation_id, sender_id, receiver_id, message_text, message_type, attachment_url, attachment_type, file_name, file_size, mime_type, reply_to_message_id, forwarded_from_id, is_delivered, is_read, delivered_at, read_at, edited_at, deleted_at, deleted_for_user_ids, created_at',
        )
        .eq('conversation_id', conversationId)
        .isFilter('deleted_at', null)
        .or('message_text.ilike.%$clean%,file_name.ilike.%$clean%')
        .order('created_at', ascending: false)
        .limit(50);

    return (res as List)
        .map((r) => DirectMessageModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .where((m) => !m.isDeletedForUser(myId))
        .toList();
  }

  Future<List<MessageSearchHit>> searchAllMessages(String query) async {
    final myId = currentUserId;
    final clean = query.trim();
    if (myId == null || clean.isEmpty) return [];

    final inbox = ChatCacheService.instance.cachedInbox;
    final convIds = inbox
        .map((c) => c.conversationId)
        .where((id) => id.isNotEmpty)
        .toList();
    if (convIds.isEmpty) return [];

    final res = await _supabase
        .from('direct_messages')
        .select(
          'id, conversation_id, sender_id, receiver_id, message_text, message_type, attachment_url, attachment_type, file_name, file_size, mime_type, deleted_at, deleted_for_user_ids, created_at',
        )
        .inFilter('conversation_id', convIds)
        .isFilter('deleted_at', null)
        .or('message_text.ilike.%$clean%,file_name.ilike.%$clean%')
        .order('created_at', ascending: false)
        .limit(35);

    final convById = {for (final c in inbox) c.conversationId: c};
    final List<MessageSearchHit> hits = [];
    for (final row in (res as List)) {
      final msg = DirectMessageModel.fromMap(Map<String, dynamic>.from(row as Map));
      if (msg.isDeletedForUser(myId)) continue;
      final conv = convById[msg.conversationId];
      if (conv == null) continue;
      hits.add(
        MessageSearchHit(
          message: msg,
          conversationTitle: conv.displayTitle,
          peerId: conv.peerId,
          peerUsername: conv.peerUsername,
          peerAvatar: conv.displayAvatar,
          isGroup: conv.isGroup,
        ),
      );
    }
    return hits;
  }

  Future<void> saveUserNote(String content) async {
    final myId = currentUserId;
    final clean = content.trim();
    if (myId == null || clean.isEmpty) return;
    final now = DateTime.now().toUtc();
    await _supabase.from('user_notes').upsert(
      {
        'user_id': myId,
        'content': clean,
        'created_at': now.toIso8601String(),
        'expires_at': now.add(const Duration(hours: 24)).toIso8601String(),
      },
      onConflict: 'user_id',
    );
  }

  Future<void> deleteUserNote() async {
    final myId = currentUserId;
    if (myId == null) return;
    await _supabase.from('user_notes').delete().eq('user_id', myId);
  }

  // ===========================================================================
  // GROUP ADMIN & MEMBER MANAGEMENT
  // ===========================================================================

  Future<GroupConversationDetails?> fetchGroupDetails(
    String conversationId,
  ) async {
    if (conversationId.isEmpty) return null;

    final results = await Future.wait<dynamic>([
      _supabase
          .from('conversations')
          .select('id, title, avatar_url, created_by')
          .eq('id', conversationId)
          .maybeSingle(),
      _supabase
          .from('conversation_members')
          .select('user_id, role, joined_at')
          .eq('conversation_id', conversationId)
          .order('joined_at', ascending: true),
    ]);

    final conv = results[0] as Map<String, dynamic>?;
    final memberRows = List<Map<String, dynamic>>.from(results[1] as List);
    if (conv == null) return null;

    final userIds = memberRows
        .map((m) => m['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    final Map<String, Map<String, dynamic>> profilesMap = {};
    if (userIds.isNotEmpty) {
      final profs = await _supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified')
          .inFilter('id', userIds);
      for (final p in (profs as List)) {
        final m = Map<String, dynamic>.from(p as Map);
        profilesMap[m['id'].toString()] = m;
      }
    }

    final members = memberRows.map((m) {
      final uid = m['user_id']?.toString() ?? '';
      final p = profilesMap[uid] ?? {};
      final fn = (p['first_name'] ?? '').toString().trim();
      final ln = (p['last_name'] ?? '').toString().trim();
      return GroupMemberInfo(
        userId: uid,
        username: (p['username'] ?? 'user').toString(),
        fullName: '$fn $ln'.trim(),
        avatarUrl: (p['avatar_url'] ?? '').toString(),
        isVerified: p['is_verified'] == true,
        role: (m['role'] ?? 'member').toString(),
        joinedAt:
            DateTime.tryParse(m['joined_at']?.toString() ?? '') ?? DateTime.now(),
      );
    }).toList();

    return GroupConversationDetails(
      conversationId: conversationId,
      title: (conv['title'] ?? 'Group Chat').toString(),
      avatarUrl: (conv['avatar_url'] ?? '').toString(),
      createdBy: (conv['created_by'] ?? '').toString(),
      members: members,
    );
  }

  Future<void> updateGroupTitle(String conversationId, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    await _supabase
        .from('conversations')
        .update({'title': clean, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', conversationId);
  }

  Future<void> addGroupMembers(
    String conversationId,
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return;
    final rows = userIds
        .map(
          (uid) => {
            'conversation_id': conversationId,
            'user_id': uid,
            'role': 'member',
          },
        )
        .toList();
    await _supabase.from('conversation_members').upsert(
      rows,
      onConflict: 'conversation_id,user_id',
    );
  }

  Future<void> removeGroupMember(String conversationId, String userId) async {
    await _supabase
        .from('conversation_members')
        .delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
  }

  Future<void> setGroupMemberRole({
    required String conversationId,
    required String userId,
    required String role, // 'admin' | 'member'
  }) async {
    await _supabase
        .from('conversation_members')
        .update({'role': role})
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
  }

  Future<void> leaveGroup(String conversationId) async {
    final myId = currentUserId;
    if (myId == null) return;
    await _supabase
        .from('conversation_members')
        .delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', myId);
  }

  // ===========================================================================
  // PUSH DISPATCH HELPER (Via Server `/api/v1/push/send`)
  // ===========================================================================

  Future<void> _dispatchChatPush({
    required String conversationId,
    required bool isGroup,
    required String peerId,
    required DirectMessageModel message,
  }) async {
    final myId = currentUserId;
    if (myId == null) return;

    String bodyText;
    switch (message.effectiveType) {
      case 'audio':
        bodyText = '🎙️ Voice message';
        break;
      case 'image':
        bodyText = '📷 Sent a photo';
        break;
      case 'video':
        bodyText = '🎥 Sent a video';
        break;
      case 'file':
        bodyText = '📎 ${message.fileName ?? 'Sent a file'}';
        break;
      case 'post_share':
        bodyText = 'Shared a post with you';
        break;
      case 'reel_share':
        bodyText = 'Shared a reel with you';
        break;
      default:
        bodyText = message.messageText.isNotEmpty
            ? message.messageText
            : 'Sent you a message';
    }

    try {
      String senderName = 'New Message';
      final cachedMyProf = ChatCacheService.instance.getCachedProfile(myId);
      if (cachedMyProf != null) {
        final uname = (cachedMyProf['username'] ?? '').toString();
        if (uname.isNotEmpty) senderName = '@$uname';
      }

      if (!isGroup && peerId.isNotEmpty) {
        final res = await ApiClient.instance.post(
          '/api/v1/push/send',
          data: {
            'recipientUserId': peerId,
            'title': senderName,
            'body': bodyText,
            'notificationType': 'message',
            'deepLink': '/chat/$myId',
            'data': {
              'type': 'chat',
              'sender_id': myId,
              'conversation_id': conversationId,
            },
          },
        );
        if (res['ok'] == false) {
          debugPrint('[ChatService] push/send returned non-ok: ${res['error'] ?? res}');
        }
      } else if (isGroup) {
        final members = await _supabase
            .from('conversation_members')
            .select('user_id')
            .eq('conversation_id', conversationId)
            .neq('user_id', myId);

        for (final m in (members as List)) {
          final uid = m['user_id']?.toString() ?? '';
          if (uid.isEmpty) continue;
          unawaited(
            ApiClient.instance
                .post(
                  '/api/v1/push/send',
                  data: {
                    'recipientUserId': uid,
                    'title': senderName,
                    'body': bodyText,
                    'notificationType': 'message',
                    'deepLink': '/chat/conv:$conversationId',
                    'data': {
                      'type': 'chat',
                      'sender_id': myId,
                      'conversation_id': conversationId,
                    },
                  },
                )
                .then<void>((res) {
                  if (res['ok'] == false) {
                    debugPrint(
                      '[ChatService] group push/send returned non-ok: ${res['error'] ?? res}',
                    );
                  }
                })
                .catchError((Object e) {
                  debugPrint('[ChatService] group push/send notice: $e');
                }),
          );
        }
      }
    } catch (e) {
      debugPrint('[ChatService] _dispatchChatPush notice: $e');
    }
  }
}

