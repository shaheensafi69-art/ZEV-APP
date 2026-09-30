import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/security_service.dart';

class SecurityLockScreen extends StatefulWidget {
  const SecurityLockScreen({super.key});

  @override
  State<SecurityLockScreen> createState() => _SecurityLockScreenState();
}

class _SecurityLockScreenState extends State<SecurityLockScreen> {
  // Direct package usage without interference
  final LocalAuthentication auth = LocalAuthentication();
  final supabase = Supabase.instance.client;

  bool _isAuthenticating = false;
  String _pinInput = "";

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color surfaceWhite = Colors.white;
  static const Color cardBorder = Color(0xFFF3F4F6);

  @override
  void initState() {
    super.initState();
    _authenticateWithBiometrics();
  }

  Future<void> _authenticateWithBiometrics() async {
    if (_isAuthenticating) return;
    try {
      final canAuth = await SecurityService.instance.canCheckBiometrics();
      if (!canAuth) return;

      setState(() => _isAuthenticating = true);

      bool authenticated = await auth.authenticate(
        localizedReason:
            'Please authenticate with Face ID or Fingerprint to access ZEV',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (authenticated && mounted) {
        SecurityService.instance.markSessionUnlocked();
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Biometric error: $e");
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  void _onNumberPressed(String number) {
    setState(() {
      if (_pinInput.length < 4) {
        _pinInput += number;
        if (_pinInput.length == 4) {
          _verifyPin(_pinInput);
        }
      }
    });
  }

  Future<void> _verifyPin(String pin) async {
    try {
      final savedPin = await SecurityService.instance.getPinCode();

      if (savedPin != null && savedPin == pin) {
        SecurityService.instance.markSessionUnlocked();
        if (mounted) Navigator.pop(context, true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.incorrectPin),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _pinInput = "");
        }
      }
    } catch (e) {
      debugPrint("PIN verification error: $e");
      setState(() => _pinInput = "");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0B0F19) : surfaceWhite;
    final primaryTextColor = isDark ? Colors.white : textDark;
    final secondaryTextColor = isDark ? Colors.white70 : textGrey;
    final keyButtonBg = isDark ? const Color(0xFF1E293B) : cardBorder;

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : lightPinkBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : primaryPink.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 36,
                  color: primaryPink,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.securityVerification,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: primaryTextColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.enter4DigitPin,
                style: TextStyle(
                  fontSize: 11,
                  color: secondaryTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 30),

              // PIN code dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  bool filled = index < _pinInput.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: filled ? 18 : 14,
                    height: filled ? 18 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? primaryPink
                          : (isDark ? const Color(0xFF1E293B) : cardBorder),
                      border: Border.all(
                        color: filled
                            ? primaryPink
                            : (isDark
                                  ? const Color(0xFF334155)
                                  : Colors.grey.shade300),
                        width: 1.5,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 40),

              // Keypad number dialer
              for (var row in [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['', '0', 'del'],
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: row.map((val) {
                      if (val.isEmpty)
                        return const SizedBox(width: 70, height: 70);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: SizedBox(
                          width: 65,
                          height: 65,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              shape: const CircleBorder(),
                              backgroundColor: keyButtonBg,
                              foregroundColor: primaryTextColor,
                              elevation: 0,
                            ),
                            onPressed: () {
                              if (val == 'del') {
                                if (_pinInput.isNotEmpty) {
                                  setState(
                                    () => _pinInput = _pinInput.substring(
                                      0,
                                      _pinInput.length - 1,
                                    ),
                                  );
                                }
                              } else {
                                _onNumberPressed(val);
                              }
                            },
                            child: val == 'del'
                                ? Icon(
                                    Icons.backspace_rounded,
                                    color: primaryTextColor,
                                    size: 20,
                                  )
                                : Text(
                                    val,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: primaryTextColor,
                                    ),
                                  ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 20),

              TextButton.icon(
                onPressed: _authenticateWithBiometrics,
                icon: const Icon(Icons.fingerprint_rounded, color: primaryPink),
                label: const Text(
                  "Use Fingerprint / FaceID",
                  style: TextStyle(
                    color: primaryPink,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
