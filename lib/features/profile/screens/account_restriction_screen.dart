import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_session_manager.dart';
import '../../../core/services/restriction_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../widgets/appeal_restriction_sheet.dart';

/// Dedicated screen displaying full details about an active account restriction.
/// Shown when a user taps a restriction notification, views their profile notice,
/// or attempts to perform a restricted action (Stories, Posts, Reels, Follow/Unfollow).
class AccountRestrictionScreen extends StatefulWidget {
  final String? actionAttempted;
  final AccountAccessResult? initialStanding;

  const AccountRestrictionScreen({
    super.key,
    this.actionAttempted,
    this.initialStanding,
  });

  static Future<void> open(
    BuildContext context, {
    String? actionAttempted,
    AccountAccessResult? standing,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountRestrictionScreen(
          actionAttempted: actionAttempted,
          initialStanding: standing,
        ),
      ),
    );
  }

  @override
  State<AccountRestrictionScreen> createState() =>
      _AccountRestrictionScreenState();
}

class _AccountRestrictionScreenState extends State<AccountRestrictionScreen> {
  SupabaseClient get _supabase => Supabase.instance.client;

  bool _isLoading = true;
  bool _isRestricted = true;
  DateTime? _restrictedUntil;
  String _restrictionReason = 'Violation of community guidelines';
  int _warningCount = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialStanding != null) {
      _isRestricted = widget.initialStanding!.isRestricted;
      _restrictedUntil = widget.initialStanding!.restrictedUntil;
      _restrictionReason = widget.initialStanding!.restrictionReason ??
          'Violation of community guidelines';
    }
    _loadFreshStanding();

    // Live update countdown timer every 30 seconds
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFreshStanding() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final data = await _supabase
          .from('profiles')
          .select(
            'is_restricted, restricted_until, restriction_reason, warning_count',
          )
          .eq('id', uid)
          .maybeSingle();

      if (data != null && mounted) {
        final untilRaw = data['restricted_until']?.toString();
        final until = untilRaw != null ? DateTime.tryParse(untilRaw)?.toUtc() : null;
        final nowUtc = DateTime.now().toUtc();

        final isActive = data['is_restricted'] == true &&
            (until == null || until.isAfter(nowUtc));

        setState(() {
          _isRestricted = isActive;
          _restrictedUntil = until;
          _restrictionReason = (data['restriction_reason'] ?? '').toString().trim().isNotEmpty
              ? data['restriction_reason'].toString().trim()
              : 'Violation of community guidelines';
          _warningCount = (data['warning_count'] as num?)?.toInt() ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AccountRestrictionScreen] Error fetching standing: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatRemainingTime() {
    if (_restrictedUntil == null) {
      return 'Indefinite • Pending administrative review';
    }

    final nowUtc = DateTime.now().toUtc();
    final diff = _restrictedUntil!.difference(nowUtc);

    if (diff.isNegative) {
      return 'Restriction expired • Features will unlock momentarily';
    }

    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;

    final parts = <String>[];
    if (days > 0) parts.add('$days day${days > 1 ? 's' : ''}');
    if (hours > 0) parts.add('$hours hour${hours > 1 ? 's' : ''}');
    if (days == 0 && minutes > 0) parts.add('$minutes min');

    if (parts.isEmpty) {
      return 'Less than a minute remaining';
    }
    return '${parts.join(', ')} remaining';
  }

  String _formatExpirationDate() {
    if (_restrictedUntil == null) return 'Permanent until reviewed';
    final local = _restrictedUntil!.toLocal();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final monthStr = months[local.month - 1];
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$monthStr ${local.day}, ${local.year} at $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Account Standing',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero Restriction Header Card
                  _buildHeroCard(isDark, cardBg, textColor, textSecondary),
                  const SizedBox(height: 18),

                  // Action Attempted Notice (if triggered by blocked action)
                  if (widget.actionAttempted != null && widget.actionAttempted!.isNotEmpty) ...[
                    _buildAttemptedActionNotice(isDark),
                    const SizedBox(height: 18),
                  ],

                  // Violation Reason Section
                  _buildReasonCard(isDark, cardBg, textColor, textSecondary),
                  const SizedBox(height: 18),

                  // Duration & Time Countdown Card
                  _buildCountdownCard(isDark, cardBg, textColor, textSecondary),
                  const SizedBox(height: 18),

                  // Restricted Features Checklist
                  _buildRestrictedFeaturesCard(isDark, cardBg, textColor, textSecondary),
                  const SizedBox(height: 18),

                  // Auto-Restoration Notice Box
                  _buildRestorationInfoBox(isDark),
                  const SizedBox(height: 26),

                  // Action Buttons: Appeal & Dismiss
                  _buildActionButtons(context),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroCard(
    bool isDark,
    Color cardBg,
    Color textColor,
    Color textSecondary,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Icon badge
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.gpp_bad_rounded,
              color: Colors.white,
              size: 38,
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            _isRestricted
                ? 'Account Temporarily Restricted'
                : 'Account Restriction Lifted',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: textColor,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),

          // Subtitle
          Text(
            _isRestricted
                ? 'Your account features have been temporarily limited due to violations of ZEV Community Guidelines.'
                : 'Your account has been fully restored and all restrictions have been cleared.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),

          if (_warningCount > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Text(
                'Policy Strikes: $_warningCount',
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttemptedActionNotice(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.block_rounded,
            color: Color(0xFFD97706),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Action Blocked',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'You cannot currently perform ${widget.actionAttempted} because your account is temporarily restricted.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonCard(
    bool isDark,
    Color cardBg,
    Color textColor,
    Color textSecondary,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFEF4444),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Reason for Restriction',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _restrictionReason,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: textColor,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownCard(
    bool isDark,
    Color cardBg,
    Color textColor,
    Color textSecondary,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.access_time_filled_rounded,
                color: Color(0xFF0284C7),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Restriction Duration',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Countdown banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  color: Color(0xFF0284C7),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _formatRemainingTime(),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0369A1),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Expiration Date Text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Scheduled End Date:',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
                Text(
                  _formatExpirationDate(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestrictedFeaturesCard(
    bool isDark,
    Color cardBg,
    Color textColor,
    Color textSecondary,
  ) {
    final features = [
      {
        'title': 'Sharing Stories',
        'desc': 'You cannot publish new stories or status updates.',
        'icon': Icons.amp_stories_rounded,
      },
      {
        'title': 'Creating Feed Posts',
        'desc': 'Publishing photos, carousels, or text to feed is disabled.',
        'icon': Icons.grid_on_rounded,
      },
      {
        'title': 'Publishing Reels',
        'desc': 'Uploading and broadcasting short video reels is blocked.',
        'icon': Icons.video_collection_rounded,
      },
      {
        'title': 'Following & Unfollowing',
        'desc': 'Connecting with or modifying relationships with users is paused.',
        'icon': Icons.person_add_disabled_rounded,
      },
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.block_rounded,
                color: Color(0xFFEF4444),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Temporarily Disabled Features',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...features.map((f) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      f['icon'] as IconData,
                      color: const Color(0xFFDC2626),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f['title'] as String,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          f['desc'] as String,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRestorationInfoBox(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_reset_rounded,
            color: Color(0xFF10B981),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Automatic Feature Restoration',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF047857),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Once the countdown timer completes, all restricted capabilities will automatically unlock without manual intervention.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Appeal Button
        ElevatedButton(
          onPressed: () {
            HapticFeedback.mediumImpact();
            AppealRestrictionSheet.show(
              context,
              initialReason: _restrictionReason,
            ).then((_) {
              RestrictionService.instance.invalidateCache();
              _loadFreshStanding();
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: ZevColors.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            elevation: 2,
          ),
          child: const Text(
            'Submit Appeal / Request Review',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 10),

        // Back / Dismiss Button
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            foregroundColor: ZevColors.textSecondary,
          ),
          child: const Text(
            'Done / Return to App',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
