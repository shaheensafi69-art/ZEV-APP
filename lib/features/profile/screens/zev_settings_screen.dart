import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/services/language_service.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../core/widgets/circular_country_flag.dart';
import '../../auth/screens/welcome_screen.dart';
import 'zev_about_screen.dart';
import 'zev_system_security_screen.dart';
import 'zev_device_activities_screen.dart';
import 'zev_help_support_screen.dart';
import 'zev_open_source_licenses_screen.dart';
import 'zev_privacy_policy_screen.dart';
import 'zev_terms_of_service_screen.dart';

class ZevSettingsScreen extends StatefulWidget {
  const ZevSettingsScreen({super.key});

  @override
  State<ZevSettingsScreen> createState() => _ZevSettingsScreenState();
}

class _ZevSettingsScreenState extends State<ZevSettingsScreen> {
  final supabase = Supabase.instance.client;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);

  String _userEmail = "";
  String _userName = "ZEV User";
  String _userAvatar = "";
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadUserHeader();
  }

  Future<void> _loadUserHeader() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    _userEmail = user.email ?? "";

    try {
      final res = await supabase
          .from('profiles')
          .select('first_name, last_name, avatar_url, role')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        final fn = res['first_name'] ?? '';
        final ln = res['last_name'] ?? '';
        final role = res['role']?.toString().toLowerCase() ?? '';
        final full = "$fn $ln".trim();
        setState(() {
          if (full.isNotEmpty) _userName = full;
          _userAvatar = res['avatar_url'] ?? '';
          _isAdmin = role == 'admin' || role == 'super_admin';
        });
      }
    } catch (_) {}
  }

  Future<void> _handleLogout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              context.zevTr('logOut'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : textDark,
              ),
            ),
          ],
        ),
        content: Text(
          context.zevTr('logOutConfirm'),
          style: TextStyle(
            color: isDark ? Colors.white70 : textGrey,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              context.zevTr('cancel'),
              style: TextStyle(
                color: isDark ? Colors.white60 : textGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              context.zevTr('logOut'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase.auth.signOut();
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _showLanguageSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
          maxWidth: 600,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131B2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 25,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.language_rounded,
                    color: primaryPink,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    context.zevTr('language'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : textDark,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: LanguageService.supportedLanguages.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 64,
                  color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                ),
                itemBuilder: (ctx, i) {
                  final lang = LanguageService.supportedLanguages[i];
                  final isSelected =
                      LanguageService.instance.currentLanguage.code ==
                      lang.code;

                  return InkWell(
                    onTap: () async {
                      await LanguageService.instance.changeLanguage(lang.code);
                      if (ctx.mounted) Navigator.pop(ctx);
                      setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          CircularCountryFlag(
                            countryCode: lang.countryCode,
                            size: 32,
                            showBorder: true,
                            borderColor: isDark
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.black.withValues(alpha: 0.12),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lang.name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isSelected
                                        ? primaryPink
                                        : (isDark ? Colors.white : textDark),
                                  ),
                                ),
                                Text(
                                  lang.englishName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white54 : textGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: primaryPink,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, activeLocale, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final isRtl = LanguageService.isRtl(activeLocale.languageCode);

        final currentLang = LanguageService.supportedLanguages.firstWhere(
          (l) => l.code == activeLocale.languageCode,
          orElse: () => LanguageService.supportedLanguages.first,
        );

        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            backgroundColor: isDark
                ? const Color(0xFF090D16)
                : const Color(0xFFF8FAFC),
            appBar: AppBar(
              backgroundColor: isDark ? const Color(0xFF090D16) : surfaceWhite,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: false,
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: isDark ? Colors.white : textDark,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                    )
                  : null,
              title: Text(
                context.zevTr('settings'),
                style: TextStyle(
                  color: isDark ? Colors.white : textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            body: ResponsiveLayout.pageConstraint(
              maxWidth: 780,
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                children: [
                  // Profile Identity Header Card
                  _buildProfileIdentityCard(isDark),
                  const SizedBox(height: 24),

                  // Section 1: Security & Devices
                  _buildSectionHeader(
                    "SECURITY & ACCESS",
                    Icons.security_rounded,
                  ),
                  _buildGroupCard(
                    isDark: isDark,
                    items: [
                      _SettingsItem(
                        icon: Icons.shield_outlined,
                        iconColor: const Color(0xFF6366F1),
                        title: context.zevTr('systemSecurity'),
                        subtitle: context.zevTr('systemSecuritySub'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ZevSystemSecurityScreen(),
                          ),
                        ),
                      ),
                      _SettingsItem(
                        icon: Icons.devices_rounded,
                        iconColor: const Color(0xFF06B6D4),
                        title: "Active Devices & Sessions",
                        subtitle:
                            "Manage logged-in devices and active browsers",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ZevDeviceActivitiesScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Section 2: Preferences
                  _buildSectionHeader(
                    "PREFERENCES & DISPLAY",
                    Icons.tune_rounded,
                  ),
                  _buildGroupCard(
                    isDark: isDark,
                    items: [
                      _SettingsItem(
                        icon: Icons.language_rounded,
                        iconColor: primaryPink,
                        title: context.zevTr('language'),
                        subtitle:
                            "${currentLang.name} (${currentLang.englishName})",
                        customLeading: CircularCountryFlag(
                          countryCode: currentLang.countryCode,
                          size: 40,
                          showBorder: true,
                          borderColor: isDark
                              ? Colors.white.withValues(alpha: 0.2)
                              : Colors.black.withValues(alpha: 0.12),
                        ),
                        trailingBadge: currentLang.code.toUpperCase(),
                        onTap: _showLanguageSelector,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Section 3: Legal & Privacy Policies
                  _buildSectionHeader("LEGAL & POLICIES", Icons.policy_rounded),
                  _buildGroupCard(
                    isDark: isDark,
                    items: [
                      _SettingsItem(
                        icon: Icons.lock_outline_rounded,
                        iconColor: const Color(0xFF10B981),
                        title: "Privacy Policy",
                        subtitle: "How ZEV protects and encrypts your data",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ZevPrivacyPolicyScreen(),
                          ),
                        ),
                      ),
                      _SettingsItem(
                        icon: Icons.description_outlined,
                        iconColor: const Color(0xFFF59E0B),
                        title: "Terms of Service",
                        subtitle: "Platform rules, guidelines, and terms",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ZevTermsOfServiceScreen(),
                          ),
                        ),
                      ),
                      _SettingsItem(
                        icon: Icons.code_rounded,
                        iconColor: const Color(0xFF8B5CF6),
                        title: "Open Source Licenses",
                        subtitle: "Libraries and software powering ZEV",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ZevOpenSourceLicensesScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Section 4: Support & About
                  _buildSectionHeader(
                    "ABOUT & SUPPORT",
                    Icons.info_outline_rounded,
                  ),
                  _buildGroupCard(
                    isDark: isDark,
                    items: [
                      _SettingsItem(
                        icon: Icons.help_outline_rounded,
                        iconColor: const Color(0xFF3B82F6),
                        title: "Help & Support Center",
                        subtitle:
                            "FAQs, community contact, and customer support",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ZevHelpSupportScreen(),
                          ),
                        ),
                      ),
                      _SettingsItem(
                        icon: Icons.auto_awesome_rounded,
                        iconColor: primaryPink,
                        title: context.zevTr('aboutZev'),
                        subtitle: "ZEV Version 2.4.0 • Built with Passion",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ZevAboutScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Log Out Button
                  InkWell(
                    onTap: _handleLogout,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(
                          alpha: isDark ? 0.12 : 0.08,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.red.withValues(
                            alpha: isDark ? 0.3 : 0.2,
                          ),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.logout_rounded,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.zevTr('logOut'),
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileIdentityCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131B2E) : surfaceWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [primaryPink, Color(0xFFFF5E8A)],
              ),
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF1F5F9),
              backgroundImage: _userAvatar.isNotEmpty
                  ? NetworkImage(_userAvatar)
                  : null,
              child: _userAvatar.isEmpty
                  ? const Icon(Icons.person, color: primaryPink, size: 30)
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _userName,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isAdmin) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.deepPurple.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Text(
                          "OFFICIAL 🛡️",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _userEmail.isNotEmpty ? _userEmail : "ZEV Verified Account",
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : textGrey,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 6, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: primaryPink),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: primaryPink,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard({
    required bool isDark,
    required List<_SettingsItem> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131B2E) : surfaceWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final isLast = i == items.length - 1;

          return Column(
            children: [
              InkWell(
                onTap: item.onTap,
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? const Radius.circular(22) : Radius.zero,
                  bottom: isLast ? const Radius.circular(22) : Radius.zero,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      if (item.customLeading != null)
                        item.customLeading!
                      else
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: item.iconColor.withValues(
                              alpha: isDark ? 0.18 : 0.1,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(item.icon, color: item.iconColor, size: 20),
                        ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : textDark,
                              ),
                            ),
                            if (item.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                item.subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white54 : textGrey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (item.trailingBadge != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: primaryPink.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.trailingBadge!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: primaryPink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: isDark
                            ? Colors.white30
                            : const Color(0xFFCBD5E1),
                      ),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 58,
                  color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _SettingsItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? trailingBadge;
  final Widget? customLeading;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailingBadge,
    this.customLeading,
    required this.onTap,
  });
}
