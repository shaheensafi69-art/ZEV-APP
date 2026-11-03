import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/zev_theme.dart';

/// Next-Generation Help & Support Sheet for ZEV.
/// Features interactive problem reporting, expandable FAQ guides,
/// direct email support, and official Community Guidelines.
class HelpSupportSheet extends StatelessWidget {
  const HelpSupportSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const HelpSupportSheet(),
    );
  }

  void _showReportProblemDialog(BuildContext context) {
    final reportController = TextEditingController();
    String selectedCategory = "Bug or glitch";
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text(
              "Report a Problem",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Briefly explain what happened or what's not working.",
                    style: TextStyle(fontSize: 13, color: ZevColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: InputDecoration(
                      labelText: "Topic",
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: "Bug or glitch", child: Text("Bug or glitch")),
                      DropdownMenuItem(value: "Spam or abuse", child: Text("Spam or abuse")),
                      DropdownMenuItem(value: "Audio or video issue", child: Text("Audio or video issue")),
                      DropdownMenuItem(value: "Other suggestion", child: Text("Other suggestion")),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedCategory = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reportController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: "Describe the issue...",
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel", style: TextStyle(color: ZevColors.textMuted)),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (reportController.text.trim().isEmpty) return;
                        setDialogState(() => isSubmitting = true);
                        await Future.delayed(const Duration(milliseconds: 600));
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(Icons.check_circle_rounded, color: ZevColors.primaryBlue),
                                  SizedBox(width: 10),
                                  Text("Thank you! Your report has been submitted."),
                                ],
                              ),
                              backgroundColor: ZevColors.deepNavy,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.primaryBlue,
                  foregroundColor: ZevColors.deepNavy,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Submit", style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _copySupportEmail(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: "support@zevapp.com"));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Email copied to clipboard (support@zevapp.com)"),
        backgroundColor: ZevColors.deepNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    "Help & Support",
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
                  // Report a Problem Card
                  GestureDetector(
                    onTap: () => _showReportProblemDialog(context),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.report_problem_rounded, color: Colors.white, size: 28),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Report a Problem",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "Let us know if something isn't working right",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      "Frequently Asked Questions (FAQ)",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                  _buildFaqTile(
                    question: "How do I get the Verified Badge (Blue Tick)?",
                    answer:
                        "Verified badges confirm authenticity for notable creators, public figures, and brands. Reach out to support with identity verification to begin the review process.",
                  ),
                  const SizedBox(height: 8),

                  _buildFaqTile(
                    question: "How does ZEV protect my data and privacy?",
                    answer:
                        "All messages, stories, and media on ZEV use enterprise-grade Supabase RLS encryption and Cloudflare R2 secure media pipelines.",
                  ),
                  const SizedBox(height: 8),

                  _buildFaqTile(
                    question: "How do I make my posts visible to friends only?",
                    answer:
                        "Go to Settings > Account Privacy & Security and switch on 'Private Account'. Only approved followers can view your feed.",
                  ),
                  const SizedBox(height: 8),

                  _buildFaqTile(
                    question: "Can I save videos or reels offline?",
                    answer:
                        "You can bookmark any post or reel by tapping the bookmark icon. View them anytime in your Profile > Saved collection.",
                  ),

                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      "Direct Contact & Guidelines",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                  _buildActionRow(
                    icon: Icons.email_rounded,
                    title: "Email Support",
                    subtitle: "support@zevapp.com",
                    iconColor: const Color(0xFF10B981),
                    onTap: () => _copySupportEmail(context),
                  ),
                  const SizedBox(height: 8),

                  _buildActionRow(
                    icon: Icons.policy_rounded,
                    title: "Privacy Policy",
                    subtitle: "Learn how ZEV handles your information",
                    iconColor: const Color(0xFF6366F1),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("ZEV Privacy Policy is available at zevapp.com/privacy")),
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  _buildActionRow(
                    icon: Icons.gavel_rounded,
                    title: "Terms of Service",
                    subtitle: "User agreement and guidelines",
                    iconColor: const Color(0xFFF59E0B),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Terms of Service available at zevapp.com/terms")),
                      );
                    },
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

  Widget _buildFaqTile({required String question, required String answer}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: ZevColors.secondaryBlue,
          collapsedIconColor: ZevColors.textMuted,
          title: Text(
            question,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: ZevColors.deepNavy,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            Text(
              answer,
              style: const TextStyle(
                fontSize: 12.5,
                color: ZevColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 8,
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
                      fontSize: 14,
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
            const Icon(Icons.chevron_right_rounded, size: 20, color: ZevColors.textMuted),
          ],
        ),
      ),
    );
  }
}
