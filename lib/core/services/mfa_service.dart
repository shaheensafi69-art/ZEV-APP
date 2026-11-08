import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Flagship Multi-Factor Authentication (MFA / TOTP) Service for ZEV.
/// Fully integrates with Supabase Auth TOTP specification for Google Authenticator,
/// Microsoft Authenticator, Apple Passwords, 1Password, and Authy.
class MfaService {
  MfaService._();
  static final MfaService instance = MfaService._();

  final SupabaseClient _supabase = Supabase.instance.client;

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
