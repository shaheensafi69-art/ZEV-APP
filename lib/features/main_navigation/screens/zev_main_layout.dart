import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../feed/screens/feed_viewer_screen.dart';
import '../../feed/screens/reels_viewer_screen.dart';
import '../../feed/screens/user_profile_screen.dart';
import '../../creator_studio/screens/zev_creator_studio_screen.dart';
import '../../explore/screens/explore_search_screen.dart';
import '../../profile/screens/zev_settings_screen.dart';
import '../../profile/screens/zev_terms_of_service_screen.dart';
import '../../profile/screens/zev_privacy_policy_screen.dart';
import '../../shop/screens/shop_screen.dart';
import '../../chat/screens/direct_chat_list_screen.dart';
import '../../notifications/screens/activity_notifications_screen.dart';
import '../../../core/widgets/auth_required_modal.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/hashtag_service.dart';

class ZevMainLayout extends StatefulWidget {
  final int initialIndex;
  const ZevMainLayout({super.key, this.initialIndex = 0});

  @override
  State<ZevMainLayout> createState() => _ZevMainLayoutState();
}

class _ZevMainLayoutState extends State<ZevMainLayout> {
  late int _currentIndex;
  final supabase = Supabase.instance.client;

  // Vibrant Pink matching the official ZEV app icon
  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkAccent = Color(0xFFFF5E8A);

  String _currentUserName = "ZEV User";
  String _currentUserAvatar = "";
  String _currentUserHandle = "";
  List<Map<String, dynamic>> _suggestedUsers = [];
  final Set<String> _rightRailFollowingIds = {};
  List<HashtagItem> _trendingHashtags = [];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadUserProfile();
    _loadRightRailSuggestedUsers();
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('first_name, last_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        final fn = res['first_name'] ?? '';
        final ln = res['last_name'] ?? '';
        final full = "$fn $ln".trim();
        setState(() {
          if (full.isNotEmpty) _currentUserName = full;
          _currentUserAvatar = res['avatar_url'] ?? '';
          _currentUserHandle = user.email?.split('@').first ?? 'user';
        });
      }
    } catch (_) {}
  }

  Future<void> _loadRightRailSuggestedUsers() async {
    final currentUserId = supabase.auth.currentUser?.id;
    try {
      final res = await supabase
          .from('profiles')
          .select('id, first_name, last_name, avatar_url, role')
          .neq('id', currentUserId ?? '')
          .limit(4);

      final tags = await HashtagService.instance.getTrendingHashtags();

      if (mounted) {
        setState(() {
          _suggestedUsers = List<Map<String, dynamic>>.from(res);
          _trendingHashtags = tags;
        });
      }
    } catch (_) {}
  }

  void _onTabTapped(int index) {
    if (index == 2) {
      final isGuest = supabase.auth.currentUser == null;
      if (isGuest) {
        AuthRequiredModal.show(
          context,
          actionName: "create posts or reels",
          customMessage:
              "Log in or sign up to share posts, reels, and stories with friends on ZEV.",
        );
        return;
      }

      if (!ResponsiveLayout.isPhone(context)) {
        HapticFeedback.lightImpact();
        setState(() {
          _currentIndex = 2;
        });
        return;
      }

      _showCreateModal();
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _currentIndex = index;
    });
  }

  void _showCreateModal() {
    final isGuest = supabase.auth.currentUser == null;
    if (isGuest) {
      AuthRequiredModal.show(
        context,
        actionName: "create posts or reels",
        customMessage:
            "Log in or sign up to share posts, reels, and stories with friends on ZEV.",
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131B2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: primaryPink.withValues(alpha: 0.2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryPink.withValues(alpha: 0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/logo-without-b.png',
                      height: 18,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.zevTr('create'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCreateItem(
                    icon: Icons.article_rounded,
                    label: context.zevTr('sharePost'),
                    gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const ZevCreatorStudioScreen(initialTab: 0),
                        ),
                      );
                    },
                  ),
                  _buildCreateItem(
                    icon: Icons.movie_filter_rounded,
                    label: context.zevTr('uploadReel'),
                    gradient: const [primaryPink, lightPinkAccent],
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const ZevCreatorStudioScreen(initialTab: 1),
                        ),
                      );
                    },
                  ),
                  _buildCreateItem(
                    icon: Icons.camera_alt_rounded,
                    label: context.zevTr('addToStory'),
                    gradient: const [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const ZevCreatorStudioScreen(initialTab: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateItem({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, activeLocale, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final isRtl = LanguageService.isRtl(activeLocale.languageCode);

        final pages = [
          const FeedViewerScreen(),
          const ExploreSearchScreen(),
          ZevCreatorStudioScreen(
            onBack: () => setState(() => _currentIndex = 0),
          ),
          StudentReelsScreen(isActive: _currentIndex == 3),
          const UserProfileScreen(),
          const ShopScreen(),
          const DirectChatListScreen(),
          const ActivityNotificationsScreen(),
          const ZevSettingsScreen(),
        ];

        final isPhone = ResponsiveLayout.isPhone(context);
        final isDesktop = ResponsiveLayout.isDesktop(context);
        final screenWidth = MediaQuery.of(context).size.width;

        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: isPhone
              ? Scaffold(
                  extendBody: true,
                  body: IndexedStack(index: _currentIndex, children: pages),
                  bottomNavigationBar: _buildBottomBar(context, isDark),
                )
              : Scaffold(
                  body: Row(
                    children: [
                      // Desktop / Tablet Left Navigation Sidebar
                      _buildSideNav(isDark: isDark, isDesktop: isDesktop),

                      // Center Content Area
                      Expanded(
                        child: IndexedStack(
                          index: _currentIndex,
                          children: pages,
                        ),
                      ),

                      // Desktop Right Rail for Feed & Explore on wide screens
                      if (isDesktop &&
                          screenWidth >= 1220 &&
                          (_currentIndex == 0 || _currentIndex == 1))
                        _buildDesktopRightRail(isDark: isDark),
                    ],
                  ),
                ),
        );
      },
    );
  }

  /// Floating glassmorphic bottom bar for iPhone and Android phones
  Widget _buildBottomBar(BuildContext context, bool isDark) {
    final bool isReels = _currentIndex == 3;
    final double barHeight = isReels ? 50.0 : 64.0;
    final EdgeInsets marginPadding = isReels
        ? const EdgeInsets.fromLTRB(28, 0, 28, 8)
        : const EdgeInsets.fromLTRB(18, 0, 18, 14);

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: marginPadding,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              height: barHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isReels
                    ? const Color(0xFF0A0A0A).withValues(alpha: 0.95)
                    : (isDark
                        ? const Color(0xFF111827).withValues(alpha: 0.88)
                        : Colors.white.withValues(alpha: 0.94)),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: isReels
                      ? Colors.white.withValues(alpha: 0.16)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : primaryPink.withValues(alpha: 0.2)),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isReels
                        ? Colors.black.withValues(alpha: 0.6)
                        : primaryPink.withValues(alpha: 0.18),
                    blurRadius: isReels ? 18 : 26,
                    offset: const Offset(0, 6),
                  ),
                  if (!isReels)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(
                    icon: Icons.home_rounded,
                    label: context.zevTr('feed'),
                    index: 0,
                    isSelected: _currentIndex == 0,
                    isDark: isDark,
                    isReels: isReels,
                  ),
                  _buildNavItem(
                    icon: Icons.explore_rounded,
                    label: context.zevTr('explore'),
                    index: 1,
                    isSelected: _currentIndex == 1,
                    isDark: isDark,
                    isReels: isReels,
                  ),
                  // Center Floating Create (+) Button
                  GestureDetector(
                    onTap: () => _onTabTapped(2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      width: isReels ? 38 : 46,
                      height: isReels ? 38 : 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [primaryPink, lightPinkAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primaryPink.withValues(alpha: 0.45),
                            blurRadius: isReels ? 8 : 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: isReels ? 22 : 30,
                      ),
                    ),
                  ),
                  _buildNavItem(
                    icon: Icons.play_circle_fill_rounded,
                    label: context.zevTr('reels'),
                    index: 3,
                    isSelected: _currentIndex == 3,
                    isDark: isDark,
                    isReels: isReels,
                  ),
                  _buildNavItem(
                    icon: Icons.person_rounded,
                    label: context.zevTr('profile'),
                    index: 4,
                    isSelected: _currentIndex == 4,
                    isDark: isDark,
                    isReels: isReels,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sleek sidebar for iPad, Android tablets, macOS, Windows, and Web browsers
  Widget _buildSideNav({required bool isDark, required bool isDesktop}) {
    final double width = isDesktop ? 240 : 80;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF6F8FB),
        border: Border(
          right: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.04),
            blurRadius: 16,
            offset: const Offset(3, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 22),
            // ZEV Logo Header
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 12),
              child: Row(
                mainAxisAlignment: isDesktop
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [primaryPink, lightPinkAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isDark
                          ? [
                              BoxShadow(
                                color: primaryPink.withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.06),
                                blurRadius: 6,
                                offset: const Offset(-2, -2),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: primaryPink.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(2, 3),
                              ),
                              const BoxShadow(
                                color: Colors.white,
                                blurRadius: 8,
                                offset: Offset(-2, -2),
                              ),
                            ],
                    ),
                    child: Image.asset(
                      'assets/logo-without-b.png',
                      height: 24,
                      width: 24,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (isDesktop) ...[
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ZEV',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: primaryPink,
                          ),
                        ),
                        Text(
                          'SOCIAL APP',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: isDark
                                ? Colors.white38
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Section Indicator
            if (isDesktop)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: primaryPink,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.zevTr('socialFeedHub'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: isDark
                            ? Colors.white38
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),

            // Scrollable Navigation Items so it never overflows vertically
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _buildSideNavItem(
                      icon: Icons.dynamic_feed_rounded,
                      label: context.zevTr('feedStream'),
                      index: 0,
                      isDark: isDark,
                      isDesktop: isDesktop,
                    ),
                    _buildSideNavItem(
                      icon: Icons.play_circle_fill_rounded,
                      label: context.zevTr('exploreReels'),
                      index: 3,
                      isDark: isDark,
                      isDesktop: isDesktop,
                    ),
                    _buildSideNavItem(
                      icon: Icons.storefront_rounded,
                      label: context.zevTr('shop'),
                      index: 5,
                      isDark: isDark,
                      isDesktop: isDesktop,
                    ),
                    _buildSideNavItem(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: context.zevTr('messages'),
                      index: 6,
                      isDark: isDark,
                      isDesktop: isDesktop,
                    ),
                    _buildSideNavItem(
                      icon: Icons.favorite_border_rounded,
                      label: context.zevTr('likesAndComments'),
                      index: 7,
                      isDark: isDark,
                      isDesktop: isDesktop,
                    ),
                    _buildSideNavItem(
                      icon: Icons.person_outline_rounded,
                      label: context.zevTr('myProfile'),
                      index: 4,
                      isDark: isDark,
                      isDesktop: isDesktop,
                    ),
                    _buildSideNavItem(
                      icon: Icons.settings_outlined,
                      label: context.zevTr('settings'),
                      index: 8,
                      isDark: isDark,
                      isDesktop: isDesktop,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // CREATE NEW POST Button (Neumorphic)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 12),
              child: InkWell(
                onTap: () => _onTabTapped(2),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: double.infinity,
                  height: isDesktop ? 48 : 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [primaryPink, Color(0xFFFF8A00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: isDark
                        ? [
                            BoxShadow(
                              color: primaryPink.withValues(alpha: 0.45),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(-2, -2),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: primaryPink.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(3, 4),
                            ),
                            const BoxShadow(
                              color: Colors.white,
                              blurRadius: 8,
                              offset: Offset(-3, -3),
                            ),
                            const BoxShadow(
                              color: Color(0xFFD1D9E6),
                              blurRadius: 6,
                              offset: Offset(2, 2),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.edit_note_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      if (isDesktop) ...[
                        const SizedBox(width: 8),
                        Text(
                          context.zevTr('createNewPost').toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Desktop User Profile Pill at bottom of sidebar (Neumorphic)
            if (isDesktop) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: InkWell(
                  onTap: () => _onTabTapped(4),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF131D30)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white,
                        width: 1.2,
                      ),
                      boxShadow: isDark
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                offset: const Offset(2, 2),
                                blurRadius: 6,
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.03),
                                offset: const Offset(-2, -2),
                                blurRadius: 4,
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: const Color(0xFFCBD5E1)
                                    .withValues(alpha: 0.8),
                                offset: const Offset(2, 2),
                                blurRadius: 5,
                              ),
                              const BoxShadow(
                                color: Colors.white,
                                offset: Offset(-2, -2),
                                blurRadius: 5,
                              ),
                            ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: primaryPink.withValues(alpha: 0.15),
                          backgroundImage: _currentUserAvatar.isNotEmpty
                              ? NetworkImage(_currentUserAvatar)
                              : null,
                          child: _currentUserAvatar.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  color: primaryPink,
                                  size: 18,
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentUserName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                "@$_currentUserHandle",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white38
                                      : const Color(0xFF94A3B8),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.more_horiz_rounded,
                          size: 18,
                          color: isDark
                              ? Colors.white38
                              : const Color(0xFF94A3B8),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildSideNavItem({
    required IconData icon,
    required String label,
    required int index,
    required bool isDark,
    required bool isDesktop,
    VoidCallback? customTap,
  }) {
    final isSelected = index != 99 && _currentIndex == index;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 14 : 8,
        vertical: 4,
      ),
      child: InkWell(
        onTap: customTap ?? () => _onTabTapped(index),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 16 : 8,
            vertical: isDesktop ? 13 : 11,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? const Color(0xFF162033)
                    : const Color(0xFFECEFF5))
                : (isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? primaryPink.withValues(alpha: 0.5)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.white),
              width: 1.2,
            ),
            boxShadow: isSelected
                ? (isDark
                    ? [
                        BoxShadow(
                          color: primaryPink.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          offset: const Offset(2, 2),
                          blurRadius: 4,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: primaryPink.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                        BoxShadow(
                          color: const Color(0xFFCBD5E1).withValues(alpha: 0.7),
                          offset: const Offset(2, 2),
                          blurRadius: 4,
                        ),
                        const BoxShadow(
                          color: Colors.white,
                          offset: Offset(-2, -2),
                          blurRadius: 4,
                        ),
                      ])
                : (isDark
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          offset: const Offset(2, 2),
                          blurRadius: 4,
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.02),
                          offset: const Offset(-1, -1),
                          blurRadius: 3,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: const Color(0xFFE2E8F0).withValues(alpha: 0.7),
                          offset: const Offset(2, 2),
                          blurRadius: 4,
                        ),
                        const BoxShadow(
                          color: Colors.white,
                          offset: Offset(-2, -2),
                          blurRadius: 4,
                        ),
                      ]),
          ),
          child: isDesktop
              ? Row(
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: isSelected
                          ? primaryPink
                          : (isDark
                                ? Colors.grey[400]
                                : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: isSelected
                              ? primaryPink
                              : (isDark
                                    ? Colors.grey[200]
                                    : const Color(0xFF1E293B)),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 24,
                      color: isSelected
                          ? primaryPink
                          : (isDark
                                ? Colors.grey[400]
                                : const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: isSelected
                            ? primaryPink
                            : (isDark
                                  ? Colors.grey[400]
                                  : const Color(0xFF64748B)),
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required bool isSelected,
    required bool isDark,
    bool isReels = false,
  }) {
    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 54,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: isReels ? 8 : 10,
                vertical: isReels ? 2 : 4,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isReels
                        ? primaryPink.withValues(alpha: 0.28)
                        : primaryPink.withValues(alpha: isDark ? 0.22 : 0.12))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: isReels ? 21 : 24,
                color: isSelected
                    ? (isReels ? Colors.white : primaryPink)
                    : (isReels
                        ? Colors.white70
                        : (isDark ? Colors.white54 : const Color(0xFF64748B))),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: isReels ? 9 : 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? (isReels ? Colors.white : primaryPink)
                    : (isReels
                        ? Colors.white54
                        : (isDark ? Colors.white38 : const Color(0xFF94A3B8))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// High-end Right Rail for Desktop Screens
  Widget _buildDesktopRightRail({required bool isDark}) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFAFAFA),
        border: Border(
          left: BorderSide(
            color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(18),
        physics: const BouncingScrollPhysics(),
        children: [
          // Trending on ZEV card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: primaryPink,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.zevTr('trendingOnZev'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_trendingHashtags.isNotEmpty)
                  ..._trendingHashtags.take(6).map((h) => _buildTrendingItem(
                        "#${h.tag}",
                        "${h.postsCount + h.reelsCount > 999 ? '${((h.postsCount + h.reelsCount) / 1000).toStringAsFixed(1)}K' : '${h.postsCount + h.reelsCount}'} posts",
                        isDark,
                      ))
                else ...[
                  _buildTrendingItem("#Technology", "14.2K posts", isDark),
                  _buildTrendingItem("#Photography", "8.5K posts", isDark),
                  _buildTrendingItem("#ArtAndDesign", "6.1K posts", isDark),
                  _buildTrendingItem("#Education", "12.8K posts", isDark),
                  _buildTrendingItem("#Music", "5.3K posts", isDark),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Suggested Users / Who to Follow
          if (_suggestedUsers.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: primaryPink,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.zevTr('whoToFollow'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._suggestedUsers.map((user) {
                    final uid = user['id']?.toString() ?? '';
                    final fn = user['first_name'] ?? '';
                    final ln = user['last_name'] ?? '';
                    final name = "$fn $ln".trim().isNotEmpty
                        ? "$fn $ln".trim()
                        : "ZEV User";
                    final avatar = user['avatar_url']?.toString() ?? '';
                    final isFollowing = _rightRailFollowingIds.contains(uid);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: primaryPink.withValues(
                              alpha: 0.15,
                            ),
                            backgroundImage: avatar.isNotEmpty
                                ? NetworkImage(avatar)
                                : null,
                            child: avatar.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: primaryPink,
                                    size: 16,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (isFollowing) {
                                  _rightRailFollowingIds.remove(uid);
                                } else {
                                  _rightRailFollowingIds.add(uid);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isFollowing
                                    ? (isDark
                                          ? Colors.white10
                                          : const Color(0xFFF1F5F9))
                                    : primaryPink,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isFollowing
                                    ? context.zevTr('following')
                                    : context.zevTr('follow'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isFollowing
                                      ? (isDark
                                            ? Colors.white70
                                            : const Color(0xFF64748B))
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Explore Topics Cloud
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.explore_rounded,
                      color: Color(0xFF6366F1),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Explore Topics 🧭",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildTopicBadge("💻 Coding", isDark),
                    _buildTopicBadge("📈 Trading", isDark),
                    _buildTopicBadge("🤖 AI & Tech", isDark),
                    _buildTopicBadge("🎨 Design", isDark),
                    _buildTopicBadge("📚 Education", isDark),
                    _buildTopicBadge("🚀 Startups", isDark),
                    _buildTopicBadge("🔥 Trending", isDark),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ZEV Community Pulse & Daily Spotlight
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E1B4B), const Color(0xFF311042)]
                    : [const Color(0xFFFAF5FF), const Color(0xFFFFF1F2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: primaryPink.withValues(alpha: 0.25),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryPink.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF22C55E),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Live Community",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white70 : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "1,420+ Online",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: primaryPink.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [primaryPink, lightPinkAccent],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Featured Creator Hub",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Share posts & grow your reach",
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Footer links
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildFooterLink(context.zevTr('termsOfService'), () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ZevTermsOfServiceScreen(),
                    ),
                  );
                }, isDark),
                Text(
                  "•",
                  style: TextStyle(
                    color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                    fontSize: 11,
                  ),
                ),
                _buildFooterLink(context.zevTr('privacyPolicy'), () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ZevPrivacyPolicyScreen(),
                    ),
                  );
                }, isDark),
                Text(
                  "•",
                  style: TextStyle(
                    color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                    fontSize: 11,
                  ),
                ),
                _buildFooterLink(
                  context.zevTr('settings'),
                  () => _onTabTapped(8),
                  isDark,
                ),
                const SizedBox(width: double.infinity, height: 6),
                Text(
                  "© 2026 ZEV Social Inc. All rights reserved.",
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingItem(String tag, String count, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            tag,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          Text(
            count,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicBadge(String label, bool isDark) {
    return InkWell(
      onTap: () {
        _onTabTapped(1); // navigate to Explore
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterLink(String label, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white54 : const Color(0xFF64748B),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
