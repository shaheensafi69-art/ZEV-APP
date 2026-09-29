import 'dart:html' as html;

/// Web implementation creating a browser blob: URL from bytes.
String? createBlobUrlFromBytes(List<int> bytes, {String mimeType = 'video/mp4'}) {
  try {
    final blob = html.Blob([bytes], mimeType.isNotEmpty ? mimeType : 'video/mp4');
    return html.Url.createObjectUrlFromBlob(blob);
  } catch (_) {
    return null;
  }
}

void revokeBlobUrl(String? url) {
  if (url == null || !url.startsWith('blob:')) return;
  try {
    html.Url.revokeObjectUrl(url);
  } catch (_) {}
}
