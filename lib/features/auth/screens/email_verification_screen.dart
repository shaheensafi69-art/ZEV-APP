import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/services/multi_account_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../main_navigation/screens/zev_main_layout.dart';

/// World-Class 8-Digit Email Verification Screen for ZEV.
/// Handles instant verification of unconfirmed emails with:
/// - 8 individual digit input boxes with auto-advance and backspace handling
/// - 1-tap clipboard paste support
/// - 60s resend timer
/// - Instant login completion and navigation to ZevMainLayout
class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String? password;
  final VoidCallback? onVerified;

  const EmailVerificationScreen({
    super.key,
    required this.email,
    this.password,
    this.onVerified,
  });

  static Future<bool?> open(
    BuildContext context, {
    required String email,
    String? password,
    VoidCallback? onVerified,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmailVerificationScreen(
          email: email,
          password: password,
          onVerified: onVerified,
        ),
      ),
    );
  }

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  final List<TextEditingController> _digitCtrls =
      List.generate(8, (_) => TextEditingController());
  final List<FocusNode> _digitFocusNodes =
      List.generate(8, (_) => FocusNode());
  final TextEditingController _unifiedCtrl = TextEditingController();

  bool _isVerifying = false;
  String? _errorMsg;
  int _resendCountdown = 60;
  Timer? _resendTimer;
  StreamSubscription<AuthState>? _authListener;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    _startResendTimer();
    _listenToAuthConfirmation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _digitFocusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _resendTimer?.cancel();
    _authListener?.cancel();
    _unifiedCtrl.dispose();
    for (final c in _digitCtrls) {
      c.dispose();
    }
    for (final f in _digitFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _resendCountdown = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  void _listenToAuthConfirmation() {
    _authListener = supabase.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;
      if ((event == AuthChangeEvent.signedIn || event == AuthChangeEvent.userUpdated) &&
          session != null) {
        _authListener?.cancel();
        await _onVerificationSuccess(session.user.id);
      }
    });
  }

  String get _currentCode {
    final unified = _unifiedCtrl.text.trim();
    if (unified.isNotEmpty) return unified;
    return _digitCtrls.map((c) => c.text.trim()).join();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.replaceAll(RegExp(r'\D'), '') ?? '';
      if (text.isNotEmpty) {
        final code = text.length > 8 ? text.substring(0, 8) : text;
        _unifiedCtrl.text = code;
        for (int i = 0; i < 8; i++) {
          if (i < code.length) {
            _digitCtrls[i].text = code[i];
          } else {
            _digitCtrls[i].clear();
          }
        }
        setState(() => _errorMsg = null);
        HapticFeedback.selectionClick();
        if (code.length >= 8) {
          _verifyCode();
        }
      }
    } catch (_) {}
  }

  Future<void> _verifyCode() async {
    final code = _currentCode;
    if (code.length < 6) {
      setState(() => _errorMsg = "Please enter all 8 digits.");
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isVerifying = true;
      _errorMsg = null;
    });

    try {
      final res = await supabase.auth.verifyOTP(
        email: widget.email.trim(),
        token: code,
        type: OtpType.signup,
      );

      final user = res.user;
      if (user == null) {
        throw "Could not verify code. Please check and try again.";
      }

      await _onVerificationSuccess(user.id);
    } on AuthException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorMsg = e.message;
        });
        _unifiedCtrl.clear();
        for (final c in _digitCtrls) {
          c.clear();
        }
        _digitFocusNodes[0].requestFocus();
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorMsg = e.toString().replaceFirst('Exception: ', '');
        });
        _unifiedCtrl.clear();
        for (final c in _digitCtrls) {
          c.clear();
        }
        _digitFocusNodes[0].requestFocus();
      }
    }
  }

  Future<void> _onVerificationSuccess(String userId) async {
    // If password provided, sign in freshly
    if (widget.password != null && widget.password!.isNotEmpty) {
      try {
        await supabase.auth.signInWithPassword(
          email: widget.email.trim(),
          password: widget.password!,
        );
      } catch (_) {}
    }

    // Fetch profile role
    String role = 'user';
    try {
      final prof = await supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      if (prof != null) {
        role = prof['role']?.toString() ?? 'user';
      }
    } catch (_) {}

    await AuthHelper.markUserLoggedIn(userId: userId, role: role);
    await MultiAccountService.saveCurrentAccount();

    if (widget.onVerified != null) {
      widget.onVerified!();
      return;
    }

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ZevMainLayout()),
        (route) => false,
      );
    }
  }

  Future<void> _resendCode() async {
    if (_resendCountdown > 0) return;

    HapticFeedback.lightImpact();
    setState(() => _errorMsg = null);

    try {
      await supabase.auth.resend(
        type: OtpType.signup,
        email: widget.email.trim(),
      );

      _startResendTimer();
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
                Text("Verification code resent to your email!"),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMsg = "Failed to resend code: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: ZevColors.deepNavy),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),

              // Animated Breathing Badge
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          ZevColors.primaryBlue.withValues(alpha: 0.15),
                          ZevColors.secondaryBlue.withValues(alpha: 0.25),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.primaryBlue.withValues(
                            alpha: 0.20 + (_pulseAnimation.value * 0.15),
                          ),
                          blurRadius: 28,
                          spreadRadius: 2 + (_pulseAnimation.value * 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: const Icon(
                          Icons.mark_email_unread_rounded,
                          size: 30,
                          color: ZevColors.primaryBlue,
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              const Text(
                "Verify Your Email",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: ZevColors.deepNavy,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 10),

              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14,
                    color: ZevColors.textSecondary,
                    height: 1.45,
                  ),
                  children: [
                    const TextSpan(text: "We have sent an 8-digit verification code to\n"),
                    TextSpan(
                      text: widget.email,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                    const TextSpan(text: "\nEnter the code below to activate your account."),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // 8-Digit OTP Matrix
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(8, (i) {
                    return Container(
                      width: ((size.width - 48 - (7 * 6)) / 8).clamp(34.0, 44.0),
                      height: 52,
                      margin: EdgeInsets.symmetric(horizontal: (size.width < 360 ? 2 : 3)),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _digitFocusNodes[i].hasFocus
                              ? ZevColors.primaryBlue
                              : (_digitCtrls[i].text.isNotEmpty
                                  ? const Color(0xFFCBD5E1)
                                  : const Color(0xFFE2E8F0)),
                          width: _digitFocusNodes[i].hasFocus ? 2.0 : 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _digitFocusNodes[i].hasFocus
                                ? ZevColors.primaryBlue.withValues(alpha: 0.15)
                                : Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: TextField(
                          controller: _digitCtrls[i],
                          focusNode: _digitFocusNodes[i],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 1,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: ZevColors.deepNavy,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            counterText: '',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) {
                            if (val.isNotEmpty) {
                              if (i < 7) {
                                _digitFocusNodes[i + 1].requestFocus();
                              } else {
                                _digitFocusNodes[i].unfocus();
                                _verifyCode();
                              }
                            } else if (val.isEmpty && i > 0) {
                              _digitFocusNodes[i - 1].requestFocus();
                            }
                          },
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 16),

              // Paste from Clipboard Button
              GestureDetector(
                onTap: _pasteFromClipboard,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.content_paste_rounded, size: 14, color: ZevColors.primaryBlue),
                      SizedBox(width: 6),
                      Text(
                        "Paste Code from Clipboard",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ZevColors.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_errorMsg != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMsg!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // Verify Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isVerifying ? null : _verifyCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZevColors.primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "Verify & Continue",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // Resend Countdown Row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Didn't receive the code? ",
                    style: TextStyle(
                      fontSize: 13,
                      color: ZevColors.textSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: _resendCountdown > 0 ? null : _resendCode,
                    child: Text(
                      _resendCountdown > 0
                          ? "Resend in ${_resendCountdown}s"
                          : "Resend Code",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _resendCountdown > 0
                            ? ZevColors.textMuted
                            : ZevColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
