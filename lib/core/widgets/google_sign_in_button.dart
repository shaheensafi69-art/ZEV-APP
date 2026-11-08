import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/google_auth_service.dart';
import '../theme/zev_theme.dart';

/// Ultra-Modern, Official Google Sign-In Button for ZEV.
/// Built with the official 4-color Google "G" vector emblem,
/// responsive claymorphic card styling, and built-in loading states.
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
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _handleTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: ZevColors.primaryBlue.withValues(alpha: 0.12),
          highlightColor: ZevColors.softSurface,
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
                      valueColor: AlwaysStoppedAnimation<Color>(ZevColors.deepNavy),
                    ),
                  )
                else
                  const GoogleLogoMark(size: 22),
                const SizedBox(width: 12),
                Text(
                  widget.text,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ZevColors.deepNavy,
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

/// Pristine Official 4-Color Google "G" Vector Mark (Red, Yellow, Green, Blue)
class GoogleLogoMark extends StatelessWidget {
  final double size;
  const GoogleLogoMark({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / 24.0;

    // 1. Blue: #4285F4 (Official Right horizontal bar and lower-right arc)
    final Paint bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final Path bluePath = Path();
    bluePath.moveTo(s * 23.745, s * 12.27);
    bluePath.cubicTo(s * 23.745, s * 11.57, s * 23.685, s * 10.87, s * 23.555, s * 10.2);
    bluePath.lineTo(s * 12.0, s * 10.2);
    bluePath.lineTo(s * 12.0, s * 14.71);
    bluePath.lineTo(s * 18.6, s * 14.71);
    bluePath.cubicTo(s * 18.31, s * 16.23, s * 17.46, s * 17.53, s * 16.2, s * 18.39);
    bluePath.lineTo(s * 16.2, s * 21.44);
    bluePath.lineTo(s * 20.08, s * 21.44);
    bluePath.cubicTo(s * 22.35, s * 19.35, s * 23.74, s * 16.27, s * 23.74, s * 12.27);
    bluePath.close();
    canvas.drawPath(bluePath, bluePaint);

    // 2. Green: #34A853 (Official Bottom arc)
    final Paint greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final Path greenPath = Path();
    greenPath.moveTo(s * 12.0, s * 24.0);
    greenPath.cubicTo(s * 15.24, s * 24.0, s * 17.95, s * 22.92, s * 19.93, s * 21.09);
    greenPath.lineTo(s * 16.05, s * 18.04);
    greenPath.cubicTo(s * 14.97, s * 18.76, s * 13.6, s * 19.2, s * 12.0, s * 19.2);
    greenPath.cubicTo(s * 8.88, s * 19.2, s * 6.23, s * 17.1, s * 5.28, s * 14.27);
    greenPath.lineTo(s * 1.25, s * 14.27);
    greenPath.lineTo(s * 1.25, s * 17.42);
    greenPath.cubicTo(s * 3.26, s * 21.36, s * 7.33, s * 24.0, s * 12.0, s * 24.0);
    greenPath.close();
    canvas.drawPath(greenPath, greenPaint);

    // 3. Yellow: #FBBC05 (Official Left arc)
    final Paint yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final Path yellowPath = Path();
    yellowPath.moveTo(s * 5.28, s * 14.27);
    yellowPath.cubicTo(s * 5.03, s * 13.55, s * 4.9, s * 12.78, s * 4.9, s * 12.0);
    yellowPath.cubicTo(s * 4.9, s * 11.22, s * 5.03, s * 10.45, s * 5.28, s * 9.73);
    yellowPath.lineTo(s * 5.28, s * 6.58);
    yellowPath.lineTo(s * 1.25, s * 6.58);
    yellowPath.cubicTo(s * 0.45, s * 8.18, s * 0.0, s * 9.99, s * 0.0, s * 12.0);
    yellowPath.cubicTo(s * 0.0, s * 14.01, s * 0.45, s * 15.82, s * 1.25, s * 17.42);
    yellowPath.lineTo(s * 5.28, s * 14.27);
    yellowPath.close();
    canvas.drawPath(yellowPath, yellowPaint);

    // 4. Red: #EA4335 (Official Top arc)
    final Paint redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final Path redPath = Path();
    redPath.moveTo(s * 12.0, s * 4.75);
    redPath.cubicTo(s * 13.77, s * 4.75, s * 15.35, s * 5.36, s * 16.6, s * 6.55);
    redPath.lineTo(s * 20.02, s * 3.13);
    redPath.cubicTo(s * 17.95, s * 1.19, s * 15.24, s * 0.0, s * 12.0, s * 0.0);
    redPath.cubicTo(s * 7.33, s * 0.0, s * 3.26, s * 2.64, s * 1.25, s * 6.58);
    redPath.lineTo(s * 5.28, s * 9.73);
    redPath.cubicTo(s * 6.23, s * 6.9, s * 8.88, s * 4.75, s * 12.0, s * 4.75);
    redPath.close();
    canvas.drawPath(redPath, redPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
