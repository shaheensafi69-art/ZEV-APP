import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zev_theme.dart';

/// Instagram-grade Professional Account Setup & Conversion Flow.
/// Supports Creator and Business account types with category selection,
/// profile display preferences, contact info configuration, and mandatory public conversion.
class ProfessionalAccountSetupScreen extends StatefulWidget {
  final Map<String, dynamic> currentProfile;

  const ProfessionalAccountSetupScreen({
    super.key,
    required this.currentProfile,
  });

  static Future<Map<String, dynamic>?> open(
    BuildContext context, {
    required Map<String, dynamic> currentProfile,
  }) {
    return Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfessionalAccountSetupScreen(
          currentProfile: currentProfile,
        ),
      ),
    );
  }

  @override
  State<ProfessionalAccountSetupScreen> createState() =>
      _ProfessionalAccountSetupScreenState();
}

class _ProfessionalAccountSetupScreenState
    extends State<ProfessionalAccountSetupScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  int _currentStep = 0; // 0: Intro Carousel, 1: Category, 2: Account Type, 3: Contact Info, 4: Confirmation
  bool _isSaving = false;

  // Step 0 Carousel Controller
  final PageController _carouselCtrl = PageController();
  int _carouselIndex = 0;

  // Step 1: Category state
  String _selectedCategory = '';
  bool _showCategoryOnProfile = true;
  final TextEditingController _categorySearchCtrl = TextEditingController();
  String _categorySearchQuery = '';

  // Step 2: Account Type ('creator' vs 'business')
  String _selectedAccountType = 'creator';

  // Step 3: Business Contact details
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  bool _showContactInfo = true;

  // Instagram-aligned category catalog
  static const List<Map<String, dynamic>> _creatorCategories = [
    {'name': 'Digital Creator', 'icon': Icons.brush_rounded},
    {'name': 'Artist', 'icon': Icons.palette_rounded},
    {'name': 'Musician / Band', 'icon': Icons.music_note_rounded},
    {'name': 'Blogger / Journalist', 'icon': Icons.article_rounded},
    {'name': 'Video Creator & Editor', 'icon': Icons.videocam_rounded},
    {'name': 'Gamer / Streamer', 'icon': Icons.sports_esports_rounded},
    {'name': 'Photographer', 'icon': Icons.camera_alt_rounded},
    {'name': 'Public Figure', 'icon': Icons.star_rounded},
    {'name': 'Educator / Teacher', 'icon': Icons.school_rounded},
    {'name': 'Athlete / Fitness Coach', 'icon': Icons.fitness_center_rounded},
    {'name': 'Software Engineer & Tech', 'icon': Icons.code_rounded},
    {'name': 'Fashion Model / Stylist', 'icon': Icons.checkroom_rounded},
    {'name': 'Financial Trader / Analyst', 'icon': Icons.trending_up_rounded},
    {'name': 'Scientist / Researcher', 'icon': Icons.biotech_rounded},
    {'name': 'Community Leader', 'icon': Icons.people_alt_rounded},
  ];

  static const List<Map<String, dynamic>> _businessCategories = [
    {'name': 'E-Commerce & Online Store', 'icon': Icons.shopping_bag_rounded},
    {'name': 'Technology & Software Company', 'icon': Icons.computer_rounded},
    {'name': 'Restaurant / Café', 'icon': Icons.restaurant_rounded},
    {'name': 'Clothing & Fashion Brand', 'icon': Icons.storefront_rounded},
    {'name': 'Media & News Agency', 'icon': Icons.newspaper_rounded},
    {'name': 'Marketing & Advertising Agency', 'icon': Icons.campaign_rounded},
    {'name': 'Financial & Investment Firm', 'icon': Icons.account_balance_rounded},
    {'name': 'Real Estate Agency', 'icon': Icons.apartment_rounded},
    {'name': 'Health & Medical Clinic', 'icon': Icons.local_hospital_rounded},
    {'name': 'Education & Academy', 'icon': Icons.school_outlined},
    {'name': 'Travel & Tourism Agency', 'icon': Icons.flight_takeoff_rounded},
    {'name': 'Non-Profit / NGO', 'icon': Icons.volunteer_activism_rounded},
    {'name': 'Consulting & Legal Services', 'icon': Icons.gavel_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.currentProfile['category']?.toString() ?? 'Digital Creator';
    _showCategoryOnProfile = widget.currentProfile['show_category_on_profile'] ?? true;
    _showContactInfo = widget.currentProfile['show_contact_info'] ?? true;
    _emailCtrl.text = widget.currentProfile['public_email']?.toString() ??
        widget.currentProfile['email']?.toString() ??
        _supabase.auth.currentUser?.email ??
        '';
    _phoneCtrl.text = widget.currentProfile['public_phone']?.toString() ?? '';
    _addressCtrl.text = widget.currentProfile['location']?.toString() ?? '';

    final currentType = (widget.currentProfile['account_type'] ?? 'creator').toString().toLowerCase();
    if (currentType == 'business') {
      _selectedAccountType = 'business';
    } else {
      _selectedAccountType = 'creator';
    }
  }

  @override
  void dispose() {
    _carouselCtrl.dispose();
    _categorySearchCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredCategories {
    final combined = [..._creatorCategories, ..._businessCategories];
    if (_categorySearchQuery.trim().isEmpty) return combined;
    return combined.where((c) {
      final name = (c['name'] as String).toLowerCase();
      return name.contains(_categorySearchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _completeSetup() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);
    HapticFeedback.heavyImpact();

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final updates = <String, dynamic>{
        'account_type': _selectedAccountType, // 'creator' or 'business'
        'category': _selectedCategory,
        'show_category_on_profile': _showCategoryOnProfile,
        'show_contact_info': _showContactInfo,
        'public_email': _emailCtrl.text.trim(),
        'public_phone': _phoneCtrl.text.trim(),
        'location': _addressCtrl.text.trim(),
        'is_private': false, // Instagram rule: Professional accounts MUST be public
        'updated_at': nowIso,
      };

      await _supabase.from('profiles').update(updates).eq('id', userId);

      // Keep user_privacy_settings in sync
      try {
        await _supabase.from('user_privacy_settings').upsert({
          'user_id': userId,
          'is_private_account': false,
          'updated_at': nowIso,
        }, onConflict: 'user_id');
      } catch (_) {}

      final merged = Map<String, dynamic>.from(widget.currentProfile)..addAll(updates);

      if (!mounted) return;
      setState(() => _isSaving = false);

      _showSuccessDialog(merged);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to switch account: $e"),
            backgroundColor: ZevColors.errorRed,
          ),
        );
      }
    }
  }

  void _showSuccessDialog(Map<String, dynamic> updatedProfile) {
    showDialog(
      context: context,
      barrierDismissible: false,
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
                    color: ZevColors.primaryBlue.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 38,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Welcome, ${_selectedAccountType == 'creator' ? 'Creator' : 'Business'}!",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Your ZEV profile is now upgraded to a Professional ${_selectedAccountType == 'creator' ? 'Creator' : 'Business'} Account. You now have access to real-time Creator Insights, Ads Manager, and audience growth tools.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: ZevColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context, updatedProfile);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  "Go to Profile",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
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
          onPressed: () {
            if (_currentStep > 0) {
              setState(() => _currentStep -= 1);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _getStepTitle(),
          style: const TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w900,
            fontSize: 17,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_currentStep > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  "Step $_currentStep of 3",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _buildCurrentStepView(),
        ),
      ),
      bottomNavigationBar: _buildBottomActionBar(),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return "Professional Account";
      case 1:
        return "Select a Category";
      case 2:
        return "Account Type";
      case 3:
        return "Contact Details";
      default:
        return "Professional Setup";
    }
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildStep0Intro();
      case 1:
        return _buildStep1Category();
      case 2:
        return _buildStep2AccountType();
      case 3:
        return _buildStep3ContactInfo();
      default:
        return const SizedBox();
    }
  }

  // ===========================================================================
  // STEP 0: VALUE PROPOSITION CAROUSEL
  // ===========================================================================
  Widget _buildStep0Intro() {
    final slides = [
      {
        'icon': Icons.insights_rounded,
        'title': 'Learn about your followers',
        'desc': 'Get deep insights into your audience demographics, reach trends, and engagement rate across your posts and reels.',
      },
      {
        'icon': Icons.campaign_rounded,
        'title': 'Reach new audiences',
        'desc': 'Create targeted promotions, sponsor your top reels, and convert viewers into loyal followers and customers.',
      },
      {
        'icon': Icons.contact_mail_rounded,
        'title': 'Get new contact options',
        'desc': 'Add direct Call, SMS, and Email buttons to your profile so clients and collaborators can reach you seamlessly.',
      },
      {
        'icon': Icons.verified_user_rounded,
        'title': 'Showcase your identity',
        'desc': 'Display your professional category badge like Digital Creator or Tech Company directly on your profile header.',
      },
    ];

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _carouselCtrl,
            onPageChanged: (idx) => setState(() => _carouselIndex = idx),
            itemCount: slides.length,
            itemBuilder: (context, idx) {
              final s = slides[idx];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: ZevColors.primaryBlue.withValues(alpha: 0.2),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        s['icon'] as IconData,
                        size: 52,
                        color: ZevColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 36),
                    Text(
                      s['title'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: ZevColors.deepNavy,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      s['desc'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: ZevColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // Dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            slides.length,
            (idx) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _carouselIndex == idx ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _carouselIndex == idx
                    ? ZevColors.primaryBlue
                    : ZevColors.border,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ===========================================================================
  // STEP 1: CATEGORY SELECTION & TOGGLE
  // ===========================================================================
  Widget _buildStep1Category() {
    final list = _filteredCategories;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "What best describes you?",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Categories help people discover what you create or sell on ZEV. You can change this at any time.",
                style: TextStyle(
                  fontSize: 13,
                  color: ZevColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              // Search input
              Container(
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: ZevColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.deepNavy.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        color: ZevColors.textSecondary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _categorySearchCtrl,
                        onChanged: (val) =>
                            setState(() => _categorySearchQuery = val),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ZevColors.deepNavy,
                        ),
                        decoration: const InputDecoration(
                          hintText: "Search categories...",
                          hintStyle: TextStyle(
                            fontSize: 13.5,
                            color: ZevColors.textMuted,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_categorySearchCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _categorySearchCtrl.clear();
                          setState(() => _categorySearchQuery = '');
                        },
                        child: const Icon(
                          Icons.clear_rounded,
                          size: 18,
                          color: ZevColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Display on profile toggle
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: ZevColors.border),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Display on profile",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Show your category badge under your name",
                            style: TextStyle(
                              fontSize: 12,
                              color: ZevColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _showCategoryOnProfile,
                      activeTrackColor: ZevColors.primaryBlue,
                      onChanged: (val) =>
                          setState(() => _showCategoryOnProfile = val),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: ZevColors.border),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            itemCount: list.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final cat = list[idx];
              final catName = cat['name'] as String;
              final catIcon = cat['icon'] as IconData;
              final isSelected = _selectedCategory == catName;

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedCategory = catName);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? ZevColors.primaryBlue.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? ZevColors.primaryBlue
                          : ZevColors.border,
                      width: isSelected ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        catIcon,
                        size: 20,
                        color: isSelected
                            ? ZevColors.primaryBlue
                            : ZevColors.textSecondary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          catName,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelected
                                ? ZevColors.primaryBlue
                                : ZevColors.deepNavy,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: ZevColors.primaryBlue,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // STEP 2: CREATOR VS BUSINESS ACCOUNT TYPE
  // ===========================================================================
  Widget _buildStep2AccountType() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Are you a Creator or a Business?",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Choose the type that best fits your goals on ZEV. You can switch between them at any time.",
            style: TextStyle(
              fontSize: 13,
              color: ZevColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // Option A: Creator
          _buildAccountTypeCard(
            typeKey: 'creator',
            title: 'Creator',
            subtitle: 'Best for public figures, content producers, artists, influencers, and educators.',
            icon: Icons.auto_awesome_rounded,
            features: [
              'Flexible category labels & profile controls',
              'Advanced reels & content performance insights',
              'Collaborator tagging & audience demographic tools',
            ],
          ),

          const SizedBox(height: 16),

          // Option B: Business
          _buildAccountTypeCard(
            typeKey: 'business',
            title: 'Business',
            subtitle: 'Best for retailers, local businesses, brands, organizations, and service providers.',
            icon: Icons.storefront_rounded,
            features: [
              'Public business contact buttons (Call, SMS, Email)',
              'Business address & physical store locator',
              'Integrated Ads Manager campaigns & conversion tracking',
            ],
          ),

          const SizedBox(height: 24),
          // Privacy Note
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF93C5FD),
                width: 1.2,
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.public_rounded,
                  color: Color(0xFF1D4ED8),
                  size: 20,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Note: Professional accounts are public by default so anyone on ZEV can discover your content and business. If your account is currently private, it will become public upon completion.",
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF1E3A8A),
                      height: 1.45,
                      fontWeight: FontWeight.w600,
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

  Widget _buildAccountTypeCard({
    required String typeKey,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<String> features,
  }) {
    final isSelected = _selectedAccountType == typeKey;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedAccountType = typeKey);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? ZevColors.primaryBlue : ZevColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? ZevColors.primaryBlue.withValues(alpha: 0.12)
                  : ZevColors.deepNavy.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? ZevColors.primaryBlue
                        : ZevColors.softSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: isSelected ? Colors.white : ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: isSelected
                          ? ZevColors.primaryBlue
                          : ZevColors.deepNavy,
                    ),
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? ZevColors.primaryBlue
                          : ZevColors.border,
                      width: 2,
                    ),
                    color: isSelected
                        ? ZevColors.primaryBlue
                        : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: ZevColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: ZevColors.border),
            const SizedBox(height: 12),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.done_all_rounded,
                      size: 16,
                      color: ZevColors.secondaryBlue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // STEP 3: CONTACT INFORMATION (PUBLIC BUSINESS DETAILS)
  // ===========================================================================
  Widget _buildStep3ContactInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Review your contact info",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "People can reach out to you using this info. You can edit or hide these details at any time.",
            style: TextStyle(
              fontSize: 13,
              color: ZevColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Display Contact Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ZevColors.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Display contact info",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: ZevColors.deepNavy,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Show direct contact options on your profile",
                        style: TextStyle(
                          fontSize: 12,
                          color: ZevColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _showContactInfo,
                  activeTrackColor: ZevColors.primaryBlue,
                  onChanged: (val) => setState(() => _showContactInfo = val),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Public Email Field
          _buildInputLabel("Public Business Email"),
          _buildContactTextField(
            controller: _emailCtrl,
            hint: "contact@company.com",
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),

          const SizedBox(height: 16),

          // Public Phone Field
          _buildInputLabel("Public Phone Number"),
          _buildContactTextField(
            controller: _phoneCtrl,
            hint: "+1 (555) 000-0000",
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),

          const SizedBox(height: 16),

          // Business Location Field
          _buildInputLabel("Business Address / City"),
          _buildContactTextField(
            controller: _addressCtrl,
            hint: "New York, USA",
            icon: Icons.location_on_outlined,
            keyboardType: TextInputType.streetAddress,
          ),

          const SizedBox(height: 24),

          // Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ZevColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Account Overview",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 10),
                _buildOverviewRow("Type", _selectedAccountType.toUpperCase()),
                const SizedBox(height: 6),
                _buildOverviewRow("Category", _selectedCategory),
                const SizedBox(height: 6),
                _buildOverviewRow("Account Privacy", "Public (Required for Professional)"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: ZevColors.deepNavy,
        ),
      ),
    );
  }

  Widget _buildContactTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required TextInputType keyboardType,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ZevColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ZevColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ZevColors.deepNavy,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  fontSize: 13.5,
                  color: ZevColors.textMuted,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: ZevColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: ZevColors.deepNavy,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // BOTTOM NAVIGATION & ACTIONS
  // ===========================================================================
  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: ZevColors.border)),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            OutlinedButton(
              onPressed: _isSaving
                  ? null
                  : () => setState(() => _currentStep -= 1),
              style: OutlinedButton.styleFrom(
                foregroundColor: ZevColors.deepNavy,
                side: const BorderSide(color: ZevColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              child: const Text(
                "Back",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: ElevatedButton(
              onPressed: _isSaving ? null : _handleNextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: ZevColors.primaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      _currentStep == 3 ? "Complete & Switch" : "Continue",
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleNextStep() {
    HapticFeedback.lightImpact();
    if (_currentStep == 0) {
      setState(() => _currentStep = 1);
    } else if (_currentStep == 1) {
      if (_selectedCategory.isEmpty) {
        _selectedCategory = 'Digital Creator';
      }
      setState(() => _currentStep = 2);
    } else if (_currentStep == 2) {
      setState(() => _currentStep = 3);
    } else if (_currentStep == 3) {
      _completeSetup();
    }
  }
}
