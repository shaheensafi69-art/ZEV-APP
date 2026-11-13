import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Central Google Authentication Service for ZEV.
/// Seamlessly authenticates users via Google OAuth across Web, Android, and iOS.
class GoogleAuthService {
  GoogleAuthService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Triggers Sign in with Google flow via Supabase OAuth
  static Future<void> signInWithGoogle({
    ValueChanged<String>? onError,
    VoidCallback? onCancel,
  }) async {
    try {
      final String? redirectTo;
      if (kIsWeb) {
        // Web: let Supabase use the current window location
        redirectTo = null;
      } else {
        // Android & iOS: deep link back into ZEV app
        redirectTo = 'zev://auth/callback';
      }

      final bool initiated = await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );

      if (!initiated) {
        onCancel?.call();
      }
    } catch (e) {
      debugPrint('[GoogleAuthService] Google Sign-In error: $e');
      onError?.call(e.toString().replaceFirst('Exception: ', ''));
    }
  }
}
