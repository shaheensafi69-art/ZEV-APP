import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/login_screen.dart';
import '../../features/main_navigation/screens/zev_main_layout.dart';
import '../theme/zev_theme.dart';
import '../widgets/zev_cached_image.dart';
import 'auth_helper.dart';

/// Represents a saved user account on the local device (Instagram-style).
class SavedAccount {
  final String userId;
  final String username;
  final String fullName;
  final String email;
  final String avatarUrl;
  final String role;
  final bool isVerified;
  final DateTime lastActive;

  const SavedAccount({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.email,
    required this.avatarUrl,
    this.role = 'student',
    this.isVerified = false,
    required this.lastActive,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'username': username,
    'fullName': fullName,
    'email': email,
    'avatarUrl': avatarUrl,
    'role': role,
    'isVerified': isVerified,
    'lastActive': lastActive.toIso8601String(),
  };

  factory SavedAccount.fromJson(Map<String, dynamic> json) {
    return SavedAccount(
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      role: json['role']?.toString() ?? 'student',
      isVerified: json['isVerified'] == true,
      lastActive: json['lastActive'] != null
          ? DateTime.tryParse(json['lastActive'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  SavedAccount copyWith({
    String? userId,
    String? username,
    String? fullName,
    String? email,
    String? avatarUrl,
    String? role,
    bool? isVerified,
    DateTime? lastActive,
  }) {
    return SavedAccount(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      isVerified: isVerified ?? this.isVerified,
      lastActive: lastActive ?? this.lastActive,
    );
  }
}

/// Central Multi-Account Manager for ZEV.
/// Enables users to create and manage 2, 3, or more accounts on the same device,
/// and switch between them instantly just like Instagram.
class MultiAccountService {
  MultiAccountService._();

  static const String _keyAccounts = 'zev_saved_accounts_v2';
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Loads all accounts saved on this device
  static Future<List<SavedAccount>> getSavedAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyAccounts);
      if (raw == null || raw.isEmpty) return [];

      final List<dynamic> decoded = jsonDecode(raw);
      final list = decoded.map((e) => SavedAccount.fromJson(e)).toList();
      list.sort((a, b) => b.lastActive.compareTo(a.lastActive));
      return list;
    } catch (e) {
      debugPrint("Error reading saved accounts: $e");
      return [];
    }
  }

  /// Saves or updates the currently authenticated user in the local accounts list
  static Future<void> saveCurrentAccount({
    String? overrideUsername,
    String? overrideFullName,
    String? overrideAvatar,
    bool? overrideIsVerified,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      String username = overrideUsername ?? '';
      String fullName = overrideFullName ?? '';
      String avatarUrl = overrideAvatar ?? '';
      String role = 'student';
      bool isVerified = overrideIsVerified ?? false;

      // Fetch latest profile info if not provided
      if (username.isEmpty || fullName.isEmpty) {
        final res = await _supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (res != null) {
          username = res['username']?.toString() ?? '';
          final first = res['first_name']?.toString() ?? '';
          final last = res['last_name']?.toString() ?? '';
          fullName = '$first $last'.trim();
          if (fullName.isEmpty) fullName = username;
          avatarUrl = res['avatar_url']?.toString() ?? '';
          role = res['role']?.toString() ?? 'student';
          if (overrideIsVerified == null) {
            isVerified = res['is_verified'] == true;
          }
        }
      }

      if (username.isEmpty) {
        username = user.email?.split('@').first ?? 'user';
      }

      final account = SavedAccount(
        userId: user.id,
        username: username,
        fullName: fullName.isNotEmpty ? fullName : username,
        email: user.email ?? '',
        avatarUrl: avatarUrl,
        role: role,
        isVerified: isVerified,
        lastActive: DateTime.now(),
      );

      final accounts = await getSavedAccounts();
      final existingIndex = accounts.indexWhere((a) => a.userId == user.id);

      if (existingIndex >= 0) {
        accounts[existingIndex] = account;
      } else {
        accounts.add(account);
      }

      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(accounts.map((a) => a.toJson()).toList());
      await prefs.setString(_keyAccounts, encoded);
    } catch (e) {
      debugPrint("Error saving current account: $e");
    }
  }

  /// Removes an account from saved accounts
  static Future<void> removeAccount(String userId) async {
    try {
      final accounts = await getSavedAccounts();
      accounts.removeWhere((a) => a.userId == userId);

      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(accounts.map((a) => a.toJson()).toList());
      await prefs.setString(_keyAccounts, encoded);
    } catch (e) {
      debugPrint("Error removing account: $e");
    }
  }

  /// Switches active account locally and navigates into ZEV Main Layout
  static Future<void> switchToAccount(
    BuildContext context,
    SavedAccount account,
  ) async {
    HapticFeedback.mediumImpact();

    try {
      // 1. Mark as logged in locally
      await AuthHelper.markUserLoggedIn(
        userId: account.userId,
        role: account.role,
      );

      // 2. Update last active timestamp
      final accounts = await getSavedAccounts();
      final idx = accounts.indexWhere((a) => a.userId == account.userId);
      if (idx >= 0) {
        accounts[idx] = accounts[idx].copyWith(lastActive: DateTime.now());
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _keyAccounts,
          jsonEncode(accounts.map((a) => a.toJson()).toList()),
        );
      }

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Switched to @${account.username}",
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ZevColors.deepNavy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ZevMainLayout()),
        (route) => false,
      );
    } catch (e) {
      debugPrint("Switch account error: $e");
    }
  }

  /// Displays the luxury Instagram-style Multi-Account Switcher Bottom Sheet
  static void showAccountSwitcherSheet(BuildContext context) async {
    HapticFeedback.lightImpact();
    final accounts = await getSavedAccounts();
    final currentUserId = _supabase.auth.currentUser?.id;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final screenHeight = MediaQuery.of(sheetContext).size.height;
        return Container(
          constraints: BoxConstraints(
            maxHeight: screenHeight * 0.85,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.14),
                blurRadius: 32,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag Handle
                Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 18),

                // Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Switch Accounts",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ZevColors.softSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${accounts.length} ${accounts.length == 1 ? 'account' : 'accounts'}",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ZevColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Scrollable Content
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Accounts List
                        if (accounts.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              "No additional accounts saved yet.",
                              style: TextStyle(
                                fontSize: 13.5,
                                color: ZevColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: accounts.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final acc = accounts[index];
                              final isCurrent = acc.userId == currentUserId;

                              return GestureDetector(
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  if (!isCurrent) {
                                    switchToAccount(context, acc);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? const Color(0xFFF0FDF4)
                                        : ZevColors.softSurface,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: isCurrent
                                          ? const Color(0xFF86EFAC)
                                          : const Color(0xFFE2E8F0),
                                      width: isCurrent ? 1.6 : 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Avatar
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isCurrent
                                                ? const Color(0xFF22C55E)
                                                : Colors.white,
                                            width: 2.0,
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(24),
                                          child: acc.avatarUrl.isNotEmpty
                                              ? ZevCachedImage.avatar(
                                                  imageUrl: acc.avatarUrl,
                                                  size: 48,
                                                )
                                              : Container(
                                                  color: ZevColors.primaryBlue.withValues(alpha: 0.18),
                                                  child: Center(
                                                    child: Text(
                                                      acc.username.isNotEmpty
                                                          ? acc.username[0].toUpperCase()
                                                          : 'U',
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        fontWeight: FontWeight.w800,
                                                        color: ZevColors.deepNavy,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),

                                      // Details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    "@${acc.username}",
                                                    style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w800,
                                                      color: ZevColors.deepNavy,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (acc.isVerified) ...[
                                                  const SizedBox(width: 5),
                                                  const Icon(
                                                    Icons.verified_rounded,
                                                    color: ZevColors.primaryBlue,
                                                    size: 15,
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              acc.fullName.isNotEmpty
                                                  ? acc.fullName
                                                  : acc.email,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w500,
                                                color: ZevColors.textSecondary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Active Checkmark or Switch Action
                                      if (isCurrent)
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF22C55E),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check_rounded,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        )
                                      else
                                        IconButton(
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            color: ZevColors.textMuted,
                                            size: 18,
                                          ),
                                          onPressed: () async {
                                            await removeAccount(acc.userId);
                                            if (sheetContext.mounted) {
                                              Navigator.pop(sheetContext);
                                            }
                                            if (context.mounted) {
                                              showAccountSwitcherSheet(context);
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 16),

                        // Add Another Account Button
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const LoginScreen(isAddingAccount: true)),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: ZevColors.softSurface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFCBD5E1),
                                width: 1.2,
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_rounded, color: ZevColors.deepNavy, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  "Add Another ZEV Account",
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: ZevColors.deepNavy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
