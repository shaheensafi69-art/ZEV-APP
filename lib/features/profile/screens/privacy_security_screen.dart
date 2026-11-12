import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/auth_helper.dart';
import '../../../core/services/mfa_service.dart';
import '../../../core/services/passkey_auth_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/services/user_presence_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../widgets/appeal_restriction_sheet.dart';
import 'mfa_settings_screen.dart';

/// Flagship Light Clearmorphic Account Privacy & Security Hub for ZEV.
/// Backed by Supabase `profiles`, `user_privacy_settings`, `user_blocks`,
/// `user_mutes`, `user_sessions`, and `/api/v1/account/*` endpoints.
class PrivacySecurityScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  final ValueChanged<Map<String, dynamic>>? onProfileUpdated;

  const PrivacySecurityScreen({
    super.key,
    required this.profile,
    this.onProfileUpdated,
  });

  static Future<void> open(
    BuildContext context, {
    required Map<String, dynamic> profile,
    ValueChanged<Map<String, dynamic>>? onProfileUpdated,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivacySecurityScreen(
          profile: profile,
          onProfileUpdated: onProfileUpdated,
        ),
      ),
    );
  }

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  final supabase = Supabase.instance.client;

  late bool _isPrivate;
  bool _showActivityStatus = true;
  String _allowMessagesFrom = 'everyone';
  String _allowMentionsFrom = 'everyone';
  String _allowTagsFrom = 'everyone';
  String _allowStoryRepliesFrom = 'everyone';

  bool _isSavingPrivacy = false;
  bool _is2faActive = false;
  int _blockedUsersCount = 0;
  List<Map<String, dynamic>> _blockedUsersList = [];
  int _mutedUsersCount = 0;
  List<Map<String, dynamic>> _mutedUsersList = [];

  @override
  void initState() {
    super.initState();
    _isPrivate = widget.profile['is_private'] == true;
    _loadPrivacySettings();
    _check2faStatus();
    _loadBlockedUsers();
    _loadMutedUsers();
  }

  Future<void> _loadPrivacySettings() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final row = await supabase
          .from('user_privacy_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row != null && mounted) {
        setState(() {
          if (row['is_private_account'] != null) {
            _isPrivate = row['is_private_account'] == true;
          }
          _showActivityStatus = row['hide_online_status'] != true;
          _allowMessagesFrom =
              _normalizeAudience(row['allow_messages_from']);
          _allowMentionsFrom =
              _normalizeAudience(row['allow_mentions_from']);
          _allowTagsFrom = _normalizeAudience(row['allow_tags_from']);
          _allowStoryRepliesFrom =
              _normalizeAudience(row['allow_story_replies_from']);
        });
      }
    } catch (e) {
      debugPrint('Load user_privacy_settings notice: $e');
    }
  }

  String _normalizeAudience(dynamic val) {
    final s = (val ?? '').toString().trim().toLowerCase();
    if (s == 'followers' || s == 'nobody') return s;
    return 'everyone';
  }

  String _audienceLabel(String val) {
    switch (val) {
      case 'followers':
        return 'Followers';
      case 'nobody':
        return 'Nobody';
      default:
        return 'Everyone';
    }
  }

  Future<void> _persistPrivacySettings() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase.from('user_privacy_settings').upsert({
      'user_id': userId,
      'is_private_account': _isPrivate,
      'hide_online_status': !_showActivityStatus,
      'allow_messages_from': _allowMessagesFrom,
      'allow_mentions_from': _allowMentionsFrom,
      'allow_tags_from': _allowTagsFrom,
      'allow_story_replies_from': _allowStoryRepliesFrom,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<void> _check2faStatus() async {
    try {
      final factors = await MfaService.instance.getEnrolledFactors();
      final hasPasskey =
          await PasskeyAuthService.instance.isPasskeyEnrolled();
      if (mounted) {
        setState(() {
          _is2faActive = factors.isNotEmpty || hasPasskey;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadBlockedUsers() async {
    final blocked = await SocialGraphService.instance.fetchBlockedUsers();
    if (mounted) {
      setState(() {
        _blockedUsersList = blocked;
        _blockedUsersCount = blocked.length;
      });
    }
  }

  Future<void> _loadMutedUsers() async {
    final muted = await SocialGraphService.instance.fetchMutedUsers();
    if (mounted) {
      setState(() {
        _mutedUsersList = muted;
        _mutedUsersCount = muted.length;
      });
    }
  }

  // ===========================================================================
  // 1. PRIVATE ACCOUNT TOGGLE (LIVE SUPABASE SYNC)
  // ===========================================================================
  Future<void> _togglePrivateAccount(bool value) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    HapticFeedback.selectionClick();
    setState(() {
      _isPrivate = value;
      _isSavingPrivacy = true;
    });

    try {
      await Future.wait([
        supabase
            .from('profiles')
            .update({'is_private': value})
            .eq('id', userId),
        _persistPrivacySettings(),
      ]);

      final updated = Map<String, dynamic>.from(widget.profile);
      updated['is_private'] = value;
      widget.onProfileUpdated?.call(updated);

      if (mounted) {
        setState(() => _isSavingPrivacy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  value ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value
                        ? "Account is now Private (Only approved followers can see your content)"
                        : "Account is now Public (Anyone on ZEV can see your profile and posts)",
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            backgroundColor: ZevColors.deepNavy,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPrivate = !value;
          _isSavingPrivacy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update privacy settings: $e"),
            backgroundColor: ZevColors.errorRed,
          ),
        );
      }
    }
  }

  // ===========================================================================
  // 2. ACTIVITY STATUS & INTERACTION AUDIENCE CONTROLS
  // ===========================================================================
  Future<void> _toggleActivityStatus(bool val) async {
    HapticFeedback.selectionClick();
    final previous = _showActivityStatus;
    setState(() => _showActivityStatus = val);
    try {
      await _persistPrivacySettings();
      await UserPresenceService.instance.setHideOnlineStatus(!val);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              val
                  ? "Activity status visible according to your privacy rules"
                  : "Activity status hidden from everyone",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            duration: const Duration(seconds: 1),
            backgroundColor: ZevColors.deepNavy,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _showActivityStatus = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not update activity status: $e"),
            backgroundColor: ZevColors.errorRed,
          ),
        );
      }
    }
  }

  Future<void> _showAudiencePicker({
    required String title,
    required String subtitle,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) async {
    HapticFeedback.lightImpact();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ZevColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: ZevColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              for (final opt in [
                (
                  key: 'everyone',
                  label: 'Everyone',
                  desc: 'Any user on ZEV',
                  icon: Icons.public_rounded,
                ),
                (
                  key: 'followers',
                  label: 'Followers',
                  desc: 'Only accounts that follow you',
                  icon: Icons.people_outline_rounded,
                ),
                (
                  key: 'nobody',
                  label: 'Nobody',
                  desc: 'Disable this interaction',
                  icon: Icons.block_rounded,
                ),
              ])
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: currentValue == opt.key
                        ? ZevColors.primaryBlue.withValues(alpha: 0.1)
                        : ZevColors.softSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: currentValue == opt.key
                          ? ZevColors.secondaryBlue
                          : ZevColors.border,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      opt.icon,
                      color: currentValue == opt.key
                          ? ZevColors.secondaryBlue
                          : ZevColors.textSecondary,
                    ),
                    title: Text(
                      opt.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ZevColors.deepNavy,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      opt.desc,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                    trailing: currentValue == opt.key
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: ZevColors.secondaryBlue,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, opt.key),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (chosen != null && chosen != currentValue) {
      final prev = currentValue;
      onSelected(chosen);
      try {
        await _persistPrivacySettings();
      } catch (e) {
        if (mounted) {
          onSelected(prev);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save setting: $e'),
              backgroundColor: ZevColors.errorRed,
            ),
          );
        }
      }
    }
  }

  // ===========================================================================
  // 4. CHANGE PASSWORD SYSTEM (WITH CURRENT PASSWORD VERIFICATION)
  // ===========================================================================
  void _showChangePasswordModal() {
    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isVerifying = false;
    String? errorMessage;
    bool resetEmailSent = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
          final currentUser = supabase.auth.currentUser;
          final userEmail = currentUser?.email ?? '';

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomPadding),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.lock_reset_rounded,
                          color: Color(0xFF0284C7),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Change Password",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              "Requires your current password for security",
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Color(0xFF64748B)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    "Your new password must be at least 6 characters and should include a combination of numbers and letters.",
                    style: TextStyle(
                        fontSize: 12.5, color: Color(0xFF64748B), height: 1.4),
                  ),

                  const SizedBox(height: 16),

                  // 1. Current Password Field
                  _buildPasswordField(
                    controller: currentPassCtrl,
                    labelText: "Current password",
                    hintText: "Enter your current password",
                    icon: Icons.key_rounded,
                    obscureText: obscureCurrent,
                    onToggleVisibility: () => setModalState(
                        () => obscureCurrent = !obscureCurrent),
                  ),

                  const SizedBox(height: 12),

                  // 2. New Password Field
                  _buildPasswordField(
                    controller: newPassCtrl,
                    labelText: "New password",
                    hintText: "At least 6 characters",
                    icon: Icons.lock_outline_rounded,
                    obscureText: obscureNew,
                    onToggleVisibility: () =>
                        setModalState(() => obscureNew = !obscureNew),
                  ),

                  const SizedBox(height: 12),

                  // 3. Confirm New Password Field
                  _buildPasswordField(
                    controller: confirmPassCtrl,
                    labelText: "Re-type new password",
                    hintText: "Confirm your new password",
                    icon: Icons.check_circle_outline_rounded,
                    obscureText: obscureConfirm,
                    onToggleVisibility: () => setModalState(
                        () => obscureConfirm = !obscureConfirm),
                  ),

                  // Error Message Banner
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Color(0xFFDC2626), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Forgot Password Link
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: resetEmailSent
                          ? null
                          : () async {
                              if (userEmail.isEmpty) {
                                setModalState(() => errorMessage =
                                    "No registered email found for this profile.");
                                return;
                              }
                              try {
                                await supabase.auth
                                    .resetPasswordForEmail(userEmail);
                                HapticFeedback.mediumImpact();
                                setModalState(() {
                                  resetEmailSent = true;
                                  errorMessage = null;
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          "Password reset email sent to $userEmail"),
                                      backgroundColor: const Color(0xFF0F172A),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                  );
                                }
                              } catch (e) {
                                setModalState(() => errorMessage =
                                    "Could not send reset email: $e");
                              }
                            },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        resetEmailSent
                            ? "Reset instructions sent to email ✓"
                            : "Forgot your current password?",
                        style: TextStyle(
                          color: resetEmailSent
                              ? const Color(0xFF10B981)
                              : const Color(0xFF0284C7),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isVerifying
                              ? null
                              : () async {
                                  final currentPass =
                                      currentPassCtrl.text.trim();
                                  final newPass = newPassCtrl.text.trim();
                                  final confirmPass =
                                      confirmPassCtrl.text.trim();

                                  // 1. Validation checks
                                  if (currentPass.isEmpty) {
                                    setModalState(() => errorMessage =
                                        "Please enter your current password.");
                                    return;
                                  }
                                  if (newPass.length < 6) {
                                    setModalState(() => errorMessage =
                                        "New password must be at least 6 characters.");
                                    return;
                                  }
                                  if (newPass == currentPass) {
                                    setModalState(() => errorMessage =
                                        "New password cannot be the same as your current password.");
                                    return;
                                  }
                                  if (newPass != confirmPass) {
                                    setModalState(() => errorMessage =
                                        "New passwords do not match.");
                                    return;
                                  }

                                  setModalState(() {
                                    isVerifying = true;
                                    errorMessage = null;
                                  });

                                  // 2. Re-authenticate Current Password with Supabase
                                  if (userEmail.isNotEmpty) {
                                    try {
                                      await supabase.auth.signInWithPassword(
                                        email: userEmail,
                                        password: currentPass,
                                      );
                                    } on AuthException catch (_) {
                                      setModalState(() {
                                        isVerifying = false;
                                        errorMessage =
                                            "Current password is incorrect. Please check and try again.";
                                      });
                                      HapticFeedback.heavyImpact();
                                      return;
                                    } catch (_) {}
                                  }

                                  // 3. Update to the New Password
                                  try {
                                    await supabase.auth.updateUser(
                                      UserAttributes(password: newPass),
                                    );

                                    HapticFeedback.heavyImpact();
                                    if (ctx.mounted) Navigator.pop(ctx);

                                    if (mounted) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: const Row(
                                            children: [
                                              Icon(Icons.check_circle_rounded,
                                                  color: Colors.white,
                                                  size: 20),
                                              SizedBox(width: 10),
                                              Text(
                                                "Password updated successfully!",
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700),
                                              ),
                                            ],
                                          ),
                                          backgroundColor:
                                              const Color(0xFF10B981),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                      );
                                    }
                                  } catch (updateErr) {
                                    setModalState(() {
                                      isVerifying = false;
                                      errorMessage =
                                          "Update failed: $updateErr";
                                    });
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: isVerifying
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Change Password",
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: labelText,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
          hintText: hintText,
          hintStyle: const TextStyle(
            fontSize: 13,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.normal,
          ),
          prefixIcon: Icon(icon, color: const Color(0xFF0284C7), size: 20),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 32, minHeight: 24),
          suffixIcon: IconButton(
            icon: Icon(
              obscureText
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: const Color(0xFF94A3B8),
              size: 19,
            ),
            onPressed: onToggleVisibility,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 5. BLOCKED ACCOUNTS SHEET
  // ===========================================================================
  void _showBlockedUsersSheet() {
    _loadBlockedUsers();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: ZevColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ZevColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      "Blocked Accounts",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Blocked accounts cannot message you, view your posts or reels, or find your profile on ZEV.",
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ZevColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_blockedUsersList.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: const BoxDecoration(
                                  color: ZevColors.softSurface,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.block_rounded,
                                  color: ZevColors.textMuted,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                "No Blocked Accounts",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: ZevColors.deepNavy,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "You haven't blocked anyone on ZEV.",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ZevColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _blockedUsersList.length,
                          itemBuilder: (_, idx) {
                            final u = _blockedUsersList[idx];
                            final uId = (u['id'] ?? '').toString();
                            final uName = (u['username'] ?? 'user').toString();
                            final fullName =
                                (u['full_name'] ?? '@$uName').toString();
                            final avatar = (u['avatar_url'] ?? '').toString();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: ZevColors.softSurface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: ZevColors.border),
                              ),
                              child: Row(
                                children: [
                                  ZevCachedImage.avatar(
                                    imageUrl: avatar,
                                    size: 40,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "@$uName",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color: ZevColors.deepNavy,
                                          ),
                                        ),
                                        Text(
                                          fullName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: ZevColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () async {
                                      HapticFeedback.mediumImpact();
                                      final ok = await SocialGraphService
                                          .instance
                                          .unblockUser(uId);
                                      if (!ok) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(this.context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Failed to unblock account'),
                                              backgroundColor:
                                                  ZevColors.errorRed,
                                            ),
                                          );
                                        }
                                        return;
                                      }
                                      setSheetState(() {
                                        _blockedUsersList.removeWhere(
                                            (item) => item['id'] == uId);
                                      });
                                      if (mounted) {
                                        setState(() {
                                          _blockedUsersCount =
                                              _blockedUsersList.length;
                                        });
                                        ScaffoldMessenger.of(this.context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text("Unblocked @$uName"),
                                            backgroundColor: ZevColors.deepNavy,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: ZevColors.white,
                                      foregroundColor: ZevColors.deepNavy,
                                      elevation: 0,
                                      side: const BorderSide(
                                        color: ZevColors.border,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                    ),
                                    child: const Text(
                                      "Unblock",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // 5B. MUTED ACCOUNTS SHEET
  // ===========================================================================
  void _showMutedUsersSheet() {
    _loadMutedUsers();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: ZevColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ZevColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      "Muted Accounts",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Hidden from your feed or stories without unfollowing.",
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_mutedUsersList.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: const BoxDecoration(
                                  color: ZevColors.softSurface,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.notifications_off_outlined,
                                  color: ZevColors.textMuted,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                "No Muted Accounts",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: ZevColors.deepNavy,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _mutedUsersList.length,
                          itemBuilder: (_, idx) {
                            final u = _mutedUsersList[idx];
                            final uId = (u['id'] ?? '').toString();
                            final uName = (u['username'] ?? 'user').toString();
                            final avatar = (u['avatar_url'] ?? '').toString();
                            final parts = <String>[
                              if (u['mute_posts'] == true) 'Posts',
                              if (u['mute_stories'] == true) 'Stories',
                              if (u['mute_messages'] == true) 'Messages',
                            ];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: ZevColors.softSurface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: ZevColors.border),
                              ),
                              child: Row(
                                children: [
                                  ZevCachedImage.avatar(
                                    imageUrl: avatar,
                                    size: 40,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "@$uName",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color: ZevColors.deepNavy,
                                          ),
                                        ),
                                        Text(
                                          parts.isEmpty
                                              ? 'Muted'
                                              : 'Muted: ${parts.join(', ')}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: ZevColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () async {
                                      HapticFeedback.mediumImpact();
                                      final ok = await SocialGraphService
                                          .instance
                                          .unmuteUser(uId);
                                      if (!ok) return;
                                      setSheetState(() {
                                        _mutedUsersList.removeWhere(
                                            (item) => item['id'] == uId);
                                      });
                                      if (mounted) {
                                        setState(() {
                                          _mutedUsersCount =
                                              _mutedUsersList.length;
                                        });
                                        ScaffoldMessenger.of(this.context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text("Unmuted @$uName"),
                                            backgroundColor: ZevColors.deepNavy,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: ZevColors.white,
                                      foregroundColor: ZevColors.deepNavy,
                                      elevation: 0,
                                      side: const BorderSide(
                                        color: ZevColors.border,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                    ),
                                    child: const Text(
                                      "Unmute",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // 6. LOGIN ACTIVITY & ACTIVE SESSIONS (DATABASE BACKED)
  // ===========================================================================
  void _showLoginActivityModal() {
    final userId = supabase.auth.currentUser?.id;
    bool loadedOnce = false;
    bool isLoadingSessions = true;
    String currentDeviceId = '';
    List<Map<String, dynamic>> sessions = [];

    String formatAgo(String? iso) {
      if (iso == null || iso.isEmpty) return 'Recently';
      final dt = DateTime.tryParse(iso)?.toLocal();
      if (dt == null) return 'Recently';
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 2) return 'Active now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          if (!loadedOnce) {
            loadedOnce = true;
            Future(() async {
              final devId = await MfaService.instance.getOrCreateDeviceId();
              List<Map<String, dynamic>> rows = [];
              if (userId != null) {
                try {
                  final res = await supabase
                      .from('user_sessions')
                      .select(
                        'id, device_id, platform, device_name, app_version, is_active, last_active_at, ended_at',
                      )
                      .eq('user_id', userId)
                      .order('last_active_at', ascending: false)
                      .limit(20);
                  rows = List<Map<String, dynamic>>.from(res as List);
                } catch (e) {
                  debugPrint('Load sessions notice: $e');
                }
              }
              if (context.mounted) {
                setModalState(() {
                  currentDeviceId = devId;
                  sessions = rows;
                  isLoadingSessions = false;
                });
              }
            });
          }

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.78,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: ZevColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ZevColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      "Login Activity",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Devices registered with your ZEV account.",
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ZevColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (isLoadingSessions)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: ZevColors.primaryBlue,
                          ),
                        ),
                      )
                    else if (sessions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: ZevColors.softSurface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: ZevColors.border),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.devices_rounded,
                              color: ZevColors.successGreen,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "This device • Active session",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: ZevColors.deepNavy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: sessions.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, idx) {
                            final s = sessions[idx];
                            final sId = (s['id'] ?? '').toString();
                            final devId = (s['device_id'] ?? '').toString();
                            final isCurrent =
                                currentDeviceId.isNotEmpty &&
                                devId == currentDeviceId;
                            final isActive = s['is_active'] == true;
                            final deviceName =
                                (s['device_name'] ?? '').toString().isNotEmpty
                                    ? s['device_name'].toString()
                                    : (s['platform'] ?? 'ZEV Device')
                                        .toString();
                            final platform =
                                (s['platform'] ?? '').toString().toUpperCase();
                            final lastAgo = formatAgo(
                              s['last_active_at']?.toString(),
                            );

                            return Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: ZevColors.softSurface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isCurrent
                                      ? ZevColors.primaryBlue
                                      : ZevColors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(9),
                                    decoration: BoxDecoration(
                                      color: (isActive
                                              ? ZevColors.successGreen
                                              : ZevColors.textMuted)
                                          .withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.devices_rounded,
                                      color: isActive
                                          ? ZevColors.successGreen
                                          : ZevColors.textMuted,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                deviceName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: ZevColors.deepNavy,
                                                ),
                                              ),
                                            ),
                                            if (isCurrent) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: ZevColors.successGreen
                                                      .withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  "This device",
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color:
                                                        ZevColors.successGreen,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "${platform.isNotEmpty ? '$platform • ' : ''}$lastAgo${!isActive ? ' • Signed out' : ''}",
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: ZevColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isCurrent && isActive && userId != null)
                                    TextButton(
                                      onPressed: () async {
                                        final nowIso = DateTime.now()
                                            .toUtc()
                                            .toIso8601String();
                                        await supabase
                                            .from('user_sessions')
                                            .update({
                                              'is_active': false,
                                              'ended_at': nowIso,
                                            })
                                            .eq('id', sId)
                                            .eq('user_id', userId);
                                        setModalState(() {
                                          sessions[idx] = {
                                            ...s,
                                            'is_active': false,
                                          };
                                        });
                                      },
                                      child: const Text(
                                        'Revoke',
                                        style: TextStyle(
                                          color: ZevColors.errorRed,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text(
                          "Log Out Of All Other Sessions",
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZevColors.errorRed,
                          foregroundColor: ZevColors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(ctx);
                          try {
                            await supabase.auth.signOut(
                              scope: SignOutScope.others,
                            );
                            if (userId != null) {
                              final nowIso =
                                  DateTime.now().toUtc().toIso8601String();
                              var q = supabase
                                  .from('user_sessions')
                                  .update({
                                    'is_active': false,
                                    'ended_at': nowIso,
                                  })
                                  .eq('user_id', userId);
                              if (currentDeviceId.isNotEmpty) {
                                q = q.neq('device_id', currentDeviceId);
                              }
                              await q;
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    "All other sessions have been logged out.",
                                  ),
                                  backgroundColor: ZevColors.deepNavy,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text("Notice: $e"),
                                  backgroundColor: ZevColors.errorRed,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // 7. DOWNLOAD DATA MODAL (LIVE GDPR/ACCOUNT JSON EXPORT + SHARE SHEET)
  // ===========================================================================
  void _showDownloadDataModal() {
    bool isExporting = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: ZevColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ZevColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  "Download Your Information",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Export your ZEV profile, posts, reels, stories, comments, messages, and privacy logs as a portable JSON file.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ZevColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ZevColors.softSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ZevColors.border),
                  ),
                  child: const Column(
                    children: [
                      _DataRow(
                        label: "Profile & Privacy Settings",
                        format: "JSON",
                      ),
                      Divider(color: ZevColors.border, height: 16),
                      _DataRow(
                        label: "Posts, Reels, Stories & Media Links",
                        format: "Full Metadata",
                      ),
                      Divider(color: ZevColors.border, height: 16),
                      _DataRow(
                        label: "Comments, Social Graph & DMs",
                        format: "Portable Archive",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ZevColors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded, size: 19),
                    label: Text(
                      isExporting
                          ? "Generating Export..."
                          : "Export & Save JSON",
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onPressed: isExporting
                        ? null
                        : () async {
                            HapticFeedback.lightImpact();
                            setModalState(() => isExporting = true);
                            try {
                              final exportData = await ApiClient.instance
                                  .get('/api/v1/account/export');
                              final pretty =
                                  const JsonEncoder.withIndent('  ').convert(
                                exportData,
                              );
                              final dir = await getTemporaryDirectory();
                              final file = File(
                                '${dir.path}/zev_account_export.json',
                              );
                              await file.writeAsString(pretty, flush: true);

                              if (ctx.mounted) Navigator.pop(ctx);
                              await Share.shareXFiles(
                                [XFile(file.path)],
                                subject: 'ZEV Account Data Export',
                              );
                            } catch (e) {
                              if (context.mounted) {
                                setModalState(() => isExporting = false);
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text('Export failed: $e'),
                                    backgroundColor: ZevColors.errorRed,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZevColors.secondaryBlue,
                      foregroundColor: ZevColors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 8. ACCOUNT DEACTIVATION & PERMANENT DELETION
  // ===========================================================================
  Future<void> _showDeactivateAccountDialog() async {
    HapticFeedback.mediumImpact();
    bool isWorking = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isWorking,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: ZevColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Deactivate Account?',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
            ),
          ),
          content: const Text(
            'Your profile, posts, reels, and comments will be hidden immediately. You can reactivate your account anytime by signing back in.',
            style: TextStyle(
              color: ZevColors.textSecondary,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: isWorking ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isWorking
                  ? null
                  : () async {
                      setDlgState(() => isWorking = true);
                      try {
                        await ApiClient.instance
                            .post('/api/v1/account/deactivate');
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          await AuthHelper.logout(this.context);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setDlgState(() => isWorking = false);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text('Could not deactivate: $e'),
                              backgroundColor: ZevColors.errorRed,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: ZevColors.white,
                elevation: 0,
              ),
              child: isWorking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ZevColors.white,
                      ),
                    )
                  : const Text('Deactivate'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    HapticFeedback.heavyImpact();
    final confirmCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    bool isWorking = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final canDelete = confirmCtrl.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            backgroundColor: ZevColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: ZevColors.errorRed),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Delete Account Permanently',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: ZevColors.errorRed,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This permanently removes your ZEV profile, photos, reels, stories, messages, and media from Cloudflare R2. This action cannot be undone.',
                    style: TextStyle(
                      color: ZevColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonCtrl,
                    decoration: InputDecoration(
                      labelText: 'Reason (optional)',
                      filled: true,
                      fillColor: ZevColors.softSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: ZevColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    onChanged: (_) => setDlgState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Type DELETE to confirm',
                      hintText: 'DELETE',
                      filled: true,
                      fillColor: ZevColors.softSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: ZevColors.border),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isWorking ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: (isWorking || !canDelete)
                    ? null
                    : () async {
                        setDlgState(() => isWorking = true);
                        try {
                          await ApiClient.instance.delete(
                            '/api/v1/account/delete',
                            data: {
                              'confirm': true,
                              if (reasonCtrl.text.trim().isNotEmpty)
                                'reason': reasonCtrl.text.trim(),
                            },
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            await AuthHelper.logout(this.context);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            setDlgState(() => isWorking = false);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('Could not delete account: $e'),
                                backgroundColor: ZevColors.errorRed,
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.errorRed,
                  foregroundColor: ZevColors.white,
                  elevation: 0,
                ),
                child: isWorking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ZevColors.white,
                        ),
                      )
                    : const Text('Delete Forever'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Account Privacy & Security",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
          children: [
            // ==========================================
            // 1. ACCOUNT PRIVACY (Private Account Switch)
            // ==========================================
            _buildSectionHeader("ACCOUNT PRIVACY"),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ZevColors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: ZevColors.white.withValues(alpha: 0.95),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ZevColors.deepNavy.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  const BoxShadow(
                    color: ZevColors.white,
                    blurRadius: 4,
                    offset: Offset(0, -1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ZevColors.secondaryBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.lock_outline_rounded,
                          color: ZevColors.secondaryBlue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          "Private Account",
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                      if (_isSavingPrivacy)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ZevColors.secondaryBlue,
                          ),
                        )
                      else
                        Switch.adaptive(
                          value: _isPrivate,
                          activeTrackColor: ZevColors.secondaryBlue,
                          onChanged: _togglePrivateAccount,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "When your account is private, only people you approve can follow you and view your photos, reels, and stories. Existing followers won't be affected.",
                    style: TextStyle(
                      fontSize: 12,
                      color: ZevColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ==========================================
            // 2. INTERACTIONS & VISIBILITY
            // ==========================================
            _buildSectionHeader("INTERACTIONS & VISIBILITY"),

            _buildSettingCard(
              title: "Activity Status",
              subtitle: "Allow accounts you follow to see when you're active",
              icon: Icons.lens_rounded,
              iconColor: ZevColors.successGreen,
              trailing: Switch.adaptive(
                value: _showActivityStatus,
                activeTrackColor: ZevColors.secondaryBlue,
                onChanged: _toggleActivityStatus,
              ),
            ),
            const SizedBox(height: 10),

            _buildSettingCard(
              title: "Who Can Message You",
              subtitle: "Direct message requests and inbox filtering",
              icon: Icons.chat_bubble_outline_rounded,
              iconColor: ZevColors.secondaryBlue,
              badge: _audienceLabel(_allowMessagesFrom),
              onTap: () => _showAudiencePicker(
                title: 'Direct Messages',
                subtitle: 'Choose who can message you on ZEV',
                currentValue: _allowMessagesFrom,
                onSelected: (v) => setState(() => _allowMessagesFrom = v),
              ),
            ),
            const SizedBox(height: 10),

            _buildSettingCard(
              title: "Who Can Mention You",
              subtitle: "Control @username mentions in captions and comments",
              icon: Icons.alternate_email_rounded,
              iconColor: ZevColors.primaryBlue,
              badge: _audienceLabel(_allowMentionsFrom),
              onTap: () => _showAudiencePicker(
                title: 'Mentions',
                subtitle: 'Choose who can @mention you',
                currentValue: _allowMentionsFrom,
                onSelected: (v) => setState(() => _allowMentionsFrom = v),
              ),
            ),
            const SizedBox(height: 10),

            _buildSettingCard(
              title: "Who Can Tag You",
              subtitle: "Control tags on posts and reels",
              icon: Icons.local_offer_outlined,
              iconColor: const Color(0xFF8B5CF6),
              badge: _audienceLabel(_allowTagsFrom),
              onTap: () => _showAudiencePicker(
                title: 'Tags',
                subtitle: 'Choose who can tag your account',
                currentValue: _allowTagsFrom,
                onSelected: (v) => setState(() => _allowTagsFrom = v),
              ),
            ),
            const SizedBox(height: 10),

            _buildSettingCard(
              title: "Story Replies",
              subtitle: "Control who can reply to your stories",
              icon: Icons.reply_rounded,
              iconColor: const Color(0xFFF59E0B),
              badge: _audienceLabel(_allowStoryRepliesFrom),
              onTap: () => _showAudiencePicker(
                title: 'Story Replies',
                subtitle: 'Choose who can reply to your stories',
                currentValue: _allowStoryRepliesFrom,
                onSelected: (v) => setState(() => _allowStoryRepliesFrom = v),
              ),
            ),
            const SizedBox(height: 10),

            _buildSettingCard(
              title: "Muted Accounts",
              subtitle: "Manage accounts hidden from your feed or stories",
              icon: Icons.notifications_off_outlined,
              iconColor: const Color(0xFFD97706),
              badge: _mutedUsersCount > 0 ? "$_mutedUsersCount" : null,
              onTap: _showMutedUsersSheet,
            ),
            const SizedBox(height: 10),

            _buildSettingCard(
              title: "Blocked Accounts",
              subtitle: "Manage accounts you have blocked across ZEV",
              icon: Icons.block_rounded,
              iconColor: ZevColors.errorRed,
              badge: _blockedUsersCount > 0 ? "$_blockedUsersCount" : null,
              onTap: _showBlockedUsersSheet,
            ),

            const SizedBox(height: 20),

            // ==========================================
            // 3. LOGIN & CREDENTIALS
            // ==========================================
            _buildSectionHeader("LOGIN & CREDENTIALS"),

            _buildSettingCard(
              title: "Change Password",
              subtitle: "Update and strengthen your account credentials",
              icon: Icons.key_rounded,
              iconColor: const Color(0xFFF59E0B),
              onTap: _showChangePasswordModal,
            ),
            const SizedBox(height: 10),

            _buildSettingCard(
              title: "Two-Factor Authentication",
              subtitle: "Protect account with Authenticator app or Passkeys",
              icon: Icons.security_rounded,
              iconColor: ZevColors.secondaryBlue,
              badge: _is2faActive ? "Active" : "Not set up",
              badgeColor: _is2faActive
                  ? ZevColors.successGreen
                  : const Color(0xFFF59E0B),
              onTap: () async {
                HapticFeedback.lightImpact();
                await MfaSettingsScreen.open(context);
                _check2faStatus();
              },
            ),
            const SizedBox(height: 10),

            _buildSettingCard(
              title: "Login Activity",
              subtitle: "View active devices and revoke other sessions",
              icon: Icons.devices_rounded,
              iconColor: ZevColors.successGreen,
              onTap: _showLoginActivityModal,
            ),

            const SizedBox(height: 20),

            // ==========================================
            // 4. DATA & ARCHIVES
            // ==========================================
            _buildSectionHeader("DATA & ARCHIVES"),

            _buildSettingCard(
              title: "Download Your Information",
              subtitle: "Export a full JSON archive of your account data",
              icon: Icons.download_rounded,
              iconColor: const Color(0xFF8B5CF6),
              onTap: _showDownloadDataModal,
            ),

            const SizedBox(height: 20),

            // ==========================================
            // 5. ACCOUNT MANAGEMENT
            // ==========================================
            _buildSectionHeader("ACCOUNT MANAGEMENT"),

            _buildSettingCard(
              title: "Account Standing & Appeals",
              subtitle: "Inspect warnings, restrictions, or submit an appeal",
              icon: Icons.gavel_rounded,
              iconColor: ZevColors.secondaryBlue,
              onTap: () => AppealRestrictionSheet.show(
                context,
                initialReason: widget.profile['restriction_reason']?.toString(),
              ),
            ),
            const SizedBox(height: 10),

            _buildSettingCard(
              title: "Deactivate Account",
              subtitle: "Temporarily hide your profile until you sign back in",
              icon: Icons.pause_circle_outline_rounded,
              iconColor: const Color(0xFFD97706),
              onTap: _showDeactivateAccountDialog,
            ),
            const SizedBox(height: 10),

            _buildSettingCard(
              title: "Delete Account Permanently",
              subtitle: "Erase your profile, posts, reels, and media forever",
              icon: Icons.delete_forever_rounded,
              iconColor: ZevColors.errorRed,
              onTap: _showDeleteAccountDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF94A3B8),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    Widget? trailing,
    String? badge,
    Color? badgeColor,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 3,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap != null
              ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? const Color(0xFF0284C7))
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: badgeColor ?? const Color(0xFF0284C7),
                      ),
                    ),
                  ),
                ],
                if (trailing != null)
                  trailing
                else
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: Color(0xFFCBD5E1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final String format;

  const _DataRow({required this.label, required this.format});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        Text(
          format,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0284C7),
          ),
        ),
      ],
    );
  }
}
