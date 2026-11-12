import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// OS-encrypted Supabase session storage backed by Android Keystore / iOS Keychain.
///
/// Automatically migrates any legacy plaintext session from `SharedPreferences`
/// (`sb-*-auth-token` or `supabase.auth.token`) on first launch so signed-in users
/// remain authenticated across app updates. Delegates cleanly on Web.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;

  static const String _legacySessionKey = 'supabase.auth.token';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  late final SharedPreferencesLocalStorage _webDelegate =
      SharedPreferencesLocalStorage(persistSessionKey: persistSessionKey);

  String? _cachedSession;
  bool _initialized = false;

  /// Expose shared secure storage helper for sensitive device secrets (e.g. passkey secret).
  static Future<void> writeSecret(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
      return;
    }
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      debugPrint('[SecureLocalStorage] writeSecret notice: $e');
    }
  }

  static Future<String?> readSecret(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      debugPrint('[SecureLocalStorage] readSecret notice: $e');
      return null;
    }
  }

  static Future<void> deleteSecret(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    }
    try {
      await _secureStorage.delete(key: key);
    } catch (e) {
      debugPrint('[SecureLocalStorage] deleteSecret notice: $e');
    }
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    if (kIsWeb) {
      await _webDelegate.initialize();
      _initialized = true;
      return;
    }

    try {
      _cachedSession = await _secureStorage.read(key: persistSessionKey);
    } on PlatformException catch (e) {
      debugPrint('[SecureLocalStorage] Secure read reset on keystore error: $e');
      try {
        await _secureStorage.delete(key: persistSessionKey);
      } catch (_) {}
      _cachedSession = null;
    } catch (e) {
      debugPrint('[SecureLocalStorage] initialize read warning: $e');
    }

    // One-time seamless migration from legacy SharedPreferences storage
    if (_cachedSession == null || _cachedSession!.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final legacyCurrent = prefs.getString(persistSessionKey);
        final legacyOld = prefs.getString(_legacySessionKey);
        final migrated = (legacyCurrent != null && legacyCurrent.isNotEmpty)
            ? legacyCurrent
            : (legacyOld != null && legacyOld.isNotEmpty ? legacyOld : null);

        if (migrated != null) {
          await _secureStorage.write(key: persistSessionKey, value: migrated);
          _cachedSession = migrated;
          await prefs.remove(persistSessionKey);
          await prefs.remove(_legacySessionKey);
          debugPrint('[SecureLocalStorage] Migrated Supabase session to secure storage.');
        }
      } catch (e) {
        debugPrint('[SecureLocalStorage] Migration notice: $e');
      }
    }

    _initialized = true;
  }

  @override
  Future<bool> hasAccessToken() async {
    if (kIsWeb) return _webDelegate.hasAccessToken();
    if (!_initialized) await initialize();
    if (_cachedSession != null && _cachedSession!.isNotEmpty) return true;
    try {
      _cachedSession = await _secureStorage.read(key: persistSessionKey);
      return _cachedSession != null && _cachedSession!.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    if (kIsWeb) return _webDelegate.accessToken();
    if (!_initialized) await initialize();
    if (_cachedSession != null && _cachedSession!.isNotEmpty) {
      return _cachedSession;
    }
    try {
      _cachedSession = await _secureStorage.read(key: persistSessionKey);
      return _cachedSession;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (kIsWeb) {
      await _webDelegate.persistSession(persistSessionString);
      return;
    }
    _cachedSession = persistSessionString;
    try {
      await _secureStorage.write(
        key: persistSessionKey,
        value: persistSessionString,
      );
    } catch (e) {
      debugPrint('[SecureLocalStorage] persistSession warning: $e');
    }
  }

  @override
  Future<void> removePersistedSession() async {
    if (kIsWeb) {
      await _webDelegate.removePersistedSession();
      return;
    }
    _cachedSession = null;
    try {
      await _secureStorage.delete(key: persistSessionKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(persistSessionKey);
      await prefs.remove(_legacySessionKey);
    } catch (e) {
      debugPrint('[SecureLocalStorage] removePersistedSession warning: $e');
    }
  }
}

