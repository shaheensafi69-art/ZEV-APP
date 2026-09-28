import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/services/auth_helper.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/widgets/language_selector_sheet.dart';
import '../../../core/widgets/circular_country_flag.dart';
import '../../../core/theme/app_theme_service.dart';
import '../../main_navigation/screens/zev_main_layout.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import '../../../core/widgets/fast_cached_image.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();

  bool isLoading = false;
  bool showPassword = false;
  bool rememberMe = false;
  String? errorMsg;

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

    _floatAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.04)).animate(
          CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
        );
  }

  @override
  void dispose() {
    _floatController.dispose();
    emailCtrl.dispose();
    passwordCtrl.dispose();
    super.dispose();
  }

  // ==========================================
  // 🔒 Robust sign-in process directly to dashboard
  // ==========================================
  Future<void> _handleLogin() async {
    final email = emailCtrl.text.trim();
    final password = passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => errorMsg = "Please enter both email and password.");
      return;
    }

    setState(() {
      isLoading = true;
      errorMsg = null;
    });

    try {
      final authResponse = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = authResponse.user;

      if (user != null) {
        // Enable account credential autofill / Keychain
        TextInput.finishAutofillContext(shouldSave: true);

        // Fetch user role from profile with fallback
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
          debugPrint("Could not fetch user role during login: $roleErr");
        }

        // Save persistent sign-in state in SharedPreferences
        await AuthHelper.markUserLoggedIn(userId: user.id, role: userRole);

        // Background operations (notification & activity log)
        try {
          NotificationService().saveFCMTokenToDatabase();
        } catch (_) {}
        try {
          ActivityLogService.instance.recordLogin(user.id);
        } catch (_) {}

        if (!mounted) return;

        // Navigate directly to appropriate home screen
        Widget destination = const ZevMainLayout();

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => destination),
          (route) => false,
        );
      } else {
        setState(() {
          errorMsg = "Login failed. Please check your credentials.";
          isLoading = false;
        });
      }
    } on AuthException catch (e) {
      setState(() {
        errorMsg = e.message;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMsg =
            "Network connection failed. Please check your internet connection.";
        isLoading = false;
      });
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 24.0,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Language selector button with circular flag
                            Align(
                              alignment: Alignment.topRight,
                              child: InkWell(
                                onTap: () =>
                                    LanguageSelectorSheet.show(context),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: surfaceWhite,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: primaryPink.withOpacity(0.35),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryPink.withOpacity(0.08),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularCountryFlag(
                                        countryCode: LanguageService
                                            .instance
                                            .currentLanguage
                                            .countryCode,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        LanguageService
                                            .instance
                                            .currentLanguage
                                            .code
                                            .toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: textDark,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: textGrey,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: primaryPink.withOpacity(0.18),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryPink.withOpacity(0.14),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/logo-without-b.png',
                                height: 50,
                                errorBuilder: (context, error, stackTrace) =>
                                    Icon(
                                      Icons.chat_bubble_rounded,
                                      size: 48,
                                      color: primaryPink,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Welcome Title
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  context.l10n.welcomeBack,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: textDark,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  color: primaryPink,
                                  size: 18,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Sign in to your ZEV social account",
                              style: TextStyle(
                                color: textGrey,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Main Login Card
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: surfaceWhite,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: cardBorder,
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryPink.withOpacity(0.06),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Error Message Banner
                                  if (errorMsg != null) ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      margin: const EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withOpacity(
                                          0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.redAccent.withOpacity(
                                            0.3,
                                          ),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: Text(
                                        errorMsg!,
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 11,
                                          height: 1.4,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],

                                  // Autofill Group for Samsung Pass / Apple Keychain / Google Autofill
                                  AutofillGroup(
                                    child: Column(
                                      children: [
                                        // Email Field
                                        _buildTextField(
                                          controller: emailCtrl,
                                          label: context.l10n.emailAddress,
                                          hint: context.l10n.enterYourEmail,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          autofillHints: const [
                                            AutofillHints.email,
                                            AutofillHints.username,
                                          ],
                                        ),
                                        const SizedBox(height: 16),

                                        // Password Field
                                        _buildTextField(
                                          controller: passwordCtrl,
                                          label: context.l10n.password,
                                          hint: "••••••••",
                                          isPassword: true,
                                          keyboardType:
                                              TextInputType.visiblePassword,
                                          autofillHints: const [
                                            AutofillHints.password,
                                          ],
                                          showPassword: showPassword,
                                          onTogglePassword: () => setState(
                                            () => showPassword = !showPassword,
                                          ),
                                          extraLabel: GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const ForgotPasswordScreen(),
                                                ),
                                              );
                                            },
                                            child: Text(
                                              context.l10n.forgot,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: primaryPink,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Remember Me Checkbox Row
                                  Row(
                                    children: [
                                      SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: primaryPink,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Theme(
                                            data: ThemeData(
                                              checkboxTheme: CheckboxThemeData(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                                side: BorderSide.none,
                                              ),
                                            ),
                                            child: Checkbox(
                                              value: rememberMe,
                                              activeColor: primaryPink,
                                              checkColor: Colors.white,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              onChanged: (val) {
                                                setState(
                                                  () =>
                                                      rememberMe = val ?? false,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        context.l10n.rememberMe,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: textGrey,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // Sign In Button
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryPink,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      onPressed: isLoading
                                          ? null
                                          : _handleLogin,
                                      child: isLoading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : Text(
                                              context.l10n.signIn,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 13,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                    ),
                                  ),

                                  // Register Link
                                  const SizedBox(height: 18),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "${context.l10n.newHere} ",
                                        style: TextStyle(
                                          color: textGrey,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const RegisterScreen(),
                                          ),
                                        ),
                                        child: Text(
                                          context.l10n.createAccount,
                                          style: TextStyle(
                                            color: primaryPink,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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
                                width: 420,
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
                              text:
                                  "“Welcome back. Enter your credentials to access your global learning ecosystem.”",
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    Function(String)? onChanged,
    Widget? suffixIcon,
    bool isPassword = false,
    bool showPassword = false,
    VoidCallback? onTogglePassword,
    Widget? extraLabel,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: textGrey,
                letterSpacing: 0.8,
              ),
            ),
            ?extraLabel,
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          obscureText: isPassword && !showPassword,
          cursorColor: primaryPink,
          style: TextStyle(
            color: textDark,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: cardBorder.withValues(alpha: 0.4),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      showPassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: textGrey,
                      size: 18,
                    ),
                    onPressed: onTogglePassword,
                  )
                : suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: primaryPink, width: 1.5),
            ),
            hintText: hint,
            hintStyle: TextStyle(color: textGrey, fontSize: 12),
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
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "— Safi Ecosystem Core",
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: Color(0xFFFC466B),
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}
