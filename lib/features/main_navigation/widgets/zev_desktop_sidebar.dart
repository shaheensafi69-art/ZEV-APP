import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/services/badge_counter_service.dart';
import '../../../core/services/multi_account_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_logo.dart';
import '../../feed/screens/create_post_screen.dart';
import '../../reels/screens/create_reel_screen.dart';
import '../../stories/screens/create_story_screen.dart';
import '../screens/zev_main_layout.dart';

/// Reusable Adaptive Left Navigation Sidebar for ZEV Desktop & Tablet Web.
/// Retains persistent Instagram Web-grade navigation across all views (Feed, Explore,
/// Visitor Profiles, Messages, Notifications, Settings).
class ZevDesktopSidebar extends StatefulWidget {
  final int activeIndex;
  final bool? isExpanded;
  final bool isReels;
  final ValueChanged<int>? onTabSelected;

  const ZevDesktopSidebar({
    super.key,
    this.activeIndex = -1,
    this.isExpanded,
    this.isReels = false,
    this.onTabSelected,
  });

  @override
  State<ZevDesktopSidebar> createState() => _ZevDesktopSidebarState();
}

class _ZevDesktopSidebarState extends State<ZevDesktopSidebar> {
  final supabase = Supabase.instance.client;
  String _avatarUrl = '';
  String _username = '';
  String _fullName = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('avatar_url, username, first_name, last_name')
          .eq('id', user.id)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _avatarUrl = res['avatar_url']?.toString() ?? '';
          _username = res['username']?.toString() ?? '';
          final fn = res['first_name']?.toString() ?? '';
          final ln = res['last_name']?.toString() ?? '';
          final full = '$fn $ln'.trim();
          _fullName = full.isNotEmpty ? full : _username;
        });
      }
    } catch (_) {}
  }

  void _handleTabTap(int index) {
    HapticFeedback.lightImpact();
    if (widget.onTabSelected != null) {
      widget.onTabSelected!(index);
    } else {
      ZevMainLayout.switchTab(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isExpanded = widget.isExpanded ?? (screenWidth >= 960);
    final isReels = widget.isReels;

    final sidebarBg = isReels ? const Color(0xFF0F172A) : Colors.white;
    final borderColor =
        isReels ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: isExpanded ? 248 : 84,
      decoration: BoxDecoration(
        color: sidebarBg,
        border: Border(right: BorderSide(color: borderColor, width: 1.2)),
        boxShadow: [
          BoxShadow(
            color: isReels
                ? Colors.black.withValues(alpha: 0.4)
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isExpanded ? 16 : 10,
            vertical: 18,
          ),
          child: Column(
            crossAxisAlignment: isExpanded
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              // 1. ZEV Logo at Top
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isExpanded ? 10 : 4,
                  vertical: 6,
                ),
                child: ZevLogo(
                  height: 36,
                  showText: isExpanded,
                  textColor: isReels ? Colors.white : ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 28),

              // 2. Navigation items list
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildNavItem(
                      index: 0,
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                      label: "Home",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 6),
                    _buildNavItem(
                      index: 1,
                      icon: Icons.search_rounded,
                      activeIcon: Icons.search_rounded,
                      label: "Explore",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 6),
                    _buildNavItem(
                      index: 3,
                      icon: Icons.play_circle_outline_rounded,
                      activeIcon: Icons.play_circle_fill_rounded,
                      label: "Reels",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<int>(
                      valueListenable:
                          BadgeCounterService.instance.unreadMessagesCount,
                      builder: (context, count, _) => _buildNavItem(
                        index: 5,
                        icon: Icons.chat_bubble_outline_rounded,
                        activeIcon: Icons.chat_bubble_rounded,
                        label: "Messages",
                        isExpanded: isExpanded,
                        isReels: isReels,
                        badgeCount: count,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<int>(
                      valueListenable:
                          BadgeCounterService.instance.unreadNotificationsCount,
                      builder: (context, count, _) => _buildNavItem(
                        index: 6,
                        icon: Icons.favorite_outline_rounded,
                        activeIcon: Icons.favorite_rounded,
                        label: "Notifications",
                        isExpanded: isExpanded,
                        isReels: isReels,
                        badgeCount: count,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 3. Create Button
                    _buildCreateButton(isExpanded: isExpanded),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Divider(
                        height: 1,
                        color: isReels
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 4. Quick Access Hub
                    _buildNavItem(
                      index: 7,
                      icon: Icons.campaign_outlined,
                      activeIcon: Icons.campaign_rounded,
                      label: "Advertise",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 4),
                    _buildNavItem(
                      index: 8,
                      icon: Icons.insights_outlined,
                      activeIcon: Icons.insights_rounded,
                      label: "Creator Insights",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 4),
                    _buildNavItem(
                      index: 9,
                      icon: Icons.schedule_send_outlined,
                      activeIcon: Icons.schedule_send_rounded,
                      label: "Drafts & Scheduled",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 4),
                    _buildNavItem(
                      index: 10,
                      icon: Icons.verified_outlined,
                      activeIcon: Icons.verified_rounded,
                      label: "ZEV Blue",
                      accentColor: ZevColors.primaryBlue,
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                  ],
                ),
              ),

              // 5. User Profile Tile at Bottom
              _buildProfileItem(
                index: 4,
                isExpanded: isExpanded,
                isReels: isReels,
              ),
              const SizedBox(height: 6),

              // 6. More / Settings Menu (Instagram Web style)
              _buildMoreButton(isExpanded: isExpanded, isReels: isReels),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isExpanded,
    required bool isReels,
    int badgeCount = 0,
    Color? accentColor,
  }) {
    final isSelected = widget.activeIndex == index;
    final inactiveColor =
        accentColor ?? (isReels ? Colors.white60 : const Color(0xFF64748B));
    final activeColor =
        accentColor ?? (isReels ? Colors.white : ZevColors.deepNavy);

    return Tooltip(
      message: isExpanded ? '' : label,
      preferBelow: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _handleTabTap(index),
          hoverColor: (isReels ? Colors.white : ZevColors.primaryBlue)
              .withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: isExpanded ? 14 : 10,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isReels
                      ? Colors.white.withValues(alpha: 0.12)
                      : ZevColors.primaryBlue.withValues(alpha: 0.12))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: badgeCount > 0
                      ? Badge.count(
                          count: badgeCount,
                          backgroundColor: const Color(0xFFEF4444),
                          textColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                          child: Icon(
                            isSelected ? activeIcon : icon,
                            size: 26,
                            color: isSelected ? activeColor : inactiveColor,
                          ),
                        )
                      : Icon(
                          isSelected ? activeIcon : icon,
                          size: 26,
                          color: isSelected ? activeColor : inactiveColor,
                        ),
                ),
                if (isExpanded) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? activeColor : inactiveColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: ZevColors.primaryBlue,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color:
                                ZevColors.primaryBlue.withValues(alpha: 0.8),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateButton({required bool isExpanded}) {
    if (isExpanded) {
      return Container(
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00D4FF), Color(0xFF4F46E5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openCreateActionSheet,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 24),
                SizedBox(width: 8),
                Text(
                  "Create",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: Tooltip(
        message: "Create",
        preferBelow: false,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00D4FF), Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _openCreateActionSheet,
              child: const Center(
                child: Icon(Icons.add_rounded, color: Colors.white, size: 26),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileItem({
    required int index,
    required bool isExpanded,
    required bool isReels,
  }) {
    final isSelected = widget.activeIndex == index;
    final inactiveBorder = isReels ? Colors.white24 : const Color(0xFFCBD5E1);
    final activeColor = isReels ? Colors.white : ZevColors.deepNavy;
    final inactiveColor = isReels ? Colors.white60 : const Color(0xFF64748B);

    return ValueListenableBuilder<String>(
      valueListenable: ZevMainLayout.userAvatarNotifier,
      builder: (context, dynamicAvatar, _) {
        final avatar = dynamicAvatar.isNotEmpty ? dynamicAvatar : _avatarUrl;

        return Tooltip(
          message: isExpanded
              ? ''
              : (_username.isNotEmpty ? "@$_username" : "Profile"),
          preferBelow: false,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _handleTabTap(index),
              hoverColor: (isReels ? Colors.white : ZevColors.primaryBlue)
                  .withValues(alpha: 0.06),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: isExpanded ? 12 : 8,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isReels
                          ? Colors.white.withValues(alpha: 0.12)
                          : ZevColors.primaryBlue.withValues(alpha: 0.12))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: isExpanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        border: isSelected
                            ? null
                            : Border.all(color: inactiveBorder, width: 1.5),
                      ),
                      padding: EdgeInsets.all(isSelected ? 2.0 : 0.0),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isReels ? Colors.black : ZevColors.white,
                        ),
                        padding: const EdgeInsets.all(1.2),
                        child: ClipOval(
                          child: avatar.isNotEmpty
                              ? ZevCachedImage.avatar(
                                  imageUrl: avatar,
                                  size: 28,
                                )
                              : Container(
                                  color: const Color(0xFFE2E8F0),
                                  child: const Icon(
                                    Icons.person_rounded,
                                    size: 18,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (isExpanded) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _fullName.isNotEmpty
                                  ? _fullName
                                  : (_username.isNotEmpty
                                      ? _username
                                      : "Profile"),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                color:
                                    isSelected ? activeColor : inactiveColor,
                              ),
                            ),
                            if (_username.isNotEmpty)
                              Text(
                                "@$_username",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isReels
                                      ? Colors.white54
                                      : ZevColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: ZevColors.primaryBlue,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: ZevColors.primaryBlue
                                    .withValues(alpha: 0.8),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoreButton({
    required bool isExpanded,
    required bool isReels,
  }) {
    return Tooltip(
      message: isExpanded ? '' : 'More Settings',
      preferBelow: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showMoreMenu(isReels: isReels, isExpanded: isExpanded),
          hoverColor: (isReels ? Colors.white : ZevColors.primaryBlue)
              .withValues(alpha: 0.08),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isExpanded ? 14 : 10,
              vertical: 10,
            ),
            child: Row(
              mainAxisAlignment: isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.menu_rounded,
                  size: 26,
                  color: isReels ? Colors.white : ZevColors.deepNavy,
                ),
                if (isExpanded) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      "More",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isReels ? Colors.white : ZevColors.deepNavy,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMoreMenu({required bool isReels, required bool isExpanded}) {
    HapticFeedback.lightImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'MoreSettingsMenu',
      barrierColor: Colors.black.withValues(alpha: 0.16),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              left: isExpanded ? 16 : 80,
              bottom: 64,
              child: Material(
                color: Colors.transparent,
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: anim1,
                    curve: Curves.easeOut,
                  ),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.88, end: 1.0).animate(
                      CurvedAnimation(
                        parent: anim1,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    alignment: Alignment.bottomLeft,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          width: 270,
                          decoration: BoxDecoration(
                            color: isReels
                                ? const Color(0xFF0F172A).withValues(alpha: 0.85)
                                : Colors.white.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isReels
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.92),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A)
                                    .withValues(alpha: 0.14),
                                blurRadius: 28,
                                offset: const Offset(4, 10),
                              ),
                              BoxShadow(
                                color: ZevColors.primaryBlue.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 16,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildMoreMenuItem(
                                  icon: Icons.settings_outlined,
                                  label: 'Settings & Privacy',
                                  isReels: isReels,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _handleTabTap(11);
                                  },
                                ),
                                _buildMoreMenuItem(
                                  icon: Icons.history_rounded,
                                  label: 'Your Activity',
                                  isReels: isReels,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _handleTabTap(12);
                                  },
                                ),
                                _buildMoreMenuItem(
                                  icon: Icons.campaign_outlined,
                                  label: 'Ads Manager',
                                  isReels: isReels,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _handleTabTap(7);
                                  },
                                ),
                                _buildMoreMenuItem(
                                  icon: Icons.security_rounded,
                                  label: 'Security & 2FA',
                                  isReels: isReels,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _handleTabTap(13);
                                  },
                                ),
                                _buildMoreMenuItem(
                                  icon: Icons.switch_account_outlined,
                                  label: 'Switch Accounts',
                                  isReels: isReels,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    MultiAccountService.showAccountSwitcherSheet(
                                      context,
                                    );
                                  },
                                ),
                                _buildMoreMenuItem(
                                  icon: Icons.help_outline_rounded,
                                  label: 'Help & Support',
                                  isReels: isReels,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _handleTabTap(14);
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: Divider(
                                    color: isReels
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFE2E8F0),
                                    height: 1,
                                  ),
                                ),
                                _buildMoreMenuItem(
                                  icon: Icons.logout_rounded,
                                  label: 'Log Out',
                                  isDestructive: true,
                                  isReels: isReels,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _showLogoutDialog();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMoreMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isReels,
    bool isDestructive = false,
  }) {
    final color = isDestructive
        ? const Color(0xFFEF4444)
        : (isReels ? Colors.white : ZevColors.deepNavy);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: isDestructive
            ? const Color(0xFFEF4444).withValues(alpha: 0.08)
            : (isReels ? Colors.white : ZevColors.primaryBlue)
                .withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isDestructive ? FontWeight.w700 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out of ZEV?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthHelper.logout(context);
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _openCreateActionSheet() {
    HapticFeedback.mediumImpact();
    final screenHeight = MediaQuery.sizeOf(context).height;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.95),
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.10),
              blurRadius: 30,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Create",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 16),
                _buildCreateOptionTile(
                  icon: Icons.post_add_rounded,
                  title: "Share Post",
                  subtitle: "Publish photos and thoughts to your feed",
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    CreatePostScreen.open(
                      context,
                      onPostCreated: () => widget.onTabSelected?.call(0),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildCreateOptionTile(
                  icon: Icons.flash_on_rounded,
                  title: "Add to Story",
                  subtitle: "Post a 24-hour photo or quick update",
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8800), Color(0xFFFF3366)],
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    CreateStoryScreen.open(
                      context,
                      onStoryCreated: () => widget.onTabSelected?.call(0),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildCreateOptionTile(
                  icon: Icons.play_arrow_rounded,
                  title: "Create Reel",
                  subtitle: "Record or upload short-form videos",
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7928CA), Color(0xFFFF0080)],
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    CreateReelScreen.open(
                      context,
                      onReelCreated: () => widget.onTabSelected?.call(3),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ZevColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
