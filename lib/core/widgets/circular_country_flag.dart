import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Circular country flag widget with vector rendering
class CircularCountryFlag extends StatelessWidget {
  final String countryCode;
  final double size;
  final bool showBorder;
  final Color borderColor;

  const CircularCountryFlag({
    super.key,
    required this.countryCode,
    this.size = 28,
    this.showBorder = true,
    this.borderColor = const Color(0x33FFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(color: borderColor, width: 1.2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          size: Size(size, size),
          painter: _FlagPainter(countryCode.toUpperCase()),
        ),
      ),
    );
  }
}

class _FlagPainter extends CustomPainter {
  final String code;

  _FlagPainter(this.code);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.fill;

    switch (code) {
      case 'GB':
      case 'UK':
        // Union Jack (United Kingdom)
        paint.color = const Color(0xFF012169); // Royal Blue
        canvas.drawRect(rect, paint);

        // White diagonal saltire
        final diagWhite = Paint()
          ..color = Colors.white
          ..strokeWidth = w * 0.22
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset.zero, Offset(w, h), diagWhite);
        canvas.drawLine(Offset(w, 0), Offset(0, h), diagWhite);

        // Red diagonal saltire
        final diagRed = Paint()
          ..color = const Color(0xFFC8102E)
          ..strokeWidth = w * 0.09
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset.zero, Offset(w, h), diagRed);
        canvas.drawLine(Offset(w, 0), Offset(0, h), diagRed);

        // White cross
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH((w - w * 0.3) / 2, 0, w * 0.3, h), paint);
        canvas.drawRect(Rect.fromLTWH(0, (h - h * 0.3) / 2, w, h * 0.3), paint);

        // Red cross
        paint.color = const Color(0xFFC8102E);
        canvas.drawRect(Rect.fromLTWH((w - w * 0.18) / 2, 0, w * 0.18, h), paint);
        canvas.drawRect(Rect.fromLTWH(0, (h - h * 0.18) / 2, w, h * 0.18), paint);
        break;

      case 'AF':
        // Afghanistan (Black, Red, Green vertical)
        paint.color = Colors.black;
        canvas.drawRect(Rect.fromLTWH(0, 0, w / 3, h), paint);
        paint.color = const Color(0xFFD32011);
        canvas.drawRect(Rect.fromLTWH(w / 3, 0, w / 3, h), paint);
        paint.color = const Color(0xFF007A3D);
        canvas.drawRect(Rect.fromLTWH((w / 3) * 2, 0, w / 3, h), paint);

        // Center white emblem
        paint.color = Colors.white.withValues(alpha: 0.9);
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = w * 0.05;
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.12, paint);
        break;

      case 'RU':
        // Russia (White, Blue, Red horizontal)
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3), paint);
        paint.color = const Color(0xFF0039A6);
        canvas.drawRect(Rect.fromLTWH(0, h / 3, w, h / 3), paint);
        paint.color = const Color(0xFFD52B1E);
        canvas.drawRect(Rect.fromLTWH(0, (h / 3) * 2, w, h / 3), paint);
        break;

      case 'TR':
        // Turkey (Red with white crescent & star)
        paint.color = const Color(0xFFE30A17);
        canvas.drawRect(rect, paint);

        // White crescent
        paint.color = Colors.white;
        canvas.drawCircle(Offset(w * 0.44, h * 0.5), w * 0.24, paint);
        paint.color = const Color(0xFFE30A17);
        canvas.drawCircle(Offset(w * 0.51, h * 0.5), w * 0.19, paint);

        // Star
        paint.color = Colors.white;
        _drawStar(canvas, Offset(w * 0.68, h * 0.5), w * 0.09, paint);
        break;

      case 'DE':
        // Germany (Black, Red, Gold horizontal)
        paint.color = const Color(0xFF000000);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3), paint);
        paint.color = const Color(0xFFFF0000);
        canvas.drawRect(Rect.fromLTWH(0, h / 3, w, h / 3), paint);
        paint.color = const Color(0xFFFFCC00);
        canvas.drawRect(Rect.fromLTWH(0, (h / 3) * 2, w, h / 3), paint);
        break;

      case 'FR':
        // France (Blue, White, Red vertical)
        paint.color = const Color(0xFF002395);
        canvas.drawRect(Rect.fromLTWH(0, 0, w / 3, h), paint);
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(w / 3, 0, w / 3, h), paint);
        paint.color = const Color(0xFFED2939);
        canvas.drawRect(Rect.fromLTWH((w / 3) * 2, 0, w / 3, h), paint);
        break;

      case 'SA':
        // Saudi Arabia (Green with white center emblem)
        paint.color = const Color(0xFF006C35);
        canvas.drawRect(rect, paint);
        paint.color = Colors.white;
        paint.strokeWidth = w * 0.06;
        paint.style = PaintingStyle.stroke;
        // Stylized sword line
        canvas.drawLine(Offset(w * 0.25, h * 0.62), Offset(w * 0.75, h * 0.62), paint);
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(Offset(w * 0.5, h * 0.42), w * 0.12, paint);
        break;

      case 'PK':
        // Pakistan (Green with white crescent and star & white vertical stripe)
        paint.color = const Color(0xFF01411C);
        canvas.drawRect(rect, paint);
        // Left white band
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.28, h), paint);
        // Crescent
        canvas.drawCircle(Offset(w * 0.62, h * 0.5), w * 0.22, paint);
        paint.color = const Color(0xFF01411C);
        canvas.drawCircle(Offset(w * 0.68, h * 0.46), w * 0.19, paint);
        // Star
        paint.color = Colors.white;
        _drawStar(canvas, Offset(w * 0.72, h * 0.42), w * 0.08, paint);
        break;

      case 'ES':
        // Spain (Red, Yellow, Red horizontal)
        paint.color = const Color(0xFFAA151B);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.25), paint);
        paint.color = const Color(0xFFF1BF00);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.25, w, h * 0.5), paint);
        paint.color = const Color(0xFFAA151B);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.75, w, h * 0.25), paint);
        // Small crest badge
        paint.color = const Color(0xFFAA151B);
        canvas.drawCircle(Offset(w * 0.35, h * 0.5), w * 0.1, paint);
        break;

      case 'CN':
        // China (Red with yellow stars)
        paint.color = const Color(0xFFDE2910);
        canvas.drawRect(rect, paint);
        paint.color = const Color(0xFFFFDE00);
        _drawStar(canvas, Offset(w * 0.32, h * 0.35), w * 0.14, paint);
        _drawStar(canvas, Offset(w * 0.52, h * 0.22), w * 0.05, paint);
        _drawStar(canvas, Offset(w * 0.60, h * 0.32), w * 0.05, paint);
        _drawStar(canvas, Offset(w * 0.60, h * 0.46), w * 0.05, paint);
        _drawStar(canvas, Offset(w * 0.52, h * 0.56), w * 0.05, paint);
        break;

      case 'IN':
        // India (Saffron, White, Green horizontal + Ashoka Chakra)
        paint.color = const Color(0xFFFF9933);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3), paint);
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(0, h / 3, w, h / 3), paint);
        paint.color = const Color(0xFF138808);
        canvas.drawRect(Rect.fromLTWH(0, (h / 3) * 2, w, h / 3), paint);
        // Chakra
        paint.color = const Color(0xFF000080);
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = w * 0.04;
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.11, paint);
        break;

      case 'IT':
        // Italy (Green, White, Red vertical)
        paint.color = const Color(0xFF009246);
        canvas.drawRect(Rect.fromLTWH(0, 0, w / 3, h), paint);
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(w / 3, 0, w / 3, h), paint);
        paint.color = const Color(0xFFCE2B37);
        canvas.drawRect(Rect.fromLTWH((w / 3) * 2, 0, w / 3, h), paint);
        break;

      case 'PT':
        // Portugal (Green 40%, Red 60% + Armillary Sphere)
        paint.color = const Color(0xFF046A38);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.4, h), paint);
        paint.color = const Color(0xFFDA291C);
        canvas.drawRect(Rect.fromLTWH(w * 0.4, 0, w * 0.6, h), paint);
        // Sphere
        paint.color = const Color(0xFFFFDD00);
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(Offset(w * 0.4, h * 0.5), w * 0.14, paint);
        paint.color = const Color(0xFFDA291C);
        canvas.drawCircle(Offset(w * 0.4, h * 0.5), w * 0.08, paint);
        break;

      case 'JP':
        // Japan (White with red sun)
        paint.color = Colors.white;
        canvas.drawRect(rect, paint);
        paint.color = const Color(0xFFBC002D);
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.28, paint);
        break;

      case 'KR':
        // South Korea (White with red/blue Taegeuk)
        paint.color = Colors.white;
        canvas.drawRect(rect, paint);
        // Red top half
        paint.color = const Color(0xFFCD2E3A);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(w / 2, h / 2), radius: w * 0.26),
          math.pi,
          math.pi,
          true,
          paint,
        );
        // Blue bottom half
        paint.color = const Color(0xFF0047A0);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(w / 2, h / 2), radius: w * 0.26),
          0,
          math.pi,
          true,
          paint,
        );
        break;

      case 'NL':
        // Netherlands (Red, White, Blue horizontal)
        paint.color = const Color(0xFFAE1C28);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3), paint);
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(0, h / 3, w, h / 3), paint);
        paint.color = const Color(0xFF21468B);
        canvas.drawRect(Rect.fromLTWH(0, (h / 3) * 2, w, h / 3), paint);
        break;

      case 'UZ':
        // Uzbekistan (Light Blue, White, Light Green with red thin borders)
        paint.color = const Color(0xFF0099B5);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.32), paint);
        paint.color = const Color(0xFFCE1126); // Red separator
        canvas.drawRect(Rect.fromLTWH(0, h * 0.32, w, h * 0.04), paint);
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(0, h * 0.36, w, h * 0.28), paint);
        paint.color = const Color(0xFFCE1126); // Red separator
        canvas.drawRect(Rect.fromLTWH(0, h * 0.64, w, h * 0.04), paint);
        paint.color = const Color(0xFF1EB53A);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.68, w, h * 0.32), paint);
        // White crescent in canton
        paint.color = Colors.white;
        canvas.drawCircle(Offset(w * 0.24, h * 0.18), w * 0.08, paint);
        paint.color = const Color(0xFF0099B5);
        canvas.drawCircle(Offset(w * 0.27, h * 0.18), w * 0.065, paint);
        break;

      case 'ID':
        // Indonesia (Red top, White bottom)
        paint.color = const Color(0xFFFF0000);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.5), paint);
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(0, h * 0.5, w, h * 0.5), paint);
        break;

      default:
        // Fallback global globe gradient
        final grad = const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF10B981)],
        ).createShader(rect);
        paint.shader = grad;
        canvas.drawCircle(Offset(w / 2, h / 2), w / 2, paint);
        paint.shader = null;
        paint.color = Colors.white;
        _drawStar(canvas, Offset(w / 2, h / 2), w * 0.2, paint);
        break;
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    const int points = 5;
    final double innerRadius = radius * 0.42;

    for (int i = 0; i < points * 2; i++) {
      final r = (i % 2 == 0) ? radius : innerRadius;
      final angle = (i * math.pi / points) - (math.pi / 2);
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FlagPainter oldDelegate) => oldDelegate.code != code;
}
