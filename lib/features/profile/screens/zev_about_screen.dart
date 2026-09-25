import 'package:flutter/material.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../core/services/language_service.dart';
import '../../../core/localization/zev_localizations.dart';
import 'zev_privacy_policy_screen.dart';
import 'zev_terms_of_service_screen.dart';
import 'zev_help_support_screen.dart';
import 'zev_open_source_licenses_screen.dart';

class ZevAboutScreen extends StatelessWidget {
  const ZevAboutScreen({super.key});

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFFF0F5);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, activeLocale, _) {
        final isRtl = LanguageService.isRtl(activeLocale.languageCode);

        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
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
                context.zevTr('aboutZev'),
                style: const TextStyle(
                  color: textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            body: ResponsiveLayout.feedConstraint(
              maxWidth: 600,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                children: [
                  // ZEV Logo Card
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: surfaceWhite,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: primaryPink.withValues(alpha: 0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Image.asset(
                            'assets/icon-clean.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Image.asset(
                                'assets/logo-clean.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Text(
                                      "ZEV",
                                      style: TextStyle(
                                        color: primaryPink,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 24,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "ZEV",
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: primaryPink,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              " Social",
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: textDark,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Version 1.0.0 (Build 2026.1)",
                          style: TextStyle(fontSize: 13, color: textGrey),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "zevapp.com",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: primaryPink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  _buildTile(
                    icon: Icons.shield_outlined,
                    title: context.zevTr('privacyPolicy'),
                    subtitle: context.zevTr('privacyPolicySub'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ZevPrivacyPolicyScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildTile(
                    icon: Icons.description_outlined,
                    title: context.zevTr('termsOfService'),
                    subtitle: context.zevTr('termsOfServiceSub'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ZevTermsOfServiceScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildTile(
                    icon: Icons.help_outline_rounded,
                    title: context.zevTr('supportAndHelp'),
                    subtitle: context.zevTr('supportAndHelpSub'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ZevHelpSupportScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildTile(
                    icon: Icons.code_rounded,
                    title: context.zevTr('openSourceLicenses'),
                    subtitle: context.zevTr('openSourceLicensesSub'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ZevOpenSourceLicensesScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 36),

                  Center(
                    child: Text(
                      "© 2026 ZEV Technologies Inc. ${context.zevTr('allRightsReserved')}",
                      style: TextStyle(
                        fontSize: 12,
                        color: textGrey.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: lightPinkBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: primaryPink, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: textDark,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: textGrey),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: textGrey,
          size: 14,
        ),
      ),
    );
  }
}
