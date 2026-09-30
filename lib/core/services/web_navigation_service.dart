import 'package:flutter/foundation.dart';
import 'web_navigation_helper_stub.dart'
    if (dart.library.html) 'web_navigation_helper_web.dart'
    as web_helper;

class WebNavigationService {
  static final WebNavigationService _instance =
      WebNavigationService._internal();
  factory WebNavigationService() => _instance;
  WebNavigationService._internal();

  static WebNavigationService get instance => _instance;

  final ValueNotifier<int> activeTabNotifier = ValueNotifier<int>(0);

  static const Map<int, String> tabToPath = {
    0: '/feed',
    1: '/explore',
    2: '/create',
    3: '/reels',
    4: '/profile',
    5: '/shop',
    6: '/chat',
    7: '/notifications',
    8: '/settings',
  };

  void init() {
    if (!kIsWeb) return;
    try {
      web_helper.listenToBrowserPopState((path) {
        final resolvedIndex = getTabIndexFromPath(path);
        activeTabNotifier.value = resolvedIndex;
      });
    } catch (_) {}
  }

  /// Resolve tab index from path string
  int getTabIndexFromPath(String? path) {
    if (path == null || path.isEmpty || path == '/') {
      return 0; // Default to Feed
    }

    final clean = path.toLowerCase().trim();
    if (clean.startsWith('/feed') || clean == '/home') return 0;
    if (clean.startsWith('/explore') || clean.startsWith('/search')) return 1;
    if (clean.startsWith('/create') || clean.startsWith('/studio')) return 2;
    if (clean.startsWith('/reel')) return 3;
    if (clean.startsWith('/profile') || clean.startsWith('/user')) return 4;
    if (clean.startsWith('/shop') || clean.startsWith('/store')) return 5;
    if (clean.startsWith('/chat') ||
        clean.startsWith('/message') ||
        clean.startsWith('/dm')) {
      return 6;
    }
    if (clean.startsWith('/notification') || clean.startsWith('/activity')) {
      return 7;
    }
    if (clean.startsWith('/setting')) {
      return 8;
    }

    return 0;
  }

  /// Get current browser path and resolve initial tab on web load / reload
  int getInitialTabIndex() {
    if (!kIsWeb) return 0;
    try {
      final currentPath = web_helper.getCurrentBrowserPath();
      return getTabIndexFromPath(currentPath);
    } catch (_) {
      return 0;
    }
  }

  /// Update browser URL when tab changes in ZevMainLayout
  void updateUrlForTab(int tabIndex) {
    if (!kIsWeb) return;
    try {
      final path = tabToPath[tabIndex] ?? '/feed';
      web_helper.updateBrowserUrl(path);
      activeTabNotifier.value = tabIndex;
    } catch (_) {}
  }

  /// Push custom URL (e.g. /chat/123)
  void pushCustomUrl(String path) {
    if (!kIsWeb) return;
    try {
      web_helper.updateBrowserUrl(path);
    } catch (_) {}
  }
}
