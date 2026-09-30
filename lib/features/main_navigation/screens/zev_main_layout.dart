import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme_service.dart';
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
import '../../../core/services/web_navigation_service.dart';
import '../../auth/screens/welcome_screen.dart';

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
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);

  String _currentUserName = "ZEV User";
  String _currentUserAvatar = "";
  String _currentUserHandle = "";
  List<Map<String, dynamic>> _suggestedUsers = [];
  List<HashtagItem> _trendingHashtags = [];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WebNavigationService.instance.updateUrlForTab(_currentIndex);
    WebNavigationService.instance.activeTabNotifier.addListener(
      _onWebNavPopState,
    );
    _loadUserProfile();
    _loadRightRailSuggestedUsers();
  }

  @override
  void dispose() {
    WebNavigationService.instance.activeTabNotifier.removeListener(
      _onWebNavPopState,
    );
    super.dispose();
  }

  void _onWebNavPopState() {
    final newTab = WebNavigationService.instance.activeTabNotifier.value;
    if (newTab != _currentIndex && mounted) {
      setState(() => _currentIndex = newTab);
    }
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('first_name, last_name, avatar_url, username')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        final fn = res['first_name'] ?? '';
        final ln = res['last_name'] ?? '';
        String un = (res['username']?.toString() ?? '').trim().replaceFirst(
          '@',
          '',
        );
        final full = "$fn $ln".trim();

        // If username is empty, auto-generate unique handle and persist to DB
        if (un.isEmpty && user.id.isNotEmpty) {
          final cleanBase = full.isNotEmpty
              ? full.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')
              : (user.email
                        ?.split('@')
                        .first
                        .toLowerCase()
                        .replaceAll(RegExp(r'[^a-z0-9]'), '') ??
                    'user');
          final randSuffix = (user.id.hashCode.abs() % 9000 + 1000).toString();
          un = "${cleanBase}_$randSuffix";
          try {
            await supabase
                .from('profiles')
                .update({'username': un})
                .eq('id', user.id);
          } catch (_) {}
        }

        setState(() {
          if (full.isNotEmpty) _currentUserName = full;
          _currentUserAvatar = res['avatar_url'] ?? '';
          _currentUserHandle = un.isNotEmpty ? un : 'user';
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
        WebNavigationService.instance.updateUrlForTab(2);
        setState(() {
          _currentIndex = 2;
        });
        return;
      }

      _showCreateModal();
      return;
    }

    HapticFeedback.lightImpact();
    WebNavigationService.instance.updateUrlForTab(index);
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
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.5 : 0.08,
                      ),
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

  /// Sleek modern sidebar for iPad, Android tablets, macOS, Windows, and Web browsers
  Widget _buildSideNav({required bool isDark, required bool isDesktop}) {
    final double width = isDesktop ? 250 : 80;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B0F19) : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2F6),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
            blurRadius: 12,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // ZEV Logo Header
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 12),
              child: Row(
                mainAxisAlignment: isDesktop
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [primaryPink, lightPinkAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: primaryPink.withValues(alpha: 0.38),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
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
                        Row(
                          children: [
                            Text(
                              'ZEV',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color: isDark ? Colors.white : primaryPink,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: primaryPink.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'PRO',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: primaryPink,
                                ),
                              ),
                            ),
                          ],
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
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: primaryPink,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primaryPink.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.zevTr('socialFeedHub').toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
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
                      icon: Icons.home_rounded,
                      label: context.zevTr('feed'),
                      index: 0,
                      isDark: isDark,
                      isDesktop: isDesktop,
                    ),
                    _buildSideNavItem(
                      icon: Icons.search_rounded,
                      label: context.zevTr('explore'),
                      index: 1,
                      isDark: isDark,
                      isDesktop: isDesktop,
                    ),
                    _buildSideNavItem(
                      icon: Icons.play_circle_outline_rounded,
                      label: context.zevTr('reels'),
                      index: 3,
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
                      icon: Icons.shopping_bag_outlined,
                      label: context.zevTr('shop'),
                      index: 5,
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

            // CREATE NEW POST Button (Modern Luxury Gradient)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _onTabTapped(2),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    height: isDesktop ? 48 : 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [primaryPink, Color(0xFFFF5277)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: primaryPink.withValues(alpha: 0.38),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
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
                              fontSize: 12.5,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Desktop User Profile Card at bottom of sidebar (Modern Luxury)
            if (isDesktop) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _onTabTapped(4),
                    borderRadius: BorderRadius.circular(16),
                    hoverColor: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF1F5F9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF131926)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.2 : 0.03,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [primaryPink, lightPinkAccent],
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 17,
                              backgroundColor: isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
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
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: primaryPink,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Tooltip(
                            message: isDark
                                ? "Switch to Light Mode"
                                : "Switch to Dark Mode",
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () async {
                                  await AppThemeService.instance.toggleTheme();
                                  if (mounted) setState(() {});
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    isDark
                                        ? Icons.light_mode_rounded
                                        : Icons.dark_mode_rounded,
                                    size: 19,
                                    color: isDark
                                        ? const Color(0xFFFBBF24)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Theme(
                            data: Theme.of(context).copyWith(
                              hoverColor: isDark
                                  ? Colors.white10
                                  : Colors.black12,
                            ),
                            child: PopupMenuButton<String>(
                              tooltip: 'Options',
                              color: isDark
                                  ? const Color(0xFF131926)
                                  : Colors.white,
                              elevation: 18,
                              shadowColor: Colors.black.withValues(
                                alpha: isDark ? 0.6 : 0.12,
                              ),
                              offset: const Offset(0, -10),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                                side: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF232D42)
                                      : cardBorder,
                                  width: 1.5,
                                ),
                              ),
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                size: 18,
                                color: isDark
                                    ? Colors.white60
                                    : const Color(0xFF94A3B8),
                              ),
                              onSelected: (val) async {
                                if (val == 'profile') {
                                  _onTabTapped(4);
                                } else if (val == 'settings') {
                                  _onTabTapped(8);
                                } else if (val == 'studio') {
                                  _onTabTapped(2);
                                } else if (val == 'logout') {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (dCtx) => AlertDialog(
                                      backgroundColor: isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(22),
                                        side: BorderSide(
                                          color: isDark
                                              ? const Color(0xFF334155)
                                              : cardBorder,
                                        ),
                                      ),
                                      title: Text(
                                        context.zevTr('logOut'),
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : textDark,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      content: Text(
                                        context.zevTr('logOutConfirm'),
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white70
                                              : textGrey,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dCtx, false),
                                          child: Text(
                                            context.zevTr('cancel'),
                                            style: const TextStyle(
                                              color: textGrey,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.redAccent,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(dCtx, true),
                                          child: Text(
                                            context.zevTr('logOut'),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await supabase.auth.signOut();
                                    if (mounted) {
                                      Navigator.of(context).pushAndRemoveUntil(
                                        MaterialPageRoute(
                                          builder: (_) => const WelcomeScreen(),
                                        ),
                                        (r) => false,
                                      );
                                    }
                                  }
                                }
                              },
                              itemBuilder: (ctx) => [
                                PopupMenuItem(
                                  value: 'profile',
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: primaryPink.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.person_outline_rounded,
                                          size: 17,
                                          color: primaryPink,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        context.zevTr('myProfile'),
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'settings',
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1)
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.settings_outlined,
                                          size: 17,
                                          color: Color(0xFF6366F1),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        context.zevTr('settings'),
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'studio',
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEC4899)
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.edit_note_rounded,
                                          size: 17,
                                          color: Color(0xFFEC4899),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        context.zevTr('creatorStudio'),
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuDivider(
                                  height: 1,
                                ),
                                PopupMenuItem(
                                  value: 'logout',
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.logout_rounded,
                                          size: 17,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        context.zevTr('logOut'),
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.redAccent,
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
                  ),
                ),
              ),
            ],
            if (!isDesktop) ...[
              Tooltip(
                message: isDark
                    ? "Switch to Light Mode"
                    : "Switch to Dark Mode",
                child: IconButton(
                  icon: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: isDark
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF64748B),
                    size: 22,
                  ),
                  onPressed: () async {
                    await AppThemeService.instance.toggleTheme();
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 6),
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
        horizontal: isDesktop ? 12 : 8,
        vertical: 3,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: customTap ?? () => _onTabTapped(index),
          borderRadius: BorderRadius.circular(14),
          hoverColor: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFF1F5F9),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 14 : 8,
              vertical: isDesktop ? 12 : 10,
            ),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? (isDark
                        ? const LinearGradient(
                            colors: [Color(0xFF381D45), Color(0xFF221733)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          )
                        : null)
                  : null,
              color: isSelected
                  ? (isDark ? null : const Color(0xFFFFF0F3))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? (isDark
                          ? const Color(0xFF5B2363)
                          : primaryPink.withValues(alpha: 0.22))
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: isDesktop
                ? Row(
                    children: [
                      Icon(
                        icon,
                        size: 21,
                        color: isSelected
                            ? (isDark ? const Color(0xFFF494AC) : primaryPink)
                            : (isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            letterSpacing: 0.2,
                            color: isSelected
                                ? (isDark ? Colors.white : primaryPink)
                                : (isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF334155)),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected)
                        Container(
                          width: 3.5,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFC466B),
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFFC466B,
                                ).withValues(alpha: 0.8),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 23,
                        color: isSelected
                            ? (isDark ? const Color(0xFFF494AC) : primaryPink)
                            : (isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: isSelected
                              ? primaryPink
                              : (isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF334155)),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
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
                          : (isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B))),
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
                          : (isDark
                                ? const Color(0xFF64748B)
                                : const Color(0xFF94A3B8))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// High-end Right Rail for Desktop Screens (Pixel-perfect matching screenshot)
  Widget _buildDesktopRightRail({required bool isDark}) {
    final cardBg = isDark ? const Color(0xFF131926) : Colors.white;
    final cardBorder = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);
    final headerColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final mutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B0F19) : const Color(0xFFF8FAFC),
        border: Border(left: BorderSide(color: cardBorder, width: 1)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        physics: const BouncingScrollPhysics(),
        children: [
          // 1. Trending Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.zevTr('trending'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: headerColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      '15,23k',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: mutedColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _trendingHashtags.isNotEmpty
                      ? _trendingHashtags
                            .take(6)
                            .map((h) => _buildHashtagChip('#${h.tag}', isDark))
                            .toList()
                      : [
                          _buildHashtagChip("#Sunset", isDark),
                          _buildHashtagChip("#DigitalArt", isDark),
                          _buildHashtagChip("#Tech2024", isDark),
                          _buildHashtagChip("#Fashion", isDark),
                          _buildHashtagChip("#OOTD", isDark),
                          _buildHashtagChip("#1,22k", isDark),
                        ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Active Contacts Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Active Contacts",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: headerColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          "Online",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 2x2 Contacts Grid
                Builder(
                  builder: (context) {
                    final c1 = _suggestedUsers.isNotEmpty
                        ? (_suggestedUsers[0]["first_name"] ?? "Maria")
                              .toString()
                        : "Maria";
                    final a1 =
                        _suggestedUsers.isNotEmpty &&
                            (_suggestedUsers[0]["avatar_url"] ?? "")
                                .toString()
                                .isNotEmpty
                        ? _suggestedUsers[0]["avatar_url"].toString()
                        : "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=120";
                    final c2 = _suggestedUsers.length > 1
                        ? (_suggestedUsers[1]["first_name"] ?? "Chloe")
                              .toString()
                        : "Chloe";
                    final a2 =
                        _suggestedUsers.length > 1 &&
                            (_suggestedUsers[1]["avatar_url"] ?? "")
                                .toString()
                                .isNotEmpty
                        ? _suggestedUsers[1]["avatar_url"].toString()
                        : "https://images.unsplash.com/photo-1517841905240-472988babdf9?w=120";
                    final c3 = _suggestedUsers.length > 2
                        ? (_suggestedUsers[2]["first_name"] ?? "David")
                              .toString()
                        : "David";
                    final a3 =
                        _suggestedUsers.length > 2 &&
                            (_suggestedUsers[2]["avatar_url"] ?? "")
                                .toString()
                                .isNotEmpty
                        ? _suggestedUsers[2]["avatar_url"].toString()
                        : "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=120";
                    final c4 = _suggestedUsers.length > 3
                        ? (_suggestedUsers[3]["first_name"] ?? "Ben").toString()
                        : "Ben";
                    final a4 =
                        _suggestedUsers.length > 3 &&
                            (_suggestedUsers[3]["avatar_url"] ?? "")
                                .toString()
                                .isNotEmpty
                        ? _suggestedUsers[3]["avatar_url"].toString()
                        : "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=120";

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildContactItem(c1, a1, isDark)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildContactItem(c2, a2, isDark)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _buildContactItem(c3, a3, isDark)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildContactItem(c4, a4, isDark)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Sponsored Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Sponsored",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: headerColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Icon(Icons.more_horiz_rounded, color: mutedColor, size: 20),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildSponsoredProductCard(
                        title: "Sleek watch",
                        imageUrl:
                            "https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=280",
                        isDark: isDark,
                      ),
                      const SizedBox(width: 10),
                      _buildSponsoredProductCard(
                        title: "Tech gadget promo",
                        imageUrl:
                            "https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=280",
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

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

  Widget _buildHashtagChip(String tag, bool isDark) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        WebNavigationService.instance.updateUrlForTab(1);
        setState(() {
          _currentIndex = 1;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2234) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF243048) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: Text(
          tag,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildContactItem(String name, String avatarUrl, bool isDark) {
    return InkWell(
      onTap: () {
        final user = supabase.auth.currentUser;
        if (user == null) {
          AuthRequiredModal.show(context, actionName: "chat with contacts");
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DirectChatListScreen()),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(
                    0xFFFC466B,
                  ).withValues(alpha: 0.15),
                  backgroundImage: NetworkImage(avatarUrl),
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF131926) : Colors.white,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSponsoredProductCard({
    required String title,
    required String imageUrl,
    required bool isDark,
  }) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182030) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF243048) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              imageUrl,
              height: 76,
              width: 114,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) => Container(
                height: 76,
                width: 114,
                color: isDark
                    ? const Color(0xFF243048)
                    : const Color(0xFFE2E8F0),
                child: const Icon(Icons.watch_rounded, color: primaryPink),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShopScreen()),
              );
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF243048)
                    : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "SHOP NOW",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
          ),
        ],
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
