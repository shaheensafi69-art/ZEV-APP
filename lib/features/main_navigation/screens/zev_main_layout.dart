import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../feed/screens/feed_viewer_screen.dart';
import '../../feed/screens/reels_viewer_screen.dart';
import '../../feed/screens/user_profile_screen.dart';
import '../../feed/screens/create_post_screen.dart';
import '../../feed/screens/upload_reel_screen.dart';
import '../../feed/screens/create_story_screen.dart';
import '../../explore/screens/explore_search_screen.dart';
import '../../../core/widgets/auth_required_modal.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/services/language_service.dart';

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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTabTapped(int index) {
    if (index == 2) {
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
        customMessage: "Log in or sign up to share posts, reels, and stories with friends on ZEV.",
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryPink.withValues(alpha: 0.2)),
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
                          builder: (_) => const CreatePostScreen(),
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
                          builder: (_) => const UploadReelScreen(),
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
                          builder: (_) => const CreateStoryScreen(),
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
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
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
          const SizedBox(), // Placeholder for Create button
          StudentReelsScreen(isActive: _currentIndex == 3),
          const UserProfileScreen(),
        ];

        final isPhone = ResponsiveLayout.isPhone(context);
        final isDesktop = ResponsiveLayout.isDesktop(context);

        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: isPhone
              ? Scaffold(
                  extendBody: true,
                  body: IndexedStack(
                    index: _currentIndex,
                    children: pages,
                  ),
                  bottomNavigationBar: _buildBottomBar(context, isDark),
                )
              : Scaffold(
                  body: Row(
                    children: [
                      _buildSideNav(isDark: isDark, isDesktop: isDesktop),
                      Expanded(
                        child: IndexedStack(
                          index: _currentIndex,
                          children: pages,
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  /// Floating glassmorphic bottom bar for iPhone and Android phones
  Widget _buildBottomBar(BuildContext context, bool isDark) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF111827).withValues(alpha: 0.88)
                    : Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : primaryPink.withValues(alpha: 0.2),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryPink.withValues(alpha: 0.18),
                    blurRadius: 26,
                    offset: const Offset(0, 8),
                  ),
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
                  ),
                  _buildNavItem(
                    icon: Icons.explore_rounded,
                    label: context.zevTr('explore'),
                    index: 1,
                    isSelected: _currentIndex == 1,
                    isDark: isDark,
                  ),
                  // Center Floating Create (+) Button
                  GestureDetector(
                    onTap: () => _onTabTapped(2),
                    child: Container(
                      width: 46,
                      height: 46,
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
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                  _buildNavItem(
                    icon: Icons.play_circle_fill_rounded,
                    label: context.zevTr('reels'),
                    index: 3,
                    isSelected: _currentIndex == 3,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    icon: Icons.person_rounded,
                    label: context.zevTr('profile'),
                    index: 4,
                    isSelected: _currentIndex == 4,
                    isDark: isDark,
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
  Widget _buildSideNav({
    required bool isDark,
    required bool isDesktop,
  }) {
    final double width = isDesktop ? 220 : 80;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE2E8F0),
            width: 1,
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
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 18 : 12),
              child: Row(
                mainAxisAlignment:
                    isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [primaryPink, lightPinkAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: primaryPink.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/logo-without-b.png',
                      height: 22,
                      width: 22,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (isDesktop) ...[
                    const SizedBox(width: 12),
                    const Text(
                      'ZEV',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: primaryPink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            // Nav Items
            _buildSideNavItem(
              icon: Icons.home_rounded,
              label: context.zevTr('feed'),
              index: 0,
              isDark: isDark,
              isDesktop: isDesktop,
            ),
            _buildSideNavItem(
              icon: Icons.explore_rounded,
              label: context.zevTr('explore'),
              index: 1,
              isDark: isDark,
              isDesktop: isDesktop,
            ),
            _buildSideNavItem(
              icon: Icons.play_circle_fill_rounded,
              label: context.zevTr('reels'),
              index: 3,
              isDark: isDark,
              isDesktop: isDesktop,
            ),
            _buildSideNavItem(
              icon: Icons.person_rounded,
              label: context.zevTr('profile'),
              index: 4,
              isDark: isDark,
              isDesktop: isDesktop,
            ),
            const Spacer(),
            // Create (+) Button
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 16 : 12,
                vertical: 16,
              ),
              child: InkWell(
                onTap: () => _onTabTapped(2),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  height: isDesktop ? 48 : 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [primaryPink, lightPinkAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: primaryPink.withValues(alpha: 0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                      if (isDesktop) ...[
                        const SizedBox(width: 8),
                        Text(
                          context.zevTr('create'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
  }) {
    final isSelected = _currentIndex == index;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 12 : 8,
        vertical: 4,
      ),
      child: InkWell(
        onTap: () => _onTabTapped(index),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 14 : 8,
            vertical: isDesktop ? 12 : 10,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? primaryPink.withValues(alpha: 0.2)
                    : primaryPink.withValues(alpha: 0.12))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: isDesktop
              ? Row(
                  children: [
                    Icon(
                      icon,
                      size: 24,
                      color: isSelected
                          ? primaryPink
                          : (isDark ? Colors.grey[400] : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
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
                          : (isDark ? Colors.grey[400] : const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryPink.withValues(alpha: isDark ? 0.22 : 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 24,
                color: isSelected
                    ? primaryPink
                    : (isDark ? Colors.white54 : const Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? primaryPink
                    : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
