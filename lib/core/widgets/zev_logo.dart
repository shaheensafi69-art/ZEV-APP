import 'package:flutter/material.dart';

/// Reusable ZEV Logo widget that displays the clean black & pink ZEV logo
/// with 100% transparent background (NO black box).
class ZevLogo extends StatelessWidget {
  final double height;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool showShadow;
  final bool showBorder;
  final bool useContainer;

  const ZevLogo({
    super.key,
    this.height = 36,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.borderRadius = 14,
    this.showShadow = false,
    this.showBorder = false,
    this.useContainer = false,
  });

  static const Color primaryPink = Color(0xFFFC466B);

  @override
  Widget build(BuildContext context) {
    final imageWidget = Image.asset(
      'assets/logo-clean.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Image.asset(
        'assets/logo-without-b.png',
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_rounded, color: primaryPink, size: 20),
            const SizedBox(width: 6),
            Text(
              'ZEV',
              style: TextStyle(
                color: Colors.black,
                fontSize: height * 0.55,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );

    if (!useContainer) {
      return Padding(padding: padding, child: imageWidget);
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: showBorder
            ? Border.all(color: primaryPink.withValues(alpha: 0.15), width: 1.2)
            : null,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: primaryPink.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: imageWidget,
    );
  }
}
