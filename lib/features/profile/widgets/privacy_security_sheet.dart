import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zev_theme.dart';
import 'mfa_settings_sheet.dart';

/// Next-Generation Account Privacy & Security Sheet for ZEV.
/// Controls public/private account status, online presence visibility,
/// password change with Supabase Auth, and blocked accounts management.
class PrivacySecuritySheet extends StatefulWidget {
  final Map<String, dynamic> profile;
  final ValueChanged<Map<String, dynamic>>? onProfileUpdated;

  const PrivacySecuritySheet({
    super.key,
    required this.profile,
    this.onProfileUpdated,
  });

  static void show(
    BuildContext context, {
    required Map<String, dynamic> profile,
    ValueChanged<Map<String, dynamic>>? onProfileUpdated,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PrivacySecuritySheet(
        profile: profile,
        onProfileUpdated: onProfileUpdated,
      ),
    );
  }

  @override
  State<PrivacySecuritySheet> createState() => _PrivacySecuritySheetState();
}

class _PrivacySecuritySheetState extends State<PrivacySecuritySheet> {
  final supabase = Supabase.instance.client;

  late bool _isPrivate;
  bool _showActivityStatus = true;
  bool _allowStorySharing = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _isPrivate = widget.profile['is_private'] == true;
  }

  Future<void> _togglePrivateAccount(bool value) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    HapticFeedback.selectionClick();
    setState(() {
      _isPrivate = value;
      _isSaving = true;
    });

    try {
      await supabase
          .from('profiles')
          .update({'is_private': value})
          .eq('id', userId);

      final updated = Map<String, dynamic>.from(widget.profile);
      updated['is_private'] = value;
      widget.onProfileUpdated?.call(updated);

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? "Account is now Private"
                  : "Account is now Public to everyone",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            backgroundColor: ZevColors.deepNavy,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPrivate = !value; // revert
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update privacy: $e"),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  void _showChangePasswordDialog() {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool isUpdating = false;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text(
              "Change Password",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Your new password must be at least 6 characters long.",
                  style: TextStyle(fontSize: 13, color: ZevColors.textMuted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: "New Password",
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: ZevColors.primaryBlue),
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPassCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: "Confirm Password",
                    prefixIcon: const Icon(Icons.lock_reset_rounded, color: ZevColors.primaryBlue),
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (errorMsg != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorMsg!,
                    style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel", style: TextStyle(color: ZevColors.textMuted)),
              ),
              ElevatedButton(
                onPressed: isUpdating
                    ? null
                    : () async {
                        final p1 = newPassCtrl.text.trim();
                        final p2 = confirmPassCtrl.text.trim();

                        if (p1.length < 6) {
                          setDialogState(() => errorMsg = "Password must be at least 6 characters.");
                          return;
                        }
                        if (p1 != p2) {
                          setDialogState(() => errorMsg = "Passwords do not match.");
                          return;
                        }

                        setDialogState(() {
                          isUpdating = true;
                          errorMsg = null;
                        });

                        try {
                          await supabase.auth.updateUser(UserAttributes(password: p1));
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: const Text("Password updated successfully!"),
                                backgroundColor: ZevColors.deepNavy,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            isUpdating = false;
                            errorMsg = "Update failed: $e";
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.primaryBlue,
                  foregroundColor: ZevColors.deepNavy,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isUpdating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Save Password", style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Clay Drag Handle
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(color: Colors.white, blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Sheet Title Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Account privacy & Security",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: ZevColors.deepNavy,
                      letterSpacing: -0.3,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: ZevColors.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(color: Color(0xFFE2E8F0), height: 1),

            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                children: [
                  // Private Account Switch
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.lock_outline_rounded,
                                color: Color(0xFF6366F1),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                "Private Account",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: ZevColors.deepNavy,
                                ),
                              ),
                            ),
                            if (_isSaving)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              Switch.adaptive(
                                value: _isPrivate,
                                activeTrackColor: ZevColors.primaryBlue,
                                onChanged: _togglePrivateAccount,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "When your account is private, only people you approve can see your photos, reels, and stories. Your existing followers won't be affected.",
                          style: TextStyle(
                            fontSize: 12,
                            color: ZevColors.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      "Interactions & Visibility",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                  _buildSettingRow(
                    title: "Activity Status",
                    subtitle: "Allow accounts you follow to see when you're active",
                    icon: Icons.lens_rounded,
                    iconColor: const Color(0xFF10B981),
                    trailing: Switch.adaptive(
                      value: _showActivityStatus,
                      activeTrackColor: ZevColors.primaryBlue,
                      onChanged: (val) {
                        setState(() => _showActivityStatus = val);
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ),
                  const SizedBox(height: 8),

                  _buildSettingRow(
                    title: "Story Sharing",
                    subtitle: "Allow people to share your story posts to messages",
                    icon: Icons.send_rounded,
                    iconColor: const Color(0xFF00D4FF),
                    trailing: Switch.adaptive(
                      value: _allowStorySharing,
                      activeTrackColor: ZevColors.primaryBlue,
                      onChanged: (val) {
                        setState(() => _allowStorySharing = val);
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ),

                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      "Login & Security",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                  _buildSettingRow(
                    title: "Password",
                    subtitle: "Update your account password",
                    icon: Icons.key_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    onTap: _showChangePasswordDialog,
                    trailing: const Icon(Icons.chevron_right_rounded, color: ZevColors.textMuted),
                  ),
                  const SizedBox(height: 8),

                  _buildSettingRow(
                    title: "Two-Factor & Passkeys",
                    subtitle: "Authenticator App (TOTP) • Biometrics",
                    icon: Icons.shield_rounded,
                    iconColor: const Color(0xFF00D4FF),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      MfaSettingsSheet.show(context);
                    },
                    trailing: const Icon(Icons.chevron_right_rounded, color: ZevColors.textMuted),
                  ),
                  const SizedBox(height: 8),

                  _buildSettingRow(
                    title: "Active Login Session",
                    subtitle: "Current Android device • Online now",
                    icon: Icons.smartphone_rounded,
                    iconColor: const Color(0xFF536DFE),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        "Active",
                        style: TextStyle(
                          color: Color(0xFF16A34A),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  _buildSettingRow(
                    title: "Blocked Accounts",
                    subtitle: "0 blocked users",
                    icon: Icons.block_rounded,
                    iconColor: const Color(0xFFDC2626),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("No blocked accounts.")),
                      );
                    },
                    trailing: const Icon(Icons.chevron_right_rounded, color: ZevColors.textMuted),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            Container(
              padding: const EdgeInsets.all(8),
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: ZevColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
