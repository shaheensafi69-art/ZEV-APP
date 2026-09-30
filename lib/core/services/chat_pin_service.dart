import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PinDuration { hours24, days7, days30 }

extension PinDurationExt on PinDuration {
  String get label {
    switch (this) {
      case PinDuration.hours24:
        return "24 Hours (۲۴ ساعت)";
      case PinDuration.days7:
        return "7 Days (۷ روز)";
      case PinDuration.days30:
        return "30 Days (۳۰ روز)";
    }
  }

  String get code {
    switch (this) {
      case PinDuration.hours24:
        return "24h";
      case PinDuration.days7:
        return "7d";
      case PinDuration.days30:
        return "30d";
    }
  }

  Duration get duration {
    switch (this) {
      case PinDuration.hours24:
        return const Duration(hours: 24);
      case PinDuration.days7:
        return const Duration(days: 7);
      case PinDuration.days30:
        return const Duration(days: 30);
    }
  }
}

class PinnedItem {
  final String id;
  final String peerId;
  final String? messageId;
  final String? messageText;
  final String durationCode;
  final DateTime expiresAt;
  final DateTime createdAt;

  PinnedItem({
    required this.id,
    required this.peerId,
    this.messageId,
    this.messageText,
    required this.durationCode,
    required this.expiresAt,
    required this.createdAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'peer_id': peerId,
    'message_id': messageId,
    'message_text': messageText,
    'duration_code': durationCode,
    'expires_at': expiresAt.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  factory PinnedItem.fromJson(Map<String, dynamic> json) => PinnedItem(
    id: json['id'] ?? '',
    peerId: json['peer_id'] ?? '',
    messageId: json['message_id'],
    messageText: json['message_text'],
    durationCode: json['duration_code'] ?? '24h',
    expiresAt:
        DateTime.tryParse(json['expires_at'] ?? '') ??
        DateTime.now().add(const Duration(hours: 24)),
    createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
  );
}

class ChatPinService {
  static final ChatPinService _instance = ChatPinService._internal();
  factory ChatPinService() => _instance;
  ChatPinService._internal();

  static ChatPinService get instance => _instance;

  final supabase = Supabase.instance.client;
  static const String _keyPinnedThreads = 'zev_pinned_threads_v1';
  static const String _keyPinnedMessages = 'zev_pinned_messages_v1';

  final Map<String, PinnedItem> _pinnedThreads = {}; // key: peerId
  final Map<String, PinnedItem> _pinnedMessages =
      {}; // key: messageId or peerId:messageId

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load local pinned threads
      final threadsRaw = prefs.getString(_keyPinnedThreads);
      if (threadsRaw != null) {
        final decoded = jsonDecode(threadsRaw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          final item = PinnedItem.fromJson(Map<String, dynamic>.from(v));
          if (!item.isExpired) {
            _pinnedThreads[k] = item;
          }
        });
      }

      // Load local pinned messages
      final messagesRaw = prefs.getString(_keyPinnedMessages);
      if (messagesRaw != null) {
        final decoded = jsonDecode(messagesRaw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          final item = PinnedItem.fromJson(Map<String, dynamic>.from(v));
          if (!item.isExpired) {
            _pinnedMessages[k] = item;
          }
        });
      }

      // Sync with Supabase if online
      final user = supabase.auth.currentUser;
      if (user != null) {
        try {
          final res = await supabase
              .from('chat_pins')
              .select('*')
              .eq('user_id', user.id)
              .gt('expires_at', DateTime.now().toIso8601String());
          for (var row in (res as List)) {
            final pinType = row['pin_type']?.toString() ?? 'thread';
            final peerId = row['peer_id']?.toString() ?? '';
            final msgId = row['message_id']?.toString();
            final item = PinnedItem(
              id: row['id']?.toString() ?? '',
              peerId: peerId,
              messageId: msgId,
              durationCode: row['duration']?.toString() ?? '24h',
              expiresAt: DateTime.parse(row['expires_at']),
              createdAt: DateTime.parse(row['created_at']),
            );

            if (pinType == 'thread') {
              _pinnedThreads[peerId] = item;
            } else if (msgId != null) {
              _pinnedMessages[msgId] = item;
            }
          }
          await _saveLocally();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("Error initializing ChatPinService: $e");
    }
  }

  Future<void> _saveLocally() async {
    final prefs = await SharedPreferences.getInstance();
    // Clean expired
    _pinnedThreads.removeWhere((_, item) => item.isExpired);
    _pinnedMessages.removeWhere((_, item) => item.isExpired);

    final threadsMap = _pinnedThreads.map((k, v) => MapEntry(k, v.toJson()));
    final messagesMap = _pinnedMessages.map((k, v) => MapEntry(k, v.toJson()));

    await prefs.setString(_keyPinnedThreads, jsonEncode(threadsMap));
    await prefs.setString(_keyPinnedMessages, jsonEncode(messagesMap));
  }

  // Check if thread is pinned
  bool isThreadPinned(String peerId) {
    final item = _pinnedThreads[peerId];
    if (item == null) return false;
    if (item.isExpired) {
      _pinnedThreads.remove(peerId);
      return false;
    }
    return true;
  }

  PinnedItem? getThreadPin(String peerId) {
    final item = _pinnedThreads[peerId];
    if (item != null && !item.isExpired) return item;
    return null;
  }

  // Pin a thread in chat list
  Future<void> pinThread({
    required String peerId,
    required PinDuration duration,
  }) async {
    final expiresAt = DateTime.now().add(duration.duration);
    final item = PinnedItem(
      id: "pin-${DateTime.now().millisecondsSinceEpoch}",
      peerId: peerId,
      durationCode: duration.code,
      expiresAt: expiresAt,
      createdAt: DateTime.now(),
    );

    _pinnedThreads[peerId] = item;
    await _saveLocally();

    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        await supabase.from('chat_pins').upsert({
          'user_id': user.id,
          'peer_id': peerId,
          'pin_type': 'thread',
          'duration': duration.code,
          'expires_at': expiresAt.toIso8601String(),
        });
      } catch (e) {
        debugPrint("Remote pinThread error: $e");
      }
    }
  }

  // Unpin a thread
  Future<void> unpinThread(String peerId) async {
    _pinnedThreads.remove(peerId);
    await _saveLocally();

    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        await supabase
            .from('chat_pins')
            .delete()
            .eq('user_id', user.id)
            .eq('peer_id', peerId)
            .eq('pin_type', 'thread');
      } catch (_) {}
    }
  }

  // Check if message is pinned
  bool isMessagePinned(String messageId) {
    final item = _pinnedMessages[messageId];
    if (item == null) return false;
    if (item.isExpired) {
      _pinnedMessages.remove(messageId);
      return false;
    }
    return true;
  }

  PinnedItem? getPinnedMessageForPeer(String peerId) {
    for (var item in _pinnedMessages.values) {
      if (item.peerId == peerId && !item.isExpired) {
        return item;
      }
    }
    return null;
  }

  // Pin a message in conversation
  Future<void> pinMessage({
    required String peerId,
    required String messageId,
    required String messageText,
    required PinDuration duration,
  }) async {
    final expiresAt = DateTime.now().add(duration.duration);
    final item = PinnedItem(
      id: "pin-msg-${DateTime.now().millisecondsSinceEpoch}",
      peerId: peerId,
      messageId: messageId,
      messageText: messageText,
      durationCode: duration.code,
      expiresAt: expiresAt,
      createdAt: DateTime.now(),
    );

    _pinnedMessages[messageId] = item;
    await _saveLocally();

    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        await supabase.from('chat_pins').insert({
          'user_id': user.id,
          'peer_id': peerId,
          'message_id': messageId,
          'pin_type': 'message',
          'duration': duration.code,
          'expires_at': expiresAt.toIso8601String(),
        });
      } catch (e) {
        debugPrint("Remote pinMessage error: $e");
      }
    }
  }

  // Unpin a message
  Future<void> unpinMessage(String messageId) async {
    _pinnedMessages.remove(messageId);
    await _saveLocally();

    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        await supabase
            .from('chat_pins')
            .delete()
            .eq('user_id', user.id)
            .eq('message_id', messageId);
      } catch (_) {}
    }
  }
}
