import 'package:flutter/material.dart';
import '../../../core/widgets/responsive_layout.dart';

class ZevTermsOfServiceScreen extends StatelessWidget {
  const ZevTermsOfServiceScreen({super.key});

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color cardBorder = Color(0xFFF1F5F9);
  static const Color lightPinkBg = Color(0xFFFFF1F2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceWhite,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Terms of Service",
          style: TextStyle(
            color: textDark,
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
                    Icon(Icons.gavel_rounded, color: primaryPink, size: 16),
                    SizedBox(width: 6),
                    Text(
                      "Community Standards 2026",
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

            const Text(
              "ZEV Community Terms & Guidelines",
              style: TextStyle(
                color: textDark,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Welcome to ZEV (zevapp.com). By downloading, creating an account, or accessing our platform, you agree to comply with and be bound by the following Terms of Service.",
              style: TextStyle(color: textGrey, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 24),

            _buildSection(
              icon: Icons.person_pin_circle_outlined,
              title: "1. Eligibility & Accounts",
              content:
                  "You must be at least 13 years old to use ZEV. You are responsible for keeping your password and 4-digit PIN confidential and for all activities occurring under your account.",
            ),
            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.shield_outlined,
              title: "2. Content Ownership & Rights",
              content:
                  "You retain full ownership of photos, videos, reels, and stories you post on ZEV. By sharing content, you grant ZEV a non-exclusive, worldwide license to host, display, and distribute it strictly within the application ecosystem.",
            ),
            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.block_rounded,
              title: "3. Prohibited Conduct",
              content:
                  "Users must not post hate speech, harassment, sexually explicit materials, copyright infringement, or deceptive content. Automated scraping or botting without written permission is strictly prohibited.",
            ),
            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.report_problem_outlined,
              title: "4. Moderation & Suspension",
              content:
                  "ZEV reserves the right to remove any content that violates these terms and suspend or permanently terminate accounts involved in repeated offenses.",
            ),
            const SizedBox(height: 16),

            _buildSection(
              icon: Icons.sync_alt_rounded,
              title: "5. Modifications to Service",
              content:
                  "We continuously improve ZEV. Features may be updated, modified, or discontinued with reasonable notice. Continued use following changes represents agreement to updated terms.",
            ),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBorder,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Legal Inquiries",
                    style: TextStyle(
                      color: textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "For terms or legal questions, email legal@zevapp.com",
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
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: lightPinkBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: primaryPink, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
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
            style: const TextStyle(
              color: textGrey,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
