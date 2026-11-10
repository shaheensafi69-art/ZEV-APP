import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Flagship Multi-Factor Authentication (MFA / TOTP) & Trusted Device Service for ZEV.
/// Fully integrates with Supabase Auth TOTP specification for Google Authenticator,
/// Microsoft Authenticator, Apple Passwords, 1Password, and Authy.
///
/// Features "Trust This Device" architecture:
/// When 2FA is active, users are challenged with a 6-digit TOTP code once per new device.
/// Subsequent logins on the same device bypass TOTP prompts until revoked or reset.
class MfaService {
  MfaService._();
  static final MfaService instance = MfaService._();

  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _deviceIdKey = 'zev_trusted_device_id';

  // ===========================================================================
  // DEVICE IDENTIFICATION & RECOGNITION
  // ===========================================================================

  /// Get or generate a persistent unique device identifier for this installation.
  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_deviceIdKey);
    if (id != null && id.isNotEmpty) return id;

    // Hardware ID lookup fallback
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        id = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        id = iosInfo.identifierForVendor;
      }
    } catch (_) {}

    if (id == null || id.isEmpty) {
      final rand = Random().nextInt(99999999);
      id = "dev_${DateTime.now().millisecondsSinceEpoch}_$rand";
    }

    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  /// Get a friendly human-readable name of the current device (e.g. "Samsung S24 Ultra", "iPhone 15").
  Future<String> getDeviceName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await deviceInfo.androidInfo;
        final mfg = a.manufacturer.isNotEmpty ? a.manufacturer : '';
        final model = a.model.isNotEmpty ? a.model : 'Android';
        return "$mfg $model".trim();
      } else if (Platform.isIOS) {
        final i = await deviceInfo.iosInfo;
        return i.name.isNotEmpty ? i.name : (i.model.isNotEmpty ? i.model : 'iPhone');
      } else if (Platform.isMacOS) {
        final m = await deviceInfo.macOsInfo;
        return m.computerName.isNotEmpty ? m.computerName : 'MacBook';
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }

  /// Check whether the current physical device has already verified 2FA for this user account.
  Future<bool> isCurrentDeviceTrusted(String userId) async {
    if (userId.isEmpty) return false;

    try {
      final deviceId = await getOrCreateDeviceId();
      final prefs = await SharedPreferences.getInstance();

      // 1. Fast local cache check
      final isLocallyTrusted = prefs.getBool('zev_trusted_${userId}_$deviceId');
      if (isLocallyTrusted == true) return true;

      // 2. Remote database lookup in public.user_trusted_devices
      final res = await _supabase
          .from('user_trusted_devices')
          .select('id, is_trusted')
          .eq('user_id', userId)
          .eq('device_id', deviceId)
          .eq('is_trusted', true)
          .maybeSingle();

      if (res != null) {
        await prefs.setBool('zev_trusted_${userId}_$deviceId', true);
        return true;
      }
    } catch (e) {
      debugPrint("MfaService isCurrentDeviceTrusted notice: $e");
    }
    return false;
  }

  /// Mark the current device as trusted upon successful 2FA verification.
  Future<void> trustCurrentDevice(String userId) async {
    if (userId.isEmpty) return;

    try {
      final deviceId = await getOrCreateDeviceId();
      final deviceName = await getDeviceName();
      final platform = Platform.operatingSystem;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('zev_trusted_${userId}_$deviceId', true);

      await _supabase.from('user_trusted_devices').upsert({
        'user_id': userId,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'is_trusted': true,
        'last_authenticated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,device_id');
    } catch (e) {
      debugPrint("MfaService trustCurrentDevice notice: $e");
    }
  }

  /// Retrieve all devices that have been authenticated with 2FA for this user.
  Future<List<Map<String, dynamic>>> getTrustedDevices(String userId) async {
    if (userId.isEmpty) return [];

    try {
      final res = await _supabase
          .from('user_trusted_devices')
          .select('*')
          .eq('user_id', userId)
          .eq('is_trusted', true)
          .order('last_authenticated_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint("MfaService getTrustedDevices error: $e");
      return [];
    }
  }

  /// Revoke trust for a specific device (will require 2FA next time it attempts login).
  Future<void> revokeDevice(String userId, String deviceId) async {
    try {
      await _supabase
          .from('user_trusted_devices')
          .delete()
          .eq('user_id', userId)
          .eq('device_id', deviceId);

      final currentDeviceId = await getOrCreateDeviceId();
      if (deviceId == currentDeviceId) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('zev_trusted_${userId}_$deviceId');
      }
    } catch (e) {
      debugPrint("MfaService revokeDevice error: $e");
    }
  }

  /// Revoke trust for all devices EXCEPT the current one.
  Future<void> revokeAllOtherDevices(String userId) async {
    try {
      final currentDeviceId = await getOrCreateDeviceId();
      await _supabase
          .from('user_trusted_devices')
          .delete()
          .eq('user_id', userId)
          .neq('device_id', currentDeviceId);
    } catch (e) {
      debugPrint("MfaService revokeAllOtherDevices error: $e");
    }
  }

  // ===========================================================================
  // TOTP MFA CORE LOGIC
  // ===========================================================================

  /// Check whether the current session needs elevation to AAL2 (Authenticator level).
  bool isMfaRequired() {
    try {
      final aal = _supabase.auth.mfa.getAuthenticatorAssuranceLevel();
      return aal.nextLevel == AuthenticatorAssuranceLevels.aal2 &&
          aal.currentLevel == AuthenticatorAssuranceLevels.aal1;
    } catch (e) {
      debugPrint("MfaService isMfaRequired notice: $e");
      return false;
    }
  }

  /// Get the current Authenticator Assurance Level response.
  AuthMFAGetAuthenticatorAssuranceLevelResponse? getAalResponse() {
    try {
      return _supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    } catch (e) {
      debugPrint("MfaService getAalResponse error: $e");
      return null;
    }
  }

  /// Fetch all enrolled MFA factors for the currently authenticated user.
  Future<List<Factor>> getEnrolledFactors() async {
    try {
      final res = await _supabase.auth.mfa.listFactors();
      return res.totp.where((f) => f.status == FactorStatus.verified).toList();
    } catch (e) {
      debugPrint("MfaService getEnrolledFactors error: $e");
      return [];
    }
  }

  /// Check if the currently authenticated user has an active TOTP factor enrolled.
  Future<bool> hasEnrolledMfa() async {
    final factors = await getEnrolledFactors();
    return factors.isNotEmpty;
  }

  /// Start enrolling a new TOTP Authenticator factor.
  /// Returns an [AuthMFAEnrollResponse] containing the base32 secret and QR code.
  Future<AuthMFAEnrollResponse> startEnrollment({
    String friendlyName = 'ZEV Authenticator',
  }) async {
    return await _supabase.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'ZEV',
      friendlyName: friendlyName,
    );
  }

  /// Complete factor enrollment by verifying the 6-digit code from the Authenticator app.
  Future<AuthMFAVerifyResponse> verifyEnrollment({
    required String factorId,
    required String code,
  }) async {
    return await _supabase.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code.trim(),
    );
  }

  /// Challenge and verify during user login to upgrade session to AAL2.
  Future<AuthMFAVerifyResponse> verifyLoginCode({
    required String factorId,
    required String code,
  }) async {
    return await _supabase.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code.trim(),
    );
  }

  /// Unenroll / Remove an MFA factor (disable 2FA).
  Future<void> unenrollFactor(String factorId) async {
    await _supabase.auth.mfa.unenroll(factorId);
  }
}
