import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_helper.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_text_field.dart';
import '../../main_navigation/screens/zev_main_layout.dart';
import 'login_screen.dart';

/// Next-Generation Instagram-Grade Registration Experience for ZEV.
/// Built with 3 streamlined steps, real-time handle verification, avatar upload,
/// and official brand palette (#00D4FF, #080D1A, #F5F8FC, #E7EDF5, #536DFE).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  int _step = 1; // 1 = Identity, 2 = Handle & Social, 3 = Security
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

  @override
  void initState() {
    super.initState();
    _usernameCtrl.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
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
    setState(() => _step = (_step < 3) ? _step + 1 : 3);
  }

  void _prevStep() {
    HapticFeedback.lightImpact();
    setState(() {
      _errorMsg = null;
      _step = (_step > 1) ? _step - 1 : 1;
    });
  }

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
      // 1. Check referral code if provided
      String? validReferrerId;
      if (_refCodeCtrl.text.trim().isNotEmpty) {
        final refData = await supabase
            .from('profiles')
            .select('id')
            .eq('referral_code', _refCodeCtrl.text.trim().toUpperCase())
            .maybeSingle();

        if (refData != null) {
          validReferrerId = refData['id'];
        }
      }

      // 2. Supabase Auth SignUp
      final authResponse = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      final userId = authResponse.user?.id;
      if (userId == null) {
        throw "Failed to create user session. Please try again.";
      }

      // 3. Upload avatar if selected
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

      // 4. Upsert User Profile
      final username = _usernameCtrl.text.trim().toLowerCase();
      await supabase.from('profiles').upsert({
        'id': userId,
        'username': username,
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'date_of_birth': _dobCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'email': email,
        'avatar_url': avatarUrl,
        'bio': _bioCtrl.text.trim(),
        'role': 'student',
        'referred_by': validReferrerId,
      });

      // 5. Mark user logged in locally
      await AuthHelper.markUserLoggedIn(userId: userId, role: 'student');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
        });
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
                "Step $_step of 3",
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
                  widthFactor: _step / 3.0,
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

                              const SizedBox(height: 28),
                            ],
                          ),
                  ),
                ),
              ),
            ),

            // Bottom Footer
            if (!_isSuccess)
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
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 16,
                    color: ZevColors.deepNavy,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        const Text(
          "Personal Details",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Let's set up your profile on ZEV",
          style: TextStyle(
            fontSize: 13.5,
            color: ZevColors.textSecondary,
          ),
        ),

        const SizedBox(height: 24),

        ZevTextField(
          label: "First Name",
          hint: "e.g. Alex",
          controller: _firstNameCtrl,
          prefixIcon: Icons.badge_outlined,
          textInputAction: TextInputAction.next,
        ),

        const SizedBox(height: 16),

        ZevTextField(
          label: "Last Name",
          hint: "e.g. Morgan",
          controller: _lastNameCtrl,
          prefixIcon: Icons.badge_outlined,
          textInputAction: TextInputAction.next,
        ),

        const SizedBox(height: 16),

        ZevTextField(
          label: "Date of Birth",
          hint: "YYYY-MM-DD",
          controller: _dobCtrl,
          prefixIcon: Icons.calendar_month_outlined,
          isReadOnly: true,
          onTap: _selectDateOfBirth,
          suffixIcon: IconButton(
            icon: const Icon(
              Icons.date_range_rounded,
              color: ZevColors.primaryBlue,
            ),
            onPressed: _selectDateOfBirth,
          ),
        ),

        const SizedBox(height: 28),

        _buildNextButton(label: "Continue to Step 2", onPressed: _nextStep),
      ],
    );
  }

  // ==========================================
  // STEP 2: HANDLE & SOCIAL
  // ==========================================
  Widget _buildStep2Handle() {
    Widget? handleSuffix;
    if (_isCheckingUsername) {
      handleSuffix = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_isUsernameAvailable == true) {
      handleSuffix = const Icon(
        Icons.check_circle_rounded,
        color: Color(0xFF10B981),
        size: 20,
      );
    } else if (_isUsernameAvailable == false) {
      handleSuffix = const Icon(
        Icons.cancel_rounded,
        color: Color(0xFFDC2626),
        size: 20,
      );
    }

    return Column(
      children: [
        const Text(
          "Your ZEV Handle",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Pick your unique username and bio",
          style: TextStyle(
            fontSize: 13.5,
            color: ZevColors.textSecondary,
          ),
        ),

        const SizedBox(height: 24),

        ZevTextField(
          label: "Username",
          hint: "username",
          controller: _usernameCtrl,
          prefixIcon: Icons.alternate_email_rounded,
          suffixIcon: handleSuffix,
          textInputAction: TextInputAction.next,
        ),

        const SizedBox(height: 16),

        ZevTextField(
          label: "Bio (Optional)",
          hint: "Tell the world what you love...",
          controller: _bioCtrl,
          prefixIcon: Icons.edit_note_rounded,
          maxLines: 2,
          textInputAction: TextInputAction.next,
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
          prefixIcon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
        ),

        const SizedBox(height: 28),

        _buildNextButton(label: "Continue to Security", onPressed: _nextStep),
      ],
    );
  }

  // ==========================================
  // STEP 3: SECURITY & ACCOUNT
  // ==========================================
  Widget _buildStep3Security() {
    return Column(
      children: [
        const Text(
          "Account Security",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Set up your email and password to log in",
          style: TextStyle(
            fontSize: 13.5,
            color: ZevColors.textSecondary,
          ),
        ),

        const SizedBox(height: 24),

        ZevTextField(
          label: "Email Address",
          hint: "name@example.com",
          controller: _emailCtrl,
          prefixIcon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
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
          autofillHints: const [AutofillHints.newPassword],
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

        const SizedBox(height: 16),

        ZevTextField(
          label: "Confirm Password",
          hint: "Repeat your password",
          controller: _confirmPasswordCtrl,
          prefixIcon: Icons.lock_reset_rounded,
          isPassword: true,
          isObscured: !_showConfirmPassword,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          suffixIcon: IconButton(
            icon: Icon(
              _showConfirmPassword
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              size: 20,
              color: ZevColors.textMuted,
            ),
            onPressed: () {
              setState(() => _showConfirmPassword = !_showConfirmPassword);
            },
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
  // SUCCESS VIEW
  // ==========================================
  Widget _buildSuccessView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 32),
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
        const SizedBox(height: 24),
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
          "Your account @${_usernameCtrl.text.trim()} has been created successfully.",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14.5,
            color: ZevColors.textSecondary,
          ),
        ),
        const SizedBox(height: 36),
        Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: ZevColors.primaryBlue,
            borderRadius: BorderRadius.circular(16),
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

