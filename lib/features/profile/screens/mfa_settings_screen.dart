import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/mfa_service.dart';
import '../../../core/services/passkey_auth_service.dart';

/// Full Dedicated Screen for Security & Two-Factor Authentication on ZEV.
/// Allows users to enroll or unenroll TOTP Authenticator apps (Google Authenticator,
/// Microsoft Authenticator, Apple Passwords) and configure Passkeys / Biometric login.
class MfaSettingsScreen extends StatefulWidget {
  const MfaSettingsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MfaSettingsScreen()),
    );
  }

  @override
  State<MfaSettingsScreen> createState() => _MfaSettingsScreenState();
}

class _MfaSettingsScreenState extends State<MfaSettingsScreen> {
  bool _isLoading = true;
  bool _hasMfa = false;
  Factor? _activeFactor;

  // Passkey state
  bool _isPasskeySupported = false;
  bool _isPasskeyEnrolled = false;

  // Trusted Devices state
  List<Map<String, dynamic>> _trustedDevices = [];
  String _currentDeviceId = '';

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
      final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      final factors = await MfaService.instance.getEnrolledFactors();
      final hasPasskeySupport = await PasskeyAuthService.instance
          .isDeviceSupported();
      final hasPasskey = await PasskeyAuthService.instance.isPasskeyEnrolled();

      final currentDeviceId = await MfaService.instance.getOrCreateDeviceId();
      final trustedDevices = userId.isNotEmpty
          ? await MfaService.instance.getTrustedDevices(userId)
          : <Map<String, dynamic>>[];

      if (mounted) {
        setState(() {
          _hasMfa = factors.isNotEmpty;
          _activeFactor = factors.isNotEmpty ? factors.first : null;
          _isPasskeySupported = hasPasskeySupport;
          _isPasskeyEnrolled = hasPasskey;
          _currentDeviceId = currentDeviceId;
          _trustedDevices = trustedDevices;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _revokeDevice(String deviceId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;

    HapticFeedback.lightImpact();
    await MfaService.instance.revokeDevice(userId, deviceId);
    await _loadSecurityStatus();
  }

  Future<void> _revokeAllOtherDevices() async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;

    HapticFeedback.mediumImpact();
    await MfaService.instance.revokeAllOtherDevices(userId);
    await _loadSecurityStatus();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: const Text(
            "All other devices revoked. They will require 2FA next time.",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
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
      setState(
        () => _enrollError = "Please enter the 6-digit verification code.",
      );
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

      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId != null) {
        await MfaService.instance.trustCurrentDevice(currentUserId);
      }

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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              content: const Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
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
          _enrollError =
              "Invalid verification code. Please check your Authenticator app and try again.";
        });
      }
    }
  }

  Future<void> _disableTotp() async {
    if (_activeFactor == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Disable Two-Factor Authentication?",
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          "Your account will no longer require a 6-digit Authenticator code upon signing in. This decreases account security.",
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              content: const Row(
                children: [
                  Icon(
                    Icons.fingerprint_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
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
    final isDesktop = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Color(0xFF0F172A),
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          "Two-Factor Authentication",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 680 : double.infinity,
            ),
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF0284C7),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Security Shield Banner
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF0284C7,
                                ).withValues(alpha: 0.28),
                                blurRadius: 16,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.security_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _hasMfa
                                          ? "Account is Highly Protected"
                                          : "Upgrade Your Account Protection",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _hasMfa
                                          ? "Two-Factor Authentication is currently active on your ZEV profile."
                                          : "Prevent unauthorized logins by adding an authenticator app or biometric passkey.",
                                      style: const TextStyle(
                                        color: Color(0xFFE0F2FE),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ==========================================
                        // 1. PASSKEY / BIOMETRICS CARD
                        // ==========================================
                        if (_isPasskeySupported) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: Text(
                              "BIOMETRICS & PASSKEYS",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.95),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0F172A,
                                  ).withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                                const BoxShadow(
                                  color: Colors.white,
                                  blurRadius: 4,
                                  offset: Offset(0, -1),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF0284C7,
                                    ).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.fingerprint_rounded,
                                    color: Color(0xFF0284C7),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Passkey (Face / Fingerprint)",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _isPasskeyEnrolled
                                            ? "Active on this device"
                                            : "Fast, passwordless sign-in",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _isPasskeyEnrolled
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFF64748B),
                                          fontWeight: _isPasskeyEnrolled
                                              ? FontWeight.w700
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch.adaptive(
                                  value: _isPasskeyEnrolled,
                                  activeTrackColor: const Color(0xFF0284C7),
                                  onChanged: (_) => _togglePasskey(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ==========================================
                        // 2. TOTP AUTHENTICATOR APP CARD
                        // ==========================================
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Text(
                            "AUTHENTICATOR APP (TOTP)",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),

                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.95),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF0F172A,
                                ).withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                              const BoxShadow(
                                color: Colors.white,
                                blurRadius: 4,
                                offset: Offset(0, -1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF6366F1,
                                      ).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(
                                      Icons.vpn_key_rounded,
                                      color: Color(0xFF6366F1),
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Authenticator App",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14.5,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _hasMfa
                                              ? "Active (${_activeFactor?.friendlyName ?? 'ZEV 2FA'})"
                                              : "Google Authenticator, Apple, Microsoft",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _hasMfa
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFF64748B),
                                            fontWeight: _hasMfa
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_hasMfa)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFEF4444),
                                      ),
                                      tooltip: "Disable 2FA",
                                      onPressed: _disableTotp,
                                    )
                                  else if (!_isEnrolling)
                                    ElevatedButton(
                                      onPressed: _startTotpEnrollment,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF0284C7,
                                        ),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                      ),
                                      child: const Text(
                                        "Set Up",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                              // Enrollment Sub-panel
                              if (_isEnrolling) ...[
                                const SizedBox(height: 18),
                                const Divider(color: Color(0xFFF1F5F9)),
                                const SizedBox(height: 12),
                                const Text(
                                  "1. Copy this setup key and paste it into your Authenticator app:",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: SelectableText(
                                          _enrollSecret ?? "Loading secret...",
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: Color(0xFF0284C7),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.copy_rounded,
                                          size: 18,
                                          color: Color(0xFF0284C7),
                                        ),
                                        onPressed: () {
                                          if (_enrollSecret != null) {
                                            Clipboard.setData(
                                              ClipboardData(
                                                text: _enrollSecret!,
                                              ),
                                            );
                                            HapticFeedback.lightImpact();
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  "Secret key copied to clipboard!",
                                                ),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  "2. Enter the 6-digit code shown in your Authenticator:",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _codeCtrl,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 8,
                                    color: Color(0xFF0F172A),
                                  ),
                                  decoration: InputDecoration(
                                    counterText: "",
                                    hintText: "000000",
                                    hintStyle: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 8,
                                      color: Color(0xFFCBD5E1),
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF0284C7),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_enrollError != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _enrollError!,
                                    style: const TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => setState(
                                          () => _isEnrolling = false,
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: const Text("Cancel"),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: _isVerifyingEnrollment
                                            ? null
                                            : _confirmTotpEnrollment,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF0284C7,
                                          ),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: _isVerifyingEnrollment
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Text(
                                                "Verify & Activate",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        if (_hasMfa) ...[
                          const SizedBox(height: 24),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: Text(
                              "TRUSTED DEVICES (VERIFIED ONCE)",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.95),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0F172A,
                                  ).withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.devices_rounded,
                                        color: Color(0xFF10B981),
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Device Verification Hub",
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14.5,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            "New devices must enter your 6-digit Authenticator code once.",
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Divider(
                                  color: Color(0xFFF1F5F9),
                                  height: 1,
                                ),
                                const SizedBox(height: 12),
                                if (_trustedDevices.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      "This device is currently authorized and active.",
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  )
                                else
                                  ..._trustedDevices.map((dev) {
                                    final isCurrent =
                                        dev['device_id'] == _currentDeviceId;
                                    final name =
                                        dev['device_name']?.toString() ??
                                        'Authorized Device';
                                    final platform =
                                        dev['platform']
                                            ?.toString()
                                            .toLowerCase() ??
                                        'mobile';

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            platform == 'ios'
                                                ? Icons.apple_rounded
                                                : (platform == 'macos'
                                                      ? Icons.laptop_mac_rounded
                                                      : Icons
                                                            .phone_android_rounded),
                                            size: 20,
                                            color: const Color(0xFF475569),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        name,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 13,
                                                          color: Color(
                                                            0xFF0F172A,
                                                          ),
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    if (isCurrent) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 1,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              const Color(
                                                                0xFF10B981,
                                                              ).withValues(
                                                                alpha: 0.12,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                        ),
                                                        child: const Text(
                                                          "THIS DEVICE",
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            color: Color(
                                                              0xFF10B981,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const Text(
                                                  "Trusted • Verified via 2FA",
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (!isCurrent)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.close_rounded,
                                                size: 18,
                                                color: Color(0xFF94A3B8),
                                              ),
                                              tooltip: "Revoke trust",
                                              onPressed: () => _revokeDevice(
                                                dev['device_id']?.toString() ??
                                                    '',
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }),
                                if (_trustedDevices.length > 1) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: _revokeAllOtherDevices,
                                      icon: const Icon(
                                        Icons.security_update_warning_rounded,
                                        size: 16,
                                        color: Color(0xFFEF4444),
                                      ),
                                      label: const Text(
                                        "Log Out & Revoke All Other Devices",
                                        style: TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                          color: const Color(
                                            0xFFEF4444,
                                          ).withValues(alpha: 0.4),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
