import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/apple_sign_in_button.dart';
import '../../../core/widgets/zev_logo.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Flagship Serene Welcome & Onboarding Screen for ZEV.
/// Engineered to provide an immediate sense of peace, clarity, and trust:
/// - Soothing multi-layered ambient radial breathing orbs
/// - Zen ripple aura around the signature 3D electric ZEV icon
/// - Interactive auto-sliding serenity highlight cards
/// - Ergonomic high-contrast claymorphic CTA buttons (Get Started, Google, Login)
/// - Responsive design with zero overflow on all screen sizes
class WelcomeScreen extends StatefulWidget {
  final VoidCallback? onLoginTap;
  final VoidCallback? onRegisterTap;
  final VoidCallback? onGuestTap;

  const WelcomeScreen({
    super.key,
    this.onLoginTap,
    this.onRegisterTap,
    this.onGuestTap,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  // Breathing animation controller for zen ambient glow & ripple
  late final AnimationController _breathingController;
  late final Animation<double> _breatheAnimation;
  late final Animation<double> _glowAnimation;
  late final Animation<double> _rippleScaleAnimation;

  // Staggered entry animation controller
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  // Carousel controller for value propositions
  late final PageController _pageController;
  int _activePageIndex = 0;
  Timer? _carouselAutoTimer;

  final List<Map<String, dynamic>> _serenityCards = [
    {
      'icon': Icons.spa_rounded,
      'title': 'Mindful & Clutter-Free',
      'subtitle':
          'A serene space designed for authentic moments, stories, and genuine connection without overwhelming noise.',
      'accentColor': const Color(0xFF00D4FF),
    },
    {
      'icon': Icons.security_rounded,
      'title': 'Privacy & Peace of Mind',
      'subtitle':
          'Built with end-to-end respect for your privacy. Your personal memories and connections stay entirely yours.',
      'accentColor': const Color(0xFF536DFE),
    },
    {
      'icon': Icons.auto_awesome_rounded,
      'title': 'Inspiring Expression',
      'subtitle':
          'Share photos, immersive 4K reels, and thoughts with a creative global community that truly values authenticity.',
      'accentColor': const Color(0xFF00C853),
    },
  ];

  @override
  void initState() {
    super.initState();

    // 1. Organic Breathing Animation (4 seconds continuous cycle)
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);

    _breatheAnimation = Tween<double>(begin: -8.0, end: 8.0).animate(
      CurvedAnimation(
        parent: _breathingController,
        curve: Curves.easeInOutSine,
      ),
    );

    _glowAnimation = Tween<double>(begin: 0.20, end: 0.42).animate(
      CurvedAnimation(
        parent: _breathingController,
        curve: Curves.easeInOutSine,
      ),
    );

    _rippleScaleAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(
        parent: _breathingController,
        curve: Curves.easeInOutSine,
      ),
    );

    // 2. Staggered Entrance
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: Curves.easeOutCubic,
      ),
    );

    _entryController.forward();

    // 3. Carousel Auto-scroll
    _pageController = PageController();
    _startCarouselTimer();
  }

  void _startCarouselTimer() {
    _carouselAutoTimer?.cancel();
    _carouselAutoTimer = Timer.periodic(const Duration(milliseconds: 4800), (
      timer,
    ) {
      if (!mounted || !_pageController.hasClients) return;
      final nextIndex = (_activePageIndex + 1) % _serenityCards.length;
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _carouselAutoTimer?.cancel();
    _pageController.dispose();
    _breathingController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  void _handleExplore() {
    HapticFeedback.lightImpact();
    if (widget.onRegisterTap != null) {
      widget.onRegisterTap!();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RegisterScreen()),
      );
    }
  }

  void _handleLogin() {
    HapticFeedback.lightImpact();
    if (widget.onLoginTap != null) {
      widget.onLoginTap!();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Ambient Zen Gradient 1: Calming Electric Cyan Glow (Top-Right)
          Positioned(
            top: -size.width * 0.45,
            right: -size.width * 0.35,
            child: AnimatedBuilder(
              animation: _breathingController,
              builder: (context, _) {
                return Container(
                  width: size.width * 1.35,
                  height: size.width * 1.35,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF00D4FF).withValues(
                          alpha: _glowAnimation.value * 0.55,
                        ),
                        const Color(0xFFE0F2FE).withValues(alpha: 0.35),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),

          // Ambient Zen Gradient 2: Peaceful Sky Blue Glow (Center-Left)
          Positioned(
            bottom: size.height * 0.18,
            left: -size.width * 0.4,
            child: AnimatedBuilder(
              animation: _breathingController,
              builder: (context, _) {
                return Container(
                  width: size.width * 1.25,
                  height: size.width * 1.25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF536DFE).withValues(
                          alpha: _glowAnimation.value * 0.28,
                        ),
                        const Color(0xFFF0F7FF).withValues(alpha: 0.4),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),

          // Ambient Zen Gradient 3: Soft Pearl Grounding Glow (Bottom-Right)
          Positioned(
            bottom: -size.width * 0.3,
            right: -size.width * 0.2,
            child: Container(
              width: size.width * 0.9,
              height: size.width * 0.9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00D4FF).withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),

          // Main Responsive Content
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(height: isSmallScreen ? 10 : 16),

                          // Top Navigation & Peaceful Brand Badge
                          _buildTopBar(),

                          SizedBox(height: isSmallScreen ? 20 : 32),

                          // Hero Section: Floating 3D ZEV App Icon with Zen Aura
                          _buildFloatingHeroIcon(isSmallScreen),

                          SizedBox(height: isSmallScreen ? 24 : 32),

                          // Calming Brand Title & Subtitle
                          _buildHeadlines(),

                          SizedBox(height: isSmallScreen ? 18 : 26),

                          // Interactive Serenity Highlights Carousel
                          _buildSerenityCarousel(isSmallScreen),

                          SizedBox(height: isSmallScreen ? 22 : 30),

                          // Primary Action Button: "Get Started"
                          _buildGetStartedButton(),

                          // Apple Sign-In Action on iOS & macOS
                          if (!kIsWeb &&
                              (defaultTargetPlatform == TargetPlatform.iOS ||
                                  defaultTargetPlatform == TargetPlatform.macOS)) ...[
                            const SizedBox(height: 12),
                            AppleSignInButton(
                              text: "Continue with Apple",
                              onError: (msg) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(msg),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: const Color(0xFFDC2626),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],

                          const SizedBox(height: 12),

                          // Secondary Action: "Log In"
                          _buildLoginButton(),

                          SizedBox(height: isSmallScreen ? 16 : 22),

                          // Serene Trust Footnote
                          _buildTrustFootnote(),

                          SizedBox(height: isSmallScreen ? 16 : 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Top Bar with Serene Status Pill and Brand Logo
  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE2E8F0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _breathingController,
                builder: (context, _) {
                  return Container(
                    width: 7.5,
                    height: 7.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF00D4FF),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(
                            alpha: _glowAnimation.value,
                          ),
                          blurRadius: 6,
                          spreadRadius: 1.5,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              const Text(
                "A Peaceful Social Space",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.deepNavy,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        const ZevLogo(height: 28),
      ],
    );
  }

  /// Floating 3D Icon with Radiant Ripple Halo
  Widget _buildFloatingHeroIcon(bool isSmallScreen) {
    final double iconSize = isSmallScreen ? 116 : 134;

    return AnimatedBuilder(
      animation: _breathingController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _breatheAnimation.value),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Ripple Ring 1 (Zen Expansion)
              Transform.scale(
                scale: _rippleScaleAnimation.value,
                child: Container(
                  width: iconSize + 48,
                  height: iconSize + 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00D4FF).withValues(
                        alpha: (0.42 - _glowAnimation.value).clamp(0.08, 0.22),
                      ),
                      width: 1.5,
                    ),
                  ),
                ),
              ),

              // Outer Ripple Ring 2 (Inner Halo)
              Container(
                width: iconSize + 22,
                height: iconSize + 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.65),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withValues(
                        alpha: _glowAnimation.value * 0.7,
                      ),
                      blurRadius: 36,
                      spreadRadius: 4,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
              ),

              // Flagship 3D ZEV Bird Icon
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(iconSize * 0.32),
                  color: Colors.white,
                  border: Border.all(
                    color: Colors.white,
                    width: 3.5,
                  ),
                  boxShadow: [
                    // Primary Electric Cyan Glow
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withValues(
                        alpha: _glowAnimation.value,
                      ),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                    // Ambient Soft Shadow
                    BoxShadow(
                      color: const Color(0xFF080D1A).withValues(alpha: 0.09),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(iconSize * 0.28),
                  child: Image.asset(
                    'assets/icon/icon-512x512.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      decoration: const BoxDecoration(
                        gradient: ZevColors.brandGradient,
                      ),
                      child: const Center(
                        child: Text(
                          'Z',
                          style: TextStyle(
                            color: ZevColors.deepNavy,
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Official Headlines
  Widget _buildHeadlines() {
    return Column(
      children: [
        const Text(
          "Connect. Share. Discover.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            letterSpacing: -0.9,
            height: 1.22,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "A calm, authentic social world crafted for you.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// Serenity Carousel displaying calming value cards
  Widget _buildSerenityCarousel(bool isSmallScreen) {
    return Column(
      children: [
        SizedBox(
          height: isSmallScreen ? 94 : 106,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) {
              setState(() => _activePageIndex = idx);
            },
            itemCount: _serenityCards.length,
            itemBuilder: (context, index) {
              final card = _serenityCards[index];
              final IconData icon = card['icon'];
              final String title = card['title'];
              final String subtitle = card['subtitle'];
              final Color accent = card['accentColor'];

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.035),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: accent, size: 23),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.deepNavy,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              height: 1.35,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // Carousel Dot Indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_serenityCards.length, (idx) {
            final isActive = idx == _activePageIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3.5),
              height: 6,
              width: isActive ? 22 : 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: isActive
                    ? const Color(0xFF00D4FF)
                    : const Color(0xFFCBD5E1),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// Primary Action: "Explore ZEV" / "Get Started"
  Widget _buildGetStartedButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF00D4FF),
            Color(0xFF0084FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D4FF).withValues(alpha: 0.38),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _handleExplore,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Get Started",
              style: TextStyle(
                color: ZevColors.deepNavy,
                fontSize: 16.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_rounded,
              color: ZevColors.deepNavy,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// Secondary Action: "Log In"
  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: _handleLogin,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(
            color: Color(0xFFE2E8F0),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
        child: const Text(
          "I already have an account • Log In",
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }

  /// Trust footnote
  Widget _buildTrustFootnote() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 13,
              color: const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 5),
            const Text(
              "Encrypted • Private • Community First",
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          "By continuing, you agree to ZEV's Terms & acknowledge our Privacy Policy.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF94A3B8),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
