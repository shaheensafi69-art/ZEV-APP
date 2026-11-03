import 'package:flutter/material.dart';
import '../theme/zev_theme.dart';

/// Reusable Official ZEV Logo Widget displaying the 3D glossy icon and wordmark.
class ZevLogo extends StatelessWidget {
  final double height;
  final bool showText;
  final double spacing;
  final Color? textColor;

  const ZevLogo({
    super.key,
    this.height = 32,
    this.showText = true,
    this.spacing = 8,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(height * 0.28),
          child: Image.asset(
            'assets/icon/icon-192x192.png',
            height: height,
            width: height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              height: height,
              width: height,
              decoration: BoxDecoration(
                gradient: ZevColors.brandGradient,
                borderRadius: BorderRadius.circular(height * 0.28),
              ),
              child: Center(
                child: Text(
                  'Z',
                  style: TextStyle(
                    color: ZevColors.deepNavy,
                    fontSize: height * 0.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showText) ...[
          SizedBox(width: spacing),
          Text(
            'ZEV',
            style: TextStyle(
              color: textColor ?? ZevColors.deepNavy,
              fontSize: height * 0.65,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
