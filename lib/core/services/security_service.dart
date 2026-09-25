import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/screens/security_lock_screen.dart';
import '../../main.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  static SecurityService get instance => _instance;

  final LocalAuthentication _auth = LocalAuthentication();
  final supabase = Supabase.instance.client;

  bool _isSessionUnlocked = false;
  bool _isLockScreenShowing = false;

  bool get isSessionUnlocked => _isSessionUnlocked;

  void markSessionUnlocked() {
    _isSessionUnlocked = true;
    _isLockScreenShowing = false;
  }

  void markSessionLocked() {
    _isSessionUnlocked = false;
  }

  /// Check if biometric or PIN lock is enabled
  Future<bool> isAppLockEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool localEnabled = prefs.getBool('app_lock_enabled') ?? false;
      if (localEnabled) return true;

      final user = supabase.auth.currentUser;
      if (user != null) {
        final res = await supabase
            .from('student_security_settings')
            .select('is_biometric_enabled, pin_code')
            .eq('student_id', user.id)
            .maybeSingle();

        if (res != null) {
          final bool dbBio = res['is_biometric_enabled'] ?? false;
          final String? pin = res['pin_code']?.toString();
          final bool hasPin = pin != null && pin.isNotEmpty;
          final bool enabled = hasPin || dbBio;
          await prefs.setBool('app_lock_enabled', enabled);
          if (pin != null) await prefs.setString('app_lock_pin', pin);
          return enabled;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Get stored PIN (local first, then server fallback)
  Future<String?> getPinCode() async {
    final prefs = await SharedPreferences.getInstance();
    String? pin = prefs.getString('app_lock_pin');
    if (pin != null && pin.isNotEmpty) return pin;

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final res = await supabase
            .from('student_security_settings')
            .select('pin_code')
            .eq('student_id', user.id)
            .maybeSingle();

        if (res != null && res['pin_code'] != null) {
          pin = res['pin_code'].toString();
          await prefs.setString('app_lock_pin', pin);
          return pin;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Save security settings (PIN & biometrics)
  Future<void> saveSecuritySettings({
    required bool enabled,
    required String pin,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_lock_enabled', enabled);
    await prefs.setString('app_lock_pin', pin);

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase.from('student_security_settings').upsert({
          'student_id': user.id,
          'pin_code': pin,
          'is_biometric_enabled': enabled,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint("SecurityService sync error: $e");
    }
  }

  /// Disable security lock
  Future<void> disableSecurity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_lock_enabled', false);
    _isSessionUnlocked = true;

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase
            .from('student_security_settings')
            .update({
              'is_biometric_enabled': false,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('student_id', user.id);
      }
    } catch (_) {}
  }

  /// Remove PIN code completely
  Future<void> disablePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('app_lock_pin');
    await prefs.setBool('app_lock_enabled', false);

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase
            .from('student_security_settings')
            .update({
              'pin_code': null,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('student_id', user.id);
      }
    } catch (_) {}
  }

  /// Check biometric hardware availability
  Future<bool> canCheckBiometrics() async {
    try {
      bool canCheck = await _auth.canCheckBiometrics;
      bool isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Authenticate using biometrics
  Future<bool> authenticateBiometric({
    String reason = 'Authenticate to unlock ZEV',
  }) async {
    try {
      bool canAuth = await canCheckBiometrics();
      if (!canAuth) return false;

      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint("Biometric auth failed: $e");
      return false;
    }
  }

  /// Verify and present lock screen if enabled
  Future<bool> verifyLockIfNeeded(BuildContext context) async {
    final user = supabase.auth.currentUser;
    if (user == null) return true; // User not signed in, lock not required

    final bool enabled = await isAppLockEnabled();
    if (!enabled) {
      _isSessionUnlocked = true;
      return true;
    }

    if (_isSessionUnlocked || _isLockScreenShowing) {
      return true;
    }

    final nav = Navigator.maybeOf(context) ?? appNavigatorKey.currentState;
    if (nav == null || !nav.mounted) {
      return false;
    }

    _isLockScreenShowing = true;
    try {
      final result = await nav.push<bool>(
        MaterialPageRoute(
          builder: (_) => const SecurityLockScreen(),
          fullscreenDialog: true,
        ),
      );

      _isLockScreenShowing = false;
      if (result == true) {
        _isSessionUnlocked = true;
        return true;
      }
      return false;
    } catch (e) {
      _isLockScreenShowing = false;
      debugPrint("Lock screen navigation error: $e");
      return false;
    }
  }
}
