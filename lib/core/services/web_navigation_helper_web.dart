// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void updateBrowserUrl(String path) {
  try {
    final current = html.window.location.pathname ?? '';
    if (current != path) {
      html.window.history.pushState(null, '', path);
    }
  } catch (_) {}
}

void replaceBrowserUrl(String path) {
  try {
    html.window.history.replaceState(null, '', path);
  } catch (_) {}
}

String getCurrentBrowserPath() {
  try {
    final path = html.window.location.pathname ?? '/';
    return path.isEmpty ? '/' : path;
  } catch (_) {
    return '/';
  }
}

void listenToBrowserPopState(void Function(String path) onPop) {
  try {
    html.window.onPopState.listen((event) {
      final path = html.window.location.pathname ?? '/';
      onPop(path);
    });
  } catch (_) {}
}
