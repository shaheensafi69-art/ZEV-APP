import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/services/auth_session_manager.dart';
import '../../../core/services/mfa_service.dart';
import '../../../core/services/multi_account_service.dart';
import '../../../core/services/passkey_auth_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/apple_sign_in_button.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../core/widgets/zev_logo.dart';
import '../../../core/widgets/zev_text_field.dart';
import '../../main_navigation/screens/zev_main_layout.dart';
import '../widgets/mfa_challenge_sheet.dart';
import 'account_standing_screen.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Flagship Instagram-Grade Multi-Account Login Screen for ZEV.
/// Engineered with:
/// - Atmospheric ambient breathing glow matching the serene ZEV brand
/// - Instagram-style Multi-Account Switcher (1-tap login to saved accounts)
/// - Seamless account creation and switching (manage 2, 3, or more accounts)
/// - Mathematically exact, razor-sharp official Google Sign-In integration
/// - Claymorphic inputs, haptic feedback, and responsive layout
class LoginScreen extends StatefulWidget {
  final bool isAddingAccount;

  const LoginScreen({
    super.key,
    this.isAddingAccount = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  late final AnimationController _breatheController;
  late final Animation<double> _breatheAnim;
  late final Animation<double> _glowAnim;

  List<SavedAccount> _savedAccounts = [];
  bool _isLoadingAccounts = true;
  bool _showSavedAccountsView = true;

  bool _isLoading = false;
  bool _showPassword = false;
  bool _rememberMe = true;
  String? _errorMsg;

  // Passkey / Biometrics state
  bool _isPasskeySupported = false;
  bool _isPasskeyEnrolled = false;
  String? _passkeyIdentifier;

  @override
  void initState() {
    super.initState();

    // 1. Serene Breathing Animation
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat(reverse: true);

    _breatheAnim = Tween<double>(begin: -5.0, end: 5.0).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOutSine),
    );

    _glowAnim = Tween<double>(begin: 0.18, end: 0.38).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOutSine),
    );

    // 2. Load Multi-Account saved list
    _loadSavedAccounts();

    // 3. Check Passkey / Biometric capability
    _checkPasskey();
  }

  Future<void> _checkPasskey() async {
    try {
      final supported = await PasskeyAuthService.instance.isDeviceSupported();
      final enrolled = await PasskeyAuthService.instance.isPasskeyEnrolled();
      final id = await PasskeyAuthService.instance.getEnrolledIdentifier();
      if (mounted) {
        setState(() {
          _isPasskeySupported = supported;
          _isPasskeyEnrolled = enrolled;
          _passkeyIdentifier = id;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSavedAccounts() async {
    final list = await MultiAccountService.getSavedAccounts();
    if (mounted) {
      setState(() {
        _savedAccounts = list;
        _isLoadingAccounts = false;
        // If user explicitly clicked "Add Account" or no accounts are saved, show form
        _showSavedAccountsView = list.isNotEmpty && !widget.isAddingAccount;
      });
    }
  }

  @override
  void dispose() {
    _breatheController.dispose();
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
        // Check Multi-Factor Authentication (Authenticator TOTP) requirement
        final hasMfa = MfaService.instance.isMfaRequired() ||
            (await MfaService.instance.hasEnrolledMfa());

        if (hasMfa) {
          final isTrusted =
              await MfaService.instance.isCurrentDeviceTrusted(user.id);
          if (!isTrusted) {
            // New or untrusted device -> Challenge user once with 6-digit Authenticator code
            final factors = await MfaService.instance.getEnrolledFactors();
            if (factors.isNotEmpty && mounted) {
              final verified = await MfaChallengeSheet.show(
                context,
                factorId: factors.first.id,
                accountEmail: email,
              );
              if (!verified) {
                setState(() {
                  _isLoading = false;
                  _errorMsg =
                      "Two-Factor Authentication cancelled. Login incomplete.";
                });
                return;
              }
              // Verification passed -> Save this device as trusted!
              await MfaService.instance.trustCurrentDevice(user.id);
            }
          }
        }

        TextInput.finishAutofillContext(shouldSave: true);

        final standing =
            await AuthSessionManager.instance.checkAccountStanding(user.id);
        if (standing.status == AccountStandingStatus.banned) {
          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => AccountStandingScreen(standing: standing),
              ),
              (route) => false,
            );
          }
          return;
        }
        if (!standing.isAllowed) {
          await AuthSessionManager.instance.signOutCurrentDevice();
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMsg = standing.reason ??
                  'This account is suspended or deactivated.';
            });
          }
          return;
        }

        // Fetch user profile info
        String userRole = 'user';
        String username = '';
        String fullName = '';
        String avatarUrl = '';
        bool isVerified = false;

        try {
          final profileRes = await supabase
              .from('profiles')
              .select()
              .eq('id', user.id)
              .maybeSingle();

          if (profileRes != null) {
            userRole = profileRes['role']?.toString() ?? 'user';
            username = profileRes['username']?.toString() ?? '';
            final first = profileRes['first_name']?.toString() ?? '';
            final last = profileRes['last_name']?.toString() ?? '';
            fullName = '$first $last'.trim();
            avatarUrl = profileRes['avatar_url']?.toString() ?? '';
            isVerified = profileRes['is_verified'] == true;
          }
        } catch (roleErr) {
          debugPrint("Profile fetch warning: $roleErr");
        }

        // 1. Mark user logged in locally, sync FCM, and log login session
        await AuthHelper.markUserLoggedIn(userId: user.id, role: userRole);
        unawaited(
          AuthSessionManager.instance.recordSecurityEvent(
            userId: user.id,
            eventType: 'password_login',
          ),
        );

        // 2. Save account into Instagram-style multi-account storage
        if (_rememberMe) {
          await MultiAccountService.saveCurrentAccount(
            overrideUsername: username,
            overrideFullName: fullName,
            overrideAvatar: avatarUrl,
            overrideIsVerified: isVerified,
          );
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              username.isNotEmpty
                  ? "Welcome back, @$username!"
                  : "Logged in successfully to ZEV.",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            backgroundColor: ZevColors.deepNavy,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

        // Navigate to Zev Main Dashboard
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ZevMainLayout()),
          (route) => false,
        );
      } else {
        throw "Login failed. Please check your credentials.";
      }
    } on AuthException catch (e) {
      HapticFeedback.heavyImpact();
      final lower = e.message.toLowerCase();
      setState(() {
        _isLoading = false;
        _errorMsg = lower.contains('banned')
            ? 'This account is suspended. Please contact support@zevapp.com to appeal or review your account standing.'
            : e.message;
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
    ForgotPasswordScreen.open(context, email: _emailCtrl.text.trim());
  }

  void _handleSocialAuthSuccess() async {
    // Save to multi-account upon Apple/external Login
    await MultiAccountService.saveCurrentAccount();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Ambient Zen Gradient 1: Cyan Glow (Top Right)
          Positioned(
            top: -size.width * 0.35,
            right: -size.width * 0.3,
            child: AnimatedBuilder(
              animation: _breatheController,
              builder: (context, _) {
                return Container(
                  width: size.width * 1.25,
                  height: size.width * 1.25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF00D4FF).withValues(
                          alpha: _glowAnim.value * 0.45,
                        ),
                        const Color(0xFFE0F2FE).withValues(alpha: 0.25),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),

          // Ambient Zen Gradient 2: Sky Indigo Glow (Bottom Left)
          Positioned(
            bottom: -size.width * 0.35,
            left: -size.width * 0.3,
            child: AnimatedBuilder(
              animation: _breatheController,
              builder: (context, _) {
                return Container(
                  width: size.width * 1.15,
                  height: size.width * 1.15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF536DFE).withValues(
                          alpha: _glowAnim.value * 0.22,
                        ),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.65],
                    ),
                  ),
                );
              },
            ),
          ),

          // Main Responsive Content
          SafeArea(
            child: Column(
              children: [
                // Top App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: ZevColors.deepNavy,
                          size: 20,
                        ),
                        onPressed: () => Navigator.maybePop(context),
                        tooltip: "Back",
                      ),
                      const ZevLogo(height: 28),
                      const SizedBox(width: 48), // balance leading icon
                    ],
                  ),
                ),

                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _isLoadingAccounts
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(40),
                                  child: CircularProgressIndicator(
                                    color: ZevColors.primaryBlue,
                                  ),
                                ),
                              )
                            : (_showSavedAccountsView
                                ? _buildInstagramSavedAccountsView()
                                : _buildStandardLoginForm()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 1. Instagram-Style Saved Accounts Switcher View
  Widget _buildInstagramSavedAccountsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 10),

        // Floating 3D Hero Brand Icon
        AnimatedBuilder(
          animation: _breatheController,
          builder: (context, _) {
            return Transform.translate(
              offset: Offset(0, _breatheAnim.value),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 3.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF).withValues(
                        alpha: _glowAnim.value * 0.9,
                      ),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: const Color(0xFF080D1A).withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/icon/icon-512x512.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        const Text(
          "Continue with Saved Account",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "Select an account to log in instantly",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),

        const SizedBox(height: 24),

        // List of Saved Accounts (Instagram-Style)
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _savedAccounts.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final acc = _savedAccounts[index];

            return GestureDetector(
              onTap: () => MultiAccountService.promptLoginForAccount(context, acc),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                  // Circular Avatar
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: acc.avatarUrl.isNotEmpty
                          ? ZevCachedImage.avatar(
                              imageUrl: acc.avatarUrl,
                              size: 52,
                            )
                          : Container(
                              color: ZevColors.primaryBlue.withValues(alpha: 0.2),
                              child: Center(
                                child: Text(
                                  acc.username.isNotEmpty
                                      ? acc.username[0].toUpperCase()
                                      : 'Z',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: ZevColors.deepNavy,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Account Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                "@${acc.username}",
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: ZevColors.deepNavy,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (acc.isVerified) ...[
                              const SizedBox(width: 5),
                              const Icon(
                                Icons.verified_rounded,
                                color: ZevColors.primaryBlue,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          acc.fullName.isNotEmpty ? acc.fullName : acc.email,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // 1-Tap Log In Button
                  ElevatedButton(
                    onPressed: () => MultiAccountService.switchToAccount(context, acc),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZevColors.primaryBlue,
                      foregroundColor: ZevColors.deepNavy,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      "Log In",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),

                  const SizedBox(width: 4),

                  // More / Remove Action
                  IconButton(
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: ZevColors.textMuted,
                      size: 20,
                    ),
                    onPressed: () => _showRemoveAccountDialog(acc),
                  ),
                ],
              ),
            ),
          );
        },
        ),

        const SizedBox(height: 24),

        // Switch to Manual Login
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: () {
              setState(() => _showSavedAccountsView = false);
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              "Log into Another Account",
              style: TextStyle(
                color: ZevColors.deepNavy,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Create New Account Option
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RegisterScreen()),
            );
          },
          child: RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              children: [
                TextSpan(text: "Don't have an account? "),
                TextSpan(
                  text: "Sign Up",
                  style: TextStyle(
                    color: ZevColors.secondaryBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  void _showRemoveAccountDialog(SavedAccount account) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          "Remove @${account.username}?",
          style: const TextStyle(
            color: ZevColors.deepNavy,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        content: const Text(
          "You will need to enter your username and password the next time you log in.",
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Cancel",
              style: TextStyle(color: ZevColors.textMuted, fontWeight: FontWeight.w700),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await MultiAccountService.removeAccount(account.userId);
              await _loadSavedAccounts();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
  }

  /// 2. Standard Credentials & Google Login Form
  Widget _buildStandardLoginForm() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 6),

          // Floating 3D Mini Icon
          AnimatedBuilder(
            animation: _breatheController,
            builder: (context, _) {
              return Transform.translate(
                offset: Offset(0, _breatheAnim.value * 0.7),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D4FF).withValues(
                          alpha: _glowAnim.value * 0.8,
                        ),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/icon/icon-192x192.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          const Text(
            "Welcome Back",
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Sign in to continue connecting and sharing",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),

          const SizedBox(height: 26),

          // Error Banner
          if (_errorMsg != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 20,
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
            const SizedBox(height: 18),
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

          const SizedBox(height: 14),

          // Remember Me & Forgot Password Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: ZevColors.primaryBlue,
                      checkColor: ZevColors.deepNavy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      side: const BorderSide(
                        color: Color(0xFFCBD5E1),
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
                        color: Color(0xFF475569),
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

          const SizedBox(height: 26),

          // Primary Log In Button
          Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00D4FF), Color(0xFF0084FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.38),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
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
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
          ),

          if ((!kIsWeb &&
                  (defaultTargetPlatform == TargetPlatform.iOS ||
                      defaultTargetPlatform == TargetPlatform.macOS)) ||
              (_isPasskeySupported && _isPasskeyEnrolled)) ...[
            const SizedBox(height: 20),

            // Clean OR Divider
            Row(
              children: [
                const Expanded(
                  child: Divider(
                    color: Color(0xFFE2E8F0),
                    thickness: 1.2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    "OR",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Expanded(
                  child: Divider(
                    color: Color(0xFFE2E8F0),
                    thickness: 1.2,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
          ],

          // Apple Sign-In on iOS & macOS
          if (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS)) ...[
            AppleSignInButton(
              text: "Continue with Apple",
              onSuccess: _handleSocialAuthSuccess,
              onError: (msg) {
                setState(() => _errorMsg = msg);
              },
            ),
          ],

          // 1-Tap Passkey / Biometrics Button
          if (_isPasskeySupported && _isPasskeyEnrolled) ...[
            const SizedBox(height: 12),
            _buildPasskeyButton(),
          ],

          // Return to Saved Accounts Option if any exist
          if (_savedAccounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                setState(() => _showSavedAccountsView = true);
              },
              icon: const Icon(Icons.people_alt_outlined, size: 18, color: ZevColors.deepNavy),
              label: Text(
                "Switch to saved accounts (${_savedAccounts.length})",
                style: const TextStyle(
                  color: ZevColors.deepNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Sign Up Route
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterScreen()),
              );
            },
            child: RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                children: [
                  TextSpan(text: "Don't have an account? "),
                  TextSpan(
                    text: "Sign Up",
                    style: TextStyle(
                      color: ZevColors.secondaryBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _handlePasskeyLogin() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final res = await PasskeyAuthService.instance.signInWithPasskey();
      if (!res.success) {
        if (res.standing?.status == AccountStandingStatus.banned && mounted) {
          setState(() => _isLoading = false);
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => AccountStandingScreen(standing: res.standing!),
            ),
            (route) => false,
          );
          return;
        }
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMsg = res.errorMessage;
          });
        }
        return;
      }

      // Check MFA if required
      if (MfaService.instance.isMfaRequired()) {
        final factors = await MfaService.instance.getEnrolledFactors();
        if (factors.isNotEmpty && mounted) {
          final verified = await MfaChallengeSheet.show(
            context,
            factorId: factors.first.id,
            accountEmail: res.email,
          );
          if (!verified) {
            setState(() {
              _isLoading = false;
              _errorMsg = "Two-Factor Authentication cancelled.";
            });
            return;
          }
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ZevMainLayout()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Widget _buildPasskeyButton() {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00D4FF).withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D4FF).withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading ? null : _handlePasskeyLogin,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fingerprint_rounded,
                  color: ZevColors.secondaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _passkeyIdentifier != null
                    ? "Sign in with Passkey ($_passkeyIdentifier)"
                    : "Sign in with Passkey / Face ID",
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.deepNavy,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
