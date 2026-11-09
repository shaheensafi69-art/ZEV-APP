import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/apple_auth_service.dart';

/// Ultra-Crisp Official Apple Sign-In Button for ZEV.
/// Conforms to official Apple Human Interface Guidelines:
/// - Crisp Apple silhouette vector mark
/// - Deep Obsidian background (#080D1A) with white typography
/// - Responsive claymorphic card styling & loading states
class AppleSignInButton extends StatefulWidget {
  final String text;
  final VoidCallback? onSuccess;
  final ValueChanged<String>? onError;

  const AppleSignInButton({
    super.key,
    this.text = "Continue with Apple",
    this.onSuccess,
    this.onError,
  });

  @override
  State<AppleSignInButton> createState() => _AppleSignInButtonState();
}

class _AppleSignInButtonState extends State<AppleSignInButton> {
  bool _isLoading = false;

  Future<void> _handleTap() async {
    if (_isLoading) return;
    HapticFeedback.mediumImpact();

    setState(() => _isLoading = true);

    try {
      await AppleAuthService.signInWithApple(
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
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF1E293B),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.15),
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
          splashColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.05),
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  const Icon(
                    Icons.apple_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                const SizedBox(width: 10),
                Text(
                  widget.text,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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
