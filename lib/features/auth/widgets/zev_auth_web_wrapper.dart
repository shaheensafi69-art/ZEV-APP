import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/zev_logo.dart';

/// Flagship Desktop Web Auth Wrapper for ZEV.
/// On Mobile (< 960px): Renders the native mobile auth layout with 100% fidelity.
/// On Desktop Web (>= 960px): Upgrades the experience to a world-class split-screen
/// layout inspired by Instagram Web & Linear (Left: High-impact Brand Showcase,
/// Right: Centered Claymorphic Form Canvas).
class ZevAuthWebWrapper extends StatefulWidget {
  final Widget child;

  const ZevAuthWebWrapper({
    super.key,
    required this.child,
  });

  @override
  State<ZevAuthWebWrapper> createState() => _ZevAuthWebWrapperState();
}

class _ZevAuthWebWrapperState extends State<ZevAuthWebWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.15, end: 0.35).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = kIsWeb && screenWidth >= 960;

    // Mobile / Tablet: Preserve existing phone layout 100%
    if (!isDesktop) {
      return widget.child;
    }

    // Desktop Web: Split-screen Flagship Design
    return Scaffold(
      backgroundColor: const Color(0xFF080D1A),
      body: Row(
        children: [
          // 1. Left Side: Luxurious Brand Hero Showcase
          Expanded(
            flex: 5,
            child: _buildDesktopHero(context),
          ),

          // 2. Right Side: Centered Form Container
          Expanded(
            flex: 5,
            child: Container(
              height: double.infinity,
              color: const Color(0xFFF8FAFC),
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                            blurRadius: 30,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 32,
                      ),
                      child: widget.child,
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

  /// High-impact visual hero showcase for Desktop Web
  Widget _buildDesktopHero(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF080D1A),
      ),
      child: Stack(
        children: [
          // Ambient Radial Glowing Mesh 1 (Cyan)
          Positioned(
            top: -120,
            left: -80,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, _) => Container(
                width: 520,
                height: 520,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF00D4FF).withValues(alpha: _pulseAnim.value),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.75],
                  ),
                ),
              ),
            ),
          ),

          // Ambient Radial Glowing Mesh 2 (Indigo)
          Positioned(
            bottom: -100,
            right: -60,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, _) => Container(
                width: 480,
                height: 480,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF536DFE).withValues(
                        alpha: _pulseAnim.value * 0.8,
                      ),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
            ),
          ),

          // Content Column
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Brand Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: const ZevLogo(height: 36),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              color: Color(0xFF00D4FF),
                              size: 14,
                            ),
                            SizedBox(width: 5),
                            Text(
                              "OFFICIAL WEB",
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF00D4FF),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const Spacer(flex: 2),

                  // Powerful Headline
                  const Text(
                    "The Next Generation",
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1.0,
                      height: 1.15,
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF00D4FF), Color(0xFF818CF8)],
                    ).createShader(bounds),
                    child: const Text(
                      "Social Network",
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1.2,
                        height: 1.15,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    "Experience authentic moments, ultra-clear 4K reels, end-to-end encrypted chats, and connect with inspiring creators worldwide.",
                    style: TextStyle(
                      fontSize: 15.5,
                      color: Color(0xFF94A3B8),
                      height: 1.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),

                  const SizedBox(height: 36),

                  // 3 Feature Showcase Cards
                  _buildFeatureBadge(
                    icon: Icons.play_circle_fill_rounded,
                    title: "Immersive 4K Reels & Stories",
                    subtitle: "Zero-lag high-framerate creator video streaming",
                    color: const Color(0xFF00D4FF),
                  ),
                  const SizedBox(height: 14),
                  _buildFeatureBadge(
                    icon: Icons.shield_rounded,
                    title: "End-to-End Encrypted Messaging",
                    subtitle: "Ultra-private chats, voice notes & HD calls",
                    color: const Color(0xFF536DFE),
                  ),
                  const SizedBox(height: 14),
                  _buildFeatureBadge(
                    icon: Icons.auto_awesome_rounded,
                    title: "Verified Creators & Communities",
                    subtitle: "Genuine interactions without algorithm noise",
                    color: const Color(0xFF10B981),
                  ),

                  const Spacer(flex: 3),

                  // Bottom Trust Badge
                  Row(
                    children: [
                      const Icon(
                        Icons.lock_rounded,
                        color: Color(0xFF64748B),
                        size: 15,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Protected by Google Cloud & Supabase Infrastructure",
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBadge({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
