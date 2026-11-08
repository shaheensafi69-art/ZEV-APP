import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/multi_account_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_logo.dart';
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
///
/// Features Adaptive Layout:
/// - Phones (< 720px): Floating Claymorphic Bottom Capsule Dock
/// - Tablets / iPads (>= 720px): Sleek Instagram-grade Adaptive Left Sidebar
class ZevMainLayout extends StatefulWidget {
  final int initialIndex;
  const ZevMainLayout({super.key, this.initialIndex = 0});

  /// Global notifier for user's active avatar URL so any screen (EditProfileSheet, etc.)
  /// can update the bottom bar in real-time.
  static final ValueNotifier<String> userAvatarNotifier = ValueNotifier<String>('');

  static void notifyAvatarChanged(String newAvatarUrl) {
    if (newAvatarUrl.isNotEmpty) {
      userAvatarNotifier.value = newAvatarUrl;
    }
  }

  @override
  State<ZevMainLayout> createState() => _ZevMainLayoutState();
}

class _ZevMainLayoutState extends State<ZevMainLayout> {
  final supabase = Supabase.instance.client;
  late int _currentIndex;

  String _myAvatarUrl = '';
  String _myUsername = '';
  String _myFullName = '';
  StreamSubscription<AuthState>? _authSubscription;

  // Persistent cached tab widgets to prevent unnecessary rebuilds
  late final Widget _feedTab;
  late final Widget _exploreTab;
  late final Widget _profileTab;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _feedTab = FeedViewerScreen(
      onOpenNotifications: () => NotificationsScreen.open(context),
      onOpenMessages: () => ChatListScreen.open(context),
    );
    _exploreTab = const ExploreScreen();
    _profileTab = const ProfileScreen();

    // Listen to static notifier updates
    ZevMainLayout.userAvatarNotifier.addListener(_onAvatarNotifierChanged);

    // Listen to Supabase auth state changes
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        _loadUserProfile();
      }
    });

    _loadUserProfile();
  }

  void _onAvatarNotifierChanged() {
    final newUrl = ZevMainLayout.userAvatarNotifier.value;
    if (newUrl.isNotEmpty && newUrl != _myAvatarUrl && mounted) {
      setState(() => _myAvatarUrl = newUrl);
    }
  }

  @override
  void dispose() {
    ZevMainLayout.userAvatarNotifier.removeListener(_onAvatarNotifierChanged);
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      try {
        final accounts = await MultiAccountService.getSavedAccounts();
        if (accounts.isNotEmpty && mounted) {
          final firstAcc = accounts.first;
          if (firstAcc.avatarUrl.isNotEmpty && _myAvatarUrl.isEmpty) {
            setState(() {
              _myAvatarUrl = firstAcc.avatarUrl;
              _myUsername = firstAcc.username;
              _myFullName = firstAcc.fullName;
            });
          }
        }
      } catch (_) {}
      return;
    }

    // Instant fallback from auth metadata (e.g. Google Sign-In avatar)
    final metaAvatar = user.userMetadata?['avatar_url']?.toString() ??
        user.userMetadata?['picture']?.toString() ??
        '';
    if (metaAvatar.isNotEmpty && _myAvatarUrl.isEmpty && mounted) {
      setState(() => _myAvatarUrl = metaAvatar);
    }

    try {
      final res = await supabase
          .from('profiles')
          .select('avatar_url, username, first_name, last_name')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        final avatar = (res['avatar_url'] ?? '').toString().trim();
        final username = (res['username'] ?? '').toString().trim();
        final first = (res['first_name'] ?? '').toString().trim();
        final last = (res['last_name'] ?? '').toString().trim();
        final fullName = '$first $last'.trim();
        final chosenAvatar = avatar.isNotEmpty ? avatar : metaAvatar;

        setState(() {
          if (chosenAvatar.isNotEmpty) {
            _myAvatarUrl = chosenAvatar;
          }
          if (username.isNotEmpty) _myUsername = username;
          if (fullName.isNotEmpty) _myFullName = fullName;
        });

        if (chosenAvatar.isNotEmpty) {
          ZevMainLayout.userAvatarNotifier.value = chosenAvatar;
        }
      } else if (metaAvatar.isNotEmpty && mounted) {
        setState(() => _myAvatarUrl = metaAvatar);
      }
    } catch (e) {
      debugPrint("Error loading user profile in ZevMainLayout: $e");
    }
  }

  void _onTabTapped(int index) {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() => _currentIndex = index);
    if (index == 4 || _myAvatarUrl.isEmpty) {
      _loadUserProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth >= 720;
    final isExpandedSidebar = screenWidth >= 960;
    final isReels = _currentIndex == 3;

    final tabChildren = [
      // Tab 0: Home Feed
      _feedTab,

      // Tab 1: Explore / Search (Flagship Instagram Explore)
      _exploreTab,

      // Tab 2: Create (opens in-feed modal or creation screen)
      _buildCreatePlaceholder(),

      // Tab 3: Reels
      ReelsViewerScreen(isScreenActive: _currentIndex == 3),

      // Tab 4: Profile
      _profileTab,
    ];

    // ========================================================
    // 1. Tablet / iPad Mode: Adaptive Left Navigation Sidebar
    // ========================================================
    if (isTablet) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: isReels ? Colors.black : const Color(0xFFF1F5F9),
        body: Row(
          children: [
            // Left Adaptive Sidebar
            _buildTabletSidebar(
              isExpanded: isExpandedSidebar,
              isReels: isReels,
            ),
            // Right Screen Area
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: tabChildren,
              ),
            ),
          ],
        ),
      );
    }

    // ========================================================
    // 2. Phone Mode: Floating Claymorphic Navigation Capsule
    // ========================================================
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: isReels ? Colors.black : const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // Five Tab Screens
          IndexedStack(
            index: _currentIndex,
            children: tabChildren,
          ),

          // Pure Floating Claymorphic Navigation Capsule Dock
          Positioned(
            left: 18,
            right: 18,
            bottom: (bottomInset > 0 ? bottomInset.clamp(0.0, 10.0) : 0) + 14,
            child: Container(
              height: 66,
              decoration: BoxDecoration(
                color: isReels
                    ? const Color(0xFF0F172A).withValues(alpha: 0.88)
                    : Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: isReels
                      ? const Color(0xFF334155).withValues(alpha: 0.5)
                      : Colors.white,
                  width: 1.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isReels
                        ? Colors.black.withValues(alpha: 0.6)
                        : const Color(0xFF0F172A).withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                    spreadRadius: 1,
                  ),
                  if (!isReels)
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

  // ========================================================
  // Tablet / iPad Sidebar Widgets
  // ========================================================

  Widget _buildTabletSidebar({
    required bool isExpanded,
    required bool isReels,
  }) {
    final sidebarBg = isReels
        ? const Color(0xFF0F172A)
        : Colors.white;
    final borderColor = isReels
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: isExpanded ? 248 : 84,
      decoration: BoxDecoration(
        color: sidebarBg,
        border: Border(
          right: BorderSide(color: borderColor, width: 1.2),
        ),
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
                    _buildSidebarNavItem(
                      index: 0,
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                      label: "Home",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 6),
                    _buildSidebarNavItem(
                      index: 1,
                      icon: Icons.search_rounded,
                      activeIcon: Icons.search_rounded,
                      label: "Explore",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 6),
                    _buildSidebarNavItem(
                      index: 3,
                      icon: Icons.play_circle_outline_rounded,
                      activeIcon: Icons.play_circle_fill_rounded,
                      label: "Reels",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 6),
                    _buildSidebarActionItem(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: "Messages",
                      isExpanded: isExpanded,
                      isReels: isReels,
                      onTap: () => ChatListScreen.open(context),
                    ),
                    const SizedBox(height: 6),
                    _buildSidebarActionItem(
                      icon: Icons.favorite_outline_rounded,
                      label: "Notifications",
                      isExpanded: isExpanded,
                      isReels: isReels,
                      onTap: () => NotificationsScreen.open(context),
                    ),
                    const SizedBox(height: 18),
                    // 3. Create Button
                    _buildSidebarCreateButton(isExpanded: isExpanded),
                  ],
                ),
              ),

              // 4. User Profile Tile at Bottom
              _buildSidebarProfileItem(
                index: 4,
                isExpanded: isExpanded,
                isReels: isReels,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isExpanded,
    required bool isReels,
  }) {
    final isSelected = _currentIndex == index;
    final inactiveColor = isReels ? Colors.white60 : const Color(0xFF64748B);
    final activeColor = isReels ? Colors.white : ZevColors.deepNavy;

    return Tooltip(
      message: isExpanded ? '' : label,
      preferBelow: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onTabTapped(index),
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
                  child: Icon(
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
                            color: ZevColors.primaryBlue.withValues(alpha: 0.8),
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

  Widget _buildSidebarActionItem({
    required IconData icon,
    required String label,
    required bool isExpanded,
    required bool isReels,
    required VoidCallback onTap,
  }) {
    final inactiveColor = isReels ? Colors.white60 : const Color(0xFF64748B);

    return Tooltip(
      message: isExpanded ? '' : label,
      preferBelow: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          hoverColor: (isReels ? Colors.white : ZevColors.primaryBlue)
              .withValues(alpha: 0.06),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isExpanded ? 14 : 10,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 25,
                  color: inactiveColor,
                ),
                if (isExpanded) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: inactiveColor,
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

  Widget _buildSidebarCreateButton({required bool isExpanded}) {
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

  Widget _buildSidebarProfileItem({
    required int index,
    required bool isExpanded,
    required bool isReels,
  }) {
    final isSelected = _currentIndex == index;
    final inactiveBorder = isReels ? Colors.white24 : const Color(0xFFCBD5E1);
    final activeColor = isReels ? Colors.white : ZevColors.deepNavy;
    final inactiveColor = isReels ? Colors.white60 : const Color(0xFF64748B);

    return Tooltip(
      message: isExpanded ? '' : (_myUsername.isNotEmpty ? "@$_myUsername" : "Profile"),
      preferBelow: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onTabTapped(index),
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
                      child: _myAvatarUrl.isNotEmpty
                          ? ZevCachedImage.avatar(
                              imageUrl: _myAvatarUrl,
                              size: 28,
                            )
                          : _buildAvatarFallback(isReels: isReels),
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
                          _myFullName.isNotEmpty
                              ? _myFullName
                              : (_myUsername.isNotEmpty ? _myUsername : "Profile"),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: isSelected ? activeColor : inactiveColor,
                          ),
                        ),
                        if (_myUsername.isNotEmpty)
                          Text(
                            "@$_myUsername",
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
                            color: ZevColors.primaryBlue.withValues(alpha: 0.8),
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

  // ========================================================
  // Action Sheets & Phone Navigation Items
  // ========================================================

  void _openCreateActionSheet() {
    HapticFeedback.mediumImpact();
    final screenHeight = MediaQuery.sizeOf(context).height;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.85,
        ),
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
    final inactiveBorder = isReels ? Colors.white30 : const Color(0xFFCBD5E1);

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isSelected
                        ? LinearGradient(
                            colors: isReels
                                ? [const Color(0xFF00D4FF), Colors.white]
                                : [const Color(0xFF00D4FF), const Color(0xFF536DFE)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    border: isSelected
                        ? null
                        : Border.all(color: inactiveBorder, width: 1.5),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00D4FF).withValues(alpha: 0.45),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  padding: EdgeInsets.all(isSelected ? 2.0 : 0.0),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isReels ? const Color(0xFF0F172A) : Colors.white,
                    ),
                    padding: const EdgeInsets.all(1.2),
                    child: ClipOval(
                      child: _myAvatarUrl.isNotEmpty
                          ? ZevCachedImage.avatar(
                              imageUrl: _myAvatarUrl,
                              size: 26,
                            )
                          : _buildAvatarFallback(isReels: isReels),
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

  Widget _buildAvatarFallback({required bool isReels}) {
    if (_myUsername.isNotEmpty) {
      final initial = _myUsername[0].toUpperCase();
      return Container(
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return Container(
      color: isReels ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      child: Icon(
        Icons.person_rounded,
        size: 16,
        color: isReels ? Colors.white70 : ZevColors.textMuted,
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
