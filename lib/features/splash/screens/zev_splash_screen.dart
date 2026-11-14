import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/services/auth_session_manager.dart';
import '../../../core/services/deep_link_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../main.dart';
import '../../auth/screens/account_standing_screen.dart';
import '../../auth/screens/welcome_screen.dart';
import '../../main_navigation/screens/zev_main_layout.dart';

/// Next-Generation Cinematic Splash Screen for ZEV Social Network.
/// Features:
/// - Official ZEV Deep Navy canvas with electric cyan and royal blue ambient radial blooms
/// - 3D ZEV emblem scale-in & floating hover physics
/// - Custom luxury metallic/cyan gradient wordmark with elegant tracking
/// - Fading brand tagline and glowing progress indicator
/// - Automatic authentication check & buttery-smooth transition to Home or Welcome
class ZevSplashScreen extends StatefulWidget {
  const ZevSplashScreen({super.key});

  @override
  State<ZevSplashScreen> createState() => _ZevSplashScreenState();
}

class _ZevSplashScreenState extends State<ZevSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _pulseController;
  late final AnimationController _shimmerController;

  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _textFadeAnimation;
  late final Animation<Offset> _textSlideAnimation;
  late final Animation<double> _taglineFadeAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Entrance Controller (Logo scale, fade, and slide)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // 2. Pulse Controller (Ambient glow expansion)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    // 3. Shimmer Controller (Metallic highlight sweep)
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 0.85, curve: Curves.easeOut),
      ),
    );

    _textSlideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _taglineFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.65, 1.0, curve: Curves.easeIn),
      ),
    );

    _entranceController.forward();
    _startSessionCheckAndNavigate();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _startSessionCheckAndNavigate() async {
    // Keep splash on screen for ~2000ms for that high-end cinematic experience
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    Widget targetScreen = const WelcomeScreen();
    String? standingNotice;

    try {
      final session = await AuthSessionManager.instance.ensureValidSession();
      if (session != null) {
        final standing = await AuthSessionManager.instance.checkAccountStanding(
          session.user.id,
        );
        if (standing.isAllowed) {
          int initialTabIndex = 0;
          if (kIsWeb) {
            final path = Uri.base.path.toLowerCase();
            final query = Uri.base.queryParameters;
            if (path.contains('messages') ||
                path.contains('chat') ||
                path.contains('direct') ||
                query.containsKey('id') ||
                query.containsKey('conv') ||
                query.containsKey('user')) {
              initialTabIndex = 5;
            } else if (path.contains('explore') || path.contains('search')) {
              initialTabIndex = 1;
            } else if (path.contains('reels')) {
              initialTabIndex = 3;
            } else if (path.contains('profile') || path.contains('@')) {
              initialTabIndex = 4;
            } else if (path.contains('notifications')) {
              initialTabIndex = 6;
            } else if (path.contains('ads') || path.contains('advertise')) {
              initialTabIndex = 7;
            } else if (path.contains('creator') || path.contains('insights')) {
              initialTabIndex = 8;
            } else if (path.contains('drafts') || path.contains('scheduled')) {
              initialTabIndex = 9;
            } else if (path.contains('blue') || path.contains('verification')) {
              initialTabIndex = 10;
            } else if (path.contains('settings') || path.contains('privacy')) {
              initialTabIndex = 11;
            } else if (path.contains('activity') || path.contains('history')) {
              initialTabIndex = 12;
            } else if (path.contains('security') || path.contains('2fa') || path.contains('mfa')) {
              initialTabIndex = 13;
            } else if (path.contains('help') || path.contains('support')) {
              initialTabIndex = 14;
            }
          }
          targetScreen = ZevMainLayout(initialIndex: initialTabIndex);
          unawaited(AuthHelper.syncZevFcmToken(session.user.id));
        } else if (standing.status == AccountStandingStatus.banned) {
          targetScreen = AccountStandingScreen(standing: standing);
        } else {
          standingNotice = standing.reason ??
              'This account is suspended or deactivated.';
          await AuthSessionManager.instance.signOutCurrentDevice();
        }
      }
    } catch (e) {
      debugPrint('Auth check error in splash: $e');
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (context, anim, secAnim) => targetScreen,
        transitionsBuilder: (context, animation, secAnim, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            ),
            child: child,
          );
        },
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.markAppReady();
      if (standingNotice != null && standingNotice.isNotEmpty) {
        final messengerCtx = appNavigatorKey.currentContext;
        if (messengerCtx != null && messengerCtx.mounted) {
          ScaffoldMessenger.of(messengerCtx).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              content: Text(
                standingNotice,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: ZevColors.deepNavy,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Ambient Electric Cyan Radial Glow (Center-Top)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final pulse = _pulseController.value;
                return Positioned(
                  top: size.height * 0.22 - (pulse * 20),
                  child: Container(
                    width: size.width * 0.85 + (pulse * 40),
                    height: size.width * 0.85 + (pulse * 40),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          ZevColors.primaryBlue.withValues(alpha: 0.26 + (pulse * 0.12)),
                          ZevColors.secondaryBlue.withValues(alpha: 0.10 + (pulse * 0.06)),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                );
              },
            ),

            // 2. Ambient Deep Indigo Glow (Bottom)
            Positioned(
              bottom: -size.width * 0.3,
              child: Container(
                width: size.width * 1.2,
                height: size.width * 1.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      ZevColors.secondaryBlue.withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.75],
                  ),
                ),
              ),
            ),

            // 3. Central Brand Identity: 3D Emblem + Wordmark + Tagline
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 3D Emblem with Neon Halo
                  AnimatedBuilder(
                    animation: _entranceController,
                    builder: (context, child) {
                      return FadeTransition(
                        opacity: _fadeAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: ZevColors.primaryBlue.withValues(alpha: 0.45),
                                  blurRadius: 36,
                                  spreadRadius: 4,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: ZevColors.secondaryBlue.withValues(alpha: 0.35),
                                  blurRadius: 28,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset(
                                'assets/icon/icon-512x512.png',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stack) => Container(
                                  decoration: const BoxDecoration(
                                    gradient: ZevColors.brandGradient,
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Z',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 54,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Official ZEV Wordmark with Shimmering Gradient
                  SlideTransition(
                    position: _textSlideAnimation,
                    child: FadeTransition(
                      opacity: _textFadeAnimation,
                      child: AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (context, child) {
                          final shimmer = _shimmerController.value;
                          return ShaderMask(
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                colors: const [
                                  Colors.white,
                                  ZevColors.primaryBlue,
                                  Color(0xFFE0F2FE),
                                  Colors.white,
                                ],
                                stops: [
                                  0.0,
                                  (shimmer - 0.2).clamp(0.0, 1.0),
                                  shimmer.clamp(0.0, 1.0),
                                  1.0,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds);
                            },
                            child: const Text(
                              'ZEV',
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 8.0,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Color(0x6600D4FF),
                                    blurRadius: 18,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Tagline with elegant letter-spacing
                  FadeTransition(
                    opacity: _taglineFadeAnimation,
                    child: const Text(
                      'THE NEXT GENERATION SOCIAL NETWORK',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.2,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 4. Bottom Signature & Glowing Dots
            Positioned(
              bottom: 44,
              child: FadeTransition(
                opacity: _taglineFadeAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sleek glowing progress pulse
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 32,
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [ZevColors.primaryBlue, ZevColors.secondaryBlue],
                            ),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: ZevColors.primaryBlue.withValues(
                                  alpha: 0.5 + (_pulseController.value * 0.4),
                                ),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'CONNECTED • SECURE • INSTANT',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.2,
                        color: Color(0xFF64748B),
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
}

