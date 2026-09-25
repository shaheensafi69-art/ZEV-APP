import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SavedAccount {
  final String id;
  final String email;
  final String name;
  final String avatarUrl;
  final String? refreshToken;

  SavedAccount({
    required this.id,
    required this.email,
    required this.name,
    required this.avatarUrl,
    this.refreshToken,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'avatarUrl': avatarUrl,
        'refreshToken': refreshToken,
      };

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
        id: json['id'] ?? '',
        email: json['email'] ?? '',
        name: json['name'] ?? '',
        avatarUrl: json['avatarUrl'] ?? '',
        refreshToken: json['refreshToken'],
      );
}

class MultiAccountService {
  MultiAccountService._internal();
  static final MultiAccountService instance = MultiAccountService._internal();

  static const String _accountsKey = 'zev_multi_saved_accounts';

  Future<List<SavedAccount>> getSavedAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_accountsKey);
      if (str == null || str.isEmpty) return [];
      final List list = jsonDecode(str);
      return list.map((e) => SavedAccount.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error getting saved accounts: $e');
      return [];
    }
  }

  Future<void> saveCurrentAccount({
    required String name,
    required String avatarUrl,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final session = supabase.auth.currentSession;
      final rToken = session?.refreshToken;

      final accounts = await getSavedAccounts();
      final existingIndex = accounts.indexWhere((a) => a.id == user.id);

      final current = SavedAccount(
        id: user.id,
        email: user.email ?? '',
        name: name.isNotEmpty ? name : (user.email?.split('@').first ?? 'ZEV User'),
        avatarUrl: avatarUrl,
        refreshToken: rToken,
      );

      if (existingIndex >= 0) {
        accounts[existingIndex] = current;
      } else {
        accounts.add(current);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _accountsKey,
        jsonEncode(accounts.map((a) => a.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Error saving account: $e');
    }
  }

  Future<bool> switchAccount(SavedAccount target) async {
    try {
      final supabase = Supabase.instance.client;
      if (target.refreshToken != null && target.refreshToken!.isNotEmpty) {
        await supabase.auth.setSession(target.refreshToken!);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error switching account: $e');
      return false;
    }
  }

  Future<void> removeAccount(String accountId) async {
    try {
      final accounts = await getSavedAccounts();
      accounts.removeWhere((a) => a.id == accountId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _accountsKey,
        jsonEncode(accounts.map((a) => a.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Error removing account: $e');
    }
  }
}
