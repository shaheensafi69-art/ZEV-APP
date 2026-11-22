import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatLockService {
  ChatLockService._();
  static final ChatLockService instance = ChatLockService._();

  final LocalAuthentication _auth = LocalAuthentication();
  final Set<String> _lockedThreadKeys = <String>{};
  String? _cachedPin;
  bool _isInitialized = false;

  static const String _kLockedChatsKey = 'zev_locked_chat_threads';
  static const String _kChatPinKey = 'zev_chat_security_pin';

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kLockedChatsKey) ?? [];
      _lockedThreadKeys.clear();
      _lockedThreadKeys.addAll(list);
      _cachedPin = prefs.getString(_kChatPinKey);
      _isInitialized = true;
    } catch (e) {
      debugPrint('[ChatLockService] init error: $e');
    }
  }

  bool isChatLocked(String threadKey) {
    return _lockedThreadKeys.contains(threadKey);
  }

  Set<String> get lockedThreadKeys => Set.unmodifiable(_lockedThreadKeys);

  Future<bool> setChatLock(String threadKey, bool locked) async {
    await init();
    try {
      if (locked) {
        _lockedThreadKeys.add(threadKey);
      } else {
        _lockedThreadKeys.remove(threadKey);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kLockedChatsKey, _lockedThreadKeys.toList());
      return true;
    } catch (e) {
      debugPrint('[ChatLockService] setChatLock error: $e');
      return false;
    }
  }

  Future<bool> setSecurityPin(String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kChatPinKey, pin);
      _cachedPin = pin;
      return true;
    } catch (e) {
      debugPrint('[ChatLockService] setSecurityPin error: $e');
      return false;
    }
  }

  bool get hasPin => _cachedPin != null && _cachedPin!.isNotEmpty;

  /// Prompt biometrics (Face ID / Fingerprint) or PIN authentication
  Future<bool> authenticate(
    BuildContext context, {
    String reason = 'Authenticate with Face ID, Fingerprint, or PIN to access this chat',
  }) async {
    await init();

    // 1. Try Native Biometrics if supported
    if (!kIsWeb) {
      try {
        final canCheck = await _auth.canCheckBiometrics;
        final isSupported = await _auth.isDeviceSupported();

        if (canCheck || isSupported) {
          final authenticated = await _auth.authenticate(
            localizedReason: reason,
          );
          if (authenticated) return true;
        }
      } catch (e) {
        debugPrint('[ChatLockService] native biometrics error: $e');
      }
    }

    // 2. Fallback to PIN dialog if biometrics failed or is on Web/unsupported device
    if (context.mounted) {
      return await _showPinVerificationDialog(context);
    }

    return false;
  }

  Future<bool> _showPinVerificationDialog(BuildContext context) async {
    final pinController = TextEditingController();
    bool isInvalid = false;

    // If no PIN is configured yet, let user setup a 4-digit PIN
    if (!hasPin) {
      final created = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_outline_rounded, color: Color(0xFF0284C7), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Create Chat PIN',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Set a 4-digit security PIN for locked chats as fallback for Face ID / Fingerprint.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: pinController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                        color: Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final val = pinController.text.trim();
                      if (val.length == 4) {
                        await setSecurityPin(val);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('Save PIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ],
              );
            },
          );
        },
      );
      return created == true;
    }

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.fingerprint_rounded, color: Color(0xFF0284C7), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Chat Security Lock',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your 4-digit PIN to view this conversation.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pinController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: isInvalid ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: isInvalid ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: isInvalid ? const Color(0xFFEF4444) : const Color(0xFF0284C7), width: 1.5),
                      ),
                    ),
                  ),
                  if (isInvalid) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Incorrect PIN. Please try again.',
                      style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  onPressed: () {
                    final val = pinController.text.trim();
                    if (val == _cachedPin) {
                      Navigator.pop(ctx, true);
                    } else {
                      HapticFeedback.heavyImpact();
                      setDialogState(() {
                        isInvalid = true;
                        pinController.clear();
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Unlock', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ],
            );
          },
        );
      },
    );

    return verified == true;
  }
}
