import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/language_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isSuccess = false;
  String? _errorMessage;

  // Color palette synchronized with app theme
  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFE5E7EB);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();

      // Send request to Supabase
      await Supabase.instance.client.auth.resetPasswordForEmail(email);

      if (mounted) {
        setState(() {
          _isSuccess = true;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          // If SMTP error occurs, show clean user-friendly message
          if (e.message.contains('Error sending recovery email')) {
            _errorMessage =
                'Server email configuration error. Please contact support.';
          } else {
            _errorMessage = e.message;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0B0F19) : surfaceWhite;
    final cardBg = isDark ? const Color(0xFF131926) : surfaceWhite;
    final borderCol = isDark ? const Color(0xFF1E293B) : cardBorder;
    final primaryTextColor = isDark ? Colors.white : textDark;
    final secondaryTextColor = isDark ? Colors.white70 : textGrey;
    final inputBg = isDark
        ? const Color(0xFF1E293B)
        : cardBorder.withOpacity(0.3);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0B0F19),
                    const Color(0xFF131926),
                    const Color(0xFF0B0F19),
                  ]
                : [surfaceWhite, lightPinkBg.withOpacity(0.35), surfaceWhite],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                sliver: SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Back button
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderCol),
                            boxShadow: [
                              BoxShadow(
                                color: isDark
                                    ? Colors.black26
                                    : textDark.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: primaryTextColor,
                            size: 18,
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Main form
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(color: borderCol, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryPink.withOpacity(0.06),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: _isSuccess
                                ? _buildSuccessState(
                                    isDark,
                                    primaryTextColor,
                                    secondaryTextColor,
                                    borderCol,
                                  )
                                : _buildFormState(
                                    isDark,
                                    primaryTextColor,
                                    secondaryTextColor,
                                    borderCol,
                                    inputBg,
                                  ),
                          ),
                        ),
                      ),

                      const Spacer(flex: 2),

                      // Security footer
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.security_rounded,
                              color: primaryPink,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Secured by Safi Ecosystem',
                              style: TextStyle(
                                color: secondaryTextColor.withOpacity(0.8),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= FORM STATE =================
  Widget _buildFormState(
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color borderCol,
    Color inputBg,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : lightPinkBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primaryPink.withOpacity(0.2)),
            ),
            child: const Icon(
              Icons.vpn_key_rounded,
              color: primaryPink,
              size: 32,
            ),
          ),
          const SizedBox(height: 24),

          Text(
            context.l10n.resetPassword,
            style: TextStyle(
              color: primaryTextColor,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),

          Text(
            context.l10n.verificationLinkSent,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),

          // Email field
          Text(
            context.l10n.email.toUpperCase(),
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            cursorColor: primaryPink,
            style: TextStyle(
              color: primaryTextColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: 'student@example.com',
              hintStyle: TextStyle(color: secondaryTextColor.withOpacity(0.5)),
              prefixIcon: const Icon(
                Icons.email_outlined,
                color: primaryPink,
                size: 20,
              ),
              filled: true,
              fillColor: inputBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: borderCol),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: borderCol),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: primaryPink, width: 1.5),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty || !value.contains('@')) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),

          // Error message
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleResetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      context.l10n.sendResetLink,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= SUCCESS STATE =================
  Widget _buildSuccessState(
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color borderCol,
  ) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: const Icon(
            Icons.mark_email_read_rounded,
            color: Colors.green,
            size: 36,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          context.l10n.checkYourInbox,
          style: TextStyle(
            color: primaryTextColor,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${context.l10n.verificationLinkSent}\n${_emailController.text}',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E293B)
                : lightPinkBg.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            context.l10n.checkSpamFolder,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: primaryPink,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _isSuccess = false;
                _emailController.clear();
              });
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: borderCol, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              context.l10n.retry.toUpperCase(),
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
