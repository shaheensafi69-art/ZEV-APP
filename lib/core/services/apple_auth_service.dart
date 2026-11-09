import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_auth_service.dart';

/// Central Sign In with Apple Dispatcher for ZEV.
/// Fully compatible with iOS, macOS, Android, and Web.
/// Performs native Face ID / Touch ID Apple authentication on Apple devices,
/// and securely authenticates with Supabase via signInWithIdToken.
class AppleAuthService {
  AppleAuthService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Check if Sign In with Apple is natively supported on current device
  static Future<bool> isSupported() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        return await SignInWithApple.isAvailable();
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Triggers Sign in with Apple flow
  static Future<void> signInWithApple({
    ValueChanged<String>? onError,
    VoidCallback? onCancel,
  }) async {
    try {
      // 1. Generate cryptographic raw nonce & sha256 hashed nonce for Supabase
      final rawNonce = _supabase.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      // 2. Request native Apple ID Credential via Face ID / Touch ID / Passcode
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw "Could not obtain identity token from Apple.";
      }

      // 3. Authenticate with Supabase using native ID Token & raw nonce
      final AuthResponse authResponse = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      final user = authResponse.user ?? _supabase.auth.currentUser;
      if (user == null) {
        throw "Sign in with Apple succeeded but user was not returned.";
      }

      // 4. On first Apple sign-in, Apple delivers user's name
      final givenName = credential.givenName ?? '';
      final familyName = credential.familyName ?? '';
      if (givenName.isNotEmpty || familyName.isNotEmpty) {
        try {
          await _supabase.from('profiles').update({
            'first_name': givenName,
            'last_name': familyName,
          }).eq('id', user.id);
        } catch (_) {}
      }

      // 5. Check profile completion and route to ZevMainLayout or Onboarding
      await GoogleAuthService.handlePostAuthCheck(explicitUser: user);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        onCancel?.call();
        return;
      }
      onError?.call(e.message);
    } on AuthException catch (e) {
      onError?.call(e.message);
    } catch (e) {
      onError?.call("Apple Sign-In notice: $e");
    }
  }
}
