import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../explore/screens/explore_screen.dart';
import '../../feed/screens/create_post_screen.dart';
import '../../feed/screens/feed_viewer_screen.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../reels/screens/create_reel_screen.dart';
import '../../reels/screens/reels_viewer_screen.dart';
import '../../stories/screens/create_story_screen.dart';

/// Next-Generation Instagram Main Shell for ZEV Social Network.
/// Hosts 5 primary tabs (Home, Search, Create, Reels, Profile)
/// with 120 FPS IndexedStack preservation and Instagram-grade navigation.
class ZevMainLayout extends StatefulWidget {
  final int initialIndex;
  const ZevMainLayout({super.key, this.initialIndex = 0});

  @override
  State<ZevMainLayout> createState() => _ZevMainLayoutState();
}

class _ZevMainLayoutState extends State<ZevMainLayout> {
  final supabase = Supabase.instance.client;
  late int _currentIndex;

  String _myAvatarUrl = '';

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    unawaited(NotificationService().saveFCMTokenToDatabase());
    try {
      final res = await supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _myAvatarUrl = res['avatar_url'] ?? '';
        });
      }
    } catch (_) {}
  }

  void _onTabTapped(int index) {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _currentIndex == 3 ? Colors.black : const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // 1. Five Tab Screens
          IndexedStack(
            index: _currentIndex,
            children: [
              // Tab 0: Home Feed
              FeedViewerScreen(
                onOpenNotifications: () => NotificationsScreen.open(context),
                onOpenMessages: () => ChatListScreen.open(context),
              ),

              // Tab 1: Explore / Search (Flagship Instagram Explore)
              const ExploreScreen(),

              // Tab 2: Create (opens in-feed modal or creation screen)
              _buildCreatePlaceholder(),

              // Tab 3: Reels
              ReelsViewerScreen(isScreenActive: _currentIndex == 3),

              // Tab 4: Profile
              const ProfileScreen(),
            ],
          ),

          // 2. Pure Floating Claymorphic Navigation Capsule Dock (Truly floating in the air)
          Positioned(
            left: 18,
            right: 18,
            bottom: (bottomInset > 0 ? bottomInset.clamp(0.0, 10.0) : 0) + 14,
            child: Container(
              height: 66,
              decoration: BoxDecoration(
                color: _currentIndex == 3
                    ? const Color(0xFF0F172A).withValues(alpha: 0.88)
                    : Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: _currentIndex == 3
                      ? const Color(0xFF334155).withValues(alpha: 0.5)
                      : Colors.white,
                  width: 1.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _currentIndex == 3
                        ? Colors.black.withValues(alpha: 0.6)
                        : const Color(0xFF0F172A).withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                    spreadRadius: 1,
                  ),
                  if (_currentIndex != 3)
                    const BoxShadow(
                      color: Colors.white,
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildNavItem(
                            index: 0,
                            icon: Icons.home_outlined,
                            activeIcon: Icons.home_rounded,
                            label: "Home",
                          ),
                        ),
                        Expanded(
                          child: _buildNavItem(
                            index: 1,
                            icon: Icons.search_rounded,
                            activeIcon: Icons.search_rounded,
                            label: "Search",
                          ),
                        ),
                        Expanded(
                          child: _buildCenterCreateButton(),
                        ),
                        Expanded(
                          child: _buildNavItem(
                            index: 3,
                            icon: Icons.play_circle_outline_rounded,
                            activeIcon: Icons.play_circle_fill_rounded,
                            label: "Reels",
                          ),
                        ),
                        Expanded(
                          child: _buildProfileNavItem(index: 4),
                        ),
                      ],
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

  void _openCreateActionSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Clay Drag Handle
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.white,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "Create",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 18),
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
                  onPostCreated: () {
                    setState(() => _currentIndex = 0);
                  },
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
                  onStoryCreated: () {
                    setState(() => _currentIndex = 0);
                  },
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
                  onReelCreated: () {
                    setState(() => _currentIndex = 3);
                  },
                );
              },
            ),
            const SizedBox(height: 24),
          ],
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
            const BoxShadow(
              color: Colors.white,
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.8),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
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
              color: ZevColors.textMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterCreateButton() {
    return GestureDetector(
      onTap: _openCreateActionSheet,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Container(
          width: 48,
          height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00D4FF), Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
              const BoxShadow(
                color: Colors.white,
                blurRadius: 4,
                offset: Offset(0, -1),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.add_rounded, color: Colors.white, size: 24),
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
  }) {
    final isSelected = _currentIndex == index;
    final isReels = _currentIndex == 3;

    final inactiveColor = isReels ? Colors.white60 : const Color(0xFF8E9BAE);
    final activeColor = isReels ? Colors.white : ZevColors.deepNavy;

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? (isReels
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFF00D4FF).withValues(alpha: 0.10))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Icon(
                  isSelected ? activeIcon : icon,
                  size: 24,
                  color: isSelected ? activeColor : inactiveColor,
                ),
              ),
              const SizedBox(height: 2),
              // Glowing Active Cyan Dot Indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: isSelected ? 12 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: isSelected ? ZevColors.primaryBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: ZevColors.primaryBlue.withValues(alpha: 0.8),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileNavItem({required int index}) {
    final isSelected = _currentIndex == index;
    final isReels = _currentIndex == 3;
    final inactiveBorder = isReels ? Colors.white24 : const Color(0xFFCBD5E1);

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28,
                height: 28,
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
                      : Border.all(color: inactiveBorder, width: 1.2),
                ),
                padding: EdgeInsets.all(isSelected ? 1.8 : 0.0),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isReels ? Colors.black : ZevColors.white,
                  ),
                  padding: const EdgeInsets.all(1.0),
                  child: ClipOval(
                    child: _myAvatarUrl.isNotEmpty
                        ? Image.network(
                            _myAvatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.person_rounded,
                              size: 16,
                              color: isReels
                                  ? Colors.white70
                                  : ZevColors.textMuted,
                            ),
                          )
                        : Icon(
                            Icons.person_rounded,
                            size: 16,
                            color: isReels ? Colors.white70 : ZevColors.textMuted,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              // Glowing Active Cyan Dot Indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: isSelected ? 12 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: isSelected ? ZevColors.primaryBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: ZevColors.primaryBlue.withValues(alpha: 0.8),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Create Placeholder
  Widget _buildCreatePlaceholder() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: ZevColors.primaryBlue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_photo_alternate_rounded,
                  size: 40,
                  color: ZevColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Create Content",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 36),
                child: Text(
                  "Share photos, short reels, or stories with the community.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => setState(() => _currentIndex = 0),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.primaryBlue,
                  foregroundColor: ZevColors.deepNavy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text("Go to Feed"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
