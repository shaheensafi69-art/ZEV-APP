import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/multi_account_service.dart';
import '../../../core/services/passkey_auth_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_text_field.dart';
import '../../main_navigation/screens/zev_main_layout.dart';
import 'login_screen.dart';

/// Next-Generation Instagram-Grade Registration Experience for ZEV.
/// Built with 4 streamlined steps:
/// 1. Identity & Avatar
/// 2. Handle & Social Profile
/// 3. Security & Credentials
/// 4. Email OTP & Activation Link Verification (with live email link listener & 6-digit PIN)
/// Plus automatic Passkey / Biometrics setup upon registration completion!
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  int _step = 1; // 1 = Identity, 2 = Handle, 3 = Security, 4 = Email OTP / Link
  bool _isLoading = false;
  bool _isSuccess = false;
  String? _errorMsg;

  // Step 1 Controllers
  File? _avatarFile;
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _dobCtrl = TextEditingController();

  // Step 2 Controllers
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _bioCtrl = TextEditingController();
  final TextEditingController _countryCtrl =
      TextEditingController(text: "United States");
  final TextEditingController _phoneCtrl = TextEditingController();
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  Timer? _usernameDebounce;

  // Step 3 Controllers
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();
  final TextEditingController _refCodeCtrl = TextEditingController();
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _agreedToTerms = true;

  // Step 4 Controllers: Email OTP & Link Verification
  String? _pendingUserId;
  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(6, (_) => FocusNode());
  bool _isVerifyingOtp = false;
  int _resendCountdown = 60;
  Timer? _resendTimer;
  StreamSubscription<AuthState>? _authListener;

  // Passkey enrollment on completion
  bool _isPasskeySupported = false;
  bool _isPasskeyEnrolling = false;
  bool _passkeyEnrolledSuccess = false;

  @override
  void initState() {
    super.initState();
    _usernameCtrl.addListener(_onUsernameChanged);
    _checkPasskeySupport();
  }

  Future<void> _checkPasskeySupport() async {
    try {
      final supported = await PasskeyAuthService.instance.isDeviceSupported();
      if (mounted) setState(() => _isPasskeySupported = supported);
    } catch (_) {}
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _resendTimer?.cancel();
    _authListener?.cancel();
    _usernameCtrl.removeListener(_onUsernameChanged);
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _dobCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _countryCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _refCodeCtrl.dispose();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onUsernameChanged() {
    final raw = _usernameCtrl.text.trim().toLowerCase();
    if (raw.isEmpty) {
      setState(() {
        _isUsernameAvailable = null;
        _isCheckingUsername = false;
      });
      return;
    }

    _usernameDebounce?.cancel();
    _usernameDebounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _isCheckingUsername = true);
      try {
        final res = await supabase
            .from('profiles')
            .select('id')
            .eq('username', raw)
            .maybeSingle();

        if (mounted) {
          setState(() {
            _isCheckingUsername = false;
            _isUsernameAvailable = (res == null);
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isCheckingUsername = false);
        }
      }
    });
  }

  Future<void> _pickAvatar() async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked != null) {
        setState(() => _avatarFile = File(picked.path));
      }
    } catch (e) {
      debugPrint("Avatar pick notice: $e");
    }
  }

  Future<void> _selectDateOfBirth() async {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1930),
      lastDate: DateTime(now.year - 12),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: ZevColors.primaryBlue,
              onPrimary: ZevColors.deepNavy,
              surface: Colors.white,
              onSurface: ZevColors.deepNavy,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final y = picked.year.toString();
      final m = picked.month.toString().padLeft(2, '0');
      final d = picked.day.toString().padLeft(2, '0');
      setState(() => _dobCtrl.text = "$y-$m-$d");
    }
  }

  void _nextStep() {
    setState(() => _errorMsg = null);

    if (_step == 1) {
      if (_firstNameCtrl.text.trim().isEmpty ||
          _lastNameCtrl.text.trim().isEmpty) {
        HapticFeedback.heavyImpact();
        setState(() => _errorMsg = "Please enter both first and last name.");
        return;
      }
      if (_dobCtrl.text.trim().isEmpty) {
        HapticFeedback.heavyImpact();
        setState(() => _errorMsg = "Please select your date of birth.");
        return;
      }
      // Auto-suggest username if blank
      if (_usernameCtrl.text.trim().isEmpty) {
        final f = _firstNameCtrl.text.trim().toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9]'),
              '',
            );
        final l = _lastNameCtrl.text.trim().toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9]'),
              '',
            );
        _usernameCtrl.text = "${f}_$l";
      }
    } else if (_step == 2) {
      final handle = _usernameCtrl.text.trim().toLowerCase();
      if (handle.length < 3) {
        HapticFeedback.heavyImpact();
        setState(() => _errorMsg = "Username must be at least 3 characters.");
        return;
      }
      if (_isUsernameAvailable == false) {
        HapticFeedback.heavyImpact();
        setState(() => _errorMsg = "This username is already taken. Please choose another.");
        return;
      }
    }

    HapticFeedback.lightImpact();
    setState(() => _step = (_step < 4) ? _step + 1 : 4);
  }

  void _prevStep() {
    HapticFeedback.lightImpact();
    setState(() {
      _errorMsg = null;
      _step = (_step > 1) ? _step - 1 : 1;
    });
  }

  /// Trigger Supabase Sign Up and transition to Step 4 (Email OTP & Link Verification)
  Future<void> _handleRegister() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;

    if (email.isEmpty || !email.contains('@')) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMsg = "Please enter a valid email address.");
      return;
    }

    if (password.length < 6) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMsg = "Password must be at least 6 characters.");
      return;
    }

    if (password != confirmPassword) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMsg = "Passwords do not match.");
      return;
    }

    if (!_agreedToTerms) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMsg = "Please agree to ZEV Terms and Privacy Policy.");
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      // 1. Supabase Auth SignUp with metadata
      final authResponse = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'username': _usernameCtrl.text.trim().toLowerCase(),
          'first_name': _firstNameCtrl.text.trim(),
          'last_name': _lastNameCtrl.text.trim(),
        },
      );

      final user = authResponse.user;
      final userId = user?.id;
      if (userId == null) {
        throw "Failed to create user session. Please try again.";
      }

      _pendingUserId = userId;

      // 2. Transition immediately to Step 4: Email OTP & Link Verification
      setState(() {
        _isLoading = false;
        _step = 4;
      });

      _startResendTimer();
      _startEmailLinkListener();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpFocusNodes[0].requestFocus();
      });
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

  // ============================================================
  // STEP 4: EMAIL OTP & ACTIVATION LINK VERIFICATION LOGIC
  // ============================================================
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

  /// Listen in real-time for when user clicks the confirmation link in their email!
  void _startEmailLinkListener() {
    _authListener?.cancel();
    _authListener = supabase.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;
      if ((event == AuthChangeEvent.signedIn || event == AuthChangeEvent.userUpdated) &&
          session != null) {
        _authListener?.cancel();
        await _completeRegistrationAndProfile(session.user.id);
      }
    });
  }

  String get _currentOtpCode => _otpCtrls.map((c) => c.text.trim()).join();

  void _onOtpDigitChanged(int index, String value) {
    setState(() => _errorMsg = null);

    // Handle paste of 6 digits
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < 6 && i < digits.length; i++) {
        _otpCtrls[i].text = digits[i];
      }
      if (digits.length >= 6) {
        _otpFocusNodes[5].requestFocus();
        _verifyOtpCode();
      } else {
        _otpFocusNodes[digits.length.clamp(0, 5)].requestFocus();
      }
      return;
    }

    if (value.isNotEmpty) {
      HapticFeedback.selectionClick();
      if (index < 5) {
        _otpFocusNodes[index + 1].requestFocus();
      } else {
        _otpFocusNodes[index].unfocus();
        _verifyOtpCode();
      }
    } else {
      if (index > 0) {
        _otpFocusNodes[index - 1].requestFocus();
      }
    }
  }

  /// Verify 6-digit OTP entered by user
  Future<void> _verifyOtpCode() async {
    final code = _currentOtpCode;
    if (code.length < 6) return;

    final email = _emailCtrl.text.trim();
    HapticFeedback.mediumImpact();
    setState(() {
      _isVerifyingOtp = true;
      _errorMsg = null;
    });

    try {
      final res = await supabase.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.signup,
      );

      final verifiedUser = res.user;
      if (verifiedUser == null) {
        throw "Could not verify code. Please check and try again.";
      }

      await _completeRegistrationAndProfile(verifiedUser.id);
    } on AuthException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isVerifyingOtp = false;
          _errorMsg = e.message;
        });
        for (final c in _otpCtrls) {
          c.clear();
        }
        _otpFocusNodes[0].requestFocus();
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isVerifyingOtp = false;
          _errorMsg = e.toString().replaceFirst('Exception: ', '');
        });
        for (final c in _otpCtrls) {
          c.clear();
        }
        _otpFocusNodes[0].requestFocus();
      }
    }
  }

  /// Resend confirmation OTP & link to user's email
  Future<void> _resendOtp() async {
    if (_resendCountdown > 0) return;

    HapticFeedback.lightImpact();
    setState(() => _errorMsg = null);

    try {
      await supabase.auth.resend(
        type: OtpType.signup,
        email: _emailCtrl.text.trim(),
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

  /// Open user's default email client
  Future<void> _openEmailApp() async {
    HapticFeedback.lightImpact();
    final mailUri = Uri.parse("mailto:");
    try {
      if (await canLaunchUrl(mailUri)) {
        await launchUrl(mailUri);
      }
    } catch (_) {}
  }

  /// Finalize Profile creation, avatar upload, local session, and MultiAccount
  Future<void> _completeRegistrationAndProfile(String userId) async {
    _authListener?.cancel();
    _resendTimer?.cancel();

    try {
      // 1. Check referral code if provided
      String? validReferrerId;
      if (_refCodeCtrl.text.trim().isNotEmpty) {
        try {
          final refData = await supabase
              .from('profiles')
              .select('id')
              .eq('referral_code', _refCodeCtrl.text.trim().toUpperCase())
              .maybeSingle();

          if (refData != null) {
            validReferrerId = refData['id'];
          }
        } catch (_) {}
      }

      // 2. Upload avatar if selected
      String avatarUrl = "";
      if (_avatarFile != null) {
        final ext = _avatarFile!.path.split('.').last;
        final fileName = 'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        try {
          avatarUrl = await CloudflareStorageService.instance.upload(
            bucket: 'avatars',
            path: fileName,
            file: _avatarFile,
          );
        } catch (uploadErr) {
          debugPrint("Avatar upload warning: $uploadErr");
        }
      }

      // 3. Upsert User Profile
      final username = _usernameCtrl.text.trim().toLowerCase();
      final firstName = _firstNameCtrl.text.trim();
      final lastName = _lastNameCtrl.text.trim();
      final email = _emailCtrl.text.trim();

      await supabase.from('profiles').upsert({
        'id': userId,
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'date_of_birth': _dobCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'email': email,
        'avatar_url': avatarUrl,
        'bio': _bioCtrl.text.trim(),
        'role': 'student',
        'referred_by': validReferrerId,
      });

      // 4. Mark user logged in locally
      await AuthHelper.markUserLoggedIn(userId: userId, role: 'student');

      // 5. Save into Instagram-style multi-account switcher
      await MultiAccountService.saveCurrentAccount(
        overrideUsername: username,
        overrideFullName: '$firstName $lastName'.trim(),
        overrideAvatar: avatarUrl,
        overrideIsVerified: false,
      );

      if (mounted) {
        setState(() {
          _isVerifyingOtp = false;
          _isSuccess = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifyingOtp = false;
          _isSuccess = true; // still let user proceed since account is verified
        });
      }
    }
  }

  /// Enroll Passkey / Biometrics on success screen
  Future<void> _enrollPasskeyFromSuccess() async {
    final userId = _pendingUserId ?? supabase.auth.currentUser?.id;
    final email = _emailCtrl.text.trim();
    if (userId == null || email.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() => _isPasskeyEnrolling = true);

    final success = await PasskeyAuthService.instance.enrollPasskey(
      email: email,
      userId: userId,
      username: _usernameCtrl.text.trim().toLowerCase(),
      passwordSecret: _passwordCtrl.text,
    );

    if (mounted) {
      setState(() {
        _isPasskeyEnrolling = false;
        _passkeyEnrolledSuccess = success;
      });
      if (success) {
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
                  "Passkey activated! You can now log in with 1 tap.",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        );
      }
    }
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
          onPressed: () {
            if (_step > 1 && !_isSuccess) {
              _prevStep();
            } else {
              Navigator.maybePop(context);
            }
          },
          tooltip: "Back",
        ),
        title: _isSuccess
            ? null
            : Text(
                "Step $_step of 4",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.secondaryBlue,
                ),
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress Bar
            if (!_isSuccess)
              Container(
                height: 3,
                width: double.infinity,
                color: ZevColors.border,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _step / 4.0,
                  child: Container(
                    color: ZevColors.primaryBlue,
                  ),
                ),
              ),

            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _isSuccess
                        ? _buildSuccessView()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 16),

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

                              if (_step == 1) _buildStep1Identity(),
                              if (_step == 2) _buildStep2Handle(),
                              if (_step == 3) _buildStep3Security(),
                              if (_step == 4) _buildStep4EmailVerification(),

                              const SizedBox(height: 28),
                            ],
                          ),
                  ),
                ),
              ),
            ),

            // Bottom Footer
            if (!_isSuccess && _step < 4)
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
                      "Already have an account? ",
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
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        "Log in",
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

  // ==========================================
  // STEP 1: IDENTITY & AVATAR
  // ==========================================
  Widget _buildStep1Identity() {
    return Column(
      children: [
        // Avatar Picker
        GestureDetector(
          onTap: _pickAvatar,
          child: Stack(
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZevColors.softSurface,
                  border: Border.all(
                    color: ZevColors.primaryBlue,
                    width: 3.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ZevColors.primaryBlue.withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _avatarFile != null
                      ? Image.file(_avatarFile!, fit: BoxFit.cover)
                      : const Center(
                          child: Icon(
                            Icons.person_rounded,
                            size: 54,
                            color: ZevColors.textMuted,
                          ),
                        ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: ZevColors.primaryBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.camera_alt_rounded,
                      size: 16,
                      color: ZevColors.deepNavy,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "Add Profile Photo",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ZevColors.secondaryBlue,
          ),
        ),

        const SizedBox(height: 28),

        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "What's your name?",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Enter the name you use in real life.",
            style: TextStyle(
              fontSize: 13.5,
              color: ZevColors.textSecondary,
            ),
          ),
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: ZevTextField(
                label: "First Name",
                hint: "First name",
                controller: _firstNameCtrl,
                prefixIcon: Icons.badge_rounded,
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ZevTextField(
                label: "Last Name",
                hint: "Last name",
                controller: _lastNameCtrl,
                prefixIcon: Icons.badge_outlined,
                textInputAction: TextInputAction.next,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        GestureDetector(
          onTap: _selectDateOfBirth,
          child: AbsorbPointer(
            child: ZevTextField(
              label: "Date of Birth",
              hint: "YYYY-MM-DD",
              controller: _dobCtrl,
              prefixIcon: Icons.cake_rounded,
              suffixIcon: const Icon(
                Icons.calendar_month_rounded,
                color: ZevColors.primaryBlue,
                size: 20,
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),

        _buildNextButton(
          label: "Continue",
          onPressed: _nextStep,
        ),
      ],
    );
  }

  // ==========================================
  // STEP 2: HANDLE & SOCIAL PROFILE
  // ==========================================
  Widget _buildStep2Handle() {
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Choose a Username",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "You can always change this later.",
            style: TextStyle(
              fontSize: 13.5,
              color: ZevColors.textSecondary,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Username Field with live availability badge
        ZevTextField(
          label: "Username",
          hint: "username",
          controller: _usernameCtrl,
          prefixIcon: Icons.alternate_email_rounded,
          textInputAction: TextInputAction.next,
          suffixIcon: _isCheckingUsername
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : (_isUsernameAvailable == null
                  ? null
                  : _isUsernameAvailable!
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF10B981),
                          size: 20,
                        )
                      : const Icon(
                          Icons.cancel_rounded,
                          color: Color(0xFFEF4444),
                          size: 20,
                        )),
        ),

        if (_isUsernameAvailable == false) ...[
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Username is already taken.",
              style: TextStyle(color: Color(0xFFEF4444), fontSize: 12),
            ),
          ),
        ],

        const SizedBox(height: 16),

        ZevTextField(
          label: "Bio (Optional)",
          hint: "Tell the ZEV community about yourself...",
          controller: _bioCtrl,
          prefixIcon: Icons.edit_note_rounded,
          maxLines: 2,
        ),

        const SizedBox(height: 16),

        ZevTextField(
          label: "Country",
          hint: "Your country",
          controller: _countryCtrl,
          prefixIcon: Icons.public_rounded,
          textInputAction: TextInputAction.next,
        ),

        const SizedBox(height: 16),

        ZevTextField(
          label: "Phone Number (Optional)",
          hint: "+1 234 567 8900",
          controller: _phoneCtrl,
          prefixIcon: Icons.phone_android_rounded,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
        ),

        const SizedBox(height: 32),

        _buildNextButton(
          label: "Continue",
          onPressed: _nextStep,
        ),
      ],
    );
  }

  // ==========================================
  // STEP 3: SECURITY & CREDENTIALS
  // ==========================================
  Widget _buildStep3Security() {
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Account Credentials",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: ZevColors.deepNavy,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Secure your account with email and password.",
            style: TextStyle(
              fontSize: 13.5,
              color: ZevColors.textSecondary,
            ),
          ),
        ),

        const SizedBox(height: 20),

        ZevTextField(
          label: "Email Address",
          hint: "name@example.com",
          controller: _emailCtrl,
          prefixIcon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),

        const SizedBox(height: 16),

        ZevTextField(
          label: "Password",
          hint: "At least 6 characters",
          controller: _passwordCtrl,
          prefixIcon: Icons.lock_outline_rounded,
          isPassword: true,
          isObscured: !_showPassword,
          textInputAction: TextInputAction.next,
          suffixIcon: IconButton(
            icon: Icon(
              _showPassword
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              size: 20,
              color: ZevColors.textMuted,
            ),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),

        const SizedBox(height: 16),

        ZevTextField(
          label: "Confirm Password",
          hint: "Re-enter your password",
          controller: _confirmPasswordCtrl,
          prefixIcon: Icons.lock_reset_rounded,
          isPassword: true,
          isObscured: !_showConfirmPassword,
          textInputAction: TextInputAction.next,
          suffixIcon: IconButton(
            icon: Icon(
              _showConfirmPassword
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              size: 20,
              color: ZevColors.textMuted,
            ),
            onPressed: () => setState(
              () => _showConfirmPassword = !_showConfirmPassword,
            ),
          ),
        ),

        const SizedBox(height: 16),

        ZevTextField(
          label: "Referral Code (Optional)",
          hint: "e.g. ZEV2026",
          controller: _refCodeCtrl,
          prefixIcon: Icons.card_giftcard_rounded,
          textInputAction: TextInputAction.done,
        ),

        const SizedBox(height: 16),

        // Terms Agreement Checkbox
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _agreedToTerms,
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
                  setState(() => _agreedToTerms = v ?? true);
                },
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "I agree to ZEV's Terms of Service and Privacy Policy.",
                style: TextStyle(
                  fontSize: 12.5,
                  color: ZevColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        _buildNextButton(
          label: "Create Account",
          isLoading: _isLoading,
          onPressed: _handleRegister,
        ),
      ],
    );
  }

  // ============================================================
  // STEP 4: EMAIL OTP & ACTIVATION LINK VERIFICATION VIEW
  // ============================================================
  Widget _buildStep4EmailVerification() {
    final email = _emailCtrl.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 10),

        // Glowing Mail & Shield Header Icon
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF00D4FF), Color(0xFF536DFE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.mark_email_read_rounded,
              color: Colors.white,
              size: 42,
            ),
          ),
        ),

        const SizedBox(height: 20),

        const Text(
          "Verify Your Email",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            "We've sent a 6-digit confirmation code and an activation link to:",
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: ZevColors.textSecondary,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 4),

        // Highlighted email badge with Edit button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.email_outlined, size: 16, color: ZevColors.secondaryBlue),
              const SizedBox(width: 6),
              Text(
                email,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: ZevColors.deepNavy,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _step = 3),
                child: const Text(
                  "Edit",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.secondaryBlue,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Explanation Pill (User decision: OTP or Link)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF0284C7), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "You can enter the 6-digit OTP code below, or simply tap the confirmation link in your email.",
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF0369A1),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 26),

        // 6-Digit OTP Boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            final hasValue = _otpCtrls[i].text.isNotEmpty;
            return Container(
              width: 46,
              height: 56,
              decoration: BoxDecoration(
                color: hasValue ? const Color(0xFFF1F5F9) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _errorMsg != null
                      ? const Color(0xFFEF4444)
                      : hasValue
                          ? ZevColors.primaryBlue
                          : const Color(0xFFCBD5E1),
                  width: hasValue ? 2.0 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: TextField(
                  controller: _otpCtrls[i],
                  focusNode: _otpFocusNodes[i],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: "",
                    border: InputBorder.none,
                  ),
                  onChanged: (val) => _onOtpDigitChanged(i, val),
                ),
              ),
            );
          }),
        ),

        const SizedBox(height: 24),

        // Verify OTP Button
        _buildNextButton(
          label: "Verify & Complete",
          isLoading: _isVerifyingOtp,
          onPressed: _verifyOtpCode,
        ),

        const SizedBox(height: 16),

        // Open Mail App Shortcut Button
        OutlinedButton.icon(
          onPressed: _openEmailApp,
          icon: const Icon(Icons.mail_outline_rounded, size: 18),
          label: const Text("Open Email App"),
          style: OutlinedButton.styleFrom(
            foregroundColor: ZevColors.deepNavy,
            side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),

        const SizedBox(height: 16),

        // Resend Timer Row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Didn't receive code? ",
              style: TextStyle(fontSize: 13, color: ZevColors.textSecondary),
            ),
            GestureDetector(
              onTap: _resendCountdown == 0 ? _resendOtp : null,
              child: Text(
                _resendCountdown > 0
                    ? "Resend in ${_resendCountdown}s"
                    : "Resend Code",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _resendCountdown > 0
                      ? const Color(0xFF94A3B8)
                      : ZevColors.secondaryBlue,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNextButton({
    required String label,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    return Container(
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
        onPressed: isLoading ? null : onPressed,
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
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    ZevColors.deepNavy,
                  ),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: ZevColors.deepNavy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }

  // ==========================================
  // SUCCESS VIEW WITH OPTIONAL PASSKEY SETUP
  // ==========================================
  Widget _buildSuccessView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF10B981),
              width: 2.5,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.check_rounded,
              color: Color(0xFF10B981),
              size: 52,
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          "Welcome to ZEV!",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Your account @${_usernameCtrl.text.trim()} is verified and ready to go.",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14.5,
            color: ZevColors.textSecondary,
          ),
        ),

        const SizedBox(height: 24),

        // Optional Passkey Enrollment Banner
        if (_isPasskeySupported && !_passkeyEnrolledSuccess) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.fingerprint_rounded,
                        color: Color(0xFF10B981),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Enable 1-Tap Passkey?",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.deepNavy,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Sign in with Face ID / Touch ID next time.",
                            style: TextStyle(
                              fontSize: 12,
                              color: ZevColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isPasskeyEnrolling ? null : _enrollPasskeyFromSuccess,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isPasskeyEnrolling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            "Activate Passkey Now",
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ] else if (_passkeyEnrolledSuccess) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF6EE7B7)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                SizedBox(width: 10),
                Text(
                  "Passkey configured for 1-Tap Login!",
                  style: TextStyle(
                    color: Color(0xFF065F46),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Final "Get Started" Navigation Button
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
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const ZevMainLayout()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              "Get Started",
              style: TextStyle(
                color: ZevColors.deepNavy,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
