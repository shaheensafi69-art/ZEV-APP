import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatBlockReportService {
  static final ChatBlockReportService _instance =
      ChatBlockReportService._internal();
  factory ChatBlockReportService() => _instance;
  ChatBlockReportService._internal();

  static ChatBlockReportService get instance => _instance;

  final supabase = Supabase.instance.client;
  static const String _keyBlockedUsers = 'zev_blocked_users_list';

  final Set<String> _blockedUserIds = {};

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyBlockedUsers) ?? [];
      _blockedUserIds.addAll(list);

      final user = supabase.auth.currentUser;
      if (user != null) {
        try {
          final res = await supabase
              .from('user_blocks')
              .select('blocked_id')
              .eq('blocker_id', user.id);
          for (var item in (res as List)) {
            final id = item['blocked_id']?.toString();
            if (id != null && id.isNotEmpty) {
              _blockedUserIds.add(id);
            }
          }
          await prefs.setStringList(_keyBlockedUsers, _blockedUserIds.toList());
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("Error initializing ChatBlockReportService: $e");
    }
  }

  bool isUserBlocked(String userId) {
    return _blockedUserIds.contains(userId);
  }

  bool isBlocked(String userId) => isUserBlocked(userId);

  Future<bool> toggleBlock(
    String userId, {
    String? peerName,
    String? reason,
  }) async {
    if (isBlocked(userId)) {
      return await unblockUser(userId);
    } else {
      return await blockUser(userId, reason: reason);
    }
  }

  Future<bool> blockUser(String userId, {String? reason}) async {
    try {
      _blockedUserIds.add(userId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyBlockedUsers, _blockedUserIds.toList());

      final user = supabase.auth.currentUser;
      if (user != null) {
        try {
          await supabase.from('user_blocks').upsert({
            'blocker_id': user.id,
            'blocked_id': userId,
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          debugPrint("Remote blockUser error (using local cache): $e");
        }
      }
      return true;
    } catch (e) {
      debugPrint("Block user error: $e");
      return false;
    }
  }

  Future<bool> unblockUser(String userId) async {
    try {
      _blockedUserIds.remove(userId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyBlockedUsers, _blockedUserIds.toList());

      final user = supabase.auth.currentUser;
      if (user != null) {
        try {
          await supabase
              .from('user_blocks')
              .delete()
              .eq('blocker_id', user.id)
              .eq('blocked_id', userId);
        } catch (e) {
          debugPrint("Remote unblockUser error: $e");
        }
      }
      return true;
    } catch (e) {
      debugPrint("Unblock user error: $e");
      return false;
    }
  }

  Future<bool> reportUser({
    required String reportedUserId,
    required String reason,
    String? details,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        try {
          await supabase.from('user_reports').insert({
            'reporter_id': user.id,
            'reported_user_id': reportedUserId,
            'reason': reason,
            'details': details ?? '',
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          debugPrint("Remote reportUser error (logging locally): $e");
        }
      }
      return true;
    } catch (e) {
      debugPrint("Report user error: $e");
      return false;
    }
  }
}
