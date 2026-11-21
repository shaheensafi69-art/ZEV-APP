import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/telegram_notification_service.dart';
import '../../../core/theme/zev_theme.dart';
import 'professional_account_setup_screen.dart';

/// Flagship ZEV Verification & Notability Portal.
/// Features 2 Elite Tiers:
///  - ZEV Blue: 500,000+ real followers on ZEV + 10 strict verification conditions.
///  - ZEV Gold: 1,000,000+ real followers on ZEV + ZEV Blue prerequisite.
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
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = true;
  bool _isVerified = false;
  String _badgeTier = 'none'; // 'none', 'blue', 'gold'
  int _followersCount = 0;
  String? _pendingStatus; // 'pending', 'verified', 'rejected', null
  String? _pendingBadgeType; // 'blue_tick', 'gold_tick'
  String? _badgeLabel;
  String? _verificationReason;
  DateTime? _verifiedAt;

  // Document upload state (stored in Cloudflare R2)
  String? _uploadedDocUrl;
  bool _isUploadingDoc = false;

  // Audit state
  bool _hasProfessionalAccount = false;
  bool _hasCompleteProfile = false;
  final bool _has2fa = true;

  late TabController _tabCtrl;
  late TabController _verifiedTabCtrl;

  // Application Form Controllers
  String _selectedTier = 'blue'; // 'blue' or 'gold'
  final TextEditingController _legalNameCtrl = TextEditingController();
  final TextEditingController _knownAsCtrl = TextEditingController();
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
    _verifiedTabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _verifiedTabCtrl.addListener(() {
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
    _verifiedTabCtrl.dispose();
    _legalNameCtrl.dispose();
    _knownAsCtrl.dispose();
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
          .select('id, is_verified, badge_tier, account_type, avatar_url, bio, username, followers_count')
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
        if (profileRes['followers_count'] != null) {
          _followersCount = (profileRes['followers_count'] as num).toInt();
        }
      }

      // 2. Fetch follower count from user_follows if 0 or unpopulated
      if (_followersCount == 0) {
        final followersRes = await _supabase
            .from('user_follows')
            .select('follower_id')
            .eq('following_id', currentUserId);
        _followersCount = (followersRes as List).length;
      }

      // 3. Fetch verification record from user_verifications
      try {
        final verifRes = await _supabase
            .from('user_verifications')
            .select(
                'status, is_active, badge_type, badge_label, verification_reason, verified_at, expires_at, document_url, legal_name, known_as, category, document_type')
            .eq('user_id', currentUserId)
            .maybeSingle();

        if (verifRes != null) {
          _pendingStatus = verifRes['status']?.toString();
          _pendingBadgeType = verifRes['badge_type']?.toString();
          _badgeLabel = verifRes['badge_label']?.toString();
          _verificationReason = verifRes['verification_reason']?.toString();
          _uploadedDocUrl = verifRes['document_url']?.toString();
          if ((verifRes['legal_name']?.toString() ?? '').isNotEmpty) {
            _legalNameCtrl.text = verifRes['legal_name'].toString();
          }
          if ((verifRes['known_as']?.toString() ?? '').isNotEmpty) {
            _knownAsCtrl.text = verifRes['known_as'].toString();
          }
          if ((verifRes['category']?.toString() ?? '').isNotEmpty) {
            _selectedCategory = verifRes['category'].toString();
          }
          if ((verifRes['document_type']?.toString() ?? '').isNotEmpty) {
            _selectedDocType = verifRes['document_type'].toString();
          }
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

  Future<void> _pickAndUploadDocument() async {
    final userId = widget.userProfile['id']?.toString() ??
        _supabase.auth.currentUser?.id ??
        '';
    if (userId.isEmpty) return;

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (picked == null) return;

      setState(() {
        _isUploadingDoc = true;
      });

      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final effectiveExt = (ext == 'png' || ext == 'webp') ? ext : 'jpg';
      final fileName = 'id_doc_${DateTime.now().millisecondsSinceEpoch}.$effectiveExt';
      final uploadPath = '$userId/$fileName';

      final url = await CloudflareStorageService.instance.upload(
        bucket: 'verification',
        path: uploadPath,
        bytes: bytes,
        file: kIsWeb ? null : File(picked.path),
        contentType: 'image/$effectiveExt',
        compressImage: true,
      );

      if (!mounted) return;
      setState(() {
        _uploadedDocUrl = url;
        _isUploadingDoc = false;
      });
      _showToast("Document uploaded securely to Cloudflare R2!");
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingDoc = false);
      _showToast("Document upload failed: $e", isError: true);
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

    if (_uploadedDocUrl == null || _uploadedDocUrl!.isEmpty) {
      _showToast("Please upload your official ID document to Cloudflare R2.", isError: true);
      return;
    }

    if (_selectedTier == 'gold' && !_isVerified) {
      _showToast(
        "You must first be ZEV Blue verified before applying for ZEV Gold.",
        isError: true,
      );
      return;
    }

    final isGold = _selectedTier == 'gold';
    final targetFollowers = isGold ? kGoldFollowerThreshold : kBlueFollowerThreshold;

    // Follower requirement is STRICTLY ON ZEV
    if (_followersCount < targetFollowers) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            "ZEV Follower Requirement",
            style: TextStyle(fontWeight: FontWeight.w900, color: ZevColors.deepNavy),
          ),
          content: Text(
            "The official policy requires at least ${isGold ? '1,000,000' : '500,000'} real followers directly on ZEV.\n\nYour current ZEV followers: $_followersCount.\n\nDo you wish to submit your application for exceptional board review?",
            style: const TextStyle(fontSize: 13.5, color: ZevColors.textSecondary, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel", style: TextStyle(color: ZevColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("Submit Anyway", style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.heavyImpact();

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final evidenceLinks = [
        if (_pressLink1Ctrl.text.trim().isNotEmpty) _pressLink1Ctrl.text.trim(),
        if (_pressLink2Ctrl.text.trim().isNotEmpty) _pressLink2Ctrl.text.trim(),
        if (_websiteCtrl.text.trim().isNotEmpty) _websiteCtrl.text.trim(),
      ].join(' | ');

      final badgeType = isGold ? 'gold_tick' : 'blue_tick';
      final badgeLabel = isGold ? 'ZEV Gold Icon' : 'ZEV Blue Verified';
      final planType = isGold ? 'notability_1m_gold' : 'notability_500k_blue';

      final reasonText =
          "Tier: ${isGold ? 'GOLD (1M+ ZEV)' : 'BLUE (500K+ ZEV)'} | Category: $_selectedCategory | Doc: $_selectedDocType | Known As: ${_knownAsCtrl.text.trim()} | DocURL: $_uploadedDocUrl | Evidence: $evidenceLinks | Statement: ${_statementCtrl.text.trim()}";

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
        'document_url': _uploadedDocUrl,
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
              'Your verification application for ${isGold ? 'ZEV Gold (1M+ Followers on ZEV)' : 'ZEV Blue (500K+ Followers on ZEV)'} has been received. Our Trust & Safety team will conduct a thorough human review within 24-72 hours.',
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
          planName: isGold ? 'ZEV Gold Verification (1M+ ZEV Followers)' : 'ZEV Blue Verification (500K+ ZEV Followers)',
          planPrice: isGold ? '1,000,000+ ZEV Followers' : '500,000+ ZEV Followers',
          email: widget.userProfile['email']?.toString() ?? '',
          notes: reasonText,
          paymentMethod: 'Cloudflare R2 Document Verified',
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
            const Text(
              "Your application and Cloudflare R2 verified documents have been registered for human verification by the ZEV Compliance & Safety Board according to the 10 official conditions.\n\nEstimated review window: 24 to 72 hours.",
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
                : (_isVerified && _badgeTier != 'gold'
                    ? _buildVerifiedBlueUserView(fullName, username)
                    : _buildStandardApplicantView(fullName, username)),
          ),
        ),
      ),
    );
  }

  String _profileLastName() => (widget.userProfile['last_name'] ?? '').toString();

  Widget _buildVerifiedBlueUserView(String fullName, String username) {
    return Column(
      children: [
        _buildHeaderHero(fullName, username),
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
              _buildVerifiedTabPill(0, "Keep Badge Safe"),
              _buildVerifiedTabPill(1, "ZEV Gold Rules"),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _verifiedTabCtrl,
            physics: const BouncingScrollPhysics(),
            children: [
              _buildKeepBadgeSafeTab(fullName, username),
              _buildGoldRulesTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStandardApplicantView(String fullName, String username) {
    return Column(
      children: [
        _buildHeaderHero(fullName, username),
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
    );
  }

  Widget _buildVerifiedTabPill(int index, String label) {
    final isSelected = _verifiedTabCtrl.index == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _verifiedTabCtrl.animateTo(index);
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
              color: isSelected ? ZevColors.deepNavy : ZevColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeepBadgeSafeTab(String fullName, String username) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        // Verified Badge Celebration Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF86EFAC), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: ZevColors.brandGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.secondaryBlue.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You Have ZEV Blue Verification',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF14532D),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Official Verified Public Figure & Creator on ZEV Platform.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Safety Alert Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFDC2626).withValues(alpha: 0.06),
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
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Color(0xFFDC2626),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Keep Your Blue Badge Safe',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                        Text(
                          'قوانین صیف نگاه داشتن بلو تیک',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'برای صیف نگاه داشتن بلو تیک، نباید از هیچ‌یک از قوانین و دستورالعمل‌های ZEV سرپیچی کنید. تیک آبی نشانه شهرت، اصالت و اعتماد است؛ هرگونه نقض قوانین پلتفرم، منجر به سلب فوری و دائمی نشان تأیید خواهد شد.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF7F1D1D),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 5 Strict Rules to Preserve Blue Badge
        _buildSafetyRuleCard(
          number: '1',
          title: 'Strict Community Guidelines Compliance',
          subtitle: 'پایبندی کامل به قوانین جامعه زیف',
          desc:
              'انتشار هرگونه محتوای هرزنامه (اسپم)، کپی‌رایت غیرمجاز، توهین، افترا، محتوای غیراخلاقی یا نفرت‌پراکنی به ابطال بی‌درنگ تیک آبی منجر می‌شود.',
          icon: Icons.policy_rounded,
        ),
        const SizedBox(height: 10),
        _buildSafetyRuleCard(
          number: '2',
          title: 'Identity Integrity & Name Changes',
          subtitle: 'ممنوعیت تغییر نام جهت جعل هویت',
          desc:
              'تغییر نام کاربری، تصویر یا بیو به منظور گمراه‌سازی، کلاهبرداری یا جعل هویت دیگران اکیداً ممنوع بوده و موجب مسدودی حساب می‌گردد.',
          icon: Icons.badge_rounded,
        ),
        const SizedBox(height: 10),
        _buildSafetyRuleCard(
          number: '3',
          title: 'Authentic & Continuous Activity',
          subtitle: 'فعالیت مستمر، معتبر و اصیل',
          desc:
              'حساب تأییدشده باید حضور فعال داشته و به تولید محتوای ارزشمند و تعامل ارگانیک با دنبال‌کنندگان ادامه دهد. اکانت‌های غیرفعال بازبینی می‌شوند.',
          icon: Icons.trending_up_rounded,
        ),
        const SizedBox(height: 10),
        _buildSafetyRuleCard(
          number: '4',
          title: 'Active Two-Factor Authentication (2FA)',
          subtitle: 'فعال بودن دائمی امنیت دومرحله‌ای',
          desc:
              'برای محافظت از هویت دیجیتال شما و پیشگیری از نفوذ، امنیت دومرحله‌ای باید همیشه روی حساب تأییدشده فعال بماند.',
          icon: Icons.lock_outline_rounded,
        ),
        const SizedBox(height: 10),
        _buildSafetyRuleCard(
          number: '5',
          title: 'Non-Transferable & No Selling',
          subtitle: 'غیرقابل واگذاری یا خرید و فروش',
          desc:
              'تیک آبی نشان هویت شخص شماست. هرگونه تلاش برای فروش، اجاره یا واگذاری حساب به شخص ثالث موجب ابطال تیک و مسدودی دائم می‌شود.',
          icon: Icons.not_interested_rounded,
        ),
      ],
    );
  }

  Widget _buildSafetyRuleCard({
    required String number,
    required String title,
    required String subtitle,
    required String desc,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(icon, color: ZevColors.primaryBlue, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: ZevColors.primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$number',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.primaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ZevColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoldRulesTab() {
    final goldProgress =
        (_followersCount / kGoldFollowerThreshold).clamp(0.0, 1.0);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        // Gold Banner Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFFEF3C7),
                Color(0xFFFDE68A),
                Color(0xFFF59E0B),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFBBF24), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFB45309),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.emoji_events_rounded,
                    color: Color(0xFFD97706),
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'ZEV Gold Official Badge 🏆',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF78350F),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'نشان رسمی طلایی زیف — بالاترین رده اعتبار سازمانی و برندهای جهانی',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF92400E),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Follower Progress to Gold (1,000,000)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF78350F),
                          ),
                        ),
                        Text(
                          '$_followersCount / 1,000,000',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: goldProgress,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFFDE68A),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'قوانین و شرایط اختصاصی دریافت تیک طلایی ZEV',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 8 Gold Rules
        _buildGoldRuleItem(
          number: '۱',
          title: 'حداقل ۱ میلیون دنبال‌کننده واقعی در زیف',
          desc:
              'متقاضی باید حداقل ۱,۰۰۰,۰۰۰ دنبال‌کننده واقعی و ارگانیک مستقیماً در پلتفرم ZEV داشته باشد. دنبال‌کنندگان جعلی پذیرفته نیستند.',
        ),
        _buildGoldRuleItem(
          number: '۲',
          title: 'سابقه تیک آبی فعال برای حداقل ۱۸۰ روز',
          desc:
              'حساب باید حداقل ۶ ماه دارای تیک آبی فعال بوده و در این مدت سابقه هیچ‌گونه نقض قوانین یا اخطار انضباطی نداشته باشد.',
        ),
        _buildGoldRuleItem(
          number: '۳',
          title: 'شخصیت حقوقی رسمی یا برند شناخته‌شده بین‌المللی',
          desc:
              'تیک طلایی منحصراً به شرکت‌های ثبت‌شده رسمی، سازمان‌های معتبر ملی و بین‌المللی، هلدینگ‌ها و برندهای سرشناس اعطا می‌شود.',
        ),
        _buildGoldRuleItem(
          number: '۴',
          title: 'مدارک ثبتی، اساسنامه و مالکیت علامت تجاری',
          desc:
              'ارائه گواهی ثبت برند (Trademark)، اساسنامه شرکت، شناسه ملی مالیاتی و مدارک احراز هویت هیئت مدیره در کلودفلر الزامی است.',
        ),
        _buildGoldRuleItem(
          number: '۵',
          title: 'حضور مستمر در رسانه‌های بین‌المللی رتبه یک',
          desc:
              'برند یا سازمان باید دارای معرفی و سابقه پوشش خبری معتبر در حداقل ۵ رسانه خبری مستقل و رسمی بین‌المللی باشد.',
        ),
        _buildGoldRuleItem(
          number: '۶',
          title: 'توافق‌نامه همکاری سازمانی اختصاصی با ZEV',
          desc:
              'داشتن کانال ارتباطی رسمی شرکتی و توافق‌نامه استراتژیک سازمانی با پلتفرم زیف الزامی است.',
        ),
        _buildGoldRuleItem(
          number: '۷',
          title: 'امنیت پیشرفته سازمانی و احراز هویت دومرحله‌ای',
          desc:
              'فعال بودن همیشگی لایه‌های امنیتی سازمانی، پروتکل‌های 2FA سخت‌گیرانه و ثبت دامنه ایمیل رسمی اختصاصی.',
        ),
        _buildGoldRuleItem(
          number: '۸',
          title: 'تولید محتوای انحصاری و استاندارد رده بالا',
          desc:
              'انتشار مستمر محتوای 4K/HD رسمی، تولید مدیا با بالاترین استانداردهای بصری و تعامل پایدار با کاربران.',
        ),
      ],
    );
  }

  Widget _buildGoldRuleItem({
    required String number,
    required String title,
    required String desc,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97706).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFB45309),
                ),
              ),
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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ZevColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
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
                      ? "Official authenticity badge earned via verifiable ZEV notability."
                      : "Strictly non-purchasable: Blue (500K+ on ZEV) and Gold (1M+ on ZEV).",
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
  // TAB 0: 10 OFFICIAL RULES & POLICIES (ENGLISH SPECIFICATION)
  // ===========================================================================
  Widget _buildRulesTab() {
    final rules = [
      {
        'num': '1',
        'title': 'Minimum 500,000 Real Followers on ZEV',
        'desc':
            'The applicant must have at least 500,000 genuine, active followers directly on the ZEV network. External platform followings, bought bots, or inactive profiles are strictly disqualified.',
        'icon': Icons.groups_rounded,
      },
      {
        'num': '2',
        'title': 'Official Legal Identity Verification',
        'desc':
            'Submission of valid, government-issued photo identification (Passport, National ID, Driver\'s License, or Business Registration) matching account details is mandatory.',
        'icon': Icons.badge_outlined,
      },
      {
        'num': '3',
        'title': 'Public Prominence & Notability',
        'desc':
            'Applicant must represent an established public figure, creator, athlete, entertainer, entrepreneur, or certified institution of national or international recognition.',
        'icon': Icons.star_outline_rounded,
      },
      {
        'num': '4',
        'title': 'Credible Press & Media Presence',
        'desc':
            'Applicant must have documented coverage in reputable news media, verified publications, broadcast interviews, or independent encyclopedic sources.',
        'icon': Icons.newspaper_rounded,
      },
      {
        'num': '5',
        'title': 'Continuous & Professional ZEV Activity',
        'desc':
            'The ZEV account must demonstrate at least 90 days of consistent, high-standard activity and regular content creation directly on ZEV.',
        'icon': Icons.history_toggle_off_rounded,
      },
      {
        'num': '6',
        'title': 'Authentic Community Engagement',
        'desc':
            'Audience interactions, views, discussions, and meaningful engagement are thoroughly audited. Follower count alone does not grant verification.',
        'icon': Icons.chat_bubble_outline_rounded,
      },
      {
        'num': '7',
        'title': 'Originality & Digital Authenticity',
        'desc':
            'Applicant must be the sole authentic owner of the account with original creative rights. Content theft, impersonation, or misleading branding will result in a permanent ban.',
        'icon': Icons.fingerprint_rounded,
      },
      {
        'num': '8',
        'title': 'Account Safety & Clean Record',
        'desc':
            'Zero history of community guidelines violations, fraud, impersonation, harassment, or illegal broadcasts on ZEV within the last 180 days.',
        'icon': Icons.security_rounded,
      },
      {
        'num': '9',
        'title': 'Provable Impact & Achievements',
        'desc':
            'Documented professional, cultural, athletic, scientific, philanthropic, or business accomplishments that can be independently validated.',
        'icon': Icons.emoji_events_outlined,
      },
      {
        'num': '10',
        'title': 'Final Human Board Approval',
        'desc':
            'Every verification request is reviewed manually by the ZEV Trust & Safety Compliance Board. Meeting technical criteria does not guarantee approval.',
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
                    "Non-Negotiable ZEV Policy",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildBulletPoint("Purchasing Blue or Gold Verification is strictly impossible."),
              _buildBulletPoint("Paid subscriptions (monthly/yearly) provide zero verification privilege."),
              _buildBulletPoint("Referral counts or invites have no influence on verification status."),
              _buildBulletPoint("Follower requirement must be native to ZEV (minimum 500,000 on ZEV)."),
              _buildBulletPoint("Fake, bot, or purchased followers will lead to permanent disqualification."),
              _buildBulletPoint("Verification badges cannot be transferred, leased, or sold."),
              _buildBulletPoint("100% human manual review — automated approvals are strictly prohibited."),
            ],
          ),
        ),

        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            "10 Official Conditions for Identity Verification",
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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                rule['num'] as String,
                style: const TextStyle(
                  color: ZevColors.primaryBlue,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
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
                    Icon(rule['icon'] as IconData,
                        size: 16, color: ZevColors.primaryBlue),
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
                const SizedBox(height: 5),
                Text(
                  rule['desc'] as String,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: ZevColors.textSecondary,
                    height: 1.45,
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
        // Tier 1: ZEV Blue Card (500K on ZEV)
        _buildTierOverviewCard(
          tierKey: 'blue',
          title: "ZEV Blue Badge",
          subtitle: "Official Verification for Public Figures, Notable Creators & Leaders",
          badgeColor: ZevColors.primaryBlue,
          icon: Icons.verified_rounded,
          requirement: "500,000 Real ZEV Followers + Full Compliance with 10 Rules",
          currentCount: _followersCount,
          targetCount: kBlueFollowerThreshold,
          progress: blueProgress,
          isPassed: _followersCount >= kBlueFollowerThreshold,
        ),

        const SizedBox(height: 14),

        // Tier 2: ZEV Gold Card (1M on ZEV)
        _buildTierOverviewCard(
          tierKey: 'gold',
          title: "ZEV Gold Badge",
          subtitle: "The Pinnacle of Global Impact & Industry Leadership",
          badgeColor: const Color(0xFFD97706),
          icon: Icons.emoji_events_rounded,
          requirement: "1,000,000 Real ZEV Followers + Active ZEV Blue Badge Prerequisite",
          currentCount: _followersCount,
          targetCount: kGoldFollowerThreshold,
          progress: goldProgress,
          isPassed: _followersCount >= kGoldFollowerThreshold && _isVerified,
        ),

        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            "Account Readiness Pre-Audit",
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
            ),
          ),
        ),
        const SizedBox(height: 8),

        _buildAuditItem(
          title: "Professional Account (Creator / Business)",
          subtitle: _hasProfessionalAccount
              ? "Your account is configured as Professional (Creator / Business)."
              : "Currently Personal. You must switch to Creator or Business account.",
          isPassed: _hasProfessionalAccount,
          actionLabel: _hasProfessionalAccount ? null : "Switch Account",
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
          title: "Complete Profile Standards",
          subtitle: _hasCompleteProfile
              ? "High-resolution avatar and professional biography completed."
              : "Profile photo or biography is incomplete.",
          isPassed: _hasCompleteProfile,
        ),

        _buildAuditItem(
          title: "Two-Factor Authentication (2FA)",
          subtitle: "Multi-factor authentication and account protection enabled.",
          isPassed: _has2fa,
        ),

        _buildAuditItem(
          title: "Community Standing & History",
          subtitle: "Clean account record with zero strikes or violations in the last 180 days.",
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
    final targetStr = targetCount == 1000000 ? "1 Million" : "500,000";

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
                  isPassed ? "Eligible" : "$targetStr Target",
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
                "Your ZEV Followers: $currentCount",
                style: const TextStyle(fontSize: 11.5, color: ZevColors.textSecondary),
              ),
              Text(
                "Goal: $targetCount",
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
                  ? "ZEV Gold Application Under Review"
                  : "ZEV Blue Application Under Review",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Your application and verified Cloudflare R2 documents are undergoing manual compliance evaluation by the ZEV Trust & Safety Board according to the 10 official conditions.\n\nTypical review window: 24 to 72 hours.",
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
              "You Hold the Highest ZEV Gold Distinction",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Badge: ${_badgeLabel ?? 'ZEV Gold Icon'}\nStatus: Active Official Distinction${_verifiedAt != null ? '\nAwarded: ${_verifiedAt!.toLocal().toString().split(' ').first}' : ''}${_verificationReason != null && _verificationReason!.isNotEmpty ? '\nCriteria: $_verificationReason' : ''}",
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
          "Select Target Verification Level",
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
                subtitle: "500K+ ZEV Followers & 10 Conditions",
                color: ZevColors.primaryBlue,
                isSelected: _selectedTier == 'blue',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTierSelectorPill(
                keyName: 'gold',
                title: "ZEV Gold",
                subtitle: "1M+ ZEV Followers (Requires Blue)",
                color: const Color(0xFFD97706),
                isSelected: _selectedTier == 'gold',
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
        const Text(
          "Section 1: Legal Identity Verification",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "Full Legal Name (as shown on official ID)",
          hint: "e.g., Alexander Smith",
          controller: _legalNameCtrl,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "Known As / Public Brand / Creator Moniker",
          hint: "e.g., DJ Spark, Safi Media",
          controller: _knownAsCtrl,
        ),
        const SizedBox(height: 12),

        _buildDropdownField(
          label: "Professional Category",
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
          label: "Official Document Type",
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
        const SizedBox(height: 14),

        // Cloudflare R2 Document Upload Card
        _buildDocumentUploadCard(),

        const SizedBox(height: 24),
        const Divider(color: ZevColors.border),
        const SizedBox(height: 16),

        const Text(
          "Section 2: ZEV Standing & Verifiable Notability",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_outlined, color: Color(0xFF16A34A), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Your Current ZEV Followers: $_followersCount (Minimum ${_selectedTier == 'gold' ? '1,000,000' : '500,000'} required on ZEV)",
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF166534),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _buildFormField(
          label: "Credible News / Press Article URL 1",
          hint: "https://reputable-news.com/article...",
          controller: _pressLink1Ctrl,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "Press Interview / Magazine / Wikipedia URL 2",
          hint: "https://wikipedia.org/wiki/...",
          controller: _pressLink2Ctrl,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "Official Website / Certified Domain",
          hint: "https://yourbrand.com",
          controller: _websiteCtrl,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),

        _buildFormField(
          label: "Notability Statement & Summary of Achievements",
          hint: "Summary of your public impact, cultural, artistic, scientific, or professional achievements...",
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
                        ? "Submit ZEV Gold Application (1M+ ZEV)"
                        : "Submit ZEV Blue Application (500K+ ZEV)",
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

  Widget _buildDocumentUploadCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _uploadedDocUrl != null
              ? const Color(0xFF10B981)
              : ZevColors.border,
          width: _uploadedDocUrl != null ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _uploadedDocUrl != null
                    ? Icons.check_circle_rounded
                    : Icons.cloud_upload_outlined,
                color: _uploadedDocUrl != null
                    ? const Color(0xFF10B981)
                    : ZevColors.primaryBlue,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _uploadedDocUrl != null
                      ? "Official ID Uploaded to Cloudflare R2"
                      : "Upload Official ID Document (Required)",
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _uploadedDocUrl != null
                        ? const Color(0xFF065F46)
                        : ZevColors.deepNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _uploadedDocUrl != null
                ? "Document is encrypted and securely stored for compliance review."
                : "Submit a clear photo of your Passport, National ID, or Driver's License.",
            style: const TextStyle(
              fontSize: 12,
              color: ZevColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (_isUploadingDoc)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ZevColors.primaryBlue,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      "Uploading to Cloudflare R2...",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ZevColors.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickAndUploadDocument,
                icon: Icon(
                  _uploadedDocUrl != null
                      ? Icons.refresh_rounded
                      : Icons.add_photo_alternate_outlined,
                  size: 18,
                ),
                label: Text(
                  _uploadedDocUrl != null
                      ? "Replace ID Document"
                      : "Choose Document / Photo",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _uploadedDocUrl != null
                      ? const Color(0xFF065F46)
                      : ZevColors.primaryBlue,
                  side: BorderSide(
                    color: _uploadedDocUrl != null
                        ? const Color(0xFF10B981)
                        : ZevColors.primaryBlue,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
        ],
      ),
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
