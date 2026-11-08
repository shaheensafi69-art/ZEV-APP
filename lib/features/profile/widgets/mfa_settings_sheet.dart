import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/mfa_service.dart';
import '../../../core/services/passkey_auth_service.dart';
import '../../../core/theme/zev_theme.dart';

/// Flagship Security & Authenticator Settings Sheet for ZEV.
/// Allows users to enroll or unenroll TOTP Authenticator apps (Google Authenticator,
/// Microsoft Authenticator, Apple Passwords) and configure Passkeys / Biometric login.
class MfaSettingsSheet extends StatefulWidget {
  const MfaSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: ZevColors.deepNavy.withValues(alpha: 0.55),
      builder: (_) => const MfaSettingsSheet(),
    );
  }

  @override
  State<MfaSettingsSheet> createState() => _MfaSettingsSheetState();
}

class _MfaSettingsSheetState extends State<MfaSettingsSheet> {
  bool _isLoading = true;
  bool _hasMfa = false;
  Factor? _activeFactor;

  // Passkey state
  bool _isPasskeySupported = false;
  bool _isPasskeyEnrolled = false;

  // Enrollment flow state
  bool _isEnrolling = false;
  String? _enrollFactorId;
  String? _enrollSecret;
  final TextEditingController _codeCtrl = TextEditingController();
  bool _isVerifyingEnrollment = false;
  String? _enrollError;

  @override
  void initState() {
    super.initState();
    _loadSecurityStatus();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSecurityStatus() async {
    setState(() => _isLoading = true);
    try {
      final factors = await MfaService.instance.getEnrolledFactors();
      final hasPasskeySupport = await PasskeyAuthService.instance.isDeviceSupported();
      final hasPasskey = await PasskeyAuthService.instance.isPasskeyEnrolled();

      if (mounted) {
        setState(() {
          _hasMfa = factors.isNotEmpty;
          _activeFactor = factors.isNotEmpty ? factors.first : null;
          _isPasskeySupported = hasPasskeySupport;
          _isPasskeyEnrolled = hasPasskey;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startTotpEnrollment() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isEnrolling = true;
      _enrollError = null;
      _codeCtrl.clear();
    });

    try {
      final enrollRes = await MfaService.instance.startEnrollment(
        friendlyName: 'ZEV Authenticator',
      );

      setState(() {
        _enrollFactorId = enrollRes.id;
        _enrollSecret = enrollRes.totp?.secret;
      });
    } catch (e) {
      setState(() {
        _isEnrolling = false;
        _enrollError = "Could not initialize Authenticator enrollment: $e";
      });
    }
  }

  Future<void> _confirmTotpEnrollment() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 6 || _enrollFactorId == null) {
      setState(() => _enrollError = "Please enter the 6-digit verification code.");
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isVerifyingEnrollment = true;
      _enrollError = null;
    });

    try {
      await MfaService.instance.verifyEnrollment(
        factorId: _enrollFactorId!,
        code: code,
      );

      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isEnrolling = false;
          _isVerifyingEnrollment = false;
        });
        await _loadSecurityStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text(
                    "Two-Factor Authentication is now active!",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isVerifyingEnrollment = false;
          _enrollError = "Invalid verification code. Please check your Authenticator app and try again.";
        });
      }
    }
  }

  Future<void> _disableTotp() async {
    if (_activeFactor == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZevColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Disable Two-Factor Authentication?",
          style: TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          "Your account will no longer require a 6-digit Authenticator code upon signing in. This decreases account security.",
          style: TextStyle(color: ZevColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Keep Enabled"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Disable 2FA"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      await MfaService.instance.unenrollFactor(_activeFactor!.id);
      await _loadSecurityStatus();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text("Error disabling 2FA: $e"),
          ),
        );
      }
    }
  }

  Future<void> _togglePasskey() async {
    HapticFeedback.lightImpact();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.email == null) return;

    if (_isPasskeyEnrolled) {
      // Disable
      await PasskeyAuthService.instance.removePasskey();
      await _loadSecurityStatus();
    } else {
      // Enable
      final success = await PasskeyAuthService.instance.enrollPasskey(
        email: user.email!,
        userId: user.id,
      );
      if (success) {
        await _loadSecurityStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: const Row(
                children: [
                  Icon(Icons.fingerprint_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text(
                    "ZEV Passkey enabled for 1-Tap Biometric sign-in!",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Color(0x33080D1A),
              blurRadius: 36,
              offset: Offset(0, -10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: _isLoading
              ? const SizedBox(
                  height: 240,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(ZevColors.primaryBlue),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag Handle
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.shield_rounded,
                                color: ZevColors.primaryBlue,
                                size: 26,
                              ),
                              SizedBox(width: 10),
                              Text(
                                "Security & Access",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: ZevColors.deepNavy,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: ZevColors.textMuted),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // ==========================================
                      // 1. PASSKEY / BIOMETRICS CARD
                      // ==========================================
                      if (_isPasskeySupported) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: ZevColors.primaryBlue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.fingerprint_rounded,
                                  color: ZevColors.secondaryBlue,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Passkey & Biometrics",
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: ZevColors.deepNavy,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      "Sign in seamlessly with Face ID, Touch ID, or Device Passkey.",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: ZevColors.textSecondary,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: _isPasskeyEnrolled,
                                activeTrackColor: ZevColors.secondaryBlue,
                                onChanged: (_) => _togglePasskey(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ==========================================
                      // 2. TOTP AUTHENTICATOR APP CARD
                      // ==========================================
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF536DFE).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.phonelink_lock_rounded,
                                    color: Color(0xFF536DFE),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Text(
                                            "Authenticator App",
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: ZevColors.deepNavy,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _hasMfa
                                                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                                  : const Color(0xFF94A3B8).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              _hasMfa ? "Active" : "Not Set",
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: _hasMfa
                                                    ? const Color(0xFF10B981)
                                                    : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      const Text(
                                        "Google Authenticator, Microsoft Authenticator, or Apple Passwords.",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: ZevColors.textSecondary,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // If enrollment is active, show the setup flow
                            if (_isEnrolling) ...[
                              const Divider(height: 28, color: Color(0xFFE2E8F0)),
                              const Text(
                                "Step 1: Copy Secret Key",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: ZevColors.deepNavy,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Open your Authenticator app, add a new account, and paste the key below:",
                                style: TextStyle(fontSize: 12, color: ZevColors.textSecondary),
                              ),
                              const SizedBox(height: 10),

                              // Secret Key Display Box with Copy Button
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: SelectableText(
                                        _enrollSecret ?? "Loading secret...",
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          fontFamily: 'monospace',
                                          color: ZevColors.deepNavy,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.copy_rounded, size: 20, color: ZevColors.secondaryBlue),
                                      tooltip: "Copy Key",
                                      onPressed: () {
                                        if (_enrollSecret != null) {
                                          Clipboard.setData(ClipboardData(text: _enrollSecret!));
                                          HapticFeedback.lightImpact();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text("Authenticator key copied to clipboard!"),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),

                              const Text(
                                "Step 2: Enter 6-Digit Code",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: ZevColors.deepNavy,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Code input field
                              TextField(
                                controller: _codeCtrl,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 6,
                                  color: ZevColors.deepNavy,
                                ),
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: InputDecoration(
                                  counterText: "",
                                  hintText: "000000",
                                  hintStyle: const TextStyle(color: Color(0xFFCBD5E1), letterSpacing: 6),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: ZevColors.primaryBlue, width: 2),
                                  ),
                                ),
                              ),

                              if (_enrollError != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _enrollError!,
                                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                                ),
                              ],

                              const SizedBox(height: 16),

                              // Verify & Activate Button
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _isVerifyingEnrollment ? null : _confirmTotpEnrollment,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: ZevColors.primaryBlue,
                                        foregroundColor: ZevColors.deepNavy,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      child: _isVerifyingEnrollment
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(ZevColors.deepNavy),
                                              ),
                                            )
                                          : const Text(
                                              "Verify & Activate",
                                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  TextButton(
                                    onPressed: () => setState(() => _isEnrolling = false),
                                    child: const Text("Cancel"),
                                  ),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 14),
                              if (_hasMfa) ...[
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _disableTotp,
                                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                      label: const Text("Remove Authenticator"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFFEE2E2),
                                        foregroundColor: const Color(0xFFDC2626),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                ElevatedButton.icon(
                                  onPressed: _startTotpEnrollment,
                                  icon: const Icon(Icons.security_rounded, size: 18),
                                  label: const Text("Set up Authenticator App"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ZevColors.primaryBlue,
                                    foregroundColor: ZevColors.deepNavy,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
