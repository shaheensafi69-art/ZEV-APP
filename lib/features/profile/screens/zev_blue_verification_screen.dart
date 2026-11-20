import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/telegram_notification_service.dart';
import '../../../core/theme/zev_theme.dart';
import 'professional_account_setup_screen.dart';

/// Flagship ZEV Blue Verification & Notability Portal.
/// Enforces high standards of authenticity, notability, and community trust.
/// Requires 500,000+ organic followers or verified public figure/institutional status,
/// an active Professional (Creator/Business) account, and compliance with the 10 Verification Rules.
class ZevBlueVerificationScreen extends StatefulWidget {
  final Map<String, dynamic> userProfile;

  const ZevBlueVerificationScreen({
    super.key,
    required this.userProfile,
  });

  static Future<void> open(
    BuildContext context, {
    required Map<String, dynamic> userProfile,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ZevBlueVerificationScreen(userProfile: userProfile),
      ),
    );
  }

  @override
  State<ZevBlueVerificationScreen> createState() =>
      _ZevBlueVerificationScreenState();
}

class _ZevBlueVerificationScreenState extends State<ZevBlueVerificationScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isVerified = false;
  int _followersCount = 0;
  String? _pendingStatus; // 'pending', 'verified', 'rejected', null
  String? _badgeLabel;
  String? _verificationReason;
  DateTime? _verifiedAt;

  // Audit state
  bool _hasProfessionalAccount = false;
  bool _hasCompleteProfile = false;
  final bool _has2fa = true;

  late TabController _tabCtrl;

  // Application Form Controllers
  final TextEditingController _legalNameCtrl = TextEditingController();
  final TextEditingController _knownAsCtrl = TextEditingController();
  final TextEditingController _link1Ctrl = TextEditingController();
  final TextEditingController _link2Ctrl = TextEditingController();
  final TextEditingController _websiteCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  String _selectedCategory = 'Creator & Influencer';
  String _selectedDocType = 'National ID Card';
  bool _isSubmitting = false;

  static const int kFollowerThreshold = 500000;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _legalNameCtrl.text =
        "${widget.userProfile['first_name'] ?? ''} ${widget.userProfile['last_name'] ?? ''}"
            .trim();
    _knownAsCtrl.text = widget.userProfile['username'] ?? '';
    _websiteCtrl.text = widget.userProfile['website'] ?? '';
    _loadAllVerificationData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _legalNameCtrl.dispose();
    _knownAsCtrl.dispose();
    _link1Ctrl.dispose();
    _link2Ctrl.dispose();
    _websiteCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllVerificationData() async {
    final currentUserId = widget.userProfile['id']?.toString() ??
        _supabase.auth.currentUser?.id ??
        '';

    _isVerified = widget.userProfile['is_verified'] == true;

    if (currentUserId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch live profile stats
      final profileRes = await _supabase
          .from('profiles')
          .select('id, is_verified, account_type, avatar_url, bio, username')
          .eq('id', currentUserId)
          .maybeSingle();

      if (profileRes != null) {
        _isVerified = profileRes['is_verified'] == true;
        final accType =
            (profileRes['account_type'] ?? 'personal').toString().toLowerCase();
        _hasProfessionalAccount = accType == 'creator' || accType == 'business';
        final hasAvatar =
            (profileRes['avatar_url']?.toString() ?? '').isNotEmpty;
        final hasBio = (profileRes['bio']?.toString() ?? '').isNotEmpty;
        _hasCompleteProfile = hasAvatar && hasBio;
      }

      // 2. Fetch follower count
      final followersRes = await _supabase
          .from('user_follows')
          .select('follower_id')
          .eq('following_id', currentUserId);
      _followersCount = (followersRes as List).length;

      // 3. Fetch verification record from user_verifications
      try {
        final verifRes = await _supabase
            .from('user_verifications')
            .select(
                'status, is_active, badge_label, verification_reason, verified_at, expires_at')
            .eq('user_id', currentUserId)
            .maybeSingle();

        if (verifRes != null) {
          _pendingStatus = verifRes['status']?.toString();
          _badgeLabel = verifRes['badge_label']?.toString();
          _verificationReason = verifRes['verification_reason']?.toString();
          if (verifRes['verified_at'] != null) {
            _verifiedAt = DateTime.tryParse(verifRes['verified_at'].toString());
          }
          if (verifRes['is_active'] == true || _pendingStatus == 'verified') {
            _isVerified = true;
          }
        }
      } catch (_) {}
    } catch (e) {
      debugPrint("Error loading verification status: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitApplication() async {
    final userId = widget.userProfile['id']?.toString() ??
        _supabase.auth.currentUser?.id ??
        '';
    if (userId.isEmpty) return;

    final legalName = _legalNameCtrl.text.trim();
    if (legalName.isEmpty) {
      _showToast("Please enter your legal full name.", isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.heavyImpact();

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final evidenceLinks = [
        if (_link1Ctrl.text.trim().isNotEmpty) _link1Ctrl.text.trim(),
        if (_link2Ctrl.text.trim().isNotEmpty) _link2Ctrl.text.trim(),
        if (_websiteCtrl.text.trim().isNotEmpty) _websiteCtrl.text.trim(),
      ].join(' | ');

      final applicationReason =
          "Category: $_selectedCategory | Document: $_selectedDocType | Known As: ${_knownAsCtrl.text.trim()} | Followers: $_followersCount | Links: $evidenceLinks | Statement: ${_notesCtrl.text.trim()}";

      // 1. Upsert into public.user_verifications
      await _supabase.from('user_verifications').upsert({
        'user_id': userId,
        'badge_type': 'blue_tick',
        'status': 'pending',
        'is_active': false,
        'plan_type': 'notability_500k',
        'badge_label': 'Verified Creator',
        'verification_reason': applicationReason,
        'updated_at': nowIso,
      }, onConflict: 'user_id');

      // 2. In-app user notification
      try {
        await _supabase.from('user_notifications').insert({
          'user_id': userId,
          'title': 'ZEV Blue Application Submitted 🌟',
          'message':
              'Your verification application has been received and queued for audit. Our Trust & Safety team will review your identity and notability within 24-72 hours.',
          'notification_type': 'verification',
          'app_source': 'zev',
          'is_read': false,
        });
      } catch (_) {}

      // 3. Admin notification
      try {
        await TelegramNotificationService.submitVerificationOrder(
          fullName: legalName,
          phone: widget.userProfile['public_phone']?.toString() ?? 'N/A',
          planKey: 'notability_500k',
          planName: 'ZEV Blue Notability Review (500K+)',
          planPrice: 'Notability Audit',
          email: widget.userProfile['email']?.toString() ?? '',
          notes: applicationReason,
          paymentMethod: 'Notability Application',
        );
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _pendingStatus = 'pending';
      });

      _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showToast("Submission failed: $e", isError: true);
      }
    }
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor:
            isError ? ZevColors.errorRed : ZevColors.deepNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [ZevColors.secondaryBlue, ZevColors.primaryBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ZevColors.primaryBlue.withValues(alpha: 0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.mark_email_read_rounded,
                size: 36,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "Application Received",
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Your ZEV Blue application has been submitted to the Trust & Safety Committee. Our compliance team verifies your identity and follower authenticity according to our 10 verification standards.\n\nEstimated review window: 24 to 72 hours.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ZevColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  "Done",
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.userProfile['username'] ?? 'user';
    final fullName =
        "${widget.userProfile['first_name'] ?? ''} ${widget.userProfile['last_name'] ?? ''}"
            .trim();
    final avatarUrl = widget.userProfile['avatar_url'] ?? '';
    final isDesktop = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "ZEV Blue Verification",
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w900,
            fontSize: 17,
            letterSpacing: -0.2,
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
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: ZevColors.primaryBlue,
                    ),
                  )
                : Column(
                    children: [
                      // Header Badge Hero
                      _buildHeaderHero(avatarUrl, fullName, username),

                      // Clay Tab Navigation
                      Container(
                        height: 44,
                        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0).withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Row(
                          children: [
                            _buildTabPill(0, "10 Rules"),
                            _buildTabPill(1, "Audit"),
                            _buildTabPill(2, "Apply"),
                          ],
                        ),
                      ),

                      // Tab Views
                      Expanded(
                        child: TabBarView(
                          controller: _tabCtrl,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _buildRulesTab(),
                            _buildAuditTab(),
                            _buildApplyTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabPill(int index, String label) {
    final isSelected = _tabCtrl.index == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _tabCtrl.animateTo(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(19),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: ZevColors.deepNavy.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              color: isSelected
                  ? ZevColors.deepNavy
                  : ZevColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HERO BADGE HEADER
  // ===========================================================================
  Widget _buildHeaderHero(
      String avatarUrl, String fullName, String username) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Glowing Blue Badge Icon
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF38BDF8),
                      ZevColors.secondaryBlue,
                      ZevColors.primaryBlue,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.secondaryBlue.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _isVerified ? "Officially Verified" : "ZEV Blue Portal",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: _isVerified
                            ? const Color(0xFFDCFCE7)
                            : (_pendingStatus == 'pending'
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFE0F2FE)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _isVerified
                            ? "ACTIVE"
                            : (_pendingStatus == 'pending'
                                ? "IN REVIEW"
                                : "STANDARDS"),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: _isVerified
                              ? const Color(0xFF166534)
                              : (_pendingStatus == 'pending'
                                  ? const Color(0xFF92400E)
                                  : ZevColors.primaryBlue),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _isVerified
                      ? "Your account represents an authentic, notable public entity on ZEV."
                      : "Reserved for notable public figures, creators (500K+), & global brands.",
                  style: const TextStyle(
                    fontSize: 12,
                    color: ZevColors.textSecondary,
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

  // ===========================================================================
  // TAB 0: 10 OFFICIAL RULES & CRITERIA
  // ===========================================================================
  Widget _buildRulesTab() {
    final rules = [
      {
        'num': '01',
        'title': 'Legal Authenticity',
        'desc':
            'The applicant must represent a genuine, registered human being, trademarked organization, or registered institution with verifiable government credentials.',
        'icon': Icons.badge_outlined,
      },
      {
        'num': '02',
        'title': 'Notability & 500,000+ Follower Baseline',
        'desc':
            'The account must maintain at least 500,000 real followers on ZEV or provide verified press coverage in Tier-1 media publications (e.g. Forbes, Reuters, BBC).',
        'icon': Icons.trending_up_rounded,
      },
      {
        'num': '03',
        'title': 'Professional Account Prerequisite',
        'desc':
            'The account must be set to a Professional Account (Creator or Business) with active analytics and public availability.',
        'icon': Icons.work_outline_rounded,
      },
      {
        'num': '04',
        'title': 'Complete & Public Profile',
        'desc':
            'Profile must be public with a high-resolution photo, informative bio, verified contact info, and regular original publishing history.',
        'icon': Icons.public_rounded,
      },
      {
        'num': '05',
        'title': 'Uniqueness & Representation',
        'desc':
            'Only one verified account per person or business entity is permitted, ensuring genuine representation without duplicate claims.',
        'icon': Icons.fingerprint_rounded,
      },
      {
        'num': '06',
        'title': 'Clean Community Integrity',
        'desc':
            'Zero community violations, copyright strikes, or harassment reports within the previous 180 days across all ZEV features.',
        'icon': Icons.shield_outlined,
      },
      {
        'num': '07',
        'title': 'Mandatory Two-Factor Authentication',
        'desc':
            'Account must have active 2FA (TOTP Authenticator or Biometric Passkey) enabled to eliminate unauthorized takeover risks.',
        'icon': Icons.lock_outline_rounded,
      },
      {
        'num': '08',
        'title': 'Organic Growth & Zero Bots',
        'desc':
            'Algorithmic screening checks engagement ratios. Any account detected utilizing bots, fake followers, or engagement farms is permanently disqualified.',
        'icon': Icons.smart_toy_outlined,
      },
      {
        'num': '09',
        'title': 'Official Corporate Domain Linkage',
        'desc':
            'Corporate entities, brands, and public organizations must link and verify through their official corporate domain email.',
        'icon': Icons.domain_rounded,
      },
      {
        'num': '10',
        'title': 'Code of Ethics & Conduct',
        'desc':
            'Blue tick holders are community leaders. ZEV reserves the unilateral right to revoke verification if an account spreads misinformation, hate speech, or abuse.',
        'icon': Icons.gavel_rounded,
      },
    ];

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF93C5FD), width: 1.2),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: ZevColors.primaryBlue, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "ZEV verification is an earned badge of authenticity and notability. Review the 10 binding rules below before submitting your formal application.",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E3A8A),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...rules.map((r) => _buildRuleCard(r)),
      ],
    );
  }

  Widget _buildRuleCard(Map<String, dynamic> rule) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ZevColors.border),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ZevColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              rule['icon'] as IconData,
              size: 20,
              color: ZevColors.primaryBlue,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      rule['num'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        rule['title'] as String,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  rule['desc'] as String,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: ZevColors.textSecondary,
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

  // ===========================================================================
  // TAB 1: LIVE ACCOUNT AUDIT (500K FOLLOWERS & ELIGIBILITY)
  // ===========================================================================
  Widget _buildAuditTab() {
    final followerProgress =
        (_followersCount / kFollowerThreshold).clamp(0.0, 1.0);
    final meetsFollowers = _followersCount >= kFollowerThreshold;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // 500K Follower Metric Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ZevColors.border),
            boxShadow: [
              BoxShadow(
                color: ZevColors.deepNavy.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Follower Baseline Audit",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: meetsFollowers
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      meetsFollowers ? "500K+ PASSED" : "500K TARGET",
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: meetsFollowers
                            ? const Color(0xFF166534)
                            : const Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _followersCount > 999
                        ? "${(_followersCount / 1000).toStringAsFixed(1)}K"
                        : "$_followersCount",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: ZevColors.deepNavy,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Text(
                    " / 500,000 Organic Followers",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ZevColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: followerProgress,
                  minHeight: 8,
                  backgroundColor: ZevColors.softSurface,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    meetsFollowers
                        ? const Color(0xFF10B981)
                        : ZevColors.primaryBlue,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                meetsFollowers
                    ? "Congratulations! Your follower threshold meets the standard for ZEV Blue Creator verification."
                    : "Accounts below 500K followers can still apply if they represent a registered public institution, official brand, or have notable press coverage.",
                style: const TextStyle(
                  fontSize: 12,
                  color: ZevColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Prerequisite Checklist
        _buildAuditItem(
          title: "Professional Account Type",
          subtitle: _hasProfessionalAccount
              ? "Configured as Creator or Business account"
              : "Account is currently Personal (Must switch to Creator/Business)",
          isPassed: _hasProfessionalAccount,
          actionLabel: _hasProfessionalAccount ? null : "Switch",
          onAction: () async {
            final updated = await ProfessionalAccountSetupScreen.open(
              context,
              currentProfile: widget.userProfile,
            );
            if (updated != null) {
              _loadAllVerificationData();
            }
          },
        ),

        _buildAuditItem(
          title: "Profile Completeness",
          subtitle: _hasCompleteProfile
              ? "Profile photo, bio, and content history active"
              : "Incomplete profile (Add high-res avatar and descriptive bio)",
          isPassed: _hasCompleteProfile,
        ),

        _buildAuditItem(
          title: "Account Security (2FA)",
          subtitle: "Protected against account takeover",
          isPassed: _has2fa,
        ),

        _buildAuditItem(
          title: "Community Standing",
          subtitle: "Zero policy strikes or copyright warnings in 180 days",
          isPassed: true,
        ),
      ],
    );
  }

  Widget _buildAuditItem({
    required String title,
    required String subtitle,
    required bool isPassed,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZevColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isPassed
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEF3C7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPassed ? Icons.check_rounded : Icons.priority_high_rounded,
              color: isPassed
                  ? const Color(0xFF166534)
                  : const Color(0xFF92400E),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: ZevColors.primaryBlue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 2: APPLICATION FORM
  // ===========================================================================
  Widget _buildApplyTab() {
    if (_pendingStatus == 'pending') {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                color: Color(0xFFB45309),
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Application in Review",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Your ZEV Blue application is currently being reviewed by the Trust & Safety Committee. Our team checks your government credentials, follower authenticity, and notability against our 10 standards.\n\nYou will receive an in-app alert once a determination is reached (24-72 hours).",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ZevColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    if (_isVerified) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: Color(0xFF166534),
                size: 44,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "You are ZEV Blue Verified",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Badge: ${_badgeLabel ?? 'Verified Creator'}\nVerified since: ${_verifiedAt != null ? _verifiedAt!.toLocal().toString().split(' ').first : 'Active'}${_verificationReason != null && _verificationReason!.isNotEmpty ? '\nCriteria: $_verificationReason' : ''}",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: ZevColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // Form Description
        const Text(
          "Step 1: Confirm Authenticity",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Enter your legal name and provide official identity verification details.",
          style: TextStyle(fontSize: 12.5, color: ZevColors.textSecondary),
        ),
        const SizedBox(height: 16),

        _buildFormField(
          label: "Full Legal Name",
          hint: "e.g. Johnathan Doe",
          controller: _legalNameCtrl,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "Known As / Brand Name",
          hint: "e.g. DJ Spark, ACME Inc.",
          controller: _knownAsCtrl,
        ),
        const SizedBox(height: 12),

        _buildDropdownField(
          label: "Category",
          value: _selectedCategory,
          items: const [
            'Creator & Influencer',
            'News & Media',
            'Sports & Athlete',
            'Government & Politics',
            'Music & Performing Arts',
            'Fashion & Entertainment',
            'Business & Technology',
            'Education & Science',
          ],
          onChanged: (val) {
            if (val != null) setState(() => _selectedCategory = val);
          },
        ),
        const SizedBox(height: 12),

        _buildDropdownField(
          label: "Identity Document Type",
          value: _selectedDocType,
          items: const [
            'National ID Card',
            'Passport',
            "Driver's License",
            'Official Business Registration',
            'Articles of Incorporation',
          ],
          onChanged: (val) {
            if (val != null) setState(() => _selectedDocType = val);
          },
        ),

        const SizedBox(height: 24),
        const Divider(color: ZevColors.border),
        const SizedBox(height: 16),

        const Text(
          "Step 2: Confirm Notability & Evidence",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Add official links demonstrating notability (press articles, Wikipedia, company site).",
          style: TextStyle(fontSize: 12.5, color: ZevColors.textSecondary),
        ),
        const SizedBox(height: 16),

        _buildFormField(
          label: "Media Coverage / Press Link 1",
          hint: "https://newsoutlet.com/article...",
          controller: _link1Ctrl,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "Media Coverage / Press Link 2",
          hint: "https://wikipedia.org/wiki/...",
          controller: _link2Ctrl,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "Official Website / Domain",
          hint: "https://yourbrand.com",
          controller: _websiteCtrl,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "Statement / Notability Summary",
          hint: "Briefly explain why this account represents a notable entity...",
          controller: _notesCtrl,
          maxLines: 3,
        ),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitApplication,
            style: ElevatedButton.styleFrom(
              backgroundColor: ZevColors.primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    "Submit Application for Audit",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ZevColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: ZevColors.deepNavy,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 13,
                color: ZevColors.textMuted,
              ),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ZevColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: ZevColors.deepNavy),
              items: items
                  .map((e) => DropdownMenuItem<String>(
                        value: e,
                        child: Text(
                          e,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
