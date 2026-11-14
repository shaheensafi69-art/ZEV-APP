import 'web_url_helper_stub.dart'
    if (dart.library.html) 'web_url_helper_web.dart' as platform;

void setBrowserUrl(String url) {
  platform.setBrowserUrl(url);
}

void replaceBrowserUrl(String url) {
  platform.replaceBrowserUrl(url);
}

String getBrowserUrl() {
  return platform.getBrowserUrl();
}

String getBrowserPath() {
  return platform.getBrowserPath();
}

String getBrowserSearch() {
  return platform.getBrowserSearch();
}

Map<String, String> getBrowserQueryParams() {
  return platform.getBrowserQueryParams();
}

