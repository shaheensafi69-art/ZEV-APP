import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/widgets/mfa_challenge_sheet.dart';
import '../../features/main_navigation/screens/zev_main_layout.dart';
import '../theme/zev_theme.dart';
import '../widgets/zev_cached_image.dart';
import '../widgets/zev_text_field.dart';
import 'auth_helper.dart';
import 'mfa_service.dart';
import 'passkey_auth_service.dart';

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
/// and switch between them seamlessly. Because Supabase free plan holds one active
/// server session per client, account switching prompts for the password (with
/// OS Keychain / Google Autofill support) or Passkey/Biometrics to ensure a 100%
/// genuine, fully authenticated session without blank screens.
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

  /// Switches to an account by prompting for password / Passkey to establish a real Supabase session
  static Future<void> switchToAccount(
    BuildContext context,
    SavedAccount account,
  ) async {
    await promptLoginForAccount(context, account);
  }

  /// Opens the elegant Claymorphic password/passkey login modal for the target account
  static Future<bool> promptLoginForAccount(
    BuildContext context,
    SavedAccount account,
  ) async {
    HapticFeedback.lightImpact();
    return await AccountLoginSheet.show(context, account: account);
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
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: ZevColors.textMuted, size: 20),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (accounts.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              "No saved accounts yet.",
                              style: TextStyle(color: ZevColors.textMuted),
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
                                    promptLoginForAccount(context, acc);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text("You are currently using @${acc.username}"),
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
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

/// Flagship Claymorphic Account Login Prompt Sheet.
/// Displays account identity with password field supported by iOS Keychain & Google Autofill,
/// and instant 1-tap Passkey / Face ID / Touch ID biometric sign-in.
class AccountLoginSheet extends StatefulWidget {
  final SavedAccount account;

  const AccountLoginSheet({super.key, required this.account});

  static Future<bool> show(BuildContext context, {required SavedAccount account}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: ZevColors.deepNavy.withValues(alpha: 0.6),
      builder: (_) => AccountLoginSheet(account: account),
    );
    return result == true;
  }

  @override
  State<AccountLoginSheet> createState() => _AccountLoginSheetState();
}

class _AccountLoginSheetState extends State<AccountLoginSheet> {
  final TextEditingController _passwordCtrl = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _showPassword = false;
  String? _errorMsg;

  bool _isPasskeySupported = false;
  bool _isPasskeyEnrolled = false;

  @override
  void initState() {
    super.initState();
    _checkPasskey();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _passwordFocus.requestFocus();
    });
  }

  Future<void> _checkPasskey() async {
    try {
      final supported = await PasskeyAuthService.instance.isDeviceSupported();
      final enrolled = await PasskeyAuthService.instance.isPasskeyEnrolled();
      if (mounted) {
        setState(() {
          _isPasskeySupported = supported;
          _isPasskeyEnrolled = enrolled;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handlePasswordLogin() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      setState(() => _errorMsg = "Please enter your password.");
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final authResponse = await Supabase.instance.client.auth.signInWithPassword(
        email: widget.account.email,
        password: password,
      );

      final user = authResponse.user;
      if (user != null) {
        // Check Multi-Factor Authentication requirement
        if (MfaService.instance.isMfaRequired()) {
          final factors = await MfaService.instance.getEnrolledFactors();
          if (factors.isNotEmpty && mounted) {
            final verified = await MfaChallengeSheet.show(
              context,
              factorId: factors.first.id,
              accountEmail: widget.account.email,
            );
            if (!verified) {
              setState(() {
                _isLoading = false;
                _errorMsg = "Two-Factor Authentication cancelled.";
              });
              return;
            }
          }
        }

        // Allow iOS Keychain and Google Autofill to save / update password
        TextInput.finishAutofillContext(shouldSave: true);

        // Mark user logged in locally and sync FCM
        await AuthHelper.markUserLoggedIn(
          userId: user.id,
          role: widget.account.role,
        );

        // Update MultiAccountService with latest info
        await MultiAccountService.saveCurrentAccount(
          overrideUsername: widget.account.username,
          overrideFullName: widget.account.fullName,
          overrideAvatar: widget.account.avatarUrl,
          overrideIsVerified: widget.account.isVerified,
        );

        if (!mounted) return;

        Navigator.pop(context, true);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Switched to @${widget.account.username}",
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
      }
    } on AuthException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = e.message;
        });
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _handlePasskeyLogin() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final res = await PasskeyAuthService.instance.signInWithPasskey();
      if (!res.success) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMsg = res.errorMessage;
          });
        }
        return;
      }

      // Check MFA if required
      if (MfaService.instance.isMfaRequired()) {
        final factors = await MfaService.instance.getEnrolledFactors();
        if (factors.isNotEmpty && mounted) {
          final verified = await MfaChallengeSheet.show(
            context,
            factorId: factors.first.id,
            accountEmail: widget.account.email,
          );
          if (!verified) {
            setState(() {
              _isLoading = false;
              _errorMsg = "Two-Factor Authentication cancelled.";
            });
            return;
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ZevMainLayout()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Color(0x33080D1A),
              blurRadius: 36,
              offset: Offset(0, -10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Header with Account Avatar
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ZevColors.primaryBlue, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(36),
                      child: widget.account.avatarUrl.isNotEmpty
                          ? ZevCachedImage.avatar(
                              imageUrl: widget.account.avatarUrl,
                              size: 72,
                            )
                          : Container(
                              color: ZevColors.softSurface,
                              child: Center(
                                child: Text(
                                  widget.account.username.isNotEmpty
                                      ? widget.account.username[0].toUpperCase()
                                      : 'Z',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: ZevColors.deepNavy,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Username & Verified Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "@${widget.account.username}",
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.deepNavy,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (widget.account.isVerified) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_rounded,
                          color: ZevColors.primaryBlue,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.account.fullName.isNotEmpty
                        ? widget.account.fullName
                        : widget.account.email,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Error Message
                  if (_errorMsg != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFDC2626)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMsg!,
                              style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Password Field with OS Autofill & Keychain
                  ZevTextField(
                    label: "Password",
                    hint: "Enter password for @${widget.account.username}",
                    controller: _passwordCtrl,
                    focusNode: _passwordFocus,
                    prefixIcon: Icons.lock_outline_rounded,
                    isPassword: true,
                    isObscured: !_showPassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _handlePasswordLogin(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                        color: ZevColors.textMuted,
                      ),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Forgot Password Shortcut
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ForgotPasswordScreen(
                              initialEmail: widget.account.email,
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        "Forgot password?",
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ZevColors.secondaryBlue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 1-Tap Log In Button
                  Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00D4FF), Color(0xFF0084FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handlePasswordLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(ZevColors.deepNavy),
                              ),
                            )
                          : Text(
                              "Log In as @${widget.account.username}",
                              style: const TextStyle(
                                color: ZevColors.deepNavy,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                    ),
                  ),

                  // Optional Passkey / Biometrics Button
                  if (_isPasskeySupported && _isPasskeyEnrolled) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _handlePasskeyLogin,
                      icon: const Icon(Icons.fingerprint_rounded, size: 20),
                      label: const Text("Sign In with Passkey / Face ID"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ZevColors.deepNavy,
                        side: BorderSide(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Cancel
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(
                        color: ZevColors.textMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
