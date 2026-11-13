import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/google_auth_service.dart';

/// Ultra-Crisp Official Google Sign-In Button for ZEV.
/// Conforms to official Google Brand Guidelines & ZEV claymorphic design system:
/// - Crisp Google 4-color "G" vector mark
/// - Pure White surface with crisp border and subtle ambient shadow
/// - High-contrast typography (#0F172A)
/// - Responsive loading states & haptic feedback
class GoogleSignInButton extends StatefulWidget {
  final String text;
  final VoidCallback? onSuccess;
  final ValueChanged<String>? onError;

  const GoogleSignInButton({
    super.key,
    this.text = "Continue with Google",
    this.onSuccess,
    this.onError,
  });

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _isLoading = false;

  Future<void> _handleTap() async {
    if (_isLoading) return;
    HapticFeedback.mediumImpact();

    setState(() => _isLoading = true);

    try {
      await GoogleAuthService.signInWithGoogle(
        onCancel: () {
          if (mounted) setState(() => _isLoading = false);
        },
        onError: (err) {
          if (mounted) {
            setState(() => _isLoading = false);
            widget.onError?.call(err);
          }
        },
      );
      if (mounted) {
        setState(() => _isLoading = false);
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        widget.onError?.call(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _handleTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: const Color(0xFF00D4FF).withValues(alpha: 0.12),
          highlightColor: const Color(0xFFF1F5F9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0084FF)),
                    ),
                  )
                else
                  Image.asset(
                    'assets/icon/google_logo.png',
                    width: 22,
                    height: 22,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.g_mobiledata_rounded,
                      size: 28,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                const SizedBox(width: 12),
                Text(
                  widget.text,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.2,
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

