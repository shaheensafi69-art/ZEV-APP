import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_logo.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Next-Generation Welcome Screen for ZEV.
/// Perfectly crafted from the official ZEV Brand Identity:
/// - Primary Blue: #00D4FF
/// - Deep Navy: #080D1A
/// - White: #FFFFFF
/// - Soft Surface: #F5F8FC
/// - Border: #E7EDF5
/// - Secondary Blue: #536DFE
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;
  late final Animation<double> _floatAnimation;
  late final Animation<double> _pulseGlowAnimation;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOutCubic),
    );

    _pulseGlowAnimation = Tween<double>(begin: 0.22, end: 0.40).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  void _handleExplore() {
    HapticFeedback.mediumImpact();
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

    return Scaffold(
      backgroundColor: ZevColors.white,
      body: Stack(
        children: [
          // Ambient Electric Cyan Radial Glow (Top Right)
          Positioned(
            top: -size.width * 0.35,
            right: -size.width * 0.3,
            child: Container(
              width: size.width * 1.25,
              height: size.width * 1.25,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    ZevColors.primaryBlue.withValues(alpha: 0.18),
                    ZevColors.secondaryBlue.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Ambient Soft Ice Glow (Bottom Left)
          Positioned(
            bottom: -size.width * 0.4,
            left: -size.width * 0.35,
            child: Container(
              width: size.width * 1.15,
              height: size.width * 1.15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    ZevColors.secondaryBlue.withValues(alpha: 0.08),
                    ZevColors.primaryBlue.withValues(alpha: 0.04),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          // Main Responsive Content
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),

                      // Top Row: Brand Identity Tag on Left, ZEV on Right
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: ZevColors.softSurface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: ZevColors.border,
                                width: 1.2,
                              ),
                            ),
                            child: const Text(
                              "Brand Identity",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: ZevColors.secondaryBlue,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const ZevLogo(height: 32),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Hero Section: Floating 3D ZEV App Icon
                      AnimatedBuilder(
                        animation: _floatController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, _floatAnimation.value),
                            child: Container(
                              width: 136,
                              height: 136,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(38),
                                color: Colors.white,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 4.0,
                                ),
                                boxShadow: [
                                  // Radiant Electric Cyan Ambient Glow
                                  BoxShadow(
                                    color: ZevColors.primaryBlue.withValues(
                                      alpha: _pulseGlowAnimation.value,
                                    ),
                                    blurRadius: 36,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 14),
                                  ),
                                  // Soft Ambient Shadow
                                  BoxShadow(
                                    color: ZevColors.deepNavy.withValues(
                                      alpha: 0.08,
                                    ),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(4),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(32),
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
                                          fontSize: 54,
                                          fontWeight: FontWeight.w900,
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

                      const SizedBox(height: 36),

                      // Official Headline: Connect. Share. Discover.
                      const Text(
                        "Connect. Share. Discover.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.deepNavy,
                          letterSpacing: -1.0,
                          height: 1.2,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Official Subtitle: A new space for everyone
                      const Text(
                        "A new space for everyone",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: ZevColors.textSecondary,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Official Primary Button: Explore ZEV (Vibrant #00D4FF)
                      Container(
                        width: double.infinity,
                        height: 54,
                        decoration: BoxDecoration(
                          color: ZevColors.primaryBlue,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: ZevColors.primaryBlue.withValues(
                                alpha: 0.40,
                              ),
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
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            "Explore ZEV",
                            style: TextStyle(
                              color: ZevColors.deepNavy,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Official Stats Row: 24/7 Connection & 12.8K Community
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              metric: "24/7",
                              label: "Connection",
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              metric: "12.8K",
                              label: "Community",
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Secondary Action: Log In Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _handleLogin,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: ZevColors.softSurface,
                            side: const BorderSide(
                              color: ZevColors.border,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            "Log In to Existing Account",
                            style: TextStyle(
                              color: ZevColors.deepNavy,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Subtle Terms & Privacy Notice
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          "By continuing, you agree to ZEV's Terms of Service and acknowledge our Privacy Policy.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: ZevColors.textMuted,
                            height: 1.45,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({required String metric, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: ZevColors.softSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZevColors.border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            metric,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ZevColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
