import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/language_service.dart';
import '../../../core/widgets/language_selector_sheet.dart';
import '../../../core/widgets/circular_country_flag.dart';
import '../../../core/widgets/zev_logo.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import '../../main_navigation/screens/zev_main_layout.dart';

class OnboardingSlide {
  final String title;
  final String highlight;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final bool isAppIconHero;

  const OnboardingSlide({
    required this.title,
    required this.highlight,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.isAppIconHero = false,
  });
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  int _currentIndex = 0;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color accentPink = Color(0xFFFF5E8A);
  static const Color softPinkBg = Color(0xFFFFF1F4);
  static const Color darkText = Color(0xFF0F172A);

  final List<OnboardingSlide> _slides = const [
    OnboardingSlide(
      title: "Welcome to",
      highlight: "ZEV Social Network",
      subtitle:
          "Connect with creators, share breathtaking stories, and experience next-gen social media tailored for you.",
      icon: Icons.auto_awesome_rounded,
      gradient: [Color(0xFFFC466B), Color(0xFFFF5E8A)],
      isAppIconHero: true,
    ),
    OnboardingSlide(
      title: "Experience the New",
      highlight: "Feed & Stories",
      subtitle:
          "Express yourself with high-res photo posts, 24-hour stories, and explore trending creators around the globe.",
      icon: Icons.dynamic_feed_rounded,
      gradient: [Color(0xFFFC466B), Color(0xFFFF5E8A)],
    ),
    OnboardingSlide(
      title: "Discover Short",
      highlight: "Viral Reels",
      subtitle:
          "Dive into lightning-fast vertical video feeds. Like with double-tap, share instantly, and join trending audio.",
      icon: Icons.play_circle_fill_rounded,
      gradient: [Color(0xFFE11D48), Color(0xFFFB7185)],
    ),
    OnboardingSlide(
      title: "Instant Direct",
      highlight: "Private Messaging",
      subtitle:
          "Chat with friends in real time with voice notes, photo sharing, delivered/read receipts, and animated emoji reactions.",
      icon: Icons.chat_bubble_rounded,
      gradient: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToGuestFeed() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ZevMainLayout()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F19) : Colors.white,
      body: Stack(
        children: [
          // Background ambient gradient inspired by the squircle app icon
          Positioned(
            top: -size.width * 0.4,
            right: -size.width * 0.3,
            child: Container(
              width: size.width * 1.3,
              height: size.width * 1.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryPink.withValues(alpha: isDark ? 0.12 : 0.18),
                    accentPink.withValues(alpha: isDark ? 0.05 : 0.08),
                    (isDark ? const Color(0xFF0B0F19) : Colors.white)
                        .withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -size.width * 0.3,
            left: -size.width * 0.3,
            child: Container(
              width: size.width * 1.1,
              height: size.width * 1.1,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF5E8A).withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ZEV Logo with white container so the black & pink pop out
                      const ZevLogo(
                        height: 32,
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        borderRadius: 16,
                      ),

                      // Language Selector Pill
                      Row(
                        children: [
                          InkWell(
                            onTap: () => LanguageSelectorSheet.show(context),
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: primaryPink.withValues(alpha: 0.25),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryPink.withValues(alpha: 0.08),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularCountryFlag(
                                    countryCode: LanguageService
                                        .instance
                                        .currentLanguage
                                        .countryCode,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    LanguageService
                                        .instance
                                        .currentLanguage
                                        .code
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: darkText,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.grey,
                                    size: 16,
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

                // Main Carousel PageView
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slides.length,
                    onPageChanged: (index) {
                      setState(() => _currentIndex = index);
                    },
                    itemBuilder: (context, index) {
                      final slide = _slides[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Feature Icon Container
                            slide.isAppIconHero
                                ? ScaleTransition(
                                    scale: _pulseAnimation,
                                    child: Container(
                                      width: 148,
                                      height: 148,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(38),
                                        border: Border.all(
                                          color: primaryPink.withValues(
                                            alpha: 0.35,
                                          ),
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: primaryPink.withValues(
                                              alpha: 0.38,
                                            ),
                                            blurRadius: 32,
                                            offset: const Offset(0, 10),
                                          ),
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.06,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      padding: const EdgeInsets.all(5),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(32),
                                        child: Image.asset(
                                          'assets/512.png',
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 140,
                                    height: 140,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: slide.gradient,
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: slide.gradient.first
                                              .withValues(alpha: 0.35),
                                          blurRadius: 28,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      slide.icon,
                                      size: 68,
                                      color: Colors.white,
                                    ),
                                  ),
                            const SizedBox(height: 36),

                            // Title & Highlight
                            Text(
                              slide.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : darkText,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: slide.gradient,
                              ).createShader(bounds),
                              child: Text(
                                slide.highlight,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Subtitle
                            Text(
                              slide.subtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Carousel Dots Indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _slides.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentIndex == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentIndex == index
                            ? primaryPink
                            : (isDark
                                  ? const Color(0xFF334155)
                                  : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Bottom Action Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // Primary Button: Get Started / Register
                      Container(
                        width: double.infinity,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [primaryPink, accentPink],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: primaryPink.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RegisterScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Create Account",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Secondary Button: Log In
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isDark
                                ? const Color(0xFF131926)
                                : Colors.white,
                            side: BorderSide(
                              color: isDark
                                  ? const Color(0xFF1E293B)
                                  : primaryPink.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            "Log In",
                            style: TextStyle(
                              color: isDark ? Colors.white : darkText,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Guest Explore Button
                      TextButton(
                        onPressed: _navigateToGuestFeed,
                        style: TextButton.styleFrom(
                          foregroundColor: isDark
                              ? Colors.white70
                              : Colors.grey.shade600,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Explore ZEV without account",
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 12,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade700,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
