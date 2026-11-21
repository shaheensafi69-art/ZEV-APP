import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/services/social_graph_service.dart';
import 'share_profile_screen.dart';
import 'edit_profile_screen.dart';

/// Fullscreen Instagram-Style Profile Picture Viewer.
/// Matches official ZEV deep-dark aesthetic with 4 circular action buttons:
/// [Follow/Edit Profile] • [Share profile] • [Copy link] • [QR code].
class ProfilePictureViewerScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final bool isMyProfile;
  final bool isFollowing;
  final bool isVerified;
  final String? bio;

  const ProfilePictureViewerScreen({
    super.key,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.isMyProfile,
    this.isFollowing = false,
    this.isVerified = false,
    this.bio,
  });

  static Future<void> open(
    BuildContext context, {
    required String userId,
    required String username,
    required String fullName,
    required String avatarUrl,
    required bool isMyProfile,
    bool isFollowing = false,
    bool isVerified = false,
    String? bio,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ProfilePictureViewerScreen(
          userId: userId,
          username: username,
          fullName: fullName,
          avatarUrl: avatarUrl,
          isMyProfile: isMyProfile,
          isFollowing: isFollowing,
          isVerified: isVerified,
          bio: bio,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<ProfilePictureViewerScreen> createState() =>
      _ProfilePictureViewerScreenState();
}

class _ProfilePictureViewerScreenState
    extends State<ProfilePictureViewerScreen> {
  late bool _isFollowing;
  bool _isFollowLoading = false;
  double _dragOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.isFollowing;
  }

  Future<void> _toggleFollow() async {
    if (widget.isMyProfile || _isFollowLoading) return;
    HapticFeedback.lightImpact();
    setState(() => _isFollowLoading = true);

    final status =
        await SocialGraphService.instance.toggleFollow(widget.userId);
    if (!mounted) return;

    setState(() {
      _isFollowLoading = false;
      if (status == FollowToggleStatus.following) {
        _isFollowing = true;
      } else if (status == FollowToggleStatus.unfollowed) {
        _isFollowing = false;
      }
    });
  }

  void _copyLink() {
    HapticFeedback.mediumImpact();
    final cleanHandle = widget.username.replaceFirst(RegExp(r'^@'), '').trim();
    final url = 'https://zevapp.com/u/@$cleanHandle';
    Clipboard.setData(ClipboardData(text: url));

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text('Copied link: $url'),
          ],
        ),
        backgroundColor: const Color(0xFF0284C7),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openShareProfile() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShareProfileScreen(
          userId: widget.userId,
          username: widget.username,
          fullName: widget.fullName,
          avatarUrl: widget.avatarUrl,
          bio: widget.bio,
          isVerified: widget.isVerified,
        ),
      ),
    );
  }

  void _openQrCode() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShareProfileScreen(
          userId: widget.userId,
          username: widget.username,
          fullName: widget.fullName,
          avatarUrl: widget.avatarUrl,
          bio: widget.bio,
          isVerified: widget.isVerified,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final avatarDiameter = (size.width * 0.72).clamp(240.0, 320.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        onVerticalDragUpdate: (details) {
          setState(() {
            _dragOffset += details.primaryDelta ?? 0.0;
          });
        },
        onVerticalDragEnd: (details) {
          if (_dragOffset.abs() > 90 ||
              (details.primaryVelocity ?? 0).abs() > 400) {
            Navigator.of(context).pop();
          } else {
            setState(() => _dragOffset = 0.0);
          }
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.25,
              colors: [
                Color(0xFF131D31),
                Color(0xFF090E17),
                Color(0xFF04060A),
              ],
              stops: [0.0, 0.65, 1.0],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                // Top Close Button
                Positioned(
                  top: 10,
                  left: 12,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 26,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),

                // Center Circular Profile Photo
                Center(
                  child: Transform.translate(
                    offset: Offset(0, _dragOffset),
                    child: GestureDetector(
                      onTap: () {}, // Prevent backdrop tap dismiss when tapping image
                      child: Hero(
                        tag: 'profile_avatar_${widget.userId}',
                        child: Container(
                          width: avatarDiameter,
                          height: avatarDiameter,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 2.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 40,
                                spreadRadius: 4,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: const Color(0xFF00D4FF).withValues(alpha: 0.12),
                                blurRadius: 60,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: widget.avatarUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: widget.avatarUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      color: const Color(0xFF1E293B),
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        _buildInitialsFallback(avatarDiameter),
                                  )
                                : _buildInitialsFallback(avatarDiameter),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom Action Buttons Row (Matching Instagram / User Reference Image)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 30,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // 1. Follow / Following / Edit Profile
                        _buildActionButton(
                          icon: widget.isMyProfile
                              ? Icons.edit_outlined
                              : (_isFollowing
                                  ? Icons.how_to_reg_outlined
                                  : Icons.person_add_outlined),
                          label: widget.isMyProfile
                              ? 'Edit profile'
                              : (_isFollowing ? 'Following' : 'Follow'),
                          isLoading: _isFollowLoading,
                          onTap: widget.isMyProfile
                              ? () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => EditProfileScreen(
                                        initialProfile: {
                                          'id': widget.userId,
                                          'username': widget.username,
                                          'full_name': widget.fullName,
                                          'avatar_url': widget.avatarUrl,
                                          'bio': widget.bio ?? '',
                                        },
                                      ),
                                    ),
                                  );
                                }
                              : _toggleFollow,
                        ),

                        // 2. Share profile
                        _buildActionButton(
                          icon: Icons.account_circle_outlined,
                          label: 'Share profile',
                          onTap: _openShareProfile,
                        ),

                        // 3. Copy link
                        _buildActionButton(
                          icon: Icons.link_rounded,
                          label: 'Copy link',
                          onTap: _copyLink,
                        ),

                        // 4. QR code
                        _buildActionButton(
                          icon: Icons.qr_code_rounded,
                          label: 'QR code',
                          onTap: _openQrCode,
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
    );
  }

  Widget _buildInitialsFallback(double diameter) {
    final initial = widget.fullName.trim().isNotEmpty
        ? widget.fullName.trim()[0].toUpperCase()
        : (widget.username.trim().isNotEmpty
            ? widget.username.trim()[0].toUpperCase()
            : 'Z');
    return Container(
      width: diameter,
      height: diameter,
      color: const Color(0xFF1E293B),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: diameter * 0.38,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isLoading ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
