import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppLanguage {
  final String code;
  final String name;
  final String englishName;
  final String flag;
  final String countryCode;
  final bool isRtl;

  const AppLanguage({
    required this.code,
    required this.name,
    required this.englishName,
    required this.flag,
    required this.countryCode,
    required this.isRtl,
  });
}

class LanguageService {
  LanguageService._internal();
  static final LanguageService instance = LanguageService._internal();

  static const String _prefKey = 'user_selected_language';

  // Full list of 19 supported languages with native names, flags, and RTL status
  static const List<AppLanguage> supportedLanguages = [
    AppLanguage(
      code: 'en',
      name: 'English',
      englishName: 'English',
      flag: '🇬🇧',
      countryCode: 'GB',
      isRtl: false,
    ),
    AppLanguage(
      code: 'fa',
      name: 'Persian (Dari)',
      englishName: 'Persian (Dari)',
      flag: '🇦🇫',
      countryCode: 'AF',
      isRtl: true,
    ),
    AppLanguage(
      code: 'ps',
      name: 'Pashto',
      englishName: 'Pashto',
      flag: '🇦🇫',
      countryCode: 'AF',
      isRtl: true,
    ),
    AppLanguage(
      code: 'ru',
      name: 'Русский',
      englishName: 'Russian',
      flag: '🇷🇺',
      countryCode: 'RU',
      isRtl: false,
    ),
    AppLanguage(
      code: 'tr',
      name: 'Türkçe',
      englishName: 'Turkish',
      flag: '🇹🇷',
      countryCode: 'TR',
      isRtl: false,
    ),
    AppLanguage(
      code: 'de',
      name: 'Deutsch',
      englishName: 'German',
      flag: '🇩🇪',
      countryCode: 'DE',
      isRtl: false,
    ),
    AppLanguage(
      code: 'fr',
      name: 'Français',
      englishName: 'French',
      flag: '🇫🇷',
      countryCode: 'FR',
      isRtl: false,
    ),
    AppLanguage(
      code: 'ar',
      name: 'Arabic',
      englishName: 'Arabic',
      flag: '🇸🇦',
      countryCode: 'SA',
      isRtl: true,
    ),
    AppLanguage(
      code: 'ur',
      name: 'Urdu',
      englishName: 'Urdu',
      flag: '🇵🇰',
      countryCode: 'PK',
      isRtl: true,
    ),
    AppLanguage(
      code: 'es',
      name: 'Español',
      englishName: 'Spanish',
      flag: '🇪🇸',
      countryCode: 'ES',
      isRtl: false,
    ),
    AppLanguage(
      code: 'zh',
      name: '简体中文',
      englishName: 'Chinese (Simplified)',
      flag: '🇨🇳',
      countryCode: 'CN',
      isRtl: false,
    ),
    AppLanguage(
      code: 'hi',
      name: 'हिन्दी',
      englishName: 'Hindi',
      flag: '🇮🇳',
      countryCode: 'IN',
      isRtl: false,
    ),
    AppLanguage(
      code: 'it',
      name: 'Italiano',
      englishName: 'Italian',
      flag: '🇮🇹',
      countryCode: 'IT',
      isRtl: false,
    ),
    AppLanguage(
      code: 'pt',
      name: 'Português',
      englishName: 'Portuguese',
      flag: '🇵🇹',
      countryCode: 'PT',
      isRtl: false,
    ),
    AppLanguage(
      code: 'ja',
      name: '日本語',
      englishName: 'Japanese',
      flag: '🇯🇵',
      countryCode: 'JP',
      isRtl: false,
    ),
    AppLanguage(
      code: 'ko',
      name: '한국어',
      englishName: 'Korean',
      flag: '🇰🇷',
      countryCode: 'KR',
      isRtl: false,
    ),
    AppLanguage(
      code: 'nl',
      name: 'Nederlands',
      englishName: 'Dutch',
      flag: '🇳🇱',
      countryCode: 'NL',
      isRtl: false,
    ),
    AppLanguage(
      code: 'uz',
      name: 'Oʻzbekcha',
      englishName: 'Uzbek',
      flag: '🇺🇿',
      countryCode: 'UZ',
      isRtl: false,
    ),
    AppLanguage(
      code: 'id',
      name: 'Bahasa Indonesia',
      englishName: 'Indonesian',
      flag: '🇮🇩',
      countryCode: 'ID',
      isRtl: false,
    ),
  ];

  final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(
    const Locale('en'),
  );

  Locale get currentLocale => localeNotifier.value;
  String get currentLanguageCode => localeNotifier.value.languageCode;

  bool get isCurrentRtl {
    return isRtl(currentLanguageCode);
  }

  TextDirection get textDirection =>
      isCurrentRtl ? TextDirection.rtl : TextDirection.ltr;

  static bool isRtl(String code) {
    return code == 'fa' || code == 'ps' || code == 'ur' || code == 'ar';
  }

  AppLanguage get currentLanguage {
    return supportedLanguages.firstWhere(
      (lang) => lang.code == currentLanguageCode,
      orElse: () => supportedLanguages.first,
    );
  }

  /// Initialize language service from local storage
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_prefKey);
      if (savedCode != null &&
          supportedLanguages.any((l) => l.code == savedCode)) {
        localeNotifier.value = Locale(savedCode);
      }
    } catch (e) {
      debugPrint('LanguageService init warning: $e');
    }
  }

  /// Change application language, persist to SharedPreferences, and sync with Supabase
  Future<void> changeLanguage(String code) async {
    if (!supportedLanguages.any((lang) => lang.code == code)) return;

    localeNotifier.value = Locale(code);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (e) {
      debugPrint('Error saving language to prefs: $e');
    }

    // Update preferred language in user Supabase profile
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({'preferred_language': code})
            .eq('id', currentUser.id);
      }
    } catch (e) {
      debugPrint('Supabase profile language sync notice: $e');
    }
  }
}

/// Useful extensions for accessing translations and RTL status
extension LocalizedContext on BuildContext {
  AppLocalizations get l10n {
    return AppLocalizations.of(this) ??
        (throw StateError('AppLocalizations not found in context'));
  }

  bool get isRtl {
    return Directionality.of(this) == TextDirection.rtl;
  }
}
