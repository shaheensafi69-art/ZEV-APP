/// Public runtime configuration for the ZEV client application.
///
/// SECURITY CONTRACT:
/// Only non-secret, public identifiers live here (and may be overridden via
/// `--dart-define=...` at build time). Secret credentials (`SUPABASE_SERVICE_ROLE_KEY`,
/// R2 S3 keys, Telegram bot tokens, Google Vision/Gemini keys, Firebase Admin JSON)
/// reside strictly on the `zev-web` server (`/api/v1/*`).
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'NEXT_PUBLIC_SUPABASE_URL',
    defaultValue: 'https://zjwmioalrhkyfbzhdnnw.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'NEXT_PUBLIC_SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_mhRdQoBdG-Ha0_nQ4dHIVw_MrXwmR5z',
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'ZEV_API_BASE_URL',
    defaultValue: 'https://www.zevapp.com',
  );

  static const String r2PublicDomain = String.fromEnvironment(
    'CLOUDFLARE_R2_PUBLIC_DOMAIN',
    defaultValue: 'https://media.zevapp.com',
  );

  static const String firebaseVapidKey = String.fromEnvironment(
    'FIREBASE_VAPID_KEY',
    defaultValue: '',
  );

  static const String agoraAppId = String.fromEnvironment(
    'NEXT_PUBLIC_AGORA_APP_ID',
    defaultValue: 'e85b079d64d04f659792de8eb3770595',
  );

  static const String admobAndroidAppId = String.fromEnvironment(
    'ADMOB_ANDROID_APP_ID',
    defaultValue: 'ca-app-pub-6551903544426492~5253464669',
  );

  static const String admobIosAppId = String.fromEnvironment(
    'ADMOB_IOS_APP_ID',
    defaultValue: 'ca-app-pub-6551903544426492~4786844584',
  );

  static const String admobAndroidNativeUnitId = String.fromEnvironment(
    'ADMOB_FEED_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-6551903544426492/4905894586',
  );

  static const String admobIosNativeUnitId = String.fromEnvironment(
    'ADMOB_IOS_NATIVE_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-6551903544426492/3940495638',
  );

  /// Derives Supabase's standard `persistSessionKey` (`sb-<ref>-auth-token`).
  static String get supabasePersistSessionKey {
    final host = Uri.tryParse(supabaseUrl)?.host ?? '';
    final projectRef = host.split('.').first;
    return 'sb-$projectRef-auth-token';
  }
}

