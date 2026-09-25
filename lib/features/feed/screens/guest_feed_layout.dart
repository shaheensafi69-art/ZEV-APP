import 'package:flutter/material.dart';
import '../../auth/screens/login_screen.dart';
import 'feed_viewer_screen.dart';
import 'reels_viewer_screen.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/services/language_service.dart';

/// Clean, dedicated layout for guest users to explore Feed and Reels seamlessly.
class GuestFeedLayout extends StatefulWidget {
  final int initialTab;
  const GuestFeedLayout({super.key, this.initialTab = 0});

  @override
  State<GuestFeedLayout> createState() => _GuestFeedLayoutState();
}

class _GuestFeedLayoutState extends State<GuestFeedLayout> {
  late int _currentIndex;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color surfaceWhite = Colors.white;
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
  }

  void _navigateToLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, activeLocale, _) {
        final isRtl = LanguageService.isRtl(activeLocale.languageCode);

        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            backgroundColor: _currentIndex == 1 ? Colors.black : surfaceWhite,
            body: IndexedStack(
              index: _currentIndex,
              children: [
                const FeedViewerScreen(),
                StudentReelsScreen(isActive: _currentIndex == 1),
              ],
            ),

            // Bottom navigation bar for guests (Feed, Reels, Sign In)
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                color: _currentIndex == 1 ? const Color(0xFF0F172A) : surfaceWhite,
                border: Border(
                  top: BorderSide(
                    color: _currentIndex == 1 ? Colors.white12 : cardBorder,
                    width: 1.5,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Feed tab
                      _buildNavItem(
                        index: 0,
                        icon: Icons.dynamic_feed_rounded,
                        label: context.zevTr('feed'),
                        isDark: _currentIndex == 1,
                      ),

                      // Reels tab
                      _buildNavItem(
                        index: 1,
                        icon: Icons.play_circle_fill_rounded,
                        label: context.zevTr('reels'),
                        isDark: _currentIndex == 1,
                      ),

                      // Sign In shortcut button
                      InkWell(
                        onTap: _navigateToLogin,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: primaryPink.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: primaryPink.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.login_rounded, size: 16, color: primaryPink),
                              const SizedBox(width: 6),
                              Text(
                                context.zevTr('signIn'),
                                style: const TextStyle(
                                  color: primaryPink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
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
          ),
        );
      },
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    final isSelected = _currentIndex == index;
    final activeColor = primaryPink;
    final inactiveColor = isDark ? Colors.white60 : textGrey;

    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryPink.withOpacity(isDark ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
