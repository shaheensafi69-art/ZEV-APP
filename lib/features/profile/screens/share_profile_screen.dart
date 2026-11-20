import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';

/// Ultra-Modern, Instagram-Style "Share Profile & QR Code" Hub for ZEV.
/// Features authentic dual-shadow 3D clay elevation, fully functional and
/// genuine scannable QR code linking directly to the user's ZEV profile URL,
/// interactive color theme switcher, and instant native system sharing.
class ShareProfileScreen extends StatefulWidget {
  final String? userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final String? bio;
  final bool isVerified;
  final String badgeTier;

  const ShareProfileScreen({
    super.key,
    this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    this.bio,
    this.isVerified = false,
    this.badgeTier = 'none',
  });

  @override
  State<ShareProfileScreen> createState() => _ShareProfileScreenState();
}

class _ShareProfileScreenState extends State<ShareProfileScreen> {
  int _colorThemeIndex = 0;

  final List<List<Color>> _themeGradients = [
    // Instagram Sunset Glow
    [const Color(0xFF833AB4), const Color(0xFFFD1D1D), const Color(0xFFFCB045)],
    // ZEV Electric Blue
    [const Color(0xFF0284C7), const Color(0xFF2563EB), const Color(0xFF1E1B4B)],
    // Midnight Cyber
    [const Color(0xFF0F172A), const Color(0xFF1E293B), const Color(0xFF0284C7)],
    // Emerald Aurora
    [const Color(0xFF059669), const Color(0xFF10B981), const Color(0xFF064E3B)],
    // Velvet Purple
    [const Color(0xFF7C3AED), const Color(0xFF9333EA), const Color(0xFF4C1D95)],
    // Ruby Rose
    [const Color(0xFFE11D48), const Color(0xFFF43F5E), const Color(0xFF881337)],
    // Gold Luxury
    [const Color(0xFFD97706), const Color(0xFFF59E0B), const Color(0xFF78350F)],
    // Obsidian Dark
    [const Color(0xFF18181B), const Color(0xFF27272A), const Color(0xFF09090B)],
  ];

  final List<String> _themeNames = [
    "SUNSET",
    "ELECTRIC",
    "MIDNIGHT",
    "EMERALD",
    "VELVET",
    "RUBY",
    "GOLD",
    "DARK",
  ];

  String get _cleanUsername => widget.username.replaceAll('@', '').trim();
  String get _profileUrl => "https://zevapp.com/@$_cleanUsername";
  String get _displayUrl => "zevapp.com/@$_cleanUsername";

  void _cycleColorTheme() {
    HapticFeedback.selectionClick();
    setState(() {
      _colorThemeIndex = (_colorThemeIndex + 1) % _themeGradients.length;
    });
  }

  void _copyProfileLink() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _profileUrl));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF38BDF8), size: 20),
            SizedBox(width: 10),
            Text(
              "Profile link copied to clipboard!",
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  void _shareProfile() {
    HapticFeedback.mediumImpact();
    final displayName = widget.fullName.isNotEmpty ? widget.fullName : "@$_cleanUsername";
    Share.share(
      "Check out $displayName (@$_cleanUsername) on ZEV:\n$_profileUrl",
      subject: "$displayName on ZEV",
    );
  }

  Widget _buildClayCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double borderRadius = 24,
    Color color = Colors.white,
    double depth = 4.0,
    Border? border,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ??
            Border.all(
              color: Colors.white.withValues(alpha: 0.95),
              width: 1.5,
            ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.14),
            blurRadius: depth * 2.8,
            offset: Offset(depth * 0.7, depth * 0.9),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.7),
            blurRadius: depth * 1.8,
            offset: Offset(-depth * 0.6, -depth * 0.6),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isSmall = screenWidth < 360 || screenHeight < 680;

    final activeGradient = _themeGradients[_colorThemeIndex];
    final primaryColor = activeGradient.first;
    final themeName = _themeNames[_colorThemeIndex];

    final isGold = widget.badgeTier == 'gold';
    final isVerified = widget.isVerified || isGold || widget.badgeTier == 'blue';

    final cardWidth = (screenWidth * (isSmall ? 0.88 : 0.84)).clamp(270.0, 360.0);
    final avatarSize = isSmall ? 68.0 : 80.0;
    final qrSize = (isSmall ? 150.0 : 185.0).clamp(130.0, 200.0);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: activeGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isSmall ? 12 : 18,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close Button
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                      },
                      child: _buildClayCard(
                        borderRadius: 14,
                        depth: 2.8,
                        color: Colors.white.withValues(alpha: 0.22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.45),
                          width: 1.4,
                        ),
                        padding: const EdgeInsets.all(9),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),

                    // Color Theme Switcher Pill
                    GestureDetector(
                      onTap: _cycleColorTheme,
                      child: _buildClayCard(
                        borderRadius: 20,
                        depth: 2.8,
                        color: Colors.white.withValues(alpha: 0.22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.45),
                          width: 1.4,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmall ? 12 : 16,
                          vertical: 7,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.palette_outlined,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              themeName,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isSmall ? 11 : 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Placeholder to maintain balance
                    const SizedBox(width: 44),
                  ],
                ),
              ),

              // Central Instagram-Style Profile Card
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmall ? 12 : 20,
                      vertical: isSmall ? 6 : 14,
                    ),
                    child: GestureDetector(
                      onTap: _cycleColorTheme,
                      child: _buildClayCard(
                        borderRadius: 32,
                        depth: 6.0,
                        color: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: isSmall ? 20 : 26,
                          horizontal: isSmall ? 16 : 22,
                        ),
                        child: SizedBox(
                          width: cardWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Top Brand Header
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.bolt_rounded, size: 14, color: primaryColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          "ZEV PROFILE",
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w900,
                                            color: primaryColor,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: isSmall ? 12 : 16),

                              // Avatar with Dynamic Theme Gradient Ring
                              Container(
                                width: avatarSize + 10,
                                height: avatarSize + 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: activeGradient,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: primaryColor.withValues(alpha: 0.35),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(3.0),
                                  child: ClipOval(
                                    child: widget.avatarUrl.isNotEmpty
                                        ? ZevCachedImage.avatar(
                                            imageUrl: widget.avatarUrl,
                                            size: avatarSize,
                                          )
                                        : Container(
                                            color: const Color(0xFFF1F5F9),
                                            child: Icon(
                                              Icons.person,
                                              color: const Color(0xFF94A3B8),
                                              size: avatarSize * 0.55,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              SizedBox(height: isSmall ? 10 : 14),

                              // Full Name
                              Text(
                                widget.fullName.isNotEmpty
                                    ? widget.fullName
                                    : "@$_cleanUsername",
                                style: TextStyle(
                                  fontSize: isSmall ? 17 : 20,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF0F172A),
                                  letterSpacing: -0.3,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),

                              // Username Handle + Verification Badge
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "@$_cleanUsername",
                                    style: TextStyle(
                                      fontSize: isSmall ? 12.5 : 14,
                                      fontWeight: FontWeight.w800,
                                      color: primaryColor,
                                    ),
                                  ),
                                  if (isVerified) ...[
                                    const SizedBox(width: 5),
                                    Icon(
                                      isGold
                                          ? Icons.emoji_events_rounded
                                          : Icons.verified_rounded,
                                      size: 16,
                                      color: isGold
                                          ? const Color(0xFFF59E0B)
                                          : ZevColors.primaryBlue,
                                    ),
                                  ],
                                ],
                              ),

                              // Optional Bio Snippet
                              if (widget.bio != null && widget.bio!.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Text(
                                    widget.bio!.trim(),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF64748B),
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                              SizedBox(height: isSmall ? 14 : 18),

                              // Scannable Profile QR Code
                              _buildClayCard(
                                borderRadius: 22,
                                depth: 2.8,
                                color: const Color(0xFFF8FAFC),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                  width: 1.4,
                                ),
                                padding: EdgeInsets.all(isSmall ? 10 : 14),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    QrImageView(
                                      data: _profileUrl,
                                      version: QrVersions.auto,
                                      size: qrSize,
                                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                                      eyeStyle: QrEyeStyle(
                                        eyeShape: QrEyeShape.square,
                                        color: const Color(0xFF0F172A),
                                      ),
                                      dataModuleStyle: const QrDataModuleStyle(
                                        dataModuleShape: QrDataModuleShape.circle,
                                        color: Color(0xFF0F172A),
                                      ),
                                      gapless: true,
                                    ),
                                    // Center ZEV Watermark Emblem
                                    Container(
                                      width: isSmall ? 32 : 38,
                                      height: isSmall ? 32 : 38,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: primaryColor,
                                          width: 2.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.15),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          "Z",
                                          style: TextStyle(
                                            color: primaryColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: isSmall ? 17 : 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: isSmall ? 14 : 18),

                              // Direct Profile Link Chip (Tap to Copy)
                              GestureDetector(
                                onTap: _copyProfileLink,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.link_rounded,
                                        size: 16,
                                        color: Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          _displayUrl,
                                          style: TextStyle(
                                            fontSize: isSmall ? 11.5 : 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF0F172A),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.copy_rounded,
                                        size: 14,
                                        color: primaryColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Instagram-Style Action Buttons
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isSmall ? 14 : 20,
                  6,
                  isSmall ? 14 : 20,
                  isSmall ? 12 : 20,
                ),
                child: Row(
                  children: [
                    // Copy Link Button
                    Expanded(
                      child: GestureDetector(
                        onTap: _copyProfileLink,
                        child: _buildClayCard(
                          borderRadius: 16,
                          depth: 3.2,
                          color: Colors.white.withValues(alpha: 0.2),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.45),
                            width: 1.4,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.link_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "Copy Link",
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: isSmall ? 12.5 : 13.5,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Share Profile Button
                    Expanded(
                      child: GestureDetector(
                        onTap: _shareProfile,
                        child: _buildClayCard(
                          borderRadius: 16,
                          depth: 3.2,
                          color: Colors.white,
                          border: Border.all(
                            color: Colors.white,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.share_rounded,
                                size: 18,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "Share Profile",
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: isSmall ? 12.5 : 13.5,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
