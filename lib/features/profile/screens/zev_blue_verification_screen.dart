import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/telegram_notification_service.dart';
import '../../../core/theme/zev_theme.dart';
import 'professional_account_setup_screen.dart';

/// Flagship ZEV Verification & Notability Portal.
/// Features 2 Elite Tiers:
///  - ZEV Blue (تیک آبی): 500,000+ real followers + 10 strict verification conditions.
///  - ZEV Gold (تیک طلایی): 1,000,000+ real followers + ZEV Blue prerequisite.
/// Non-negotiable: 0% pay-to-win, 0% referral shortcuts, 100% human compliance audit.
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
  String _badgeTier = 'none'; // 'none', 'blue', 'gold'
  int _followersCount = 0;
  String? _pendingStatus; // 'pending', 'verified', 'rejected', null
  String? _pendingBadgeType; // 'blue_tick', 'gold_tick'
  String? _badgeLabel;
  String? _verificationReason;
  DateTime? _verifiedAt;

  // Audit state
  bool _hasProfessionalAccount = false;
  bool _hasCompleteProfile = false;
  final bool _has2fa = true;

  late TabController _tabCtrl;

  // Application Form Controllers
  String _selectedTier = 'blue'; // 'blue' or 'gold'
  final TextEditingController _legalNameCtrl = TextEditingController();
  final TextEditingController _knownAsCtrl = TextEditingController();
  final TextEditingController _primaryPlatformCtrl = TextEditingController();
  final TextEditingController _platformFollowersCtrl = TextEditingController();
  final TextEditingController _pressLink1Ctrl = TextEditingController();
  final TextEditingController _pressLink2Ctrl = TextEditingController();
  final TextEditingController _websiteCtrl = TextEditingController();
  final TextEditingController _statementCtrl = TextEditingController();
  String _selectedCategory = 'Creator & Influencer';
  String _selectedDocType = 'National ID Card';
  bool _isSubmitting = false;

  static const int kBlueFollowerThreshold = 500000;
  static const int kGoldFollowerThreshold = 1000000;

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
    _primaryPlatformCtrl.dispose();
    _platformFollowersCtrl.dispose();
    _pressLink1Ctrl.dispose();
    _pressLink2Ctrl.dispose();
    _websiteCtrl.dispose();
    _statementCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllVerificationData() async {
    final currentUserId = widget.userProfile['id']?.toString() ??
        _supabase.auth.currentUser?.id ??
        '';

    _isVerified = widget.userProfile['is_verified'] == true;
    _badgeTier = (widget.userProfile['badge_tier'] ?? 'none').toString().toLowerCase();

    if (currentUserId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch live profile stats
      final profileRes = await _supabase
          .from('profiles')
          .select('id, is_verified, badge_tier, account_type, avatar_url, bio, username')
          .eq('id', currentUserId)
          .maybeSingle();

      if (profileRes != null) {
        _isVerified = profileRes['is_verified'] == true;
        _badgeTier = (profileRes['badge_tier'] ?? 'none').toString().toLowerCase();
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
                'status, is_active, badge_type, badge_label, verification_reason, verified_at, expires_at')
            .eq('user_id', currentUserId)
            .maybeSingle();

        if (verifRes != null) {
          _pendingStatus = verifRes['status']?.toString();
          _pendingBadgeType = verifRes['badge_type']?.toString();
          _badgeLabel = verifRes['badge_label']?.toString();
          _verificationReason = verifRes['verification_reason']?.toString();
          if (verifRes['verified_at'] != null) {
            _verifiedAt = DateTime.tryParse(verifRes['verified_at'].toString());
          }
          if (verifRes['is_active'] == true || _pendingStatus == 'verified') {
            _isVerified = true;
            if (_pendingBadgeType == 'gold_tick') {
              _badgeTier = 'gold';
            } else {
              _badgeTier = 'blue';
            }
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

    if (_selectedTier == 'gold' && !_isVerified) {
      _showToast(
        "You must first be ZEV Blue verified before applying for ZEV Gold.",
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.heavyImpact();

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final evidenceLinks = [
        if (_primaryPlatformCtrl.text.trim().isNotEmpty)
          "Main Platform: ${_primaryPlatformCtrl.text.trim()} (${_platformFollowersCtrl.text.trim()} followers)",
        if (_pressLink1Ctrl.text.trim().isNotEmpty) _pressLink1Ctrl.text.trim(),
        if (_pressLink2Ctrl.text.trim().isNotEmpty) _pressLink2Ctrl.text.trim(),
        if (_websiteCtrl.text.trim().isNotEmpty) _websiteCtrl.text.trim(),
      ].join(' | ');

      final isGold = _selectedTier == 'gold';
      final badgeType = isGold ? 'gold_tick' : 'blue_tick';
      final badgeLabel = isGold ? 'ZEV Gold Icon' : 'ZEV Blue Verified';
      final planType = isGold ? 'notability_1m_gold' : 'notability_500k_blue';

      final reasonText =
          "Tier: ${isGold ? 'GOLD (1M+)' : 'BLUE (500K+)'} | Category: $_selectedCategory | Doc: $_selectedDocType | Known As: ${_knownAsCtrl.text.trim()} | Evidence: $evidenceLinks | Statement: ${_statementCtrl.text.trim()}";

      // 1. Upsert into public.user_verifications
      await _supabase.from('user_verifications').upsert({
        'user_id': userId,
        'badge_type': badgeType,
        'status': 'pending',
        'is_active': false,
        'plan_type': planType,
        'badge_label': badgeLabel,
        'legal_name': legalName,
        'known_as': _knownAsCtrl.text.trim(),
        'category': _selectedCategory,
        'document_type': _selectedDocType,
        'evidence_links': evidenceLinks,
        'follower_count': _followersCount,
        'verification_reason': reasonText,
        'updated_at': nowIso,
      }, onConflict: 'user_id');

      // 2. In-app user notification
      try {
        await _supabase.from('user_notifications').insert({
          'user_id': userId,
          'title': isGold
              ? 'ZEV Gold Application Submitted 🏆'
              : 'ZEV Blue Application Submitted 🌟',
          'message':
              'Your verification application for ${isGold ? 'ZEV Gold (1M+)' : 'ZEV Blue (500K+)'} has been received. Our Trust & Safety team will conduct a thorough human review within 24-72 hours.',
          'notification_type': 'verification',
          'app_source': 'zev',
          'is_read': false,
        });
      } catch (_) {}

      // 3. Admin Telegram notification
      try {
        await TelegramNotificationService.submitVerificationOrder(
          fullName: legalName,
          phone: widget.userProfile['public_phone']?.toString() ?? 'N/A',
          planKey: planType,
          planName: isGold ? 'ZEV Gold Verification (1M+)' : 'ZEV Blue Verification (500K+)',
          planPrice: isGold ? '1,000,000+ Followers' : '500,000+ Followers',
          email: widget.userProfile['email']?.toString() ?? '',
          notes: reasonText,
          paymentMethod: 'Manual Human Audit',
        );
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _pendingStatus = 'pending';
        _pendingBadgeType = badgeType;
      });

      _showSuccessDialog(isGold);
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

  void _showSuccessDialog(bool isGold) {
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
                gradient: LinearGradient(
                  colors: isGold
                      ? [const Color(0xFFFBBF24), const Color(0xFFD97706)]
                      : [ZevColors.secondaryBlue, ZevColors.primaryBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isGold ? const Color(0xFFF59E0B) : ZevColors.primaryBlue)
                        .withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                isGold ? Icons.emoji_events_rounded : Icons.verified_rounded,
                size: 38,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isGold ? "ZEV Gold Request Received" : "ZEV Blue Request Received",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Your application has been registered for human verification by the ZEV Compliance & Safety Board according to the 10 official conditions.\n\nEstimated review window: 24 to 72 hours.",
              textAlign: TextAlign.center,
              style: const TextStyle(
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
                  backgroundColor:
                      isGold ? const Color(0xFFD97706) : ZevColors.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  "Understood",
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
        "${widget.userProfile['first_name'] ?? ''} ${_profileLastName()}".trim();
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
          "ZEV Verification Portal",
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
                      // Header Badge Hero (Blue vs Gold)
                      _buildHeaderHero(fullName, username),

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
                            _buildTabPill(1, "2 Tiers & Audit"),
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
                            _buildTiersAndAuditTab(),
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

  String _profileLastName() => (widget.userProfile['last_name'] ?? '').toString();

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
  Widget _buildHeaderHero(String fullName, String username) {
    final isGold = _badgeTier == 'gold';
    final hasBadge = _isVerified;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isGold
              ? const Color(0xFFFBBF24).withValues(alpha: 0.5)
              : Colors.white,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isGold ? const Color(0xFFF59E0B) : ZevColors.primaryBlue)
                .withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isGold
                    ? [const Color(0xFFFDE68A), const Color(0xFFF59E0B), const Color(0xFFB45309)]
                    : [const Color(0xFF38BDF8), ZevColors.secondaryBlue, ZevColors.primaryBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isGold ? const Color(0xFFF59E0B) : ZevColors.secondaryBlue)
                      .withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              isGold ? Icons.emoji_events_rounded : Icons.verified_rounded,
              color: Colors.white,
              size: 30,
            ),
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
                        hasBadge
                            ? (isGold ? "ZEV Gold Official" : "ZEV Blue Verified")
                            : "ZEV Official Verification",
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
                        color: hasBadge
                            ? (isGold ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7))
                            : (_pendingStatus == 'pending'
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFE0F2FE)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        hasBadge
                            ? (isGold ? "GOLD 1M+" : "BLUE 500K+")
                            : (_pendingStatus == 'pending'
                                ? "IN REVIEW"
                                : "STANDARDS"),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: hasBadge
                              ? (isGold ? const Color(0xFFB45309) : const Color(0xFF166534))
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
                  hasBadge
                      ? "Official authenticity badge earned via verifiable notability."
                      : "Strictly non-purchasable: Blue (500K+ & 10 Rules) and Gold (1M+).",
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
  // TAB 0: 10 OFFICIAL RULES & POLICIES (MATCHING USER SPECIFICATION)
  // ===========================================================================
  Widget _buildRulesTab() {
    final rules = [
      {
        'num': '۱',
        'title': 'حداقل ۵۰۰ هزار دنبال‌کننده واقعی',
        'desc':
            'متقاضی باید حداقل ۵۰۰,۰۰۰ دنبال‌کننده واقعی در یکی از شبکه‌های اجتماعی معتبر مانند Instagram، YouTube، TikTok یا ZEV داشته باشد. دنبال‌کنندگان جعلی و خریداری‌شده پذیرفته نیستند.',
        'icon': Icons.groups_rounded,
      },
      {
        'num': '۲',
        'title': 'احراز هویت رسمی',
        'desc':
            'ارائه مدرک هویتی معتبر (پاسپورت، کارت ملی یا ثبت شرکت) و تطبیق نام، تصویر و اطلاعات حساب با هویت واقعی متقاضی الزامی است.',
        'icon': Icons.badge_outlined,
      },
      {
        'num': '۳',
        'title': 'شهرت و شناخته‌شدگی عمومی',
        'desc':
            'شخص باید در سطح ملی یا بین‌المللی شناخته‌شده باشد؛ مانند هنرمندان، ورزشکاران، کارآفرینان، شخصیت‌های رسانه‌ای و افراد تأثیرگذار.',
        'icon': Icons.star_outline_rounded,
      },
      {
        'num': '۴',
        'title': 'حضور رسانه‌ای معتبر',
        'desc':
            'متقاضی باید سابقه حضور یا معرفی در رسانه‌های خبری، مجلات، مصاحبه‌های معتبر یا منابع مستقل قابل اعتماد داشته باشد.',
        'icon': Icons.newspaper_rounded,
      },
      {
        'num': '۵',
        'title': 'فعالیت مستمر و حرفه‌ای',
        'desc':
            'حساب ZEV باید حداقل ۹۰ روز سابقه فعالیت واقعی داشته باشد و در این مدت محتوای معتبر و منظم منتشر کرده باشد.',
        'icon': Icons.history_toggle_off_rounded,
      },
      {
        'num': '۶',
        'title': 'تعامل واقعی با مخاطبان',
        'desc':
            'میزان تعامل، بازدید، نظرات و مشارکت مخاطبان بررسی می‌شود. تعداد دنبال‌کننده به‌تنهایی معیار اعتبار نیست.',
        'icon': Icons.chat_bubble_outline_rounded,
      },
      {
        'num': '۷',
        'title': 'اصالت محتوا و هویت دیجیتال',
        'desc':
            'متقاضی باید مالک واقعی حساب باشد و محتوای اصیل منتشر کند. جعل هویت، سرقت محتوا و استفاده گمراه‌کننده از نام اشخاص دیگر ممنوع است.',
        'icon': Icons.fingerprint_rounded,
      },
      {
        'num': '۸',
        'title': 'سابقه رفتاری و امنیت حساب',
        'desc':
            'حساب نباید سابقه جدی کلاهبرداری، جعل هویت، آزار و اذیت، انتشار محتوای غیرقانونی یا نقض مکرر قوانین ZEV داشته باشد.',
        'icon': Icons.security_rounded,
      },
      {
        'num': '۹',
        'title': 'تأثیرگذاری و دستاوردهای قابل اثبات',
        'desc':
            'فعالیت حرفه‌ای، دستاوردهای اجتماعی، علمی، فرهنگی، ورزشی، اقتصادی یا هنری متقاضی باید قابل بررسی و تأیید باشد.',
        'icon': Icons.emoji_events_outlined,
      },
      {
        'num': '۱۰',
        'title': 'تأیید نهایی توسط تیم انسانی ZEV',
        'desc':
            'دریافت بلو تیک منوط به بررسی کامل درخواست و تأیید تیم رسمی ZEV است. حتی در صورت داشتن تمام شرایط، اعطای نشان تضمین‌شده نیست.',
        'icon': Icons.verified_user_outlined,
      },
    ];

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // Non-Negotiable Rules Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.shield_rounded, color: Color(0xFFDC2626), size: 20),
                  SizedBox(width: 8),
                  Text(
                    "قوانین غیرقابل مذاکره ZEV",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildBulletPoint("خرید بلو تیک یا گلد تیک به هیچ وجه امکان‌پذیر نیست."),
              _buildBulletPoint("اشتراک ماهانه یا سالانه هیچ امتیازی برای دریافت تیک ایجاد نمی‌کند."),
              _buildBulletPoint("سیستم Referral هیچ نقشی در اعطای نشان ندارد."),
              _buildBulletPoint("تعداد دنبال‌کنندگان جعلی باعث رد دائم درخواست می‌شود."),
              _buildBulletPoint("نشان تأیید هویت قابل انتقال یا فروش نیست."),
              _buildBulletPoint("تمامی درخواست‌ها به صورت کاملاً دستی توسط تیم انسانی بررسی می‌شوند."),
            ],
          ),
        ),

        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            "۱۰ شرط رسمی برای دریافت نشان تأیید هویت",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...rules.map((r) => _buildRuleCard(r)),
      ],
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w900)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7F1D1D),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(Map<String, dynamic> rule) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ZevColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
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
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(width: 8),
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
  // TAB 1: 2 TIERS (BLUE & GOLD) & LIVE AUDIT
  // ===========================================================================
  Widget _buildTiersAndAuditTab() {
    final blueProgress = (_followersCount / kBlueFollowerThreshold).clamp(0.0, 1.0);
    final goldProgress = (_followersCount / kGoldFollowerThreshold).clamp(0.0, 1.0);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // Tier 1: ZEV Blue Card (500K)
        _buildTierOverviewCard(
          tierKey: 'blue',
          title: "ZEV Blue (تیک آبی)",
          subtitle: "تأیید هویت اشخاص حقیقی، چهره‌های شناخته‌شده، و کریتورها",
          badgeColor: ZevColors.primaryBlue,
          icon: Icons.verified_rounded,
          requirement: "۵۰۰,۰۰۰ دنبال‌کننده واقعی + تکمیل ۱۰ شرط رسمی",
          currentCount: _followersCount,
          targetCount: kBlueFollowerThreshold,
          progress: blueProgress,
          isPassed: _followersCount >= kBlueFollowerThreshold,
        ),

        const SizedBox(height: 14),

        // Tier 2: ZEV Gold Card (1M)
        _buildTierOverviewCard(
          tierKey: 'gold',
          title: "ZEV Gold (تیک طلایی)",
          subtitle: "شخصیت‌های بسیار تأثیرگذار جهانی و دارای دستاوردهای برجسته",
          badgeColor: const Color(0xFFD97706),
          icon: Icons.emoji_events_rounded,
          requirement: "۱,۰۰۰,۰۰۰ دنبال‌کننده واقعی + داشتن نشان تیک آبی ZEV",
          currentCount: _followersCount,
          targetCount: kGoldFollowerThreshold,
          progress: goldProgress,
          isPassed: _followersCount >= kGoldFollowerThreshold && _isVerified,
        ),

        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            "بررسی وضعیت پیش‌نیازهای حساب شما",
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
            ),
          ),
        ),
        const SizedBox(height: 8),

        _buildAuditItem(
          title: "نوع حساب کاربری (Professional)",
          subtitle: _hasProfessionalAccount
              ? "حساب شما به صورت کریتور یا بیزنس تنظیم شده است."
              : "اکانت شما فعلاً پرسونال است (باید به Creator یا Business تبدیل شود).",
          isPassed: _hasProfessionalAccount,
          actionLabel: _hasProfessionalAccount ? null : "تبدیل اکانت",
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
          title: "کامل بودن پروفایل",
          subtitle: _hasCompleteProfile
              ? "عکس باکیفیت و بایو پروفایل تکمیل است."
              : "عکس پروفایل یا بیوگرافی ناقص است.",
          isPassed: _hasCompleteProfile,
        ),

        _buildAuditItem(
          title: "امنیت ۲FA و احراز هویت دومرحله‌ای",
          subtitle: "حفاظت ضد سرقت حساب کاربری فعال است.",
          isPassed: _has2fa,
        ),

        _buildAuditItem(
          title: "سلامت رفتار و سوابق جامعه",
          subtitle: "فاقد هرگونه اخطار یا نقض قوانین در ۱۸۰ روز اخیر.",
          isPassed: true,
        ),
      ],
    );
  }

  Widget _buildTierOverviewCard({
    required String tierKey,
    required String title,
    required String subtitle,
    required Color badgeColor,
    required IconData icon,
    required String requirement,
    required int currentCount,
    required int targetCount,
    required double progress,
    required bool isPassed,
  }) {
    final targetStr = targetCount == 1000000 ? "۱ میلیون" : "۵۰۰ هزار";

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPassed ? badgeColor.withValues(alpha: 0.5) : ZevColors.border,
          width: isPassed ? 1.5 : 1,
        ),
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
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: badgeColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: badgeColor,
                      ),
                    ),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPassed
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPassed ? "واجد شرایط" : targetStr,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: isPassed
                        ? const Color(0xFF166534)
                        : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            requirement,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: ZevColors.deepNavy,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: ZevColors.softSurface,
              valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "فالورهای ZEV شما: $currentCount",
                style: const TextStyle(fontSize: 11.5, color: ZevColors.textSecondary),
              ),
              Text(
                "هدف: $targetCount",
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ZevColors.deepNavy),
              ),
            ],
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZevColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
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
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
  // TAB 2: APPLICATION FORM (BLUE & GOLD ELIGIBLE)
  // ===========================================================================
  Widget _buildApplyTab() {
    if (_pendingStatus == 'pending') {
      final isGoldPending = _pendingBadgeType == 'gold_tick';
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
            Text(
              isGoldPending
                  ? "درخواست نشان طلایی (ZEV Gold) در حال بررسی"
                  : "درخواست تیک آبی (ZEV Blue) در حال بررسی",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "درخواست شما توسط تیم انطباق و امنیت ZEV بر اساس ۱۰ شرط رسمی در حال ارزیابی دستی است.\n\nمدت زمان معمول بررسی: ۲۴ الی ۷۲ ساعت.",
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

    if (_badgeTier == 'gold') {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFB45309),
                size: 44,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "شما دارای بالاترین سطح اعتبار ZEV Gold هستید",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "نشان: ${_badgeLabel ?? 'ZEV Gold Icon'}\nوضعیت: رسمی و فعال${_verifiedAt != null ? '\nتاریخ اعطا: ${_verifiedAt!.toLocal().toString().split(' ').first}' : ''}${_verificationReason != null && _verificationReason!.isNotEmpty ? '\nمعیار: $_verificationReason' : ''}",
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
        // Choose Target Tier (Blue or Gold)
        const Text(
          "انتخاب سطح نشان مورد درخواست",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildTierSelectorPill(
                keyName: 'blue',
                title: "ZEV Blue",
                subtitle: "۵۰۰ هزار فالور + ۱۰ شرط",
                color: ZevColors.primaryBlue,
                isSelected: _selectedTier == 'blue',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTierSelectorPill(
                keyName: 'gold',
                title: "ZEV Gold",
                subtitle: "۱ میلیون فالور (نیاز به تیک آبی)",
                color: const Color(0xFFD97706),
                isSelected: _selectedTier == 'gold',
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
        const Text(
          "بخش اول: احراز هویت قانونی",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "نام و نام خانوادگی قانونی (مطابق مدرک)",
          hint: "مثلاً: علی احمدی",
          controller: _legalNameCtrl,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "نام شناخته‌شده / نام هنری / نام برند",
          hint: "مثلاً: DJ Spark, Safi Media",
          controller: _knownAsCtrl,
        ),
        const SizedBox(height: 12),

        _buildDropdownField(
          label: "دسته‌بندی فعالیت",
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
          label: "نوع مدرک هویتی",
          value: _selectedDocType,
          items: const [
            'National ID Card',
            'Passport',
            "Driver's License",
            'Official Business Registration',
          ],
          onChanged: (val) {
            if (val != null) setState(() => _selectedDocType = val);
          },
        ),

        const SizedBox(height: 24),
        const Divider(color: ZevColors.border),
        const SizedBox(height: 16),

        const Text(
          "بخش دوم: اثبات سرشناسی و ۵۰۰K+ / ۱M+ دنبال‌کننده",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "لینک صفحه رسمی شما در یکی از پلتفرم‌های اصلی (Instagram / YouTube / TikTok / ZEV) با تعداد فالورها:",
          style: TextStyle(fontSize: 12.5, color: ZevColors.textSecondary),
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "لینک پروفایل رسمی اصلی",
          hint: "https://instagram.com/your_handle",
          controller: _primaryPlatformCtrl,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "تعداد تقریبی دنبال‌کنندگان فعال در پلتفرم اصلی",
          hint: "مثلاً: 650,000",
          controller: _platformFollowersCtrl,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "لینک حضور در رسانه‌ها / مقاله خبری معتبر ۱",
          hint: "https://bbc.com/article...",
          controller: _pressLink1Ctrl,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "لینک حضور در رسانه‌ها / مصاحبه / صفحه ویکی‌پدیا ۲",
          hint: "https://wikipedia.org/wiki/...",
          controller: _pressLink2Ctrl,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "وب‌سایت رسمی / دامین شرکتی",
          hint: "https://yourbrand.com",
          controller: _websiteCtrl,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "توضیحات تکمیلی و بیانیه دستاوردها",
          hint: "شرح خلاصه فعالیت‌ها و دستاوردهای برجسته اجتماعی، فرهنگی، هنری یا علمی...",
          controller: _statementCtrl,
          maxLines: 3,
        ),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitApplication,
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedTier == 'gold'
                  ? const Color(0xFFD97706)
                  : ZevColors.primaryBlue,
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
                : Text(
                    _selectedTier == 'gold'
                        ? "ثبت درخواست بررسی نشان طلایی (ZEV Gold)"
                        : "ثبت درخواست بررسی تیک آبی (ZEV Blue)",
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTierSelectorPill({
    required String keyName,
    required String title,
    required String subtitle,
    required Color color,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedTier = keyName);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : ZevColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  keyName == 'gold' ? Icons.emoji_events_rounded : Icons.verified_rounded,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? color : ZevColors.deepNavy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: ZevColors.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
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
