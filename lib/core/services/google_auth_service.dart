import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/google_profile_completion_screen.dart';
import '../../features/main_navigation/screens/zev_main_layout.dart';
import '../../main.dart';
import 'auth_helper.dart';
import 'multi_account_service.dart';

/// Central Google Authentication & Onboarding Dispatcher for ZEV.
/// Handles:
/// 1. Native in-app Google Sign-In sheet (ChatGPT-style) via Google Play Services / Credential Manager
/// 2. Session verification & Profile check
/// 3. Redirection to GoogleProfileCompletionScreen if username or DOB is missing
/// 4. Direct entry to ZevMainLayout if profile is already complete
class GoogleAuthService {
  GoogleAuthService._();

  static final supabase = Supabase.instance.client;
  static StreamSubscription<AuthState>? _authSub;

  /// Initialize global auth state listener to automatically handle Google OAuth redirects
  static void init() {
    _authSub?.cancel();
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;
      final user = session?.user;

      if (event == AuthChangeEvent.signedIn && user != null) {
        final provider = user.appMetadata['provider']?.toString().toLowerCase();
        // Check if provider is Google or has google identities
        final isGoogle = provider == 'google' ||
            (user.identities?.any((i) => i.provider.toLowerCase() == 'google') ?? false);

        if (isGoogle) {
          handlePostAuthCheck(explicitUser: user);
        }
      }
    });
  }

  /// Triggers Native Google Sign-In flow (ChatGPT-style bottom sheet)
  /// using Google Play Services One-Tap / Account Picker, authenticates
  /// seamlessly with Supabase using signInWithIdToken, and avoids opening
  /// any web browser or exposing backend URLs.
  static Future<void> signInWithGoogle({
    ValueChanged<String>? onError,
    VoidCallback? onCancel,
  }) async {
    try {
      // 1. On Web, standard OAuth redirect or popup is required
      if (kIsWeb) {
        final res = await supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: null,
          authScreenLaunchMode: LaunchMode.externalApplication,
        );

        if (!res) {
          onError?.call("Could not open Google sign-in window.");
          return;
        }

        await Future.delayed(const Duration(milliseconds: 1500));
        final currentUser = supabase.auth.currentUser;
        if (currentUser != null) {
          await handlePostAuthCheck(explicitUser: currentUser);
        }
        return;
      }

      // 2. Native Google Sign-In on Android & iOS
      final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'] ??
          '467206192154-6opg0v3iafqhovalsjpngdb3gmtc6586.apps.googleusercontent.com';
      final iosClientId = dotenv.env['GOOGLE_IOS_CLIENT_ID'];

      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: (defaultTargetPlatform == TargetPlatform.iOS) ? iosClientId : null,
        serverClientId: webClientId.isNotEmpty ? webClientId : null,
        scopes: const ['email', 'profile'],
      );

      // Sign out from any cached local Google session to always prompt account selector
      try {
        await googleSignIn.signOut();
      } catch (_) {}

      // Pops up the native Android One-Tap Account Picker bottom sheet (ChatGPT-style!)
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User closed or dismissed the bottom sheet
        onCancel?.call();
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null || idToken.isEmpty) {
        debugPrint("Google Sign-In: idToken is null, falling back to OAuth...");
        final res = await supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'zev://auth/callback',
          authScreenLaunchMode: LaunchMode.externalApplication,
        );
        if (!res) {
          onError?.call("Could not complete Google Sign-In.");
        }
        return;
      }

      // 3. Authenticate with Supabase via ID token (100% In-App, Zero Browser!)
      final AuthResponse authResponse = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final user = authResponse.user ?? supabase.auth.currentUser;
      if (user != null) {
        await handlePostAuthCheck(explicitUser: user);
      } else {
        onError?.call("Authentication succeeded but user profile was not returned.");
      }
    } on AuthException catch (e) {
      onError?.call(e.message);
    } catch (e) {
      onError?.call("Google Sign-In failed: $e");
    }
  }

  /// Verifies if user profile exists and is complete in database
  static Future<void> handlePostAuthCheck({
    User? explicitUser,
  }) async {
    final user = explicitUser ?? supabase.auth.currentUser;
    if (user == null) return;

    try {
      final res = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final username = res?['username']?.toString().trim() ?? '';
      final dob = res?['date_of_birth']?.toString().trim() ?? '';

      // Profile is incomplete if username or date_of_birth is missing,
      // or if username is a generic auto-placeholder like 'user_...'
      final bool isProfileIncomplete = res == null ||
          username.isEmpty ||
          dob.isEmpty ||
          username.startsWith('user_');

      final nav = appNavigatorKey.currentState;
      if (nav == null) return;

      if (isProfileIncomplete) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => GoogleProfileCompletionScreen(
              user: user,
              existingProfile: res,
            ),
          ),
          (route) => false,
        );
      } else {
        final role = res['role']?.toString() ?? 'student';
        await AuthHelper.markUserLoggedIn(userId: user.id, role: role);

        // Cache account in multi-account switcher
        try {
          final first = res['first_name']?.toString() ?? '';
          final last = res['last_name']?.toString() ?? '';
          final fullName = '$first $last'.trim();
          await MultiAccountService.saveCurrentAccount(
            overrideUsername: username,
            overrideFullName: fullName,
            overrideAvatar: res['avatar_url']?.toString() ?? '',
            overrideIsVerified: res['is_verified'] == true,
          );
        } catch (_) {}

        appNavigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ZevMainLayout()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint("Post-Google Auth verification notice: $e");
      appNavigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => GoogleProfileCompletionScreen(user: user),
        ),
        (route) => false,
      );
    }
  }
}
