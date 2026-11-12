import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_helper.dart';
import 'auth_session_manager.dart';
import 'multi_account_service.dart';
import 'secure_local_storage.dart';

/// Biometric & Passkey Authentication Service for ZEV.
/// Stores sensitive credential secrets strictly in OS-encrypted Keychain / Keystore
/// via [SecureLocalStorage], automatically migrating any legacy SharedPreferences key.
class PasskeyAuthService {
  PasskeyAuthService._();
  static final PasskeyAuthService instance = PasskeyAuthService._();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _prefKeyPasskeyEnabled = 'zev_passkey_enabled';
  static const String _prefKeyPasskeyEmail = 'zev_passkey_email';
  static const String _prefKeyPasskeyToken = 'zev_passkey_secure_token';
  static const String _prefKeyPasskeyUserId = 'zev_passkey_user_id';
  static const String _prefKeyPasskeyUsername = 'zev_passkey_username';

  static String _secretKey(String userId) => 'zev_pk_secret_$userId';

  /// Check if the current device supports hardware biometrics / passkey authentication.
  Future<bool> isDeviceSupported() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return isSupported && canCheck;
    } catch (e) {
      debugPrint('PasskeyAuthService isDeviceSupported notice: $e');
      return false;
    }
  }

  /// Get list of available biometrics (Face, Fingerprint, Iris).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Check whether the user currently has an active Passkey enrolled on this device.
  Future<bool> isPasskeyEnrolled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool(_prefKeyPasskeyEnabled) ?? false;
      final email = prefs.getString(_prefKeyPasskeyEmail);
      return isEnabled && email != null && email.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Get the email/username associated with the enrolled Passkey.
  Future<String?> getEnrolledIdentifier() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefKeyPasskeyUsername) ??
          prefs.getString(_prefKeyPasskeyEmail);
    } catch (_) {
      return null;
    }
  }

  /// Enroll or update the current user's Passkey on this device.
  Future<bool> enrollPasskey({
    required String email,
    required String userId,
    String? username,
    String? passwordSecret,
  }) async {
    final supported = await isDeviceSupported();
    if (!supported) return false;

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Verify your biometrics to set up your ZEV Passkey',
        biometricOnly: true,
      );

      if (!authenticated) return false;

      final tokenPayload = '$userId:$email:${DateTime.now().millisecondsSinceEpoch}';
      final signature = sha256.convert(utf8.encode(tokenPayload)).toString();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyPasskeyEnabled, true);
      await prefs.setString(_prefKeyPasskeyEmail, email);
      await prefs.setString(_prefKeyPasskeyUserId, userId);
      await prefs.setString(_prefKeyPasskeyToken, signature);
      if (username != null) {
        await prefs.setString(_prefKeyPasskeyUsername, username);
      }

      if (passwordSecret != null && passwordSecret.isNotEmpty) {
        await SecureLocalStorage.writeSecret(_secretKey(userId), passwordSecret);
        // Remove any legacy plaintext SharedPreferences copy
        await prefs.remove(_secretKey(userId));
      }

      return true;
    } on PlatformException catch (e) {
      debugPrint('Passkey enrollment platform exception: $e');
      return false;
    } catch (e) {
      debugPrint('Passkey enrollment error: $e');
      return false;
    }
  }

  /// Authenticate and sign in using the device Passkey.
  Future<PasskeyLoginResult> signInWithPasskey() async {
    final isEnrolled = await isPasskeyEnrolled();
    if (!isEnrolled) {
      return PasskeyLoginResult(
        success: false,
        errorMessage:
            'No Passkey enrolled on this device. Please log in with password first.',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_prefKeyPasskeyEmail);
      final userId = prefs.getString(_prefKeyPasskeyUserId);

      String? savedSecret;
      if (userId != null && userId.isNotEmpty) {
        savedSecret = await SecureLocalStorage.readSecret(_secretKey(userId));
        // Seamless one-time migration from legacy SharedPreferences
        if (savedSecret == null || savedSecret.isEmpty) {
          final legacySecret = prefs.getString(_secretKey(userId));
          if (legacySecret != null && legacySecret.isNotEmpty) {
            await SecureLocalStorage.writeSecret(_secretKey(userId), legacySecret);
            await prefs.remove(_secretKey(userId));
            savedSecret = legacySecret;
          }
        }
      }

      if (email == null || email.isEmpty) {
        return PasskeyLoginResult(
          success: false,
          errorMessage: 'Passkey credential data missing.',
        );
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Authenticate with your ZEV Passkey to sign in to $email',
      );

      if (!didAuthenticate) {
        return PasskeyLoginResult(
          success: false,
          errorMessage: 'Biometric authentication cancelled.',
        );
      }

      // 1. If an active session for this account exists, validate & resume
      final validSession = await AuthSessionManager.instance.ensureValidSession();
      if (validSession != null && validSession.user.email == email) {
        final uid = validSession.user.id;
        final standing = await AuthSessionManager.instance.checkAccountStanding(uid);
        if (standing.status == AccountStandingStatus.banned) {
          return PasskeyLoginResult(
            success: false,
            email: email,
            userId: uid,
            standing: standing,
            errorMessage: standing.reason ?? 'This account is suspended.',
          );
        }
        if (!standing.isAllowed) {
          await AuthSessionManager.instance.signOutCurrentDevice();
          return PasskeyLoginResult(
            success: false,
            standing: standing,
            errorMessage: standing.reason ??
                'This account is restricted or suspended.',
          );
        }

        await AuthHelper.markUserLoggedIn(userId: uid, role: 'user');
        unawaited(
          AuthSessionManager.instance.recordSecurityEvent(
            userId: uid,
            eventType: 'passkey_login',
          ),
        );
        return PasskeyLoginResult(success: true, email: email, userId: uid);
      }

      // 2. Authenticate fresh session with encrypted Passkey secret
      if (savedSecret != null && savedSecret.isNotEmpty) {
        final authRes = await _supabase.auth.signInWithPassword(
          email: email,
          password: savedSecret,
        );

        final u = authRes.user;
        if (u != null) {
          final standing =
              await AuthSessionManager.instance.checkAccountStanding(u.id);
          if (standing.status == AccountStandingStatus.banned) {
            return PasskeyLoginResult(
              success: false,
              email: email,
              userId: u.id,
              standing: standing,
              errorMessage: standing.reason ?? 'This account is suspended.',
            );
          }
          if (!standing.isAllowed) {
            await AuthSessionManager.instance.signOutCurrentDevice();
            return PasskeyLoginResult(
              success: false,
              standing: standing,
              errorMessage: standing.reason ??
                  'This account is restricted or suspended.',
            );
          }

          await AuthHelper.markUserLoggedIn(userId: u.id, role: 'user');
          await MultiAccountService.saveCurrentAccount();
          unawaited(
            AuthSessionManager.instance.recordSecurityEvent(
              userId: u.id,
              eventType: 'passkey_login',
            ),
          );
          return PasskeyLoginResult(success: true, email: email, userId: u.id);
        }
      }

      return PasskeyLoginResult(
        success: false,
        errorMessage:
            'Could not restore session. Please sign in with your password once to refresh your Passkey.',
      );
    } on PlatformException catch (e) {
      return PasskeyLoginResult(
        success: false,
        errorMessage: e.message ?? 'Biometric authentication failed.',
      );
    } on AuthException catch (e) {
      return PasskeyLoginResult(
        success: false,
        errorMessage: e.message,
      );
    } catch (e) {
      return PasskeyLoginResult(
        success: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Remove/Disable the Passkey on this device and wipe its encrypted secret.
  Future<void> removePasskey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(_prefKeyPasskeyUserId);
      if (userId != null && userId.isNotEmpty) {
        await SecureLocalStorage.deleteSecret(_secretKey(userId));
        await prefs.remove(_secretKey(userId));
      }
      await prefs.remove(_prefKeyPasskeyEnabled);
      await prefs.remove(_prefKeyPasskeyEmail);
      await prefs.remove(_prefKeyPasskeyUserId);
      await prefs.remove(_prefKeyPasskeyToken);
      await prefs.remove(_prefKeyPasskeyUsername);
    } catch (e) {
      debugPrint('Remove passkey error: $e');
    }
  }
}

class PasskeyLoginResult {
  final bool success;
  final String? email;
  final String? userId;
  final String? errorMessage;
  final AccountAccessResult? standing;

  PasskeyLoginResult({
    required this.success,
    this.email,
    this.userId,
    this.errorMessage,
    this.standing,
  });
}
