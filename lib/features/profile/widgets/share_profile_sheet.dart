import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';

/// Serene, Instagram-Grade Share Profile Bottom Sheet for ZEV.
/// Displays user card with copy link, WhatsApp, and system share.
class ShareProfileSheet extends StatelessWidget {
  final String? userId;
  final String username;
  final String fullName;
  final String avatarUrl;

  const ShareProfileSheet({
    super.key,
    this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
  });

  static void show(
    BuildContext context, {
    String? userId,
    required String username,
    required String fullName,
    required String avatarUrl,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareProfileSheet(
        userId: userId,
        username: username,
        fullName: fullName,
        avatarUrl: avatarUrl,
      ),
    );
  }

  String get _profileUrl => "https://zevapp.com/@$username";

  void _copyLink(BuildContext context) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _profileUrl));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Profile link copied to clipboard!"),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareViaWhatsApp(BuildContext context) async {
    HapticFeedback.lightImpact();
    final text = Uri.encodeComponent(
      "Connect with $fullName (@$username) on ZEV:\n$_profileUrl",
    );
    final uri = Uri.parse("whatsapp://send?text=$text");
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(
          Uri.parse("https://api.whatsapp.com/send?text=$text"),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {}
  }

  void _shareSystem(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
    Share.share(
      "Connect with $fullName (@$username) on ZEV:\n$_profileUrl",
      subject: "$fullName on ZEV",
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
            const SizedBox(height: 18),

            // Profile Card Badge (Tactile Clay 3D Card)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF080D1A), Color(0xFF131D31)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  const BoxShadow(
                    color: Colors.white24,
                    blurRadius: 6,
                    offset: Offset(0, -1),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ZevColors.primaryBlue,
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: avatarUrl.isNotEmpty
                        ? ZevCachedImage.avatar(imageUrl: avatarUrl, size: 76)
                        : const Icon(Icons.person, color: Colors.white70, size: 40),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    fullName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "@$username",
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ZevColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      "ZEV SOCIAL NETWORK",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white70,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons Row (Claymorphic Tactile Pills)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionItem(
                  icon: Icons.link_rounded,
                  label: "Copy Link",
                  bgColor: Colors.white,
                  iconColor: ZevColors.deepNavy,
                  onTap: () => _copyLink(context),
                ),
                _buildActionItem(
                  icon: Icons.chat_rounded,
                  label: "WhatsApp",
                  bgColor: const Color(0xFF25D366),
                  iconColor: Colors.white,
                  onTap: () => _shareViaWhatsApp(context),
                ),
                _buildActionItem(
                  icon: Icons.share_rounded,
                  label: "Share",
                  bgColor: Colors.white,
                  iconColor: ZevColors.deepNavy,
                  onTap: () => _shareSystem(context),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
                const BoxShadow(
                  color: Colors.white,
                  blurRadius: 6,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ZevColors.deepNavy,
            ),
          ),
        ],
      ),
    );
  }
}

