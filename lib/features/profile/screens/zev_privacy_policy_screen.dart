import 'package:flutter/material.dart';
import '../../../core/widgets/responsive_layout.dart';

class ZevPrivacyPolicyScreen extends StatelessWidget {
  const ZevPrivacyPolicyScreen({super.key});

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color cardBorder = Color(0xFFF1F5F9);
  static const Color lightPinkBg = Color(0xFFFFF1F2);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F19) : surfaceWhite,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF131926) : surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Privacy Policy",
          style: TextStyle(
            color: isDark ? Colors.white : textDark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ResponsiveLayout.feedConstraint(
        maxWidth: 700,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            // Top Badge
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: lightPinkBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: primaryPink.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      color: primaryPink,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      "Last Updated: September 2026",
                      style: TextStyle(
                        color: primaryPink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              "Your Privacy Matters to ZEV",
              style: TextStyle(
                color: isDark ? Colors.white : textDark,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "At ZEV (zevapp.com), we are committed to safeguarding your personal data and ensuring transparent privacy practices. This policy outlines how your information is collected, encrypted, and utilized.",
              style: TextStyle(
                color: isDark ? Colors.white70 : textGrey,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),

            _buildSection(
              icon: Icons.lock_outline_rounded,
              title: "1. Data Encryption & Storage",
              content:
                  "All direct messages, passwords, and personal credentials are encrypted in transit using industry-standard TLS 1.3 and at rest with AES-256 encryption. We never store plain text passwords.",
              isDark: isDark,
            ),
            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.account_circle_outlined,
              title: "2. Information We Collect",
              content:
                  "We collect your account details (username, email, optional phone number), profile bio, and content you post on feeds and reels. Usage analytics and device information are collected strictly to protect against unauthorized logins.",
              isDark: isDark,
            ),
            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.share_outlined,
              title: "3. Third-Party Sharing",
              content:
                  "ZEV does NOT sell your personal data to data brokers or third-party advertisers. Information is only shared when legally required or with authorized cloud service providers strictly to deliver our services.",
              isDark: isDark,
            ),
            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.fingerprint_rounded,
              title: "4. Biometric & Security Data",
              content:
                  "Biometric records (Fingerprint / Face ID) are securely processed on your local device hardware using the operating system's secure enclave and are NEVER transmitted to or stored on ZEV remote servers.",
              isDark: isDark,
            ),
            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.delete_outline_rounded,
              title: "5. Account Deletion & Rights",
              content:
                  "You have the right to export your data or permanently delete your ZEV account and all associated media directly from the settings menu at any time.",
              isDark: isDark,
            ),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131926) : cardBorder,
                borderRadius: BorderRadius.circular(16),
                border: isDark
                    ? Border.all(color: const Color(0xFF1E293B))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Have questions regarding privacy?",
                    style: TextStyle(
                      color: isDark ? Colors.white : textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Contact our Data Protection Officer at privacy@zevapp.com",
                    style: TextStyle(
                      color: primaryPink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String content,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131926) : surfaceWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : cardBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
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
                  color: isDark ? const Color(0xFF1E293B) : lightPinkBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: primaryPink, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              color: isDark ? Colors.white70 : textGrey,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
