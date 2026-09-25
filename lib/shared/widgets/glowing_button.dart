import 'package:flutter/material.dart';

class GlowingButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color glowColor;
  final IconData? icon;
  final bool isLoading;
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const GlowingButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.glowColor = const Color(0xFFFC466B),
    this.icon,
    this.isLoading = false,
    this.width = double.infinity,
    this.height = 54.0,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? BorderRadius.circular(24);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: effectiveRadius,
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.45),
            blurRadius: 18,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: glowColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: effectiveRadius),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
