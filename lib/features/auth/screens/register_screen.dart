import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/language_service.dart';
import '../../../core/theme/app_theme_service.dart';
import '../../../core/utils/app_media_picker.dart';
import '../../../core/widgets/fast_cached_image.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  // State Management
  int step = 1;
  bool isLoading = false;
  String? errorMsg;
  bool isSuccess = false; // <--- Success state for email verification screen
  bool showPassword = false;
  bool showConfirmPassword = false;

  File? _photoFile;

  // Controllers
  final firstNameCtrl = TextEditingController();
  final lastNameCtrl = TextEditingController();
  final fatherNameCtrl = TextEditingController();
  final dobCtrl = TextEditingController();
  final countryCtrl = TextEditingController(text: 'Afghanistan');
  final languageCtrl = TextEditingController(text: 'English');
  final phoneCtrl = TextEditingController();
  final bioCtrl = TextEditingController();
  final refCodeCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final confirmPasswordCtrl = TextEditingController();

  final List<String> _selectedLearningGoals = [];
  final List<String> _availableGoals = [
    'Trading & Finance',
    'Coding & Mobile Dev',
    'Artificial Intelligence',
    'Foreign Languages',
    'Digital Marketing',
    'Design & UI/UX',
  ];

  late AnimationController _floatController;
  late Animation<Offset> _floatAnimation;

  // Color palette synchronized with app theme
  Color get primaryPink => AppThemeService.instance.current.primary;
  Color get lightPinkBg => AppThemeService.instance.current.background;
  Color get surfaceWhite => AppThemeService.instance.current.surface;
  Color get textDark => AppThemeService.instance.current.textPrimary;
  Color get textGrey => AppThemeService.instance.current.textSecondary;
  Color get cardBorder => AppThemeService.instance.current.cardBorder;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _floatAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.04),
    ).animate(CurvedAnimation(parent: _floatController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _floatController.dispose();
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    fatherNameCtrl.dispose();
    dobCtrl.dispose();
    countryCtrl.dispose();
    languageCtrl.dispose();
    phoneCtrl.dispose();
    bioCtrl.dispose();
    refCodeCtrl.dispose();
    emailCtrl.dispose();
    passwordCtrl.dispose();
    confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final file = await AppMediaPicker.instance.pickImage(imageQuality: 80);
      if (file != null) {
        setState(() {
          _photoFile = file;
        });
      }
    } catch (e) {
      setState(() => errorMsg = "Error selecting image. Please try again.");
    }
  }

  void _nextStep() {
    setState(() => errorMsg = null);
    if (step == 1) {
      if (_photoFile == null) {
        setState(() => errorMsg = "Profile photo is required.");
        return;
      }
      if (firstNameCtrl.text.trim().isEmpty ||
          lastNameCtrl.text.trim().isEmpty ||
          fatherNameCtrl.text.trim().isEmpty ||
          dobCtrl.text.trim().isEmpty) {
        setState(() => errorMsg = "Please fill in all personal details.");
        return;
      }
    } else if (step == 2) {
      if (countryCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty) {
        setState(() => errorMsg = "Country and phone number are required.");
        return;
      }
    }
    setState(() => step = (step < 3) ? step + 1 : 3);
  }

  void _prevStep() {
    setState(() {
      errorMsg = null;
      step = (step > 1) ? step - 1 : 1;
    });
  }

  Future<void> _handleRegister() async {
    setState(() {
      isLoading = true;
      errorMsg = null;
    });

    if (passwordCtrl.text != confirmPasswordCtrl.text) {
      setState(() {
        errorMsg = "Passwords do not match.";
        isLoading = false;
      });
      return;
    }

    if (passwordCtrl.text.length < 6) {
      setState(() {
        errorMsg = "Password must be at least 6 characters.";
        isLoading = false;
      });
      return;
    }

    try {
      String? validReferrerId;

      if (refCodeCtrl.text.trim().isNotEmpty) {
        final refData = await supabase
            .from('profiles')
            .select('id')
            .eq('referral_code', refCodeCtrl.text.trim().toUpperCase())
            .maybeSingle();

        if (refData == null) {
          throw "Invalid referral code. Please check or leave blank.";
        }
        validReferrerId = refData['id'];
      }

      // Sign up with Supabase
      final authResponse = await supabase.auth.signUp(
        email: emailCtrl.text.trim(),
        password: passwordCtrl.text,
      );

      final userId = authResponse.user?.id;
      if (userId == null) throw "Failed to create user auth ID.";

      String avatarUrl = "";
      if (_photoFile != null) {
        final fileExt = _photoFile!.path.split('.').last;
        final fileName = '$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        avatarUrl = await CloudflareStorageService.instance.upload(
          bucket: 'avatars',
          path: fileName,
          file: _photoFile,
        );
      }

      await supabase.from('profiles').upsert({
        'id': userId,
        'first_name': firstNameCtrl.text.trim(),
        'last_name': lastNameCtrl.text.trim(),
        'father_name': fatherNameCtrl.text.trim(),
        'date_of_birth': dobCtrl.text.trim(),
        'country': countryCtrl.text.trim(),
        'phone_number': phoneCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'avatar_url': avatarUrl,
        'bio': bioCtrl.text.trim(),
        'role': 'student',
        'referred_by': validReferrerId,
      });

      if (validReferrerId != null) {
        await supabase.from('referrals').insert({
          'referrer_id': validReferrerId,
          'referred_student_id': userId,
          'reward_amount': 5,
          'is_paid': false,
        });
      }

      // Show email verification screen instead of redirecting
      setState(() {
        isSuccess = true;
      });

    } catch (e) {
      setState(() => errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceWhite,
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 850;

          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  surfaceWhite,
                  lightPinkBg.withOpacity(0.35),
                  surfaceWhite,
                ],
              ),
            ),
            child: Row(
              children: [
                // Form Container
                Expanded(
                  flex: 1,
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Header Logo
                            if (!isSuccess) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: primaryPink.withOpacity(0.18), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: primaryPink.withOpacity(0.12),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  'assets/logo-without-b.png',
                                  height: 40,
                                  errorBuilder: (context, error, stackTrace) => Icon(
                                    Icons.chat_bubble_rounded,
                                    size: 40,
                                    color: primaryPink,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                context.l10n.createAccount,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: textDark,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Join ZEV - The Next-Gen Social Network.",
                                style: TextStyle(color: textGrey, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 18),

                              // Step Indicators
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildStepDot(1),
                                  _buildStepDot(2),
                                  _buildStepDot(3),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Card Form Container
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: surfaceWhite,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: cardBorder, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryPink.withOpacity(0.06),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: isSuccess
                                  ? _buildSuccessView()
                                  : _buildFormSteps(),
                            ),

                            if (!isSuccess) ...[
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: () => Navigator.pop(context),
                                    child: Text(
                                      context.l10n.alreadyHaveAccount,
                                      style: TextStyle(color: primaryPink, fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Right Column (Desktop Banner & Typewriter Text)
                if (isDesktop)
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [lightPinkBg.withOpacity(0.5), surfaceWhite],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: SlideTransition(
                              position: _floatAnimation,
                              child: FastCachedImage(
                                imageUrl:
                                    'https://i.ibb.co/HTZ6DPsS/original-33b8479c324a5448d6145b3cad7c51e7-removebg-preview.png',
                                width: 450,
                                fit: BoxFit.contain,
                                errorWidget: Icon(
                                  Icons.school_outlined,
                                  size: 140,
                                  color: primaryPink,
                                ),
                              ),
                            ),
                          ),
                          const Positioned(
                            bottom: 60,
                            left: 40,
                            right: 40,
                            child: TypewriterText(
                              text: "“Create an account. A new chapter awaits in global digital architecture.”",
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStepDot(int stepIndex) {
    bool isActive = step == stepIndex;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 5,
      width: isActive ? 28 : 14,
      decoration: BoxDecoration(
        color: isActive ? primaryPink : cardBorder,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  // ==========================================
  // 💎 SUCCESS / VERIFY EMAIL VIEW
  // ==========================================
  Widget _buildSuccessView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: lightPinkBg,
            shape: BoxShape.circle,
            border: Border.all(color: primaryPink.withOpacity(0.3)),
          ),
          child: Icon(Icons.mark_email_unread_rounded, color: primaryPink, size: 40),
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.verifyYourIdentity,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textDark),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.verificationLinkSent,
          style: TextStyle(color: textGrey, fontSize: 11),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cardBorder.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            emailCtrl.text.trim(),
            style: TextStyle(color: primaryPink, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: lightPinkBg.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryPink.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Text(
                context.l10n.clickLinkInEmail,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.checkSpamFolder,
                style: TextStyle(fontSize: 9, color: textGrey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryPink,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.proceedToLogin, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
          ),
        ),
      ],
    );
  }

  Widget _buildFormSteps() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (errorMsg != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1.5),
            ),
            child: Text(errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
          )
        ],

        if (step == 1) ...[
          // Step 1: Avatar & Personal Info
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: lightPinkBg,
                    backgroundImage: _photoFile != null ? FileImage(_photoFile!) : null,
                    child: _photoFile == null ? Icon(Icons.camera_alt_rounded, color: primaryPink, size: 26) : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: primaryPink, shape: BoxShape.circle),
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 14),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildTextField("FIRST NAME *", firstNameCtrl, "John")),
              const SizedBox(width: 8),
              Expanded(child: _buildTextField("LAST NAME *", lastNameCtrl, "Doe")),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildTextField("FATHER'S NAME *", fatherNameCtrl, "Michael")),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime(2000),
                      firstDate: DateTime(1950),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            textTheme: Theme.of(context).textTheme.copyWith(
                              bodyLarge: TextStyle(color: textDark),
                              bodyMedium: TextStyle(color: textDark),
                            ),
                            colorScheme: ColorScheme.light(
                              primary: primaryPink,
                              onPrimary: Colors.white,
                              surface: surfaceWhite,
                              onSurface: textDark,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() => dobCtrl.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}");
                    }
                  },
                  child: AbsorbPointer(child: _buildTextField("DATE OF BIRTH *", dobCtrl, "YYYY-MM-DD")),
                ),
              ),
            ],
          ),
        ] else if (step == 2) ...[
          // Step 2: Location, Language & Goals
          Row(
            children: [
              Expanded(child: _buildTextField("COUNTRY *", countryCtrl, "Afghanistan")),
              const SizedBox(width: 8),
              Expanded(child: _buildTextField("PHONE *", phoneCtrl, "+93...", isPhone: true)),
            ],
          ),
          const SizedBox(height: 10),
          _buildTextField("PREFERRED LANGUAGE *", languageCtrl, "English / Dari / Pashto"),
          const SizedBox(height: 10),

          // Learning Goals Chips
          Text("LEARNING GOALS", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: textGrey, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _availableGoals.map((goal) {
              final isSelected = _selectedLearningGoals.contains(goal);
              return ChoiceChip(
                label: Text(goal, style: TextStyle(fontSize: 10, color: isSelected ? Colors.white : textDark, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                selected: isSelected,
                selectedColor: primaryPink,
                backgroundColor: cardBorder.withOpacity(0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedLearningGoals.add(goal);
                    } else {
                      _selectedLearningGoals.remove(goal);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          _buildTextField("BIOGRAPHY", bioCtrl, "Brief background...", maxLines: 2),
          const SizedBox(height: 10),
          _buildTextField("REFERRAL CODE (OPTIONAL)", refCodeCtrl, "e.g. SAFI-X"),
        ] else if (step == 3) ...[
          // Step 3: Account Security
          _buildTextField("EMAIL ADDRESS *", emailCtrl, "name@example.com"),
          const SizedBox(height: 10),
          _buildTextField("PASSWORD *", passwordCtrl, "••••••••", isPassword: true, showObscure: showPassword, onToggleObscure: () => setState(() => showPassword = !showPassword)),
          const SizedBox(height: 10),
          _buildTextField("CONFIRM PASSWORD *", confirmPasswordCtrl, "••••••••", isPassword: true, showObscure: showConfirmPassword, onToggleObscure: () => setState(() => showConfirmPassword = !showConfirmPassword)),
        ],

        const SizedBox(height: 18),
        Row(
          children: [
            if (step > 1)
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cardBorder,
                      foregroundColor: textDark,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: cardBorder, width: 1.5),
                    ),
                    onPressed: _prevStep,
                    child: Text(context.l10n.back.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                ),
              ),
            if (step > 1) const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: isLoading ? null : (step < 3 ? _nextStep : _handleRegister),
                  child: isLoading
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text(step < 3 ? context.l10n.nextStep : context.l10n.completeRegistration, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
                ),
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint, {
    bool isPassword = false,
    bool? showObscure,
    VoidCallback? onToggleObscure,
    int maxLines = 1,
    bool isPhone = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: textGrey, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          obscureText: isPassword && !(showObscure ?? false),
          maxLines: maxLines,
          cursorColor: primaryPink,
          keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
          style: TextStyle(color: textDark, fontSize: 11, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true,
            fillColor: cardBorder.withOpacity(0.4),
            contentPadding: maxLines > 1 ? const EdgeInsets.all(10) : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon((showObscure ?? false) ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: textGrey, size: 16),
                    onPressed: onToggleObscure,
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cardBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cardBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primaryPink, width: 1.5)),
            hintText: hint,
            hintStyle: TextStyle(color: textGrey, fontSize: 10),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// Typewriter Text Effect Widget
// ==========================================
class TypewriterText extends StatefulWidget {
  final String text;
  const TypewriterText({super.key, required this.text});

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String displayedText = "";
  int charIndex = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (charIndex < widget.text.length) {
        if (mounted) {
          setState(() {
            displayedText += widget.text[charIndex];
            charIndex++;
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          displayedText,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF111827), fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 8),
        const Text("— Safi Ecosystem Core", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFFC466B), letterSpacing: 2)),
      ],
    );
  }
}