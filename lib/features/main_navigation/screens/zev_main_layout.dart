import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/theme/zev_theme.dart';
import '../../feed/screens/create_post_screen.dart';
import '../../feed/screens/feed_viewer_screen.dart';
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
  String _myUsername = 'user';
  String _myFullName = 'ZEV User';
  String _myBio = '';

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('avatar_url, username, first_name, last_name, bio')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        final fn = res['first_name'] ?? '';
        final ln = res['last_name'] ?? '';
        setState(() {
          _myAvatarUrl = res['avatar_url'] ?? '';
          _myUsername = res['username'] ?? 'user';
          _myFullName = "$fn $ln".trim().isNotEmpty ? "$fn $ln".trim() : 'ZEV User';
          _myBio = res['bio'] ?? '';
        });
      }
    } catch (_) {}
  }

  void _onTabTapped(int index) {
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZevColors.white,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Home Feed
          const FeedViewerScreen(),

          // Tab 1: Explore / Search
          _buildExplorePlaceholder(),

          // Tab 2: Create (opens in-feed modal or creation screen)
          _buildCreatePlaceholder(),

          // Tab 3: Reels
          ReelsViewerScreen(isScreenActive: _currentIndex == 3),

          // Tab 4: Profile
          _buildProfileScreen(),
        ],
      ),

      // Sculpted Modern ZEV Global Bottom Navigation Bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: _currentIndex == 3 ? const Color(0xFF000000) : ZevColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: _currentIndex == 3
              ? const Border(
                  top: BorderSide(color: Colors.white12, width: 0.8),
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: _currentIndex == 3
                  ? Colors.black.withValues(alpha: 0.8)
                  : const Color(0xFF080D1A).withValues(alpha: 0.07),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
            if (_currentIndex != 3)
              BoxShadow(
                color: const Color(0xFF080D1A).withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: "Home",
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.search_rounded,
                  activeIcon: Icons.search_rounded,
                  label: "Search",
                ),
                _buildCenterCreateButton(),
                _buildNavItem(
                  index: 3,
                  icon: Icons.play_circle_outline_rounded,
                  activeIcon: Icons.play_circle_fill_rounded,
                  label: "Reels",
                ),
                _buildProfileNavItem(index: 4),
              ],
            ),
          ),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: const BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Container(
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "Create",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
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
                  onPostCreated: () {
                    setState(() => _currentIndex = 0);
                  },
                );
              },
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 10),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: ZevColors.softSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZevColors.border, width: 1.0),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
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
                      fontSize: 14.5,
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
              size: 20,
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          width: 48,
          height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.add_rounded,
              color: Colors.white,
              size: 26,
            ),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Icon(
                isSelected ? activeIcon : icon,
                size: 26,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 5),
            // Glowing Active Cyan Dot Indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              width: isSelected ? 14 : 0,
              height: 3.5,
              decoration: BoxDecoration(
                color: isSelected ? ZevColors.primaryBlue : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.8),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
            ),
          ],
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 30,
              height: 30,
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
                    : Border.all(
                        color: inactiveBorder,
                        width: 1.2,
                      ),
              ),
              padding: EdgeInsets.all(isSelected ? 2.0 : 0.0),
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
                          errorBuilder: (context, error, stackTrace) =>
                              Icon(
                            Icons.person_rounded,
                            size: 18,
                            color: isReels ? Colors.white70 : ZevColors.textMuted,
                          ),
                        )
                      : Icon(
                          Icons.person_rounded,
                          size: 18,
                          color: isReels ? Colors.white70 : ZevColors.textMuted,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            // Glowing Active Cyan Dot Indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              width: isSelected ? 14 : 0,
              height: 3.5,
              decoration: BoxDecoration(
                color: isSelected ? ZevColors.primaryBlue : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.8),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Explore Placeholder
  Widget _buildExplorePlaceholder() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              height: 42,
              decoration: BoxDecoration(
                color: ZevColors.softSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ZevColors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded, color: ZevColors.textMuted, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "Search creators, tags, or topics...",
                    style: TextStyle(
                      color: ZevColors.textMuted,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.explore_outlined,
                      size: 48,
                      color: ZevColors.primaryBlue,
                    ),
                    SizedBox(height: 14),
                    Text(
                      "Explore ZEV",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      "Discover trending reels, posts, and creators.",
                      style: TextStyle(
                        fontSize: 13,
                        color: ZevColors.textSecondary,
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

  // Create Placeholder
  Widget _buildCreatePlaceholder() {
    return SafeArea(
      child: Center(
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
    );
  }

  // Profile Screen
  Widget _buildProfileScreen() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header Row
            Row(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ZevColors.primaryBlue,
                      width: 2.5,
                    ),
                  ),
                  child: ClipOval(
                    child: _myAvatarUrl.isNotEmpty
                        ? Image.network(_myAvatarUrl, fit: BoxFit.cover)
                        : const Icon(
                            Icons.person_rounded,
                            size: 44,
                            color: ZevColors.textMuted,
                          ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildProfileStat("Posts", "0"),
                      _buildProfileStat("Followers", "0"),
                      _buildProfileStat("Following", "0"),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Text(
              _myFullName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ZevColors.deepNavy,
              ),
            ),
            Text(
              "@$_myUsername",
              style: const TextStyle(
                fontSize: 13,
                color: ZevColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_myBio.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _myBio,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: ZevColors.deepNavy,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      backgroundColor: ZevColors.softSurface,
                      side: const BorderSide(color: ZevColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      "Edit Profile",
                      style: TextStyle(
                        color: ZevColors.deepNavy,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await AuthHelper.logout(context);
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEF2F2),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    "Log Out",
                    style: TextStyle(
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),
            const Divider(color: ZevColors.border),
            const SizedBox(height: 16),

            const Center(
              child: Column(
                children: [
                  Icon(
                    Icons.grid_on_rounded,
                    size: 36,
                    color: ZevColors.deepNavy,
                  ),
                  SizedBox(height: 12),
                  Text(
                    "No posts yet",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: ZevColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
