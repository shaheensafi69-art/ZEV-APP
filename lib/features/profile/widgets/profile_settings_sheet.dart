import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/services/multi_account_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../auth/screens/login_screen.dart';
import 'help_support_sheet.dart';
import 'notification_settings_sheet.dart';
import 'privacy_security_sheet.dart';
import 'user_activity_sheet.dart';

/// Instagram-Grade Settings & Options Sheet for ZEV Profile.
/// Opened via the top-right hamburger menu (☰).
/// Features 8 fully activated options with real database integrations.
class ProfileSettingsSheet extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback? onOpenSaved;
  final VoidCallback? onOpenShareProfile;
  final VoidCallback? onOpenEditProfile;
  final ValueChanged<Map<String, dynamic>>? onProfileUpdated;

  const ProfileSettingsSheet({
    super.key,
    required this.profile,
    this.onOpenSaved,
    this.onOpenShareProfile,
    this.onOpenEditProfile,
    this.onProfileUpdated,
  });

  static void show(
    BuildContext context, {
    required Map<String, dynamic> profile,
    VoidCallback? onOpenSaved,
    VoidCallback? onOpenShareProfile,
    VoidCallback? onOpenEditProfile,
    ValueChanged<Map<String, dynamic>>? onProfileUpdated,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProfileSettingsSheet(
        profile: profile,
        onOpenSaved: onOpenSaved,
        onOpenShareProfile: onOpenShareProfile,
        onOpenEditProfile: onOpenEditProfile,
        onProfileUpdated: onProfileUpdated,
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZevColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Log Out of ZEV?",
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          "You will need to sign back in with your email or username.",
          style: TextStyle(color: ZevColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: ZevColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(context); // close sheet
              await AuthHelper.logout(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFEF2F2),
              foregroundColor: const Color(0xFFDC2626),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
              ),
            ),
            child: const Text(
              "Log Out",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.88,
      ),
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
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Clay Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.white,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header with Clay close button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Settings and activity",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: ZevColors.deepNavy,
                      letterSpacing: -0.3,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                          const BoxShadow(
                            color: Colors.white,
                            blurRadius: 3,
                            offset: Offset(0, -1),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: ZevColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Scrollable List of Options
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 4, 16, 28 + bottomPadding),
                child: Column(
                  children: [
                    // 1. Edit profile
                    _buildMenuItem(
                      icon: Icons.edit_outlined,
                      title: "Edit profile",
                      onTap: () {
                        Navigator.pop(context);
                        if (onOpenEditProfile != null) onOpenEditProfile!();
                      },
                    ),
                    const SizedBox(height: 8),

                    // 2. Saved
                    _buildMenuItem(
                      icon: Icons.bookmark_border_rounded,
                      title: "Saved",
                      onTap: () {
                        Navigator.pop(context);
                        if (onOpenSaved != null) onOpenSaved!();
                      },
                    ),
                    const SizedBox(height: 8),

                    // 3. QR code & Share profile
                    _buildMenuItem(
                      icon: Icons.qr_code_rounded,
                      title: "QR code & Share profile",
                      onTap: () {
                        Navigator.pop(context);
                        if (onOpenShareProfile != null) onOpenShareProfile!();
                      },
                    ),
                    const SizedBox(height: 8),

                    // 4. Your activity
                    _buildMenuItem(
                      icon: Icons.history_rounded,
                      title: "Your activity",
                      onTap: () {
                        Navigator.pop(context);
                        UserActivitySheet.show(context, profile: profile);
                      },
                    ),
                    const SizedBox(height: 8),

                    // 5. Notifications
                    _buildMenuItem(
                      icon: Icons.notifications_none_rounded,
                      title: "Notifications",
                      onTap: () {
                        Navigator.pop(context);
                        NotificationSettingsSheet.show(context);
                      },
                    ),
                    const SizedBox(height: 8),

                    // 6. Account privacy & Security
                    _buildMenuItem(
                      icon: Icons.security_outlined,
                      title: "Account privacy & Security",
                      onTap: () {
                        Navigator.pop(context);
                        PrivacySecuritySheet.show(
                          context,
                          profile: profile,
                          onProfileUpdated: onProfileUpdated,
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    // 7. Help & Support
                    _buildMenuItem(
                      icon: Icons.help_outline_rounded,
                      title: "Help & Support",
                      onTap: () {
                        Navigator.pop(context);
                        HelpSupportSheet.show(context);
                      },
                    ),
                    const SizedBox(height: 8),

                    // 8. Switch Accounts (Instagram Multi-Account)
                    _buildMenuItem(
                      icon: Icons.switch_account_rounded,
                      title: "Switch Accounts",
                      onTap: () {
                        Navigator.pop(context);
                        MultiAccountService.showAccountSwitcherSheet(context);
                      },
                    ),
                    const SizedBox(height: 8),

                    // 9. Add Account
                    _buildMenuItem(
                      icon: Icons.person_add_alt_1_rounded,
                      title: "Add ZEV Account",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(isAddingAccount: true),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // 10. Log Out
                    _buildMenuItem(
                      icon: Icons.logout_rounded,
                      title: "Log Out",
                      titleColor: const Color(0xFFDC2626),
                      iconColor: const Color(0xFFDC2626),
                      isDestructive: true,
                      onTap: () => _showLogoutDialog(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? titleColor,
    Color? iconColor,
    bool isDestructive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDestructive ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDestructive
              ? const Color(0xFFFCA5A5).withValues(alpha: 0.6)
              : Colors.white,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDestructive
                ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          if (!isDestructive)
            const BoxShadow(
              color: Colors.white,
              blurRadius: 4,
              offset: Offset(0, -1),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          splashColor: isDestructive
              ? const Color(0xFFFEE2E2)
              : const Color(0xFF00D4FF).withValues(alpha: 0.08),
          highlightColor: isDestructive
              ? const Color(0xFFFEF2F2)
              : const Color(0xFFF1F5F9),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                // Clay icon badge
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDestructive
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                      const BoxShadow(
                        color: Colors.white,
                        blurRadius: 3,
                        offset: Offset(0, -1),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      color: iconColor ??
                          (isDestructive
                              ? const Color(0xFFDC2626)
                              : ZevColors.deepNavy),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: titleColor ??
                          (isDestructive
                              ? const Color(0xFFDC2626)
                              : ZevColors.deepNavy),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: isDestructive
                      ? const Color(0xFFDC2626)
                      : ZevColors.textMuted.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
