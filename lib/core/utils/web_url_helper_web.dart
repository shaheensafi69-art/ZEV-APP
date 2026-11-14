// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

void setBrowserUrl(String url) {
  try {
    html.window.history.pushState(null, '', url);
  } catch (_) {}
}

void replaceBrowserUrl(String url) {
  try {
    html.window.history.replaceState(null, '', url);
  } catch (_) {}
}

String getBrowserUrl() {
  try {
    return html.window.location.href;
  } catch (_) {
    return '';
  }
}

String getBrowserPath() {
  try {
    return html.window.location.pathname ?? '';
  } catch (_) {
    return '';
  }
}

String getBrowserSearch() {
  try {
    return html.window.location.search ?? '';
  } catch (_) {
    return '';
  }
}

Map<String, String> getBrowserQueryParams() {
  try {
    final uri = Uri.parse(html.window.location.href);
    return uri.queryParameters;
  } catch (_) {
    return {};
  }
}
