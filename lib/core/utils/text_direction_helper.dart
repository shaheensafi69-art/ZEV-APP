import 'package:flutter/material.dart';

/// Professional text direction and alignment helper.
/// Automatically detects Persian, Dari, Pashto, and Arabic scripts (RTL)
/// vs English and Latin scripts (LTR) so text never looks broken or awkwardly flipped.
class TextDirectionHelper {
  TextDirectionHelper._();

  // Unicode ranges for Persian, Dari, Arabic, Urdu, Pashto
  static final RegExp _rtlRegExp = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
  );

  /// Check whether a given text is predominantly RTL (Persian, Dari, Arabic).
  static bool isRtl(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    final clean = text.trim();
    // Test the first meaningful characters
    for (int i = 0; i < clean.length && i < 40; i++) {
      final char = clean[i];
      if (_rtlRegExp.hasMatch(char)) return true;
      if (RegExp(r'[a-zA-Z]').hasMatch(char)) return false;
    }
    return _rtlRegExp.hasMatch(clean);
  }

  /// Get the appropriate TextDirection for the text content.
  static TextDirection getDirection(String? text) {
    return isRtl(text) ? TextDirection.rtl : TextDirection.ltr;
  }

  /// Get the appropriate TextAlign for the text content.
  static TextAlign getTextAlign(String? text, {TextAlign defaultLtr = TextAlign.left}) {
    return isRtl(text) ? TextAlign.right : defaultLtr;
  }
}
