import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/account_standing_screen.dart';
import '../../features/auth/screens/google_profile_completion_screen.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../features/main_navigation/screens/zev_main_layout.dart';
import '../../main.dart';
import '../theme/zev_theme.dart';
import 'auth_helper.dart';
import 'auth_session_manager.dart';
import 'multi_account_service.dart';

/// Post-Authentication standing verification & onboarding router for external OAuth/Apple sign-ins.
class PostAuthService {
  PostAuthService._();

  static final SupabaseClient supabase = Supabase.instance.client;
  static bool _isHandlingPostAuth = false;
  static String? _lastHandledUserId;
  static DateTime? _lastHandledAt;

  /// Verifies standing & profile completeness and routes the user safely.
  static Future<void> handlePostAuthCheck({
    User? explicitUser,
    String eventType = 'apple_login',
  }) async {
    final user = explicitUser ?? supabase.auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    if (_isHandlingPostAuth) return;
    if (_lastHandledUserId == user.id &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(seconds: 3)) {
      return;
    }

    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    _isHandlingPostAuth = true;
    _lastHandledUserId = user.id;
    _lastHandledAt = now;
    try {
      // 1. Check account standing (banned / deactivated)
      final standing =
          await AuthSessionManager.instance.checkAccountStanding(user.id);
      if (standing.status == AccountStandingStatus.banned) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => AccountStandingScreen(standing: standing),
          ),
          (route) => false,
        );
        return;
      }
      if (!standing.isAllowed) {
        await AuthSessionManager.instance.signOutCurrentDevice();
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
        final ctx = appNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              content: Text(
                standing.reason ??
                    'This account has been suspended or deactivated.',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        return;
      }

      try {
        final res = await supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        final username = res?['username']?.toString().trim() ?? '';
        final dob = res?['date_of_birth']?.toString().trim() ?? '';

        final bool isProfileIncomplete = res == null ||
            username.isEmpty ||
            dob.isEmpty ||
            username.startsWith('user_');

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
          await AuthHelper.markUserLoggedIn(userId: user.id, role: 'user');
          unawaited(
            AuthSessionManager.instance.recordSecurityEvent(
              userId: user.id,
              eventType: eventType,
            ),
          );

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
        debugPrint('Post-Auth verification notice: $e');
        final ctx = appNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              backgroundColor: ZevColors.deepNavy,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              content: const Text(
                'Please finish setting up your ZEV profile.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          );
        }
        appNavigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => GoogleProfileCompletionScreen(user: user),
          ),
          (route) => false,
        );
      }
    } finally {
      _isHandlingPostAuth = false;
    }
  }
}

