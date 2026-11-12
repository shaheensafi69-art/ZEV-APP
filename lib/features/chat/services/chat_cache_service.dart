import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_conversation_item.dart';
import '../models/direct_message_model.dart';

/// In-memory cache + SharedPreferences persistent offline outbox for ZEV Chat.
/// Guarantees 0ms conversation rendering, zero duplicate messages, and
/// durable offline message queuing with automatic/manual retry.
class ChatCacheService {
  ChatCacheService._();
  static final ChatCacheService instance = ChatCacheService._();

  static const int _maxCachedThreads = 40;
  static const int _maxMessagesPerThread = 160;

  List<ChatConversationItem> _cachedInbox = [];
  List<Map<String, dynamic>> _cachedActiveFriends = [];
  final Map<String, List<DirectMessageModel>> _threads = {};
  final Map<String, Map<String, dynamic>> _profileCache = {};
  final Map<String, String> _peerToConversationId = {};

  // Persistent failed / pending outgoing messages keyed by userId
  String? _loadedOutboxUserId;
  final List<DirectMessageModel> _outbox = [];

  List<ChatConversationItem> get cachedInbox => List.unmodifiable(_cachedInbox);
  List<Map<String, dynamic>> get cachedActiveFriends =>
      List.unmodifiable(_cachedActiveFriends);
  bool get hasCachedInbox => _cachedInbox.isNotEmpty;

  void linkPeerConversation(String peerId, String conversationId) {
    if (peerId.isEmpty || conversationId.isEmpty) return;
    _peerToConversationId[peerId] = conversationId;
  }

  String _resolveKey(String key) => _peerToConversationId[key] ?? key;

  List<DirectMessageModel> getThread(String threadKey) {
    final primary = _threads[threadKey];
    if (primary != null && primary.isNotEmpty) return primary;
    final linked = _peerToConversationId[threadKey];
    if (linked != null && _threads[linked] != null) return _threads[linked]!;
    return [];
  }

  bool hasThread(String threadKey) => getThread(threadKey).isNotEmpty;

  void setInbox(List<ChatConversationItem> items) {
    _cachedInbox = List.from(items);
    for (final c in items) {
      if (!c.isGroup && c.peerId.isNotEmpty && c.conversationId.isNotEmpty) {
        _peerToConversationId[c.peerId] = c.conversationId;
      }
    }
  }

  void setActiveFriends(List<Map<String, dynamic>> friends) {
    _cachedActiveFriends = List.from(friends);
  }

  void setThread(String threadKey, List<DirectMessageModel> messages) {
    final resolved = _resolveKey(threadKey);
    if (_threads.length >= _maxCachedThreads && !_threads.containsKey(resolved)) {
      _threads.remove(_threads.keys.first);
    }
    final deduped = <String, DirectMessageModel>{};
    for (final m in messages) {
      if (m.id.isNotEmpty) deduped[m.id] = m;
    }
    final sorted = deduped.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _threads[resolved] = sorted.take(_maxMessagesPerThread).toList();
  }

  void addMessage(String threadKey, DirectMessageModel msg) {
    final resolved = _resolveKey(threadKey);
    final list = _threads.putIfAbsent(resolved, () => []);
    final existingIdx = list.indexWhere((m) => m.id == msg.id);
    if (existingIdx != -1) {
      list[existingIdx] = msg;
    } else {
      list.insert(0, msg);
      if (list.length > _maxMessagesPerThread) {
        list.removeRange(_maxMessagesPerThread, list.length);
      }
    }
    _updateInboxWithNewMessage(resolved, msg);
  }

  void replaceTempMessage(
    String threadKey,
    String tempId,
    DirectMessageModel confirmedMsg,
  ) {
    final resolved = _resolveKey(threadKey);
    final list = _threads.putIfAbsent(resolved, () => []);
    list.removeWhere((m) => m.id == tempId || m.id == confirmedMsg.id);
    list.insert(0, confirmedMsg);
    _updateInboxWithNewMessage(resolved, confirmedMsg);
  }

  void updateMessage(String threadKey, DirectMessageModel msg) {
    final resolved = _resolveKey(threadKey);
    final list = _threads[resolved];
    if (list != null) {
      final idx = list.indexWhere((m) => m.id == msg.id);
      if (idx != -1) {
        list[idx] = msg;
      }
    }
    final inboxIdx = _cachedInbox.indexWhere(
      (c) => c.conversationId == resolved || c.peerId == threadKey,
    );
    if (inboxIdx != -1 && _cachedInbox[inboxIdx].lastMessageId == msg.id) {
      _cachedInbox[inboxIdx] = _cachedInbox[inboxIdx].copyWith(
        lastMessageText:
            msg.isDeletedForEveryone ? 'Message deleted' : msg.messageText,
        isLastMessageDelivered: msg.isDelivered,
        isLastMessageRead: msg.isRead,
      );
    }
  }

  void removeMessage(String threadKey, String messageId) {
    final resolved = _resolveKey(threadKey);
    _threads[resolved]?.removeWhere((m) => m.id == messageId);
  }

  void markThreadRead(String threadKey, {String? currentUserId}) {
    final resolved = _resolveKey(threadKey);
    final list = _threads[resolved];
    if (list != null) {
      for (int i = 0; i < list.length; i++) {
        final m = list[i];
        final isIncoming =
            currentUserId != null ? m.senderId != currentUserId : m.senderId == threadKey;
        if (isIncoming && !m.isRead) {
          list[i] = m.copyWith(isRead: true, isDelivered: true);
        }
      }
    }

    final inboxIdx = _cachedInbox.indexWhere(
      (c) => c.conversationId == resolved || c.peerId == threadKey,
    );
    if (inboxIdx != -1) {
      _cachedInbox[inboxIdx] = _cachedInbox[inboxIdx].copyWith(unreadCount: 0);
    }
  }

  void _updateInboxWithNewMessage(String resolvedKey, DirectMessageModel msg) {
    final idx = _cachedInbox.indexWhere(
      (c) => c.conversationId == resolvedKey || (!c.isGroup && c.peerId == resolvedKey),
    );
    if (idx != -1) {
      final existing = _cachedInbox[idx];
      final myId = Supabase.instance.client.auth.currentUser?.id;
      final isMine = myId != null
          ? msg.senderId == myId
          : (!existing.isGroup && msg.senderId != existing.peerId);
      _cachedInbox[idx] = existing.copyWith(
        lastMessageId: msg.id,
        lastMessageText: msg.messageText,
        lastMessageType: msg.effectiveType,
        lastAttachmentUrl: msg.attachmentUrl,
        lastAttachmentType: msg.attachmentType,
        lastSenderId: msg.senderId,
        isLastMessageMine: isMine,
        isLastMessageDelivered: msg.isDelivered,
        isLastMessageRead: msg.isRead,
        lastMessageAt: msg.createdAt,
        unreadCount: isMine ? existing.unreadCount : (existing.unreadCount + 1),
      );
      _sortInbox();
    }
  }

  void _sortInbox() {
    _cachedInbox.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastMessageAt.compareTo(a.lastMessageAt);
    });
  }

  void cacheProfile(String userId, Map<String, dynamic> profile) {
    _profileCache[userId] = profile;
  }

  Map<String, dynamic>? getCachedProfile(String userId) => _profileCache[userId];

  // ═══════════════════════════════════════════════════════════════════════════
  // PERSISTENT OFFLINE OUTBOX QUEUE (SharedPreferences)
  // ═══════════════════════════════════════════════════════════════════════════

  String _outboxKey(String userId) => 'zev_chat_outbox_$userId';

  Future<List<DirectMessageModel>> loadOutbox(String userId) async {
    if (userId.isEmpty) return [];
    if (_loadedOutboxUserId == userId) {
      return List.unmodifiable(_outbox);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_outboxKey(userId));
      _outbox.clear();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              _outbox.add(
                DirectMessageModel.fromMap(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      }
      _loadedOutboxUserId = userId;
    } catch (e) {
      debugPrint('[ChatCacheService] loadOutbox notice: $e');
    }
    return List.unmodifiable(_outbox);
  }

  Future<List<DirectMessageModel>> getOutboxForThread({
    required String userId,
    String? conversationId,
    String? peerId,
  }) async {
    final all = await loadOutbox(userId);
    return all.where((m) {
      if (conversationId != null &&
          conversationId.isNotEmpty &&
          m.conversationId == conversationId) {
        return true;
      }
      if (peerId != null && peerId.isNotEmpty && m.receiverId == peerId) {
        return true;
      }
      return false;
    }).toList();
  }

  Future<void> upsertOutboxMessage(
    String userId,
    DirectMessageModel msg,
  ) async {
    if (userId.isEmpty) return;
    await loadOutbox(userId);
    final idx = _outbox.indexWhere((m) => m.id == msg.id);
    if (idx != -1) {
      _outbox[idx] = msg;
    } else {
      _outbox.add(msg);
    }
    await _persistOutbox(userId);
  }

  Future<void> removeOutboxMessage(String userId, String messageId) async {
    if (userId.isEmpty) return;
    await loadOutbox(userId);
    _outbox.removeWhere((m) => m.id == messageId);
    await _persistOutbox(userId);
  }

  Future<void> _persistOutbox(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _outboxKey(userId),
        jsonEncode(_outbox.map((m) => m.toMap()).toList()),
      );
    } catch (e) {
      debugPrint('[ChatCacheService] _persistOutbox notice: $e');
    }
  }

  void clear() {
    _cachedInbox.clear();
    _cachedActiveFriends.clear();
    _threads.clear();
    _profileCache.clear();
    _peerToConversationId.clear();
    _outbox.clear();
    _loadedOutboxUserId = null;
  }
}
