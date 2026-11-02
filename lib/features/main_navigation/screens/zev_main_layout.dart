import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/theme/zev_theme.dart';
import '../../feed/screens/feed_viewer_screen.dart';

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
          _buildReelsPlaceholder(),

          // Tab 4: Profile
          _buildProfileScreen(),
        ],
      ),

      // Docked Instagram Global Bottom Navigation Bar
      bottomNavigationBar: Container(
        height: 56,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: ZevColors.border,
              width: 0.8,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
              index: 0,
              icon: Icons.home_outlined,
              activeIcon: Icons.home_filled,
              label: "Home",
            ),
            _buildNavItem(
              index: 1,
              icon: Icons.search_rounded,
              activeIcon: Icons.search_rounded,
              label: "Search",
            ),
            _buildNavItem(
              index: 2,
              icon: Icons.add_box_outlined,
              activeIcon: Icons.add_box_rounded,
              label: "Create",
            ),
            _buildNavItem(
              index: 3,
              icon: Icons.movie_creation_outlined,
              activeIcon: Icons.movie_creation_rounded,
              label: "Reels",
            ),
            _buildProfileNavItem(index: 4),
          ],
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
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Icon(
          isSelected ? activeIcon : icon,
          size: 27,
          color: isSelected ? ZevColors.deepNavy : ZevColors.deepNavy.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _buildProfileNavItem({required int index}) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? ZevColors.deepNavy : Colors.transparent,
              width: 2.0,
            ),
          ),
          padding: const EdgeInsets.all(1.5),
          child: ClipOval(
            child: _myAvatarUrl.isNotEmpty
                ? Image.network(
                    _myAvatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.person_rounded,
                      size: 18,
                      color: ZevColors.textMuted,
                    ),
                  )
                : const Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: ZevColors.textMuted,
                  ),
          ),
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

  // Reels Placeholder
  Widget _buildReelsPlaceholder() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline_rounded,
              color: ZevColors.primaryBlue,
              size: 56,
            ),
            SizedBox(height: 16),
            Text(
              "ZEV Reels",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 6),
            Text(
              "Immersive short videos from creators",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
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
