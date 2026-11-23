import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/services/multi_account_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../ads/screens/ads_manager_screen.dart';
import '../../feed/screens/drafts_scheduled_screen.dart';
import 'creator_insights_screen.dart';
import 'edit_profile_screen.dart';
import 'help_support_screen.dart';
import 'mfa_settings_screen.dart';
import 'notification_settings_screen.dart';
import 'privacy_security_screen.dart';
import 'professional_account_setup_screen.dart';
import 'share_profile_screen.dart';
import 'user_activity_screen.dart';
import 'zev_blue_verification_screen.dart';
import 'data_saver_settings_screen.dart';
import 'active_sessions_screen.dart';
import 'two_factor_auth_screen.dart';
import 'zev_coins_screen.dart';
import 'zev_payout_screen.dart';
import '../../chat/screens/saved_messages_screen.dart';
import '../../communities/screens/communities_list_screen.dart';

/// Full-Screen, 100% Claymorphic "Settings and Activity" Hub for ZEV.
/// Every section links to a dedicated standalone screen instead of bottom sheets.
class ProfileSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback? onOpenSaved;
  final ValueChanged<Map<String, dynamic>>? onProfileUpdated;

  const ProfileSettingsScreen({
    super.key,
    required this.profile,
    this.onOpenSaved,
    this.onProfileUpdated,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late Map<String, dynamic> _profile;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _profile = Map<String, dynamic>.from(widget.profile);
  }

  Future<void> _showSwitchAccountTypeSheet() async {
    final accountType =
        (_profile['account_type'] ?? 'personal').toString().toLowerCase();
    final isCreator = accountType == 'creator';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: ZevColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              "Switch Account Type",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ZevColors.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isCreator
                      ? Icons.storefront_rounded
                      : Icons.auto_awesome_rounded,
                  color: ZevColors.primaryBlue,
                ),
              ),
              title: Text(
                isCreator
                    ? "Switch to Business Account"
                    : "Switch to Creator Account",
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: ZevColors.deepNavy,
                ),
              ),
              subtitle: Text(
                isCreator
                    ? "Best for brands, retailers, and service providers"
                    : "Best for public figures, artists, and content producers",
                style: const TextStyle(fontSize: 12, color: ZevColors.textSecondary),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () async {
                Navigator.pop(ctx);
                await _updateAccountType(isCreator ? 'business' : 'creator');
              },
            ),
            const Divider(color: ZevColors.border),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: Color(0xFFEF4444),
                ),
              ),
              title: const Text(
                "Switch to Personal Account",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: Color(0xFFEF4444),
                ),
              ),
              subtitle: const Text(
                "Return to standard personal profile and enable private option",
                style: TextStyle(fontSize: 12, color: ZevColors.textSecondary),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () {
                Navigator.pop(ctx);
                _showConfirmSwitchToPersonalDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showConfirmSwitchToPersonalDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          "Switch to Personal Account?",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: ZevColors.deepNavy,
          ),
        ),
        content: const Text(
          "When you switch back to a personal account, your insights data will be cleared, active promotions will be paused, and you will regain the option to make your account private at any time.",
          style: TextStyle(fontSize: 13.5, color: ZevColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Cancel",
              style: TextStyle(fontWeight: FontWeight.w700, color: ZevColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _updateAccountType('personal');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              "Switch to Personal",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateAccountType(String newType) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      await Supabase.instance.client
          .from('profiles')
          .update({'account_type': newType, 'updated_at': nowIso})
          .eq('id', userId);

      final updated = Map<String, dynamic>.from(_profile);
      updated['account_type'] = newType;
      setState(() => _profile = updated);
      widget.onProfileUpdated?.call(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newType == 'personal'
                  ? "Switched to Personal Account."
                  : "Switched to ${newType == 'creator' ? 'Creator' : 'Business'} Account.",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            backgroundColor: ZevColors.deepNavy,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update account type: $e"),
            backgroundColor: ZevColors.errorRed,
          ),
        );
      }
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          "Log Out of ZEV?",
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        content: const Text(
          "You will need to sign back in with your email or username.",
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Cancel",
              style: TextStyle(
                  color: Color(0xFF64748B), fontWeight: FontWeight.w700),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(context); // close screen
              await AuthHelper.logout(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
    final isVerified = _profile['is_verified'] == true;
    final fullName =
        "${_profile['first_name'] ?? ''} ${_profile['last_name'] ?? ''}".trim();
    final username = _profile['username'] ?? 'user';
    final avatarUrl = _profile['avatar_url'] ?? '';
    final isDesktop = MediaQuery.of(context).size.width >= 720;
    final accountType =
        (_profile['account_type'] ?? 'personal').toString().toLowerCase();
    final isProfessional =
        accountType == 'creator' || accountType == 'business';

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: ZevColors.deepNavy,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          "Settings and activity",
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 680 : double.infinity,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
              child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Clay Search Bar
            Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.95),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                  const BoxShadow(
                    color: Colors.white,
                    blurRadius: 4,
                    offset: Offset(0, -1),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF0284C7),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      onChanged: (val) =>
                          setState(() => _searchQuery = val.trim().toLowerCase()),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                      decoration: const InputDecoration(
                        hintText: "Search settings and features...",
                        hintStyle: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _searchQuery = ''),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE2E8F0),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // VIP ZEV Blue Card (Tactile Clay)
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ZevBlueVerificationScreen(
                      userProfile: _profile,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                    const BoxShadow(
                      color: Colors.white,
                      blurRadius: 4,
                      offset: Offset(0, -1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isVerified
                                ? "ZEV Blue Verified"
                                : "ZEV Blue Official Verification",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isVerified
                                ? "Your account is officially verified with Blue Tick."
                                : "Official verification for recognized creators with 500K+ followers & public figures.",
                            style: const TextStyle(
                              color: Color(0xFFE0F2FE),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Section 1: Account & Profile
            _buildSectionHeader("Account & Profile"),
            _buildSettingsTile(
              icon: Icons.person_outline_rounded,
              title: "Edit profile",
              subtitle: "Name, bio, links, category & pronouns",
              onTap: () async {
                final updated = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(
                      initialProfile: _profile,
                    ),
                  ),
                );
                if (updated != null) {
                  setState(() => _profile = updated);
                  widget.onProfileUpdated?.call(updated);
                }
              },
            ),
            _buildSettingsTile(
              icon: Icons.qr_code_rounded,
              title: "QR code & Share profile",
              subtitle: "Share your profile QR code and link",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShareProfileScreen(
                      userId: _profile['id']?.toString(),
                      username: username,
                      fullName: fullName,
                      avatarUrl: avatarUrl,
                      bio: _profile['bio']?.toString(),
                      isVerified: _profile['is_verified'] == true,
                      badgeTier: (_profile['badge_tier'] ?? 'none').toString(),
                    ),
                  ),
                );
              },
            ),
            _buildSettingsTile(
              icon: Icons.bookmark_border_rounded,
              title: "Saved",
              subtitle: "Reels and posts you saved",
              onTap: () {
                Navigator.pop(context);
                widget.onOpenSaved?.call();
              },
            ),
            _buildSettingsTile(
              icon: Icons.cloud_outlined,
              title: "Saved Messages & Cloud Drive",
              subtitle: "Unlimited cloud storage for notes, documents, and media",
              iconColor: const Color(0xFF00B2FF),
              onTap: () => SavedMessagesScreen.open(context),
            ),
            _buildSettingsTile(
              icon: Icons.groups_rounded,
              title: "Communities & Discussion Groups",
              subtitle: "Facebook-style groups and Q&A discussion forums",
              iconColor: const Color(0xFF10B981),
              onTap: () => CommunitiesListScreen.open(context),
            ),
            _buildSettingsTile(
              icon: Icons.monetization_on_rounded,
              title: "ZEV Coins & Virtual Wallet",
              subtitle: "Check balance and recharge coins on ZEV Web",
              iconColor: const Color(0xFFF59E0B),
              onTap: () => ZevCoinsScreen.open(context, userProfile: _profile),
            ),
            _buildSettingsTile(
              icon: Icons.payments_rounded,
              title: "Creator Cashout & Payouts",
              subtitle: "Withdraw earnings via PayPal, USDT or Bank wire",
              iconColor: const Color(0xFF10B981),
              onTap: () => ZevPayoutScreen.open(
                context,
                currentEarningsUsd: (_profile['earnings_usd'] as num?)?.toDouble() ?? 0.0,
                totalEarningsCoins: (_profile['earnings_coins'] as num?)?.toInt() ?? 0,
              ),
            ),
            _buildSettingsTile(
              icon: Icons.data_usage_rounded,
              title: "Data Saver & Quality",
              subtitle: "Reduce mobile data usage by up to 75% on slow networks",
              iconColor: const Color(0xFFF59E0B),
              onTap: () => DataSaverSettingsScreen.open(context),
            ),
            _buildSettingsTile(
              icon: Icons.history_rounded,
              title: "Your activity",
              subtitle: "Likes, comments, and interactions history",
              onTap: () => UserActivityScreen.open(context, profile: _profile),
            ),
            _buildSettingsTile(
              icon: Icons.schedule_send_rounded,
              title: "Drafts & Scheduled Posts",
              subtitle: "Publish saved drafts or manage upcoming scheduled posts",
              onTap: () => DraftsScheduledScreen.open(context),
            ),
            const SizedBox(height: 18),

            // Section 2: Professional Tools & Account Switching
            if (isProfessional) ...[
              _buildSectionHeader("For Professionals (${accountType.toUpperCase()})"),
              _buildSettingsTile(
                icon: Icons.insights_rounded,
                title: accountType == 'business'
                    ? "Business Insights & Analytics"
                    : "Creator Insights & Dashboard",
                subtitle: "Views, engagement rate, top content & audience growth",
                onTap: () => CreatorInsightsScreen.open(
                  context,
                  userProfile: _profile,
                ),
              ),
              _buildSettingsTile(
                icon: Icons.campaign_rounded,
                title: "Ads Manager",
                subtitle: "Create sponsored campaigns, targeting, analytics & billing",
                onTap: () => AdsManagerScreen.open(context),
              ),
              _buildSettingsTile(
                icon: Icons.swap_horiz_rounded,
                title: "Switch account type",
                subtitle: "Switch to ${accountType == 'creator' ? 'Business' : 'Creator'} or Personal account",
                iconColor: ZevColors.primaryBlue,
                onTap: _showSwitchAccountTypeSheet,
              ),
            ] else ...[
              _buildSectionHeader("For Professionals"),
              _buildSettingsTile(
                icon: Icons.auto_awesome_rounded,
                title: "Switch to Professional Account",
                subtitle: "Get free insights, advertising tools, and category badges",
                iconColor: ZevColors.primaryBlue,
                titleColor: ZevColors.primaryBlue,
                onTap: () async {
                  final updated =
                      await ProfessionalAccountSetupScreen.open(
                    context,
                    currentProfile: _profile,
                  );
                  if (updated != null) {
                    setState(() => _profile = updated);
                    widget.onProfileUpdated?.call(updated);
                  }
                },
              ),
            ],
            const SizedBox(height: 18),

            // Section 3: Privacy & Security
            _buildSectionHeader("Privacy & Security"),
            _buildSettingsTile(
              icon: Icons.devices_rounded,
              title: "Active Sessions & Devices",
              subtitle: "View logged-in devices and revoke remote sessions",
              iconColor: const Color(0xFF10B981),
              onTap: () => ActiveSessionsScreen.open(context),
            ),
            _buildSettingsTile(
              icon: Icons.lock_outline_rounded,
              title: "Two-Step Verification (PIN Code)",
              subtitle: "Protect account with independent secondary PIN",
              iconColor: const Color(0xFF00B2FF),
              onTap: () => TwoFactorAuthScreen.open(context),
            ),
            _buildSettingsTile(
              icon: Icons.shield_outlined,
              title: "Account privacy & Blocked",
              subtitle: "Private account and restricted profiles",
              onTap: () => PrivacySecurityScreen.open(
                context,
                profile: _profile,
                onProfileUpdated: (newProf) {
                  setState(() => _profile = newProf);
                  widget.onProfileUpdated?.call(newProf);
                },
              ),
            ),
            _buildSettingsTile(
              icon: Icons.security_rounded,
              title: "Two-Factor Authentication (2FA)",
              subtitle: "Extra layer of security with Authenticator and Passkeys",
              onTap: () => MfaSettingsScreen.open(context),
            ),
            _buildSettingsTile(
              icon: Icons.notifications_none_rounded,
              title: "Notifications",
              subtitle: "Pause, sound, and push notification alerts",
              onTap: () => NotificationSettingsScreen.open(context),
            ),
            const SizedBox(height: 18),

            // Section 3: Help & More
            _buildSectionHeader("Support & About"),
            _buildSettingsTile(
              icon: Icons.help_outline_rounded,
              title: "Help & Support",
              subtitle: "Report a problem, FAQs and community help",
              onTap: () => HelpSupportScreen.open(context),
            ),
            const SizedBox(height: 18),

            // Section 4: Login & Multi-Account
            _buildSectionHeader("Login & Accounts"),
            _buildSettingsTile(
              icon: Icons.switch_account_rounded,
              title: "Switch or add account",
              subtitle: "Manage multiple ZEV profiles",
              onTap: () => MultiAccountService.showAccountSwitcherSheet(context),
            ),
            _buildSettingsTile(
              icon: Icons.logout_rounded,
              title: "Log out",
              subtitle: "Sign out of @$username",
              iconColor: const Color(0xFFEF4444),
              titleColor: const Color(0xFFEF4444),
              onTap: _showLogoutDialog,
            ),
          ],
        ),
      ),
    ),
  ),
),
);
}

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF94A3B8),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    if (_searchQuery.isNotEmpty &&
        !title.toLowerCase().contains(_searchQuery) &&
        !subtitle.toLowerCase().contains(_searchQuery)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 3,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (iconColor ?? const Color(0xFF0284C7))
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: iconColor ?? const Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: titleColor ?? const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Color(0xFFCBD5E1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
