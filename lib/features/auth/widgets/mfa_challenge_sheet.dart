import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/mfa_service.dart';
import '../../../core/theme/zev_theme.dart';

/// Flagship Claymorphic MFA / TOTP Challenge Modal Sheet for ZEV.
/// Prompts users to enter the 6-digit verification code from Google Authenticator,
/// Microsoft Authenticator, Apple Passwords, or Authy.
class MfaChallengeSheet extends StatefulWidget {
  final String factorId;
  final String? accountEmail;

  const MfaChallengeSheet({
    super.key,
    required this.factorId,
    this.accountEmail,
  });

  static Future<bool> show(
    BuildContext context, {
    required String factorId,
    String? accountEmail,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: ZevColors.deepNavy.withValues(alpha: 0.55),
      builder: (ctx) => MfaChallengeSheet(
        factorId: factorId,
        accountEmail: accountEmail,
      ),
    );
    return result == true;
  }

  @override
  State<MfaChallengeSheet> createState() => _MfaChallengeSheetState();
}

class _MfaChallengeSheetState extends State<MfaChallengeSheet> {
  final List<TextEditingController> _digitCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _digitCtrls) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _currentCode =>
      _digitCtrls.map((c) => c.text.trim()).join();

  void _onDigitChanged(int index, String value) {
    setState(() => _errorMessage = null);

    // Handle paste of 6 digits
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < 6 && i < digits.length; i++) {
        _digitCtrls[i].text = digits[i];
      }
      if (digits.length >= 6) {
        _focusNodes[5].requestFocus();
        _verifyCode();
      } else {
        _focusNodes[digits.length.clamp(0, 5)].requestFocus();
      }
      return;
    }

    if (value.isNotEmpty) {
      HapticFeedback.selectionClick();
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        _verifyCode();
      }
    } else {
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _currentCode;
    if (code.length < 6) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      await MfaService.instance.verifyLoginCode(
        factorId: widget.factorId,
        code: code,
      );

      HapticFeedback.heavyImpact();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorMessage = "Invalid or expired Authenticator code. Please try again.";
        });
        // Clear input for retry
        for (final c in _digitCtrls) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: ZevColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Color(0x33080D1A),
              blurRadius: 36,
              offset: Offset(0, -10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Shield Icon with Gradient Glow
                Container(
                  width: 76,
                  height: 76,
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
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.security_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Title
                const Text(
                  "Two-Factor Authentication",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: ZevColors.deepNavy,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),

                // Description
                Text(
                  widget.accountEmail != null
                      ? "Enter the 6-digit code from your Authenticator app for ${widget.accountEmail}."
                      : "Enter the 6-digit code generated by your Authenticator app (Google Authenticator, Microsoft Authenticator, or Apple Passwords).",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: ZevColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 26),

                // 6-Digit PIN Boxes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (i) {
                    final hasValue = _digitCtrls[i].text.isNotEmpty;
                    return Container(
                      width: 46,
                      height: 56,
                      decoration: BoxDecoration(
                        color: hasValue ? const Color(0xFFF1F5F9) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _errorMessage != null
                              ? const Color(0xFFEF4444)
                              : hasValue
                                  ? ZevColors.primaryBlue
                                  : const Color(0xFFE2E8F0),
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
                          controller: _digitCtrls[i],
                          focusNode: _focusNodes[i],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 1,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: ZevColors.deepNavy,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            counterText: "",
                            border: InputBorder.none,
                          ),
                          onChanged: (val) => _onDigitChanged(i, val),
                        ),
                      ),
                    );
                  }),
                ),

                // Error Message
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFEF4444),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),

                // Verify Button
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
                    onPressed: _isVerifying ? null : _verifyCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isVerifying
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
                            "Verify & Continue",
                            style: TextStyle(
                              color: ZevColors.deepNavy,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // Cancel Button
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(
                      color: ZevColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
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
}

