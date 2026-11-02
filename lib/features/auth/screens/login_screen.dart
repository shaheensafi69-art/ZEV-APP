import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_text_field.dart';
import 'register_screen.dart';

/// Next-Generation Instagram-Grade Login Screen for ZEV.
/// Fully crafted with the official #00D4FF / #080D1A / #F5F8FC design system.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final supabase = Supabase.instance.client;

  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _showPassword = false;
  bool _rememberMe = true;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMsg = "Please enter both email and password.");
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final authResponse = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = authResponse.user;

      if (user != null) {
        TextInput.finishAutofillContext(shouldSave: true);

        // Fetch user role
        String userRole = 'student';
        try {
          final profileRes = await supabase
              .from('profiles')
              .select('role')
              .eq('id', user.id)
              .maybeSingle();

          if (profileRes != null && profileRes['role'] != null) {
            userRole = profileRes['role'].toString();
          }
        } catch (roleErr) {
          debugPrint("Profile role fetch warning: $roleErr");
        }

        // Store local session in SharedPreferences
        if (_rememberMe) {
          await AuthHelper.markUserLoggedIn(userId: user.id, role: userRole);
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Logged in successfully! Welcome to ZEV."),
            backgroundColor: ZevColors.deepNavy,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );

        // Pop back to root or open main dashboard
        Navigator.of(context).pop(true);
      } else {
        throw "Login failed. Please check your credentials.";
      }
    } on AuthException catch (e) {
      HapticFeedback.heavyImpact();
      setState(() {
        _isLoading = false;
        _errorMsg = e.message;
      });
    } catch (e) {
      HapticFeedback.heavyImpact();
      setState(() {
        _isLoading = false;
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _handleForgotPassword() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ForgotPasswordSheet(initialEmail: _emailCtrl.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          onPressed: () => Navigator.maybePop(context),
          tooltip: "Back",
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 8),

                          // Brand 3D Mini Icon
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: ZevColors.border,
                                width: 2.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: ZevColors.primaryBlue.withValues(alpha: 0.25),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(2),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.asset(
                                'assets/icon/icon-192x192.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.bolt_rounded,
                                  size: 38,
                                  color: ZevColors.primaryBlue,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          const Text(
                            "Welcome Back",
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: ZevColors.deepNavy,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            "Sign in to continue connecting and sharing",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: ZevColors.textSecondary,
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Error Banner
                          if (_errorMsg != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFFCA5A5),
                                  width: 1.0,
                                ),
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
                                      _errorMsg!,
                                      style: const TextStyle(
                                        color: Color(0xFF991B1B),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Email Field
                          ZevTextField(
                            label: "Email Address",
                            hint: "name@example.com",
                            controller: _emailCtrl,
                            focusNode: _emailFocus,
                            prefixIcon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            onSubmitted: (_) => _passwordFocus.requestFocus(),
                          ),

                          const SizedBox(height: 16),

                          // Password Field
                          ZevTextField(
                            label: "Password",
                            hint: "••••••••",
                            controller: _passwordCtrl,
                            focusNode: _passwordFocus,
                            prefixIcon: Icons.lock_outline_rounded,
                            isPassword: true,
                            isObscured: !_showPassword,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _handleLogin(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                size: 20,
                                color: ZevColors.textMuted,
                              ),
                              onPressed: () {
                                setState(() => _showPassword = !_showPassword);
                              },
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Remember Me & Forgot Password Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      activeColor: ZevColors.primaryBlue,
                                      checkColor: ZevColors.deepNavy,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      side: const BorderSide(
                                        color: ZevColors.border,
                                        width: 1.5,
                                      ),
                                      onChanged: (v) {
                                        setState(() => _rememberMe = v ?? true);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() => _rememberMe = !_rememberMe);
                                    },
                                    child: const Text(
                                      "Remember Me",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: ZevColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              TextButton(
                                onPressed: _handleForgotPassword,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  "Forgot password?",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: ZevColors.secondaryBlue,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 28),

                          // Primary Log In Button
                          Container(
                            width: double.infinity,
                            height: 52,
                            decoration: BoxDecoration(
                              color: ZevColors.primaryBlue,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: ZevColors.primaryBlue.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          ZevColors.deepNavy,
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      "Log In",
                                      style: TextStyle(
                                        color: ZevColors.deepNavy,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Docked Bottom Instagram Footer: Sign Up Link
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: ZevColors.border, width: 1.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(
                      fontSize: 13.5,
                      color: ZevColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      "Sign up",
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: ZevColors.secondaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reset Password Bottom Sheet.
class _ForgotPasswordSheet extends StatefulWidget {
  final String initialEmail;
  const _ForgotPasswordSheet({required this.initialEmail});

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  final supabase = Supabase.instance.client;
  late final TextEditingController _resetEmailCtrl;
  bool _isLoading = false;
  bool _isSent = false;
  String? _sheetError;

  @override
  void initState() {
    super.initState();
    _resetEmailCtrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _resetEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendPasswordReset() async {
    final email = _resetEmailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _sheetError = "Please enter a valid email address.");
      return;
    }

    setState(() {
      _isLoading = true;
      _sheetError = null;
    });

    try {
      await supabase.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSent = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _sheetError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: ZevColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Reset Password",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Enter your registered email and we'll send a recovery link.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: ZevColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          if (_isSent) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ZevColors.softSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ZevColors.border),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Reset link sent! Please check your inbox and follow the link.",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ZevColors.deepNavy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  "Done",
                  style: TextStyle(
                    color: ZevColors.deepNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ] else ...[
            if (_sheetError != null) ...[
              Text(
                _sheetError!,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
            ],
            ZevTextField(
              label: "Email",
              hint: "name@example.com",
              controller: _resetEmailCtrl,
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _sendPasswordReset,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZevColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ZevColors.deepNavy,
                        ),
                      )
                    : const Text(
                        "Send Recovery Link",
                        style: TextStyle(
                          color: ZevColors.deepNavy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
