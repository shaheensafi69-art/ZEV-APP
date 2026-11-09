import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/telegram_notification_service.dart';
import '../../../core/widgets/zev_cached_image.dart';

/// Flagship ZEV Blue Verification & Monetization Center.
/// Engineered for high conversion with authentic 3D Claymorphism, transparent guidelines,
/// 3-tier subscription plans (Yearly, Monthly, Lifetime), 100-referral free pathway,
/// and live multi-table database recording (user_verifications + subscriptions + notifications + Telegram).
class ZevBlueVerificationScreen extends StatefulWidget {
  final Map<String, dynamic> userProfile;

  const ZevBlueVerificationScreen({
    super.key,
    required this.userProfile,
  });

  static Future<void> open(BuildContext context,
      {required Map<String, dynamic> userProfile}) {
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
  int _referralCount = 0;
  String _referralCode = '';
  bool _isVerified = false;
  String? _pendingStatus; // 'pending', 'verified', null

  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAllVerificationData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllVerificationData() async {
    final currentUserId = widget.userProfile['id']?.toString() ??
        _supabase.auth.currentUser?.id ??
        '';
    final username = widget.userProfile['username']?.toString() ?? 'user';

    _isVerified = widget.userProfile['is_verified'] == true;
    _referralCode = widget.userProfile['referral_code']?.toString() ?? username;

    if (currentUserId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Fetch live profile stats
      final profileRes = await _supabase
          .from('profiles')
          .select('referral_count, referral_code, is_verified')
          .eq('id', currentUserId)
          .maybeSingle();

      if (profileRes != null) {
        _referralCount = (profileRes['referral_count'] as num?)?.toInt() ?? 0;
        if (profileRes['referral_code'] != null &&
            profileRes['referral_code'].toString().isNotEmpty) {
          _referralCode = profileRes['referral_code'].toString();
        }
        if (profileRes['is_verified'] != null) {
          _isVerified = profileRes['is_verified'] == true;
        }
      }

      // 2. Fetch live verification record from user_verifications
      try {
        final verifRes = await _supabase
            .from('user_verifications')
            .select('status, is_active')
            .eq('user_id', currentUserId)
            .maybeSingle();

        if (verifRes != null) {
          _pendingStatus = verifRes['status']?.toString();
          if (verifRes['is_active'] == true || _pendingStatus == 'verified') {
            _isVerified = true;
          }
        }
      } catch (_) {}

      // 3. Fallback count from referrals table
      try {
        final referralsRes = await _supabase
            .from('referrals')
            .select('id')
            .eq('referrer_id', currentUserId);

        final totalFound = (referralsRes as List).length;
        if (totalFound > _referralCount) {
          _referralCount = totalFound;
        }
      } catch (_) {}
    } catch (e) {
      debugPrint("Error loading verification stats: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _referralLink => "https://www.zevapp.com/join?ref=$_referralCode";

  void _copyReferralCode() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _referralCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF38BDF8), size: 20),
            const SizedBox(width: 10),
            Text(
              "Referral Code '$_referralCode' copied!",
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  void _copyReferralLink() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _referralLink));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: Color(0xFF38BDF8), size: 20),
            SizedBox(width: 10),
            Text(
              "Referral link copied to clipboard!",
              style:
                  TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  void _shareReferralLink() {
    HapticFeedback.mediumImpact();
    final username = widget.userProfile['username'] ?? 'friend';
    Share.share(
      "Join me on ZEV, the peaceful, high-quality social space! Sign up using my link: $_referralLink\n#ZEV #SocialApp",
      subject: "Join ZEV with @$username",
    );
  }

  void _openCheckoutModal({
    required String planKey, // 'yearly', 'monthly', 'lifetime'
    required String planName,
    required String planPrice,
    required double numericAmount,
    required String planBilling,
  }) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CheckoutModalSheet(
        planKey: planKey,
        planName: planName,
        planPrice: planPrice,
        numericAmount: numericAmount,
        planBilling: planBilling,
        userProfile: widget.userProfile,
        referralCode: _referralCode,
        currentReferrals: _referralCount,
        onSuccess: () {
          setState(() => _pendingStatus = 'pending');
          _showCelebrationDialog();
        },
      ),
    );
  }

  void _showCelebrationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: Color(0xFF0284C7),
                size: 44,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Request Received!",
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Your ZEV Blue Verification request has been successfully recorded in the database and dispatched directly to the admin review desk.\n\nYour account will be verified shortly.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
              child: const Text("Awesome",
                  style: TextStyle(fontWeight: FontWeight.w800)),
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
    final avatarUrl = (widget.userProfile['avatar_url'] ?? '').toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF0F172A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "ZEV Blue Verification",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),

            // Segmented 3-Tab Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 46,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(23),
                ),
                child: Row(
                  children: [
                    _buildTabPill(index: 0, label: "Plans"),
                    _buildTabPill(index: 1, label: "Free Pathway"),
                    _buildTabPill(index: 2, label: "Guidelines"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF0284C7)),
                      ),
                    )
                  : TabBarView(
                      controller: _tabCtrl,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        // Tab 1: Premium Subscription Plans
                        _buildPlansTab(username, fullName, avatarUrl),

                        // Tab 2: Free 100-Referral Pathway
                        _buildReferralTab(username, fullName),

                        // Tab 3: Official Verification Guidelines & Terms
                        _buildGuidelinesTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPill({required int index, required String label}) {
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
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
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
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 1: PAID SUBSCRIPTION PLANS (MAIN REVENUE ENGINE)
  // ===========================================================================
  Widget _buildPlansTab(String username, String fullName, String avatarUrl) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
      children: [
        // Pending Status Banner (if user already submitted)
        if (_pendingStatus == 'pending') ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                width: 1.2,
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.hourglass_top_rounded,
                    color: Color(0xFFD97706), size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Verification Request In Review",
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Our admin team is reviewing your account. You will receive your Blue Tick within 1-24 hours.",
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ] else if (_isVerified) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.3),
                width: 1.2,
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_rounded,
                    color: Color(0xFF10B981), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Official Blue Tick Active ⭐",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF065F46),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Your account is officially verified with the ZEV Blue Badge.",
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 1. Interactive Profile Preview Card
        _buildProfilePreviewCard(username, fullName, avatarUrl),

        const SizedBox(height: 20),

        const Center(
          child: Text(
            "SELECT YOUR VERIFICATION PLAN",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // PLAN 1: YEARLY (BEST VALUE / MOST POPULAR)
        _buildPlanCard(
          planKey: 'yearly',
          badgeText: "MOST POPULAR • SAVE 30%",
          badgeColor: const Color(0xFF0284C7),
          title: "ZEV Blue Yearly",
          price: "\$24.99",
          billing: "Billed annually • Only \$2.08/month",
          isPopular: true,
          benefits: const [
            "Official Blue Verification Badge beside your name",
            "Highest trust in feeds, searches & comments",
            "Impersonation & copycat protection",
            "Direct priority creator assistance",
            "Full annual accreditation (cancel anytime)",
          ],
          onTap: () => _openCheckoutModal(
            planKey: 'yearly',
            planName: "ZEV Blue Yearly",
            planPrice: "\$24.99/year",
            numericAmount: 24.99,
            planBilling: "Annual Subscription (\$2.08/mo)",
          ),
        ),

        const SizedBox(height: 14),

        // PLAN 2: MONTHLY (FLEXIBLE)
        _buildPlanCard(
          planKey: 'monthly',
          badgeText: "FLEXIBLE",
          badgeColor: const Color(0xFF64748B),
          title: "ZEV Blue Monthly",
          price: "\$2.99",
          billing: "Billed monthly • Cancel anytime with 1-tap",
          isPopular: false,
          benefits: const [
            "Official Blue Verification Badge beside your name",
            "Active as long as subscription is maintained",
            "Priority support and impersonation monitoring",
            "Flexible monthly commitment",
          ],
          onTap: () => _openCheckoutModal(
            planKey: 'monthly',
            planName: "ZEV Blue Monthly",
            planPrice: "\$2.99/month",
            numericAmount: 2.99,
            planBilling: "Monthly Subscription",
          ),
        ),

        const SizedBox(height: 14),

        // PLAN 3: LIFETIME VIP (SPECIAL LAUNCH OFFER)
        _buildPlanCard(
          planKey: 'lifetime',
          badgeText: "VIP PROMO • PAY ONCE FOR LIFE",
          badgeColor: const Color(0xFF8B5CF6),
          title: "ZEV Blue Lifetime VIP",
          price: "\$49.99",
          billing: "One-time payment • Never pay again",
          isPopular: false,
          benefits: const [
            "Permanent Blue Verification Badge forever",
            "Never worry about monthly or yearly renewals",
            "Exclusive Lifetime Verified Founding Creator status",
            "VIP expedited support queue",
          ],
          onTap: () => _openCheckoutModal(
            planKey: 'lifetime',
            planName: "ZEV Blue Lifetime VIP",
            planPrice: "\$49.99 (One-Time)",
            numericAmount: 49.99,
            planBilling: "Permanent Lifetime Accreditation",
          ),
        ),

        const SizedBox(height: 20),

        // Core Guarantee Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.95),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            children: [
              Icon(Icons.verified_user_rounded,
                  color: Color(0xFF10B981), size: 26),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Our Free Community Pledge",
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      "All core features on ZEV—posting, reels, chatting, audio & video calls—will always remain 100% FREE for everyone. ZEV Blue is strictly for authentic identity verification.",
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 2: FREE 100-REFERRAL PATHWAY
  // ===========================================================================
  Widget _buildReferralTab(String username, String fullName) {
    final progress = (_referralCount / 100).clamp(0.0, 1.0);
    final remaining = max(0, 100 - _referralCount);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
      children: [
        // Milestone Progress Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stars_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text(
                          "FREE LIFETIME PATHWAY",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    "$_referralCount / 100",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                "Invite 100 Friends for Free Lifetime Blue Tick",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                remaining > 0
                    ? "Invite $remaining more friends to qualify for free lifetime verification automatically."
                    : "🎉 You have reached 100 referrals! Lifetime Blue Tick unlocked!",
                style: const TextStyle(
                  color: Color(0xFFE0F2FE),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // Animated Progress Bar
              Stack(
                children: [
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF38BDF8), Color(0xFF67E8F9)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF38BDF8)
                                .withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Mini Stats Cards
        Row(
          children: [
            Expanded(
              child: _buildMiniStatCard(
                title: "Total Invited",
                value: "$_referralCount",
                icon: Icons.people_alt_rounded,
                color: const Color(0xFF0284C7),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMiniStatCard(
                title: "Remaining",
                value: "$remaining",
                icon: Icons.flag_rounded,
                color: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMiniStatCard(
                title: "Reward",
                value: "\$49.99 Free",
                icon: Icons.card_giftcard_rounded,
                color: const Color(0xFF10B981),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Referral Code Card
        const Text(
          "Your Referral Code",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "SHARE WITH FRIENDS",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _referralCode.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF38BDF8),
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _copyReferralCode,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text("Copy"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Deep Link Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.link_rounded,
                      size: 16, color: Color(0xFF0284C7)),
                  SizedBox(width: 6),
                  Text(
                    "Direct Download Link",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _referralLink,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded,
                        size: 18, color: Color(0xFF0284C7)),
                    onPressed: _copyReferralLink,
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_rounded,
                        size: 18, color: Color(0xFF0284C7)),
                    onPressed: _shareReferralLink,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 3: OFFICIAL VERIFICATION GUIDELINES
  // ===========================================================================
  Widget _buildGuidelinesTab() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
      children: [
        _buildGuidelineSection(
          icon: Icons.fact_check_rounded,
          iconColor: const Color(0xFF0284C7),
          title: "Account Eligibility Requirements",
          points: const [
            "Your account must have a clear profile photo and complete full name.",
            "You must have published at least 1 public post, photo, or reel.",
            "Account must be in good standing with zero active policy violations.",
            "Must be at least 13 years old or authorized representative.",
          ],
        ),
        const SizedBox(height: 14),

        _buildGuidelineSection(
          icon: Icons.shield_rounded,
          iconColor: const Color(0xFF10B981),
          title: "Verification Meaning & Code of Conduct",
          points: const [
            "The Blue Badge certifies authentic identity and prevents impersonation.",
            "It does NOT grant immunity from community guidelines or content moderation.",
            "Engaging in hate speech, scamming, or copyright infringement will result in badge revocation.",
            "Accounts cannot change their verified identity name to an unrelated brand or person.",
          ],
        ),
        const SizedBox(height: 14),

        _buildGuidelineSection(
          icon: Icons.payment_rounded,
          iconColor: const Color(0xFFF59E0B),
          title: "Billing & Review Timeline",
          points: const [
            "All verification requests are reviewed by our team within 1 to 24 hours.",
            "Subscriptions can be cancelled at any time from your account settings.",
            "100% refund guarantee if an account cannot be verified for policy reasons.",
            "Payment support includes in-app purchase, credit cards, and direct coordinator transfer.",
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // REUSABLE CLAYMORPHIC COMPONENTS
  // ===========================================================================

  Widget _buildProfilePreviewCard(
      String username, String fullName, String avatarUrl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF0284C7),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: avatarUrl.isNotEmpty
                      ? ZevCachedImage.avatar(
                          imageUrl: avatarUrl,
                          size: 52,
                        )
                      : Container(
                          color: const Color(0xFFE2E8F0),
                          child: const Icon(Icons.person_rounded,
                              size: 28, color: Color(0xFF94A3B8)),
                        ),
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
                            username,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF0284C7),
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fullName.isNotEmpty ? fullName : "Verified Creator",
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "PREVIEW",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0284C7),
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            "This badge will appear next to your name across feeds, stories, reels, chats, and comments.",
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required String planKey,
    required String badgeText,
    required Color badgeColor,
    required String title,
    required String price,
    required String billing,
    required bool isPopular,
    required List<String> benefits,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isPopular
              ? const Color(0xFF0284C7)
              : Colors.white.withValues(alpha: 0.95),
          width: isPopular ? 2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isPopular
                ? const Color(0xFF0284C7).withValues(alpha: 0.14)
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: isPopular ? 16 : 10,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: badgeColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      billing,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Color(0xFFF1F5F9), height: 1),

          // Benefits List
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              children: [
                ...benefits.map((b) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              size: 16, color: Color(0xFF10B981)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              b,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF334155),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPopular
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      "Get Verified • $price",
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
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
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidelineSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<String> points,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...points.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("• ",
                      style: TextStyle(
                          color: Color(0xFF0284C7),
                          fontWeight: FontWeight.w900)),
                  Expanded(
                    child: Text(
                      p,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF475569),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// CHECKOUT MODAL SHEET WITH MULTI-TABLE RECORDING
// ===========================================================================
class _CheckoutModalSheet extends StatefulWidget {
  final String planKey;
  final String planName;
  final String planPrice;
  final double numericAmount;
  final String planBilling;
  final Map<String, dynamic> userProfile;
  final String referralCode;
  final int currentReferrals;
  final VoidCallback onSuccess;

  const _CheckoutModalSheet({
    required this.planKey,
    required this.planName,
    required this.planPrice,
    required this.numericAmount,
    required this.planBilling,
    required this.userProfile,
    required this.referralCode,
    required this.currentReferrals,
    required this.onSuccess,
  });

  @override
  State<_CheckoutModalSheet> createState() => _CheckoutModalSheetState();
}

class _CheckoutModalSheetState extends State<_CheckoutModalSheet> {
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _isSubmitting = false;
  String _paymentMethod = "In-App Review / Direct";

  @override
  void initState() {
    super.initState();
    final fn = widget.userProfile['first_name'] ?? '';
    final ln = widget.userProfile['last_name'] ?? '';
    _fullNameCtrl.text = "$fn $ln".trim();
    _phoneCtrl.text = (widget.userProfile['public_phone'] ??
            widget.userProfile['phone_number'] ??
            '')
        .toString();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitOrder() async {
    final fullName = _fullNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (fullName.isEmpty) {
      _showToast("Please enter your legal or official name.");
      return;
    }
    if (phone.isEmpty || phone.length < 5) {
      _showToast("Please enter a valid Phone or WhatsApp number.");
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final userId = widget.userProfile['id']?.toString() ??
        Supabase.instance.client.auth.currentUser?.id ??
        '';
    final username = widget.userProfile['username']?.toString() ?? 'user';
    final email = widget.userProfile['email']?.toString() ??
        Supabase.instance.client.auth.currentUser?.email ??
        '';

    final reason =
        "Plan: ${widget.planName} (${widget.planPrice}) | Contact: $phone | Name: $fullName | Notes: ${_notesCtrl.text.trim()} | Method: $_paymentMethod";

    try {
      // 1. Dispatch Instant Notification to Admin Telegram
      await TelegramNotificationService.sendVerificationOrderNotification(
        userId: userId,
        username: username,
        fullName: fullName,
        phone: phone,
        planName: widget.planName,
        planPrice: widget.planPrice,
        email: email,
        notes: _notesCtrl.text.trim(),
        referralCode: widget.referralCode,
        currentReferrals: widget.currentReferrals,
      );

      // 2. Real Record in public.user_verifications (with upsert)
      try {
        await Supabase.instance.client.from('user_verifications').upsert({
          'user_id': userId,
          'badge_type': 'blue_tick',
          'badge_label': 'Verified Creator',
          'status': 'pending',
          'is_active': false,
          'verification_reason': reason,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (err) {
        debugPrint("Notice: user_verifications upsert: $err");
      }

      // 3. Real Record in public.subscriptions
      try {
        await Supabase.instance.client.from('subscriptions').upsert({
          'user_id': userId,
          'plan': widget.planKey,
          'status': 'pending',
          'amount': widget.numericAmount,
          'currency': 'USD',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (err) {
        debugPrint("Notice: subscriptions upsert: $err");
      }

      // 4. In-App Notification to User
      try {
        await Supabase.instance.client.from('user_notifications').insert({
          'user_id': userId,
          'title': 'ZEV Blue Order Placed ⭐',
          'message':
              'Your verification order for ${widget.planName} (${widget.planPrice}) has been registered and is under review.',
          'notification_type': 'verification',
          'app_source': 'zev',
          'is_read': false,
        });
      } catch (err) {
        debugPrint("Notice: user_notifications insert: $err");
      }

      if (mounted) {
        Navigator.pop(context); // Close sheet
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showToast("Could not submit order: $e");
      }
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        content: Text(msg, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Order Verification",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF64748B)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Plan Summary Pill
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded,
                      color: Color(0xFF0284C7), size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.planName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0369A1),
                          ),
                        ),
                        Text(
                          widget.planBilling,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF0284C7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    widget.planPrice,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Legal Name
            const Text(
              "Full Legal / Official Name *",
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _fullNameCtrl,
              decoration: InputDecoration(
                hintText: "e.g. Shaheen Safi",
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Phone / WhatsApp
            const Text(
              "Phone or WhatsApp Number *",
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: "e.g. +93 70 123 4567",
                prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Payment Coordinator Preference
            const Text(
              "Payment Coordinator Method",
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: "In-App Review / Direct",
                  child: Text("In-App Review / Direct"),
                ),
                DropdownMenuItem(
                  value: "Telegram / WhatsApp Support Transfer",
                  child: Text("Telegram / WhatsApp Transfer"),
                ),
                DropdownMenuItem(
                  value: "International Card / Crypto",
                  child: Text("Credit Card / Crypto"),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _paymentMethod = val);
              },
            ),

            const SizedBox(height: 20),

            // Submit Button
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
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
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      "Submit & Confirm • ${widget.planPrice}",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
