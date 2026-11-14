import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/services/badge_counter_service.dart';
import '../../../core/services/multi_account_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/zev_rtc_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/web_url_helper.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_logo.dart';
import '../../ads/screens/ads_manager_screen.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../explore/screens/explore_screen.dart';
import '../../feed/screens/create_post_screen.dart';
import '../../feed/screens/drafts_scheduled_screen.dart';
import '../../feed/screens/feed_viewer_screen.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../profile/screens/creator_insights_screen.dart';
import '../../profile/screens/help_support_screen.dart';
import '../../profile/screens/mfa_settings_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../profile/screens/profile_settings_screen.dart';
import '../../profile/screens/user_activity_screen.dart';
import '../../profile/screens/zev_blue_verification_screen.dart';
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
  static final ValueNotifier<String> userAvatarNotifier = ValueNotifier<String>(
    '',
  );

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
  Map<String, dynamic> _myProfileMap = {};
  StreamSubscription<AuthState>? _authSubscription;

  // Persistent cached tab widgets to prevent unnecessary rebuilds
  late final Widget _feedTab;
  late final Widget _exploreTab;
  late final Widget _profileTab;
  late final Widget _messagesTab;
  late final Widget _notificationsTab;
  late final Widget _adsTab;
  late final Widget _draftsTab;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _feedTab = FeedViewerScreen(
      onOpenNotifications: () async {
        if (MediaQuery.sizeOf(context).width >= 720) {
          _onTabTapped(6);
        } else {
          await NotificationsScreen.open(context);
          BadgeCounterService.instance.refreshCounts();
        }
      },
      onOpenMessages: () async {
        if (MediaQuery.sizeOf(context).width >= 720) {
          _onTabTapped(5);
        } else {
          await ChatListScreen.open(context);
          BadgeCounterService.instance.refreshCounts();
        }
      },
    );
    _exploreTab = const ExploreScreen();
    _profileTab = const ProfileScreen();
    _messagesTab = const ChatListScreen();
    _notificationsTab = const NotificationsScreen();
    _adsTab = const AdsManagerScreen();
    _draftsTab = const DraftsScheduledScreen();

    // Listen to static notifier updates
    ZevMainLayout.userAvatarNotifier.addListener(_onAvatarNotifierChanged);

    // Start centralized badge counter, real-time push & incoming call listeners
    BadgeCounterService.instance.startListening();
    NotificationService().startRealtimeNotifications();
    ZevRtcService.instance.startIncomingCallListener();

    // Listen to Supabase auth state changes
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        BadgeCounterService.instance.startListening();
        NotificationService().startRealtimeNotifications();
        ZevRtcService.instance.startIncomingCallListener();
      } else {
        BadgeCounterService.instance.stopListening();
        NotificationService().stopRealtimeNotifications();
        ZevRtcService.instance.stopIncomingCallListener();
      }
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
      return;
    }

    // Instant fallback from auth metadata (e.g. Google Sign-In avatar)
    final metaAvatar =
        user.userMetadata?['avatar_url']?.toString() ??
        user.userMetadata?['picture']?.toString() ??
        '';
    if (metaAvatar.isNotEmpty && _myAvatarUrl.isEmpty && mounted) {
      setState(() => _myAvatarUrl = metaAvatar);
    }

    try {
      final res = await supabase
          .from('profiles')
          .select(
            'id, avatar_url, username, first_name, last_name, bio, is_verified',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        _myProfileMap = Map<String, dynamic>.from(res);
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
    if (kIsWeb) {
      switch (index) {
        case 0:
          setBrowserUrl('/');
          break;
        case 1:
          setBrowserUrl('/explore');
          break;
        case 3:
          setBrowserUrl('/reels');
          break;
        case 4:
          setBrowserUrl(_myUsername.isNotEmpty ? '/@$_myUsername' : '/profile');
          break;
        case 5:
          setBrowserUrl('/messages');
          break;
        case 6:
          setBrowserUrl('/notifications');
          break;
        case 7:
          setBrowserUrl('/ads');
          break;
        case 8:
          setBrowserUrl('/creator-insights');
          break;
        case 9:
          setBrowserUrl('/drafts');
          break;
        case 10:
          setBrowserUrl('/zev-blue');
          break;
        case 11:
          setBrowserUrl('/settings');
          break;
        case 12:
          setBrowserUrl('/activity');
          break;
        case 13:
          setBrowserUrl('/security');
          break;
        case 14:
          setBrowserUrl('/help');
          break;
      }
    }
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

      // Tab 5: Messages (Persistent Web & Tablet Shell)
      _messagesTab,

      // Tab 6: Notifications (Persistent Web & Tablet Shell)
      _notificationsTab,

      // Tab 7: Advertise / Ads Manager
      _adsTab,

      // Tab 8: Creator Insights
      CreatorInsightsScreen(userProfile: _myProfileMap),

      // Tab 9: Drafts & Scheduled
      _draftsTab,

      // Tab 10: ZEV Blue Verification
      ZevBlueVerificationScreen(userProfile: _myProfileMap),

      // Tab 11: Settings & Privacy (Web/Tablet Shell with Sidebar)
      ProfileSettingsScreen(
        profile: _myProfileMap,
        onProfileUpdated: (updated) {
          setState(() {
            _myProfileMap = updated;
            final avatar = updated['avatar_url']?.toString();
            if (avatar != null && avatar.isNotEmpty) {
              _myAvatarUrl = avatar;
              ZevMainLayout.userAvatarNotifier.value = avatar;
            }
          });
        },
      ),

      // Tab 12: Your Activity (Web/Tablet Shell with Sidebar)
      UserActivityScreen(profile: _myProfileMap),

      // Tab 13: Security & 2FA (Web/Tablet Shell with Sidebar)
      const MfaSettingsScreen(),

      // Tab 14: Help & Support (Web/Tablet Shell with Sidebar)
      const HelpSupportScreen(),
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
              child: IndexedStack(index: _currentIndex, children: tabChildren),
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
          IndexedStack(index: _currentIndex, children: tabChildren),

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
                        Expanded(child: _buildCenterCreateButton()),
                        Expanded(
                          child: _buildNavItem(
                            index: 3,
                            icon: Icons.play_circle_outline_rounded,
                            activeIcon: Icons.play_circle_fill_rounded,
                            label: "Reels",
                          ),
                        ),
                        Expanded(child: _buildProfileNavItem(index: 4)),
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
    final sidebarBg = isReels ? const Color(0xFF0F172A) : Colors.white;
    final borderColor = isReels
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);

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
                    ValueListenableBuilder<int>(
                      valueListenable:
                          BadgeCounterService.instance.unreadMessagesCount,
                      builder: (context, count, _) => _buildSidebarNavItem(
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
                      builder: (context, count, _) => _buildSidebarNavItem(
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
                    _buildSidebarCreateButton(isExpanded: isExpanded),
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

                    // 4. Quick Access Hub (Advertise, Insights, Drafts, VIP Blue)
                    _buildSidebarNavItem(
                      index: 7,
                      icon: Icons.campaign_outlined,
                      activeIcon: Icons.campaign_rounded,
                      label: "Advertise",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 4),
                    _buildSidebarNavItem(
                      index: 8,
                      icon: Icons.insights_outlined,
                      activeIcon: Icons.insights_rounded,
                      label: "Creator Insights",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 4),
                    _buildSidebarNavItem(
                      index: 9,
                      icon: Icons.schedule_send_outlined,
                      activeIcon: Icons.schedule_send_rounded,
                      label: "Drafts & Scheduled",
                      isExpanded: isExpanded,
                      isReels: isReels,
                    ),
                    const SizedBox(height: 4),
                    _buildSidebarNavItem(
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
              _buildSidebarProfileItem(
                index: 4,
                isExpanded: isExpanded,
                isReels: isReels,
              ),
              const SizedBox(height: 6),
              // 6. More / Settings Menu (Instagram Web style)
              _buildSidebarMoreButton(isExpanded: isExpanded, isReels: isReels),
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
    int badgeCount = 0,
    Color? accentColor,
  }) {
    final isSelected = _currentIndex == index;
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
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
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
      message: isExpanded
          ? ''
          : (_myUsername.isNotEmpty ? "@$_myUsername" : "Profile"),
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
                              : (_myUsername.isNotEmpty
                                    ? _myUsername
                                    : "Profile"),
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

  Widget _buildSidebarMoreButton({
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
          onTap: () => _showSidebarMoreMenu(
            context,
            isReels: isReels,
            isExpanded: isExpanded,
          ),
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

  void _showSidebarMoreMenu(
    BuildContext context, {
    required bool isReels,
    required bool isExpanded,
  }) {
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
                                ? const Color(
                                    0xFF0F172A,
                                  ).withValues(alpha: 0.85)
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
                                color: const Color(
                                  0xFF0F172A,
                                ).withValues(alpha: 0.14),
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
                                    _onTabTapped(11);
                                  },
                                ),
                                _buildMoreMenuItem(
                                  icon: Icons.history_rounded,
                                  label: 'Your Activity',
                                  isReels: isReels,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _onTabTapped(12);
                                  },
                                ),
                                _buildMoreMenuItem(
                                  icon: Icons.campaign_outlined,
                                  label: 'Ads Manager',
                                  isReels: isReels,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _onTabTapped(7);
                                  },
                                ),
                                _buildMoreMenuItem(
                                  icon: Icons.security_rounded,
                                  label: 'Security & 2FA',
                                  isReels: isReels,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _onTabTapped(13);
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
                                    _onTabTapped(14);
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
                                    _showLogoutDialog(context);
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
    bool isDestructive = false,
    bool isReels = false,
  }) {
    final defaultColor = isReels ? Colors.white : const Color(0xFF334155);
    final color = isDestructive ? const Color(0xFFEF4444) : defaultColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        hoverColor: (isReels ? Colors.white : ZevColors.primaryBlue).withValues(
          alpha: 0.08,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isDestructive
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: color,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          "Log Out of ZEV?",
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        content: const Text(
          "You will need to sign back in with your account credentials.",
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Cancel",
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthHelper.logout(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text(
              "Log Out",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
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
                  color: isSelected
                      ? ZevColors.primaryBlue
                      : Colors.transparent,
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
                                : [
                                    const Color(0xFF00D4FF),
                                    const Color(0xFF536DFE),
                                  ],
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
                              color: const Color(
                                0xFF00D4FF,
                              ).withValues(alpha: 0.45),
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
                  color: isSelected
                      ? ZevColors.primaryBlue
                      : Colors.transparent,
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
