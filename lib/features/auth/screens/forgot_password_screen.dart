import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_text_field.dart';

/// Steps in the Password Reset Flow
enum _ResetStep {
  email,
  otp,
  newPassword,
  success,
}

/// Ultra-Modern, Multi-Step Password Recovery Experience for ZEV.
/// Handles:
/// 1. Email input -> sends OTP via Supabase Auth
/// 2. OTP Verification -> flexible 6 to 8-digit input with resend countdown
/// 3. Secure New Password -> live strength meter & confirmation check
/// 4. Success celebration -> seamless redirect to login
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  final String? initialToken;

  const ForgotPasswordScreen({
    super.key,
    this.initialEmail = '',
    this.initialToken,
  });

  static Future<void> open(
    BuildContext context, {
    String email = '',
    String? token,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: email,
          initialToken: token,
        ),
      ),
    );
  }

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  _ResetStep _currentStep = _ResetStep.email;
  bool _isLoading = false;
  String? _errorMessage;

  // Step 1: Email
  late final TextEditingController _emailCtrl;

  // Step 2: OTP
  late final TextEditingController _otpCtrl;
  final FocusNode _otpFocusNode = FocusNode();
  int _resendCountdown = 60;
  Timer? _countdownTimer;
  bool _canResend = false;

  // Step 3: New Password
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  // Animation controller for step transitions
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail);
    _otpCtrl = TextEditingController(text: widget.initialToken ?? '');

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.04, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();

    // If initialToken is provided via deep link, jump to OTP or new password
    if (widget.initialToken != null && widget.initialToken!.isNotEmpty) {
      if (widget.initialEmail.isNotEmpty) {
        _currentStep = _ResetStep.otp;
        _startResendTimer();
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _otpFocusNode.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _transitionToStep(_ResetStep step) {
    HapticFeedback.mediumImpact();
    setState(() {
      _currentStep = step;
      _errorMessage = null;
    });
    _animController.reset();
    _animController.forward();

    if (step == _ResetStep.otp) {
      _startResendTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _otpFocusNode.requestFocus();
      });
    }
  }

  void _startResendTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _resendCountdown = 60;
      _canResend = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown <= 1) {
        timer.cancel();
        setState(() {
          _resendCountdown = 0;
          _canResend = true;
        });
      } else {
        setState(() {
          _resendCountdown--;
        });
      }
    });
  }

  // -------------------------------------------------------------
  // ACTION: Step 1 -> Send Recovery OTP
  // -------------------------------------------------------------
  Future<void> _sendRecoveryEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _errorMessage = "Please enter a valid email address.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await supabase.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() => _isLoading = false);
        _transitionToStep(_ResetStep.otp);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('AuthException: ', '');
        });
      }
    }
  }

  // -------------------------------------------------------------
  // ACTION: Step 2 -> Verify Recovery OTP
  // -------------------------------------------------------------
  Future<void> _verifyOtpCode() async {
    final email = _emailCtrl.text.trim();
    final otp = _otpCtrl.text.trim();

    if (otp.isEmpty || otp.length < 6) {
      setState(() => _errorMessage = "Please enter the full verification code.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await supabase.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.recovery,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (res.user != null || res.session != null) {
          _transitionToStep(_ResetStep.newPassword);
        } else {
          setState(() => _errorMessage = "Verification failed. Please check the code and try again.");
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          final rawMsg = e.toString().replaceFirst('Exception: ', '').replaceFirst('AuthException: ', '');
          if (rawMsg.toLowerCase().contains('expired') || rawMsg.toLowerCase().contains('invalid')) {
            _errorMessage = "The code is invalid or has expired. Please request a new one.";
          } else {
            _errorMessage = rawMsg;
          }
        });
      }
    }
  }

  // -------------------------------------------------------------
  // ACTION: Resend OTP Code
  // -------------------------------------------------------------
  Future<void> _resendCode() async {
    if (!_canResend || _isLoading) return;

    final email = _emailCtrl.text.trim();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await supabase.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() => _isLoading = false);
        _startResendTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "New verification code sent! Check your email.",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: ZevColors.deepNavy,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('AuthException: ', '');
        });
      }
    }
  }

  // -------------------------------------------------------------
  // ACTION: Step 3 -> Update Password
  // -------------------------------------------------------------
  Future<void> _updatePassword() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;

    if (password.length < 8) {
      setState(() => _errorMessage = "Password must be at least 8 characters.");
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = "Passwords do not match.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await supabase.auth.updateUser(
        UserAttributes(password: password),
      );

      // Sign out to enforce clean login with new password
      try {
        await supabase.auth.signOut();
      } catch (_) {}

      if (mounted) {
        setState(() => _isLoading = false);
        _transitionToStep(_ResetStep.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('AuthException: ', '');
        });
      }
    }
  }

  // -------------------------------------------------------------
  // Password Strength Calculation
  // -------------------------------------------------------------
  double _calculatePasswordStrength(String password) {
    if (password.isEmpty) return 0.0;
    double score = 0.0;
    if (password.length >= 8) score += 0.35;
    if (RegExp(r'[0-9]').hasMatch(password)) score += 0.25;
    if (RegExp(r'[a-zA-Z]').hasMatch(password)) score += 0.25;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) score += 0.15;
    return score.clamp(0.0, 1.0);
  }

  Color _getStrengthColor(double strength) {
    if (strength <= 0.35) return const Color(0xFFEF4444);
    if (strength <= 0.70) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  String _getStrengthLabel(double strength) {
    if (strength <= 0.35) return "Weak";
    if (strength <= 0.70) return "Fair";
    if (strength <= 0.90) return "Good";
    return "Strong";
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: ZevColors.white,
      appBar: AppBar(
        backgroundColor: ZevColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ZevColors.deepNavy,
            size: 20,
          ),
          onPressed: () {
            if (_currentStep == _ResetStep.otp) {
              _transitionToStep(_ResetStep.email);
            } else if (_currentStep == _ResetStep.newPassword) {
              _transitionToStep(_ResetStep.otp);
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
        title: Text(
          _currentStep == _ResetStep.success ? "Success" : "Reset Password",
          style: const TextStyle(
            color: ZevColors.deepNavy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                // Top Progress Stepper (hidden on success)
                if (_currentStep != _ResetStep.success) ...[
                  const SizedBox(height: 12),
                  _buildStepper(),
                  const SizedBox(height: 16),
                ],

                // Content Area with Smooth Animation
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Error banner
                            if (_errorMessage != null) ...[
                              _buildErrorBanner(_errorMessage!),
                              const SizedBox(height: 18),
                            ],

                            // Step-specific views
                            if (_currentStep == _ResetStep.email)
                              _buildEmailStep()
                            else if (_currentStep == _ResetStep.otp)
                              _buildOtpStep()
                            else if (_currentStep == _ResetStep.newPassword)
                              _buildNewPasswordStep()
                            else
                              _buildSuccessStep(),

                            if (!isKeyboardOpen) const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Top 3-Step Progress Tracker
  // -------------------------------------------------------------
  Widget _buildStepper() {
    int activeIndex = 0;
    if (_currentStep == _ResetStep.otp) activeIndex = 1;
    if (_currentStep == _ResetStep.newPassword) activeIndex = 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Row(
        children: [
          _buildStepNode(0, "Email", activeIndex),
          _buildStepDivider(0, activeIndex),
          _buildStepNode(1, "Code", activeIndex),
          _buildStepDivider(1, activeIndex),
          _buildStepNode(2, "Password", activeIndex),
        ],
      ),
    );
  }

  Widget _buildStepNode(int index, String label, int activeIndex) {
    final isDone = activeIndex > index;
    final isCurrent = activeIndex == index;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: (isDone || isCurrent) ? ZevColors.brandGradient : null,
            color: (isDone || isCurrent) ? null : const Color(0xFFF1F5F9),
            border: Border.all(
              color: isCurrent
                  ? ZevColors.primaryBlue
                  : (isDone ? Colors.transparent : const Color(0xFFE2E8F0)),
              width: 2,
            ),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: ZevColors.primaryBlue.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : Text(
                    "${index + 1}",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: isCurrent ? Colors.white : const Color(0xFF94A3B8),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
            color: isCurrent ? ZevColors.deepNavy : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider(int index, int activeIndex) {
    final isPassed = activeIndex > index;
    return Expanded(
      child: Container(
        height: 2.5,
        margin: const EdgeInsets.only(bottom: 16, left: 6, right: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          gradient: isPassed ? ZevColors.brandGradient : null,
          color: isPassed ? null : const Color(0xFFE2E8F0),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Error Banner
  // -------------------------------------------------------------
  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 19,
            color: Color(0xFFDC2626),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // STEP 1: Email Form
  // =============================================================
  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),

        // Shimmering 3D App Icon Badge
        _buildHeroBadge(
          icon: Icons.lock_reset_rounded,
          gradientColors: [const Color(0xFF00D4FF), const Color(0xFF0284C7)],
          showAppLogo: true,
        ),

        const SizedBox(height: 22),

        const Text(
          "Forgot Your Password?",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Enter your registered ZEV email address. We'll send you an instant verification code to reset your password.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: ZevColors.textSecondary,
            height: 1.45,
          ),
        ),

        const SizedBox(height: 30),

        ZevTextField(
          label: "Email Address",
          hint: "example@domain.com",
          controller: _emailCtrl,
          prefixIcon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendRecoveryEmail(),
        ),

        const SizedBox(height: 26),

        _buildPrimaryButton(
          title: "Send Verification Code",
          isLoading: _isLoading,
          onTap: _sendRecoveryEmail,
        ),

        const SizedBox(height: 20),

        TextButton.icon(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 16, color: ZevColors.textSecondary),
          label: const Text(
            "Return to Sign In",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ZevColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // =============================================================
  // STEP 2: OTP Verification Form
  // =============================================================
  Widget _buildOtpStep() {
    final enteredEmail = _emailCtrl.text.trim();
    final otpLength = _otpCtrl.text.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),

        _buildHeroBadge(
          icon: Icons.mark_email_read_rounded,
          gradientColors: [const Color(0xFF00D4FF), const Color(0xFF536DFE)],
        ),

        const SizedBox(height: 22),

        const Text(
          "Enter Verification Code",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "We sent a recovery code to your inbox:",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: ZevColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),

        // Clickable Email Badge with Edit icon
        GestureDetector(
          onTap: () => _transitionToStep(_ResetStep.email),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: ZevColors.softSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ZevColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  enteredEmail,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ZevColors.deepNavy,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: ZevColors.primaryBlue,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 30),

        // OTP PIN Visual Display (Supports 6 to 8 digits)
        _buildOtpInputBoxes(),

        const SizedBox(height: 14),

        // Auto-paste button
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () async {
                final clipboard = await Clipboard.getData('text/plain');
                final text = clipboard?.text?.replaceAll(RegExp(r'\s+'), '').trim() ?? '';
                if (text.isNotEmpty) {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _otpCtrl.text = text;
                  });
                }
              },
              icon: const Icon(Icons.content_paste_rounded, size: 15, color: ZevColors.secondaryBlue),
              label: const Text(
                "Paste Code",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: ZevColors.secondaryBlue,
                ),
              ),
            ),
            if (_otpCtrl.text.isNotEmpty) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _otpCtrl.clear());
                },
                child: const Text(
                  "Clear",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 20),

        _buildPrimaryButton(
          title: "Verify Code",
          isLoading: _isLoading,
          isEnabled: otpLength >= 6,
          onTap: _verifyOtpCode,
        ),

        const SizedBox(height: 20),

        // Resend Timer Row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _canResend ? "Didn't receive the code? " : "Resend code in ",
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ZevColors.textSecondary,
              ),
            ),
            if (!_canResend)
              Text(
                "${_resendCountdown}s",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.primaryBlue,
                ),
              )
            else
              GestureDetector(
                onTap: _resendCode,
                child: const Text(
                  "Resend Now",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.secondaryBlue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Builds a responsive, modern PIN entry that handles 6, 7, or 8 digits smoothly.
  Widget _buildOtpInputBoxes() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Default to 8 visual slots (matches ZEV's 8-digit email token)
        const totalSlots = 8;
        final availableWidth = constraints.maxWidth;
        // Spacing: 5px on small screens, up to 7px on wider screens
        final spacing = availableWidth < 350 ? 4.0 : 6.0;
        final boxWidth = ((availableWidth - (totalSlots - 1) * spacing) / totalSlots).clamp(28.0, 46.0);
        final currentText = _otpCtrl.text;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Invisible native TextField on top for keyboard and paste handling
            Opacity(
              opacity: 0.0,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: TextField(
                  controller: _otpCtrl,
                  focusNode: _otpFocusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  autofillHints: const [AutofillHints.oneTimeCode],
                  onChanged: (val) {
                    setState(() {});
                    if (val.length == 8) {
                      _verifyOtpCode();
                    }
                  },
                ),
              ),
            ),

            // Visual Segmented Digit Boxes
            GestureDetector(
              onTap: () {
                _otpFocusNode.requestFocus();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(totalSlots, (index) {
                  final hasValue = index < currentText.length;
                  final isFocused = _otpFocusNode.hasFocus && index == currentText.length;
                  final digit = hasValue ? currentText[index] : "";

                  return Container(
                    width: boxWidth,
                    height: 52,
                    margin: EdgeInsets.symmetric(horizontal: spacing / 2),
                    decoration: BoxDecoration(
                      color: hasValue ? Colors.white : ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isFocused
                            ? ZevColors.primaryBlue
                            : (hasValue
                                ? ZevColors.deepNavy.withValues(alpha: 0.3)
                                : ZevColors.border),
                        width: isFocused ? 2.0 : 1.4,
                      ),
                      boxShadow: isFocused
                          ? [
                              BoxShadow(
                                color: ZevColors.primaryBlue.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        digit,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.deepNavy,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }

  // =============================================================
  // STEP 3: Set New Password Form
  // =============================================================
  Widget _buildNewPasswordStep() {
    final password = _passwordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;
    final strength = _calculatePasswordStrength(password);
    final strengthColor = _getStrengthColor(strength);
    final strengthLabel = _getStrengthLabel(strength);

    final bool hasMinLength = password.length >= 8;
    final bool hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final bool hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
    final bool passwordsMatch = password.isNotEmpty && password == confirm;
    final bool isFormValid = hasMinLength && passwordsMatch;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),

        _buildHeroBadge(
          icon: Icons.key_rounded,
          gradientColors: [const Color(0xFF10B981), const Color(0xFF00D4FF)],
        ),

        const SizedBox(height: 22),

        const Text(
          "Create New Password",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Your identity has been verified. Choose a strong, memorable password to secure your ZEV account.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: ZevColors.textSecondary,
            height: 1.4,
          ),
        ),

        const SizedBox(height: 28),

        // New Password Field
        ZevTextField(
          label: "New Password",
          hint: "Minimum 8 characters",
          controller: _passwordCtrl,
          prefixIcon: Icons.lock_outline_rounded,
          isPassword: true,
          isObscured: !_showPassword,
          onChanged: (_) => setState(() {}),
          suffixIcon: IconButton(
            icon: Icon(
              _showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: ZevColors.textSecondary,
              size: 20,
            ),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),

        // Password Strength Indicator Bar
        if (password.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: strength,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                strengthLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: strengthColor,
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 16),

        // Confirm Password Field
        ZevTextField(
          label: "Confirm New Password",
          hint: "Re-enter new password",
          controller: _confirmPasswordCtrl,
          prefixIcon: Icons.lock_reset_rounded,
          isPassword: true,
          isObscured: !_showConfirmPassword,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (isFormValid) _updatePassword();
          },
          suffixIcon: IconButton(
            icon: Icon(
              _showConfirmPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: ZevColors.textSecondary,
              size: 20,
            ),
            onPressed: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
          ),
        ),

        const SizedBox(height: 16),

        // Criteria Checklist
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ZevColors.softSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ZevColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCriteriaRow("At least 8 characters", hasMinLength),
              const SizedBox(height: 6),
              _buildCriteriaRow("Contains letters and numbers", hasNumber && hasLetter),
              const SizedBox(height: 6),
              _buildCriteriaRow("Passwords match exactly", passwordsMatch),
            ],
          ),
        ),

        const SizedBox(height: 26),

        _buildPrimaryButton(
          title: "Update Password",
          isLoading: _isLoading,
          isEnabled: isFormValid,
          onTap: _updatePassword,
        ),
      ],
    );
  }

  Widget _buildCriteriaRow(String text, bool isMet) {
    return Row(
      children: [
        Icon(
          isMet ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 15,
          color: isMet ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isMet ? FontWeight.w700 : FontWeight.w500,
            color: isMet ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // =============================================================
  // STEP 4: Success Celebration State
  // =============================================================
  Widget _buildSuccessStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),

        // Glowing 3D Celebration Badge
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF00D4FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.35),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
        ),

        const SizedBox(height: 28),

        const Text(
          "Password Updated!",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Your password has been successfully reset. You can now use your new credentials to sign in to your ZEV account.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: ZevColors.textSecondary,
              height: 1.45,
            ),
          ),
        ),

        const SizedBox(height: 36),

        _buildPrimaryButton(
          title: "Sign In to ZEV",
          isLoading: false,
          onTap: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ],
    );
  }

  // =============================================================
  // Shared UI Helpers
  // =============================================================
  Widget _buildHeroBadge({
    required IconData icon,
    required List<Color> gradientColors,
    bool showAppLogo = false,
  }) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ZevColors.border, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: showAppLogo
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/icon/icon-192x192.png',
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                ),
              )
            : Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
              ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String title,
    required bool isLoading,
    bool isEnabled = true,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isEnabled ? ZevColors.brandGradientHorizontal : null,
          color: isEnabled ? null : const Color(0xFFCBD5E1),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: ZevColors.primaryBlue.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: (isEnabled && !isLoading) ? onTap : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isEnabled ? Colors.white : const Color(0xFF64748B),
                    letterSpacing: -0.2,
                  ),
                ),
        ),
      ),
    );
  }
}

