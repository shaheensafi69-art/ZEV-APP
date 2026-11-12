import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_session_manager.dart';
import '../../../core/theme/zev_theme.dart';
import '../../main_navigation/screens/zev_main_layout.dart';
import '../../profile/widgets/appeal_restriction_sheet.dart';
import 'welcome_screen.dart';

/// Light Clearmorphic Account Suspension / Standing Screen for ZEV.
/// Presented instead of silently logging banned accounts out, so affected
/// users can inspect their standing, submit an appeal with evidence, or sign out.
class AccountStandingScreen extends StatefulWidget {
  final AccountAccessResult standing;

  const AccountStandingScreen({
    super.key,
    required this.standing,
  });

  @override
  State<AccountStandingScreen> createState() => _AccountStandingScreenState();
}

class _AccountStandingScreenState extends State<AccountStandingScreen> {
  late AccountAccessResult _standing;
  bool _isChecking = false;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    _standing = widget.standing;
  }

  Future<void> _recheckStanding() async {
    final uid = _standing.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() => _isChecking = true);
    final updated = await AuthSessionManager.instance.checkAccountStanding(uid);
    if (!mounted) return;
    setState(() {
      _standing = updated;
      _isChecking = false;
    });

    if (updated.isAllowed) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ZevMainLayout()),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Suspension is still active. Submit or check your appeal below.'),
          backgroundColor: ZevColors.deepNavy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _signOut() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSigningOut = true);
    await AuthSessionManager.instance.signOutCurrentDevice();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Indefinite / Pending Review';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final reason = (_standing.reason ?? _standing.restrictionReason ?? '').trim();

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: ZevColors.softSurface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: ZevColors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white, width: 1.6),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.deepNavy.withValues(alpha: 0.08),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: ZevColors.errorRed.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ZevColors.errorRed.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.gpp_maybe_rounded,
                        size: 36,
                        color: ZevColors.errorRed,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Account Suspended',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your ZEV account has been suspended for violating Community Guidelines. You may appeal this decision directly with our moderation team.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: ZevColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: ZevColors.softSurface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: ZevColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'REASON',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.textMuted,
                              letterSpacing: 0.7,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reason.isNotEmpty
                                ? reason
                                : 'Community safety & policy enforcement',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'DURATION / EXPIRES',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.textMuted,
                              letterSpacing: 0.7,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(_standing.bannedUntil),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          AppealRestrictionSheet.show(
                            context,
                            initialReason: reason.isNotEmpty ? reason : null,
                          );
                        },
                        icon: const Icon(Icons.gavel_rounded, size: 19),
                        label: const Text(
                          'Submit / View Appeal',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZevColors.secondaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _isChecking ? null : _recheckStanding,
                        icon: _isChecking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: ZevColors.secondaryBlue,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(
                          'Re-check Account Status',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ZevColors.deepNavy,
                          side: const BorderSide(color: ZevColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _isSigningOut ? null : _signOut,
                      icon: const Icon(
                        Icons.logout_rounded,
                        size: 18,
                        color: ZevColors.errorRed,
                      ),
                      label: const Text(
                        'Sign Out',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: ZevColors.errorRed,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
