import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/services/language_service.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../core/utils/zev_alert.dart';

class ZevHelpSupportScreen extends StatefulWidget {
  const ZevHelpSupportScreen({super.key});

  @override
  State<ZevHelpSupportScreen> createState() => _ZevHelpSupportScreenState();
}

class _ZevHelpSupportScreenState extends State<ZevHelpSupportScreen> {
  static const Color primaryPink = Color(0xFFFC466B);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color cardBorder = Color(0xFFF1F5F9);

  final TextEditingController _feedbackController = TextEditingController();
  bool _isSubmitting = false;

  final List<Map<String, String>> _faqs = [
    {
      "q": "How do I switch between multiple ZEV accounts?",
      "a":
          "Tap on your name at the top of the Direct Chat screen to open the Account Switcher drawer. From there, you can switch instantly between your registered accounts or tap '+ Add ZEV Account'.",
    },
    {
      "q": "How does Biometric login work?",
      "a":
          "Enable Biometric Login in Settings > System & Security. Your device's fingerprint sensor or Face ID will be securely used to verify your identity upon app launch.",
    },
    {
      "q": "Can I disable the 4-digit PIN code?",
      "a":
          "Yes! In Settings > System & Security, you can turn off the App PIN Code toggle at any time to access ZEV directly without entering a code.",
    },
    {
      "q": "How do I repost or remix a feed post?",
      "a":
          "Tap the circular Repost / Remix icon on any feed post. The post will instantly be pinned to your profile's reposts list, and you can undo it by tapping again.",
    },
    {
      "q": "Where are my active device sessions listed?",
      "a":
          "Navigate to Settings > System & Security > Device Activity. You will see all devices currently logged into your account and can terminate other sessions with one tap.",
    },
  ];

  Future<void> _submitFeedback() async {
    final text = _feedbackController.text.trim();
    if (text.isEmpty) {
      ZevAlert.error(context, "Please enter your message before sending.");
      return;
    }

    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _feedbackController.clear();
    });

    ZevAlert.success(
      context,
      "Thank you! Your inquiry has been dispatched to ZEV Support.",
      title: "Message Sent",
    );
  }

  Future<void> _openEmailSupport() async {
    final uri = Uri.parse(
      "mailto:support@zevapp.com?subject=ZEV%20Support%20Inquiry",
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (!mounted) return;
        ZevAlert.show(
          context,
          "Contact support directly at support@zevapp.com",
        );
      }
    } catch (_) {
      if (!mounted) return;
      ZevAlert.show(context, "Contact support directly at support@zevapp.com");
    }
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, locale, _) {
        final isRtl = LanguageService.instance.isCurrentRtl;

        return Directionality(
          textDirection: LanguageService.instance.textDirection,
          child: Scaffold(
            backgroundColor: surfaceWhite,
            appBar: AppBar(
              backgroundColor: surfaceWhite,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: true,
              leading: IconButton(
                icon: Icon(
                  isRtl
                      ? Icons.arrow_forward_ios_rounded
                      : Icons.arrow_back_ios_new_rounded,
                  color: textDark,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                context.zevTr('supportAndHelp'),
                style: const TextStyle(
                  color: textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
      body: ResponsiveLayout.feedConstraint(
        maxWidth: 700,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Contact Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFC466B), Color(0xFFFF5E7E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: primaryPink.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.headset_mic_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      SizedBox(width: 10),
                      Text(
                        "ZEV 24/7 Support",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Have an issue or inquiry? Our community operations team is here to assist you anytime.",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _openEmailSupport,
                    icon: const Icon(Icons.mail_outline_rounded, size: 18),
                    label: const Text("Email: support@zevapp.com"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: primaryPink,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Quick Message Box
            const Text(
              "Send Direct Inquiry",
              style: TextStyle(
                color: textDark,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: surfaceWhite,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cardBorder),
              ),
              child: TextField(
                controller: _feedbackController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: "Describe your issue or feedback in detail...",
                  hintStyle: TextStyle(color: textGrey, fontSize: 13),
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitFeedback,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryPink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "Submit Ticket",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 32),

            // FAQs
            const Text(
              "Frequently Asked Questions",
              style: TextStyle(
                color: textDark,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),

            for (var faq in _faqs)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: surfaceWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    iconColor: primaryPink,
                    collapsedIconColor: textGrey,
                    title: Text(
                      faq["q"]!,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    children: [
                      Text(
                        faq["a"]!,
                        style: const TextStyle(
                          color: textGrey,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    ),
  );
      },
    );
  }
}
