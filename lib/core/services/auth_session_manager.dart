import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_helper.dart';
import 'mfa_service.dart';

enum AccountStandingStatus {
  active,
  banned,
  deactivated,
  unauthenticated,
}

class AccountAccessResult {
  final AccountStandingStatus status;
  final String? reason;
  final String? userId;
  final DateTime? bannedUntil;
  final bool isRestricted;
  final DateTime? restrictedUntil;
  final String? restrictionReason;

  const AccountAccessResult({
    required this.status,
    this.reason,
    this.userId,
    this.bannedUntil,
    this.isRestricted = false,
    this.restrictedUntil,
    this.restrictionReason,
  });

  bool get isAllowed => status == AccountStandingStatus.active;
}

/// Manages session lifecycle, singleflight token refreshes (preventing
/// rotating refresh-token races), offline resilience, and device-scoped sign-outs.
class AuthSessionManager {
  AuthSessionManager._();
  static final AuthSessionManager instance = AuthSessionManager._();

  SupabaseClient get _supabase => Supabase.instance.client;

  StreamSubscription<AuthState>? _authSub;
  Completer<Session?>? _inFlightRefresh;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    _authSub?.cancel();
    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.tokenRefreshed && session != null) {
        unawaited(_touchDeviceSession(session.user.id));
      } else if (event == AuthChangeEvent.signedIn && session != null) {
        unawaited(_touchDeviceSession(session.user.id));
      } else if (event == AuthChangeEvent.signedOut) {
        unawaited(_clearLocalFlagsOnly());
      }
    });
  }

  void dispose() {
    _authSub?.cancel();
    _authSub = null;
    _initialized = false;
  }

  /// Ensures we have a usable [Session] using a singleflight refresh lock.
  ///
  /// - Never signs the user out on offline / network / 5xx transient errors.
  /// - Only returns `null` when no session exists or Supabase explicitly rejects
  ///   the refresh token (`invalid_grant`, revoked/expired token).
  Future<Session?> ensureValidSession({bool forceRefresh = false}) async {
    final current = _supabase.auth.currentSession;
    if (current == null) return null;

    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresAt = current.expiresAt;
    final needsRefresh =
        forceRefresh || (expiresAt != null && expiresAt <= nowSeconds + 60);

    if (!needsRefresh) {
      return current;
    }

    if (_inFlightRefresh != null) {
      return _inFlightRefresh!.future;
    }

    final completer = Completer<Session?>();
    _inFlightRefresh = completer;

    try {
      final res = await _supabase.auth
          .refreshSession()
          .timeout(const Duration(seconds: 12));
      final refreshed = res.session ?? _supabase.auth.currentSession;
      completer.complete(refreshed);
      return refreshed;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      final isHardInvalidToken = msg.contains('invalid_grant') ||
          msg.contains('refresh token') ||
          msg.contains('token has expired') ||
          msg.contains('user not found') ||
          e.statusCode == '400' ||
          e.statusCode == '401' ||
          e.statusCode == '403';

      if (isHardInvalidToken) {
        debugPrint('[AuthSessionManager] Session revoked/expired: ${e.message}');
        completer.complete(null);
        return null;
      }

      debugPrint(
        '[AuthSessionManager] AuthException during refresh, keeping cached session: ${e.message}',
      );
      completer.complete(_supabase.auth.currentSession);
      return _supabase.auth.currentSession;
    } on SocketException catch (e) {
      debugPrint('[AuthSessionManager] Offline during refresh ($e); using cached session.');
      completer.complete(_supabase.auth.currentSession);
      return _supabase.auth.currentSession;
    } on TimeoutException {
      debugPrint('[AuthSessionManager] Refresh timeout; keeping cached session.');
      completer.complete(_supabase.auth.currentSession);
      return _supabase.auth.currentSession;
    } catch (e) {
      debugPrint('[AuthSessionManager] Transient refresh error ($e); keeping cached session.');
      completer.complete(_supabase.auth.currentSession);
      return _supabase.auth.currentSession;
    } finally {
      _inFlightRefresh = null;
    }
  }

  /// Checks whether the signed-in account is banned or deactivated.
  Future<AccountAccessResult> checkAccountStanding(String userId) async {
    if (userId.isEmpty) {
      return const AccountAccessResult(
        status: AccountStandingStatus.unauthenticated,
      );
    }

    try {
      final row = await _supabase
          .from('profiles')
          .select(
            'is_banned, banned_until, ban_reason, is_restricted, restricted_until, restriction_reason, account_status',
          )
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (row == null) {
        return const AccountAccessResult(status: AccountStandingStatus.active);
      }

      final nowUtc = DateTime.now().toUtc();
      final accountStatus =
          (row['account_status'] ?? 'active').toString().toLowerCase();
      final bannedUntilRaw = row['banned_until']?.toString();
      final bannedUntil =
          bannedUntilRaw != null ? DateTime.tryParse(bannedUntilRaw) : null;
      final isBanActive = row['is_banned'] == true &&
          (bannedUntil == null || bannedUntil.isAfter(nowUtc));

      final restrictedUntilRaw = row['restricted_until']?.toString();
      final restrictedUntil = restrictedUntilRaw != null
          ? DateTime.tryParse(restrictedUntilRaw)
          : null;
      final isRestrictionActive = row['is_restricted'] == true &&
          (restrictedUntil == null || restrictedUntil.isAfter(nowUtc));
      final restrReason = row['restriction_reason']?.toString();

      if (isBanActive || accountStatus == 'banned') {
        final reason = row['ban_reason']?.toString().trim().isNotEmpty == true
            ? row['ban_reason'].toString()
            : restrReason;
        return AccountAccessResult(
          status: AccountStandingStatus.banned,
          reason: reason,
          userId: userId,
          bannedUntil: bannedUntil,
          isRestricted: isRestrictionActive,
          restrictedUntil: restrictedUntil,
          restrictionReason: restrReason,
        );
      }

      if (accountStatus == 'deactivated' ||
          accountStatus == 'pending_deletion') {
        return AccountAccessResult(
          status: AccountStandingStatus.deactivated,
          reason: restrReason,
          userId: userId,
          isRestricted: isRestrictionActive,
          restrictedUntil: restrictedUntil,
          restrictionReason: restrReason,
        );
      }

      return AccountAccessResult(
        status: AccountStandingStatus.active,
        userId: userId,
        isRestricted: isRestrictionActive,
        restrictedUntil: restrictedUntil,
        restrictionReason: restrReason,
      );
    } catch (e) {
      // Do not falsely lock users out if offline or network unavailable
      debugPrint('[AuthSessionManager] Standing check skipped/offline: $e');
      return AccountAccessResult(
        status: AccountStandingStatus.active,
        userId: userId,
      );
    }
  }

  /// Records/refreshes this device's active session metadata & security audit log.
  Future<void> recordSecurityEvent({
    required String userId,
    required String eventType,
    String? details,
  }) async {
    try {
      final deviceId = await MfaService.instance.getOrCreateDeviceId();
      final deviceName = await MfaService.instance.getDeviceName();
      final platform = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
      final nowIso = DateTime.now().toUtc().toIso8601String();

      await _supabase.from('user_sessions').upsert({
        'user_id': userId,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'app_version': '1.0.0+9',
        'is_active': true,
        'last_active_at': nowIso,
      }, onConflict: 'user_id,device_id');

      await _supabase.from('user_security_logs').insert({
        'user_id': userId,
        'event_type': eventType,
        'status': 'success',
        'device_id': deviceId,
        'platform': platform,
        'metadata': {
          'device_name': deviceName,
          'platform': platform,
          'details': ?details,
        },
        'created_at': nowIso,
      });
    } catch (e) {
      debugPrint('[AuthSessionManager] recordSecurityEvent notice: $e');
    }
  }

  Future<void> _touchDeviceSession(String userId) async {
    try {
      final deviceId = await MfaService.instance.getOrCreateDeviceId();
      final deviceName = await MfaService.instance.getDeviceName();
      await _supabase.from('user_sessions').upsert({
        'user_id': userId,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase(),
        'app_version': '1.0.0+9',
        'is_active': true,
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,device_id');
    } catch (_) {}
  }

  /// Signs out ONLY the current physical device without wiping other devices' FCM tokens.
  Future<void> signOutCurrentDevice() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        final deviceId = await MfaService.instance.getOrCreateDeviceId();
        final prefs = await SharedPreferences.getInstance();
        final cachedToken = prefs.getString('zev_last_fcm_token_${user.id}');

        // Deactivate ONLY this device in user_devices (Phase 2+)
        try {
          await _supabase
              .from('user_devices')
              .update({'is_active': false, 'updated_at': DateTime.now().toIso8601String()})
              .match({'user_id': user.id, 'device_id': deviceId});
        } catch (_) {}

        // Mark this session inactive
        try {
          await _supabase
              .from('user_sessions')
              .update({'is_active': false})
              .match({'user_id': user.id, 'device_id': deviceId});
        } catch (_) {}

        // Deactivate ONLY this device's push token (preserve other active devices)
        if (cachedToken != null && cachedToken.isNotEmpty) {
          try {
            await _supabase
                .from('push_subscriptions')
                .update({'is_active': false, 'updated_at': DateTime.now().toIso8601String()})
                .match({'user_id': user.id, 'fcm_token': cachedToken});
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[AuthSessionManager] Device deactivation notice: $e');
      }
    }

    await _clearLocalFlagsOnly(userId: user?.id);

    try {
      await _supabase.auth
          .signOut(scope: SignOutScope.local)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[AuthSessionManager] Local signOut notice: $e');
    }
  }

  /// Signs out across ALL devices (SignOutScope.global) and revokes all user sessions/tokens.
  Future<void> signOutAllDevices() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        await _supabase
            .from('user_devices')
            .update({'is_active': false, 'updated_at': DateTime.now().toIso8601String()})
            .eq('user_id', user.id);
      } catch (_) {}

      try {
        await _supabase
            .from('user_sessions')
            .update({'is_active': false})
            .eq('user_id', user.id);
      } catch (_) {}

      try {
        await _supabase
            .from('push_subscriptions')
            .update({'is_active': false, 'updated_at': DateTime.now().toIso8601String()})
            .match({'user_id': user.id, 'app_name': 'zev'});
      } catch (_) {}

      try {
        await _supabase
            .from('profiles')
            .update({'fcm_token': null})
            .eq('id', user.id);
      } catch (_) {}
    }

    await _clearLocalFlagsOnly(userId: user?.id);

    try {
      await _supabase.auth
          .signOut(scope: SignOutScope.global)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[AuthSessionManager] Global signOut fallback local: $e');
      try {
        await _supabase.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
    }
  }

  Future<void> _clearLocalFlagsOnly({String? userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AuthHelper.keyUserLoggedIn, false);
      await prefs.setBool(AuthHelper.keyUserExplicitlyLoggedOut, true);
      await prefs.remove(AuthHelper.keyCachedUserRole);
      if (userId != null) {
        await prefs.remove('cached_user_role_$userId');
        await prefs.remove(AuthHelper.keyLoggedInUserId);
        await prefs.remove('zev_last_fcm_token_$userId');
      }
    } catch (_) {}
  }
}

