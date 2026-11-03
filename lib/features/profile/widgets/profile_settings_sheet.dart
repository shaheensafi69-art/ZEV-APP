import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/theme/zev_theme.dart';
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
    return Container(
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
          mainAxisSize: MainAxisSize.min,
          children: [
            // Clay Drag Handle
            Container(
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
            const SizedBox(height: 16),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Settings and activity",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  const SizedBox(height: 12),

                  // 8. Log Out
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

            const SizedBox(height: 8),
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDestructive ? const Color(0xFFFEF2F2) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDestructive ? const Color(0xFFFCA5A5) : Colors.white,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 8,
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
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor ?? ZevColors.deepNavy,
              size: 22,
            ),
            const SizedBox(width: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: titleColor ?? ZevColors.deepNavy,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDestructive ? const Color(0xFFDC2626) : ZevColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
