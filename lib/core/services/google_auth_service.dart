import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/google_profile_completion_screen.dart';
import '../../features/main_navigation/screens/zev_main_layout.dart';
import '../../main.dart';
import 'auth_helper.dart';

/// Central Google Authentication & Onboarding Dispatcher for ZEV.
/// Handles:
/// 1. OAuth Sign In with Google via Supabase
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

  /// Triggers Google OAuth sign-in flow
  static Future<void> signInWithGoogle({
    ValueChanged<String>? onError,
  }) async {
    try {
      final res = await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'zev://auth/callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      if (!res) {
        onError?.call("Could not open Google sign-in window.");
        return;
      }

      // On web or synchronous platforms, wait briefly and check
      if (kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 1500));
        final currentUser = supabase.auth.currentUser;
        if (currentUser != null) {
          await handlePostAuthCheck(explicitUser: currentUser);
        }
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
