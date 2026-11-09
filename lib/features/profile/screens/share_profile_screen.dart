import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/widgets/zev_cached_image.dart';

/// Ultra-Modern, 100% Tactile Claymorphic "Share Profile & QR Code" Hub for ZEV.
/// Features authentic dual-shadow 3D clay elevation, fully functional and
/// genuine scannable QR code generation, interactive color palette customization,
/// responsive geometry for small and large screens, and instant referral sharing.
class ShareProfileScreen extends StatefulWidget {
  final String? userId;
  final String username;
  final String fullName;
  final String avatarUrl;

  const ShareProfileScreen({
    super.key,
    this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
  });

  @override
  State<ShareProfileScreen> createState() => _ShareProfileScreenState();
}

class _ShareProfileScreenState extends State<ShareProfileScreen> {
  int _colorThemeIndex = 0;

  final List<List<Color>> _themeGradients = [
    [const Color(0xFF0284C7), const Color(0xFF0369A1), const Color(0xFF0F172A)],
    [const Color(0xFF7C3AED), const Color(0xFF4F46E5), const Color(0xFF0F172A)],
    [const Color(0xFF059669), const Color(0xFF0D9488), const Color(0xFF0F172A)],
    [const Color(0xFFE11D48), const Color(0xFFBE123C), const Color(0xFF0F172A)],
    [const Color(0xFF0F172A), const Color(0xFF1E293B), const Color(0xFF334155)],
  ];

  String get _referralCode => widget.username.toLowerCase();
  String get _referralLink => "https://www.zevapp.com/join?ref=$_referralCode";

  void _cycleColorTheme() {
    HapticFeedback.selectionClick();
    setState(() {
      _colorThemeIndex = (_colorThemeIndex + 1) % _themeGradients.length;
    });
  }

  void _copyLink() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _referralLink));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF38BDF8), size: 20),
            SizedBox(width: 10),
            Text(
              "Profile deep link copied to clipboard!",
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

  void _copyReferralCode() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _referralCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
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
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  void _shareProfile() {
    HapticFeedback.mediumImpact();
    Share.share(
      "Connect with ${widget.fullName.isNotEmpty ? widget.fullName : widget.username} (@${widget.username}) on ZEV!\n"
      "Download or open the app directly with my referral code [$_referralCode]:\n"
      "$_referralLink",
      subject: "${widget.fullName} on ZEV",
    );
  }

  // ---------------------------------------------------------------------------
  // Core Claymorphic Elevation Helper
  // ---------------------------------------------------------------------------
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
          // Dark tactile drop shadow (bottom-right)
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.12),
            blurRadius: depth * 2.8,
            offset: Offset(depth * 0.7, depth * 0.9),
          ),
          // Crisp glossy white ambient light (top-left)
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

    // Responsive dimensions
    final cardWidth = (screenWidth * (isSmall ? 0.88 : 0.82)).clamp(260.0, 360.0);
    final avatarSize = isSmall ? 68.0 : 82.0;
    final qrSize = (isSmall ? 150.0 : 185.0).clamp(130.0, 200.0);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: activeGradient,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ---------------------------------------------------------------
              // Clay Top Bar
              // ---------------------------------------------------------------
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isSmall ? 12 : 18,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Clay Close Button
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

                    // Clay Color Theme Switcher
                    GestureDetector(
                      onTap: _cycleColorTheme,
                      child: _buildClayCard(
                        borderRadius: 18,
                        depth: 2.8,
                        color: Colors.white.withValues(alpha: 0.22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.45),
                          width: 1.4,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmall ? 10 : 14,
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
                            const SizedBox(width: 6),
                            Text(
                              "COLOR",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isSmall ? 10.5 : 11.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Balance placeholder
                    const SizedBox(width: 44),
                  ],
                ),
              ),

              // ---------------------------------------------------------------
              // Central Scrollable Clay QR Hero Card
              // ---------------------------------------------------------------
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
                              // 1. 3D Tactile Clay Avatar Well
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: avatarSize + 12,
                                    height: avatarSize + 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(
                                          color: primaryColor
                                              .withValues(alpha: 0.35),
                                          blurRadius: 18,
                                          offset: const Offset(0, 4),
                                        ),
                                        const BoxShadow(
                                          color: Colors.white,
                                          blurRadius: 10,
                                          offset: Offset(-3, -3),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: primaryColor,
                                        width: 2.8,
                                      ),
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
                                ],
                              ),
                              SizedBox(height: isSmall ? 10 : 14),

                              // 2. Full Name & @Username
                              Text(
                                widget.fullName.isNotEmpty
                                    ? widget.fullName
                                    : "@${widget.username}",
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
                              const SizedBox(height: 2),
                              Text(
                                "@${widget.username}",
                                style: TextStyle(
                                  fontSize: isSmall ? 12.5 : 14,
                                  fontWeight: FontWeight.w800,
                                  color: primaryColor,
                                ),
                              ),
                              SizedBox(height: isSmall ? 14 : 18),

                              // 3. GENUINE, REAL SCANNABLE QR CODE
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
                                    // Real QR Image View
                                    QrImageView(
                                      data: _referralLink,
                                      version: QrVersions.auto,
                                      size: qrSize,
                                      errorCorrectionLevel:
                                          QrErrorCorrectLevel.M,
                                      eyeStyle: QrEyeStyle(
                                        eyeShape: QrEyeShape.square,
                                        color: const Color(0xFF0F172A),
                                      ),
                                      dataModuleStyle: const QrDataModuleStyle(
                                        dataModuleShape:
                                            QrDataModuleShape.circle,
                                        color: Color(0xFF0F172A),
                                      ),
                                      gapless: true,
                                    ),

                                    // Center ZEV Network Watermark Badge
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
                                            color: Colors.black
                                                .withValues(alpha: 0.15),
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
                              SizedBox(height: isSmall ? 12 : 16),

                              // 4. Referral Code Box (Pill Container with Copy)
                              GestureDetector(
                                onTap: _copyReferralCode,
                                child: _buildClayCard(
                                  borderRadius: 14,
                                  depth: 2.0,
                                  color: const Color(0xFFF1F5F9),
                                  border: Border.all(
                                    color: const Color(0xFFCBD5E1),
                                    width: 1.2,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.confirmation_number_outlined,
                                        size: 15,
                                        color: Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          "Code: $_referralCode",
                                          style: TextStyle(
                                            fontSize: isSmall ? 11.5 : 12.5,
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFF0F172A),
                                            fontFamily: 'monospace',
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

              // ---------------------------------------------------------------
              // Clay Bottom Action Buttons
              // ---------------------------------------------------------------
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isSmall ? 14 : 20,
                  6,
                  isSmall ? 14 : 20,
                  isSmall ? 12 : 20,
                ),
                child: Row(
                  children: [
                    // Copy Link Clay Button
                    Expanded(
                      child: GestureDetector(
                        onTap: _copyLink,
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

                    // Share Profile Clay Button
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
