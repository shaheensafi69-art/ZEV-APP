import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/zev_call_effects.dart';

/// Renders real-time AR face filters (Puppy Dog, Monkey, Cat, Big Nose, Big Mouth, Alien, Disguise, Crown).
class ZevArFaceOverlay extends StatefulWidget {
  final ZevFaceOverlayType type;

  const ZevArFaceOverlay({
    super.key,
    required this.type,
  });

  @override
  State<ZevArFaceOverlay> createState() => _ZevArFaceOverlayState();
}

class _ZevArFaceOverlayState extends State<ZevArFaceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.type == ZevFaceOverlayType.none) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _animCtrl,
        builder: (context, _) {
          return CustomPaint(
            painter: _ZevArFacePainter(
              type: widget.type,
              progress: _animCtrl.value,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ZevArFacePainter extends CustomPainter {
  final ZevFaceOverlayType type;
  final double progress;

  _ZevArFacePainter({
    required this.type,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final cx = size.width / 2;
    final cy = size.height * 0.42; // Center of head in standard selfie view
    final faceW = size.width * 0.65;
    final faceH = size.height * 0.45;

    switch (type) {
      case ZevFaceOverlayType.dog:
        _paintDog(canvas, cx, cy, faceW, faceH);
        break;
      case ZevFaceOverlayType.monkey:
        _paintMonkey(canvas, cx, cy, faceW, faceH);
        break;
      case ZevFaceOverlayType.cat:
        _paintCat(canvas, cx, cy, faceW, faceH);
        break;
      case ZevFaceOverlayType.bigNose:
        _paintBigNose(canvas, cx, cy, faceW, faceH);
        break;
      case ZevFaceOverlayType.bigMouth:
        _paintBigMouth(canvas, cx, cy, faceW, faceH);
        break;
      case ZevFaceOverlayType.alien:
        _paintAlien(canvas, cx, cy, faceW, faceH);
        break;
      case ZevFaceOverlayType.tinyFace:
        _paintTinyFace(canvas, cx, cy, faceW, faceH);
        break;
      case ZevFaceOverlayType.disguise:
        _paintDisguise(canvas, cx, cy, faceW, faceH);
        break;
      case ZevFaceOverlayType.crown:
        _paintCrown(canvas, cx, cy, faceW, faceH);
        break;
      case ZevFaceOverlayType.sunglasses:
        _paintSunglasses(canvas, cx, cy, faceW, faceH);
        break;
      case ZevFaceOverlayType.none:
        break;
    }
  }

  // 1. Dog Filter: Floppy Animated Ears + Snout & Tongue
  void _paintDog(Canvas canvas, double cx, double cy, double fw, double fh) {
    final earBounce = math.sin(progress * math.pi) * 8.0;

    final earPaint = Paint()
      ..color = const Color(0xFF8D5B2E)
      ..style = PaintingStyle.fill;
    final innerEarPaint = Paint()
      ..color = const Color(0xFFD49A6A)
      ..style = PaintingStyle.fill;

    // Left Floppy Ear
    final leftEar = Path()
      ..moveTo(cx - fw * 0.42, cy - fh * 0.45)
      ..cubicTo(
        cx - fw * 0.70, cy - fh * 0.35 + earBounce,
        cx - fw * 0.65, cy + fh * 0.15 + earBounce,
        cx - fw * 0.45, cy + fh * 0.20 + earBounce,
      )
      ..cubicTo(
        cx - fw * 0.35, cy + fh * 0.05,
        cx - fw * 0.32, cy - fh * 0.30,
        cx - fw * 0.42, cy - fh * 0.45,
      );
    canvas.drawPath(leftEar, earPaint);

    final leftInner = Path()
      ..moveTo(cx - fw * 0.44, cy - fh * 0.35)
      ..cubicTo(
        cx - fw * 0.62, cy - fh * 0.25 + earBounce,
        cx - fw * 0.58, cy + fh * 0.10 + earBounce,
        cx - fw * 0.46, cy + fh * 0.12 + earBounce,
      )
      ..close();
    canvas.drawPath(leftInner, innerEarPaint);

    // Right Floppy Ear
    final rightEar = Path()
      ..moveTo(cx + fw * 0.42, cy - fh * 0.45)
      ..cubicTo(
        cx + fw * 0.70, cy - fh * 0.35 - earBounce,
        cx + fw * 0.65, cy + fh * 0.15 - earBounce,
        cx + fw * 0.45, cy + fh * 0.20 - earBounce,
      )
      ..cubicTo(
        cx + fw * 0.35, cy + fh * 0.05,
        cx + fw * 0.32, cy - fh * 0.30,
        cx + fw * 0.42, cy - fh * 0.45,
      );
    canvas.drawPath(rightEar, earPaint);

    final rightInner = Path()
      ..moveTo(cx + fw * 0.44, cy - fh * 0.35)
      ..cubicTo(
        cx + fw * 0.62, cy - fh * 0.25 - earBounce,
        cx + fw * 0.58, cy + fh * 0.10 - earBounce,
        cx + fw * 0.46, cy + fh * 0.12 - earBounce,
      )
      ..close();
    canvas.drawPath(rightInner, innerEarPaint);

    // Snout & Cute Doggy Nose
    final noseY = cy + fh * 0.08;
    final noseW = fw * 0.28;
    final noseH = fh * 0.18;

    final snoutPaint = Paint()
      ..color = const Color(0xFFE8D3B9).withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, noseY), width: noseW * 1.5, height: noseH * 1.4),
      snoutPaint,
    );

    final blackNosePaint = Paint()..color = const Color(0xFF1E1E1E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, noseY - 4), width: noseW * 0.75, height: noseH * 0.6),
        const Radius.circular(16),
      ),
      blackNosePaint,
    );

    // Tongue
    final tongueY = noseY + noseH * 0.8;
    final tongueBounce = math.sin(progress * math.pi * 2) * 5.0;
    final tonguePath = Path()
      ..moveTo(cx - 16, tongueY)
      ..cubicTo(
        cx - 20, tongueY + 28 + tongueBounce,
        cx + 20, tongueY + 28 + tongueBounce,
        cx + 16, tongueY,
      )
      ..close();
    final tonguePaint = Paint()..color = const Color(0xFFFF5277);
    canvas.drawPath(tonguePath, tonguePaint);

    final tongueLinePaint = Paint()
      ..color = const Color(0xFFB82645)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(cx, tongueY), Offset(cx, tongueY + 18 + tongueBounce), tongueLinePaint);
  }

  // 2. Monkey Filter: Huge Cartoon Ape Ears & Wide Monkey Smile
  void _paintMonkey(Canvas canvas, double cx, double cy, double fw, double fh) {
    final earRadius = fw * 0.28;
    final outerEar = Paint()..color = const Color(0xFF6B4226);
    final innerEar = Paint()..color = const Color(0xFFD4A373);

    // Left Monkey Ear
    canvas.drawCircle(Offset(cx - fw * 0.58, cy - fh * 0.05), earRadius, outerEar);
    canvas.drawCircle(Offset(cx - fw * 0.58, cy - fh * 0.05), earRadius * 0.65, innerEar);

    // Right Monkey Ear
    canvas.drawCircle(Offset(cx + fw * 0.58, cy - fh * 0.05), earRadius, outerEar);
    canvas.drawCircle(Offset(cx + fw * 0.58, cy - fh * 0.05), earRadius * 0.65, innerEar);

    // Muzzle & Smile
    final muzzleY = cy + fh * 0.22;
    final muzzlePaint = Paint()..color = const Color(0xFFD4A373).withValues(alpha: 0.92);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, muzzleY), width: fw * 0.70, height: fh * 0.35),
      muzzlePaint,
    );

    // Big Monkey Nostrils
    final nostrilPaint = Paint()..color = const Color(0xFF3E2723);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 16, muzzleY - 14), width: 14, height: 18), nostrilPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 16, muzzleY - 14), width: 14, height: 18), nostrilPaint);

    // Big Comical Teeth / Smile
    final smilePath = Path()
      ..moveTo(cx - fw * 0.22, muzzleY + 8)
      ..quadraticBezierTo(cx, muzzleY + 36, cx + fw * 0.22, muzzleY + 8);
    final smilePaint = Paint()
      ..color = const Color(0xFF3E2723)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawPath(smilePath, smilePaint);
  }

  // 3. Cat Filter: Cute Kitty Ears + Whiskers + Pink Snout
  void _paintCat(Canvas canvas, double cx, double cy, double fw, double fh) {
    final earPaint = Paint()..color = Colors.white;
    final innerEarPaint = Paint()..color = const Color(0xFFFF8DA1);

    // Left Ear Triangle
    final leftEar = Path()
      ..moveTo(cx - fw * 0.45, cy - fh * 0.28)
      ..lineTo(cx - fw * 0.35, cy - fh * 0.72)
      ..lineTo(cx - fw * 0.12, cy - fh * 0.40)
      ..close();
    canvas.drawPath(leftEar, earPaint);

    final leftInner = Path()
      ..moveTo(cx - fw * 0.40, cy - fh * 0.32)
      ..lineTo(cx - fw * 0.35, cy - fh * 0.64)
      ..lineTo(cx - fw * 0.18, cy - fh * 0.42)
      ..close();
    canvas.drawPath(leftInner, innerEarPaint);

    // Right Ear Triangle
    final rightEar = Path()
      ..moveTo(cx + fw * 0.45, cy - fh * 0.28)
      ..lineTo(cx + fw * 0.35, cy - fh * 0.72)
      ..lineTo(cx + fw * 0.12, cy - fh * 0.40)
      ..close();
    canvas.drawPath(rightEar, earPaint);

    final rightInner = Path()
      ..moveTo(cx + fw * 0.40, cy - fh * 0.32)
      ..lineTo(cx + fw * 0.35, cy - fh * 0.64)
      ..lineTo(cx + fw * 0.18, cy - fh * 0.42)
      ..close();
    canvas.drawPath(rightInner, innerEarPaint);

    // Pink Triangle Nose
    final noseY = cy + fh * 0.08;
    final nosePath = Path()
      ..moveTo(cx - 16, noseY - 6)
      ..lineTo(cx + 16, noseY - 6)
      ..lineTo(cx, noseY + 12)
      ..close();
    canvas.drawPath(nosePath, innerEarPaint);

    // Whiskers
    final whiskerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.90)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Left Whiskers
    canvas.drawLine(Offset(cx - 30, noseY), Offset(cx - fw * 0.50, noseY - 12), whiskerPaint);
    canvas.drawLine(Offset(cx - 30, noseY + 8), Offset(cx - fw * 0.52, noseY + 8), whiskerPaint);
    canvas.drawLine(Offset(cx - 30, noseY + 16), Offset(cx - fw * 0.48, noseY + 28), whiskerPaint);

    // Right Whiskers
    canvas.drawLine(Offset(cx + 30, noseY), Offset(cx + fw * 0.50, noseY - 12), whiskerPaint);
    canvas.drawLine(Offset(cx + 30, noseY + 8), Offset(cx + fw * 0.52, noseY + 8), whiskerPaint);
    canvas.drawLine(Offset(cx + 30, noseY + 16), Offset(cx + fw * 0.48, noseY + 28), whiskerPaint);
  }

  // 4. Big Nose: Comedic Magnified Red Cartoon Nose with Highlights
  void _paintBigNose(Canvas canvas, double cx, double cy, double fw, double fh) {
    final noseRadius = fw * 0.28 + (progress * 4.0);
    final noseCenter = Offset(cx, cy + fh * 0.08);

    // Shading aura
    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF5252).withValues(alpha: 0.75),
          const Color(0xFFD32F2F).withValues(alpha: 0.85),
          const Color(0xFFB71C1C).withValues(alpha: 0.95),
        ],
      ).createShader(Rect.fromCircle(center: noseCenter, radius: noseRadius));

    canvas.drawCircle(noseCenter, noseRadius, auraPaint);

    // Highlight reflection
    final highlightPaint = Paint()..color = Colors.white.withValues(alpha: 0.65);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(noseCenter.dx - noseRadius * 0.35, noseCenter.dy - noseRadius * 0.35),
        width: noseRadius * 0.45,
        height: noseRadius * 0.30,
      ),
      highlightPaint,
    );

    // Big Comical Nostrils
    final nostrilPaint = Paint()..color = const Color(0xFF5D0000);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(noseCenter.dx - noseRadius * 0.55, noseCenter.dy + noseRadius * 0.40), width: 22, height: 16),
      nostrilPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(noseCenter.dx + noseRadius * 0.55, noseCenter.dy + noseRadius * 0.40), width: 22, height: 16),
      nostrilPaint,
    );
  }

  // 5. Big Mouth: Giant Cartoon Smile with Big Shiny Teeth & Tongue
  void _paintBigMouth(Canvas canvas, double cx, double cy, double fw, double fh) {
    final mouthY = cy + fh * 0.32;
    final mouthW = fw * 0.85 + (progress * 10.0);
    final mouthH = fh * 0.45;

    // Dark cavity
    final cavityPath = Path()
      ..moveTo(cx - mouthW / 2, mouthY)
      ..cubicTo(
        cx - mouthW * 0.4, mouthY + mouthH,
        cx + mouthW * 0.4, mouthY + mouthH,
        cx + mouthW / 2, mouthY,
      )
      ..close();
    final cavityPaint = Paint()..color = const Color(0xFF310008);
    canvas.drawPath(cavityPath, cavityPaint);

    // Red cartoon lips
    final lipPaint = Paint()
      ..color = const Color(0xFFFF1744)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(cavityPath, lipPaint);

    // Giant teeth
    final teethPaint = Paint()..color = Colors.white;
    final teethRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - mouthW * 0.35, mouthY, mouthW * 0.70, mouthH * 0.35),
      const Radius.circular(8),
    );
    canvas.drawRRect(teethRect, teethPaint);

    // Big Pink Tongue
    final tonguePaint = Paint()..color = const Color(0xFFFF5277);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, mouthY + mouthH * 0.72), width: mouthW * 0.55, height: mouthH * 0.45),
      tonguePaint,
    );
  }

  // 6. Alien: Giant Glowing Black/Green Alien Eyes
  void _paintAlien(Canvas canvas, double cx, double cy, double fw, double fh) {
    final eyeY = cy - fh * 0.05;
    final eyeW = fw * 0.38;
    final eyeH = fh * 0.40;

    final eyePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00FF66),
          const Color(0xFF003311),
          Colors.black,
        ],
      ).createShader(Rect.fromLTWH(cx - fw * 0.45, eyeY, fw * 0.9, eyeH));

    // Left Alien Eye (Tilted)
    canvas.save();
    canvas.translate(cx - fw * 0.28, eyeY);
    canvas.rotate(-0.35);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: eyeW, height: eyeH), eyePaint);
    // Green reflection
    final glow = Paint()..color = const Color(0xFF76FF03).withValues(alpha: 0.7);
    canvas.drawCircle(Offset(-eyeW * 0.25, -eyeH * 0.25), 14, glow);
    canvas.restore();

    // Right Alien Eye (Tilted)
    canvas.save();
    canvas.translate(cx + fw * 0.28, eyeY);
    canvas.rotate(0.35);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: eyeW, height: eyeH), eyePaint);
    canvas.drawCircle(Offset(-eyeW * 0.25, -eyeH * 0.25), 14, glow);
    canvas.restore();
  }

  // 7. Tiny Face: Miniature Cartoon Frame
  void _paintTinyFace(Canvas canvas, double cx, double cy, double fw, double fh) {
    final frameRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: fw * 0.50, height: fh * 0.55),
      const Radius.circular(24),
    );
    final borderPaint = Paint()
      ..color = const Color(0xFFFFD600)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawRRect(frameRect, borderPaint);

    // Baby pacifier icon
    final pacifierY = cy + fh * 0.16;
    final pPaint = Paint()..color = const Color(0xFF00E5FF);
    canvas.drawCircle(Offset(cx, pacifierY), 16, pPaint);
    final pRing = Paint()
      ..color = const Color(0xFFFFD600)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(Offset(cx, pacifierY + 12), 12, pRing);
  }

  // 8. Disguise: Groucho Marx Bushy Eyebrows, Thick Glasses, Giant Mustache
  void _paintDisguise(Canvas canvas, double cx, double cy, double fw, double fh) {
    final glassesY = cy - fh * 0.04;
    final glassesR = fw * 0.22;

    final framePaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0;

    // Eyeglasses
    canvas.drawCircle(Offset(cx - fw * 0.25, glassesY), glassesR, framePaint);
    canvas.drawCircle(Offset(cx + fw * 0.25, glassesY), glassesR, framePaint);
    // Bridge
    canvas.drawLine(Offset(cx - fw * 0.10, glassesY), Offset(cx + fw * 0.10, glassesY), framePaint);

    // Bushy Eyebrows
    final browPaint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 14.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - fw * 0.42, glassesY - glassesR - 6), Offset(cx - fw * 0.08, glassesY - glassesR - 10), browPaint);
    canvas.drawLine(Offset(cx + fw * 0.42, glassesY - glassesR - 6), Offset(cx + fw * 0.08, glassesY - glassesR - 10), browPaint);

    // Big Curly Mustache
    final musY = cy + fh * 0.20;
    final musPaint = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.fill;
    final musPath = Path()
      ..moveTo(cx, musY)
      ..cubicTo(cx - fw * 0.35, musY - 14, cx - fw * 0.45, musY + 28, cx - fw * 0.50, musY + 12)
      ..cubicTo(cx - fw * 0.30, musY + 36, cx - fw * 0.15, musY + 22, cx, musY + 8)
      ..cubicTo(cx + fw * 0.15, musY + 22, cx + fw * 0.30, musY + 36, cx + fw * 0.50, musY + 12)
      ..cubicTo(cx + fw * 0.45, musY + 28, cx + fw * 0.35, musY - 14, cx, musY)
      ..close();
    canvas.drawPath(musPath, musPaint);
  }

  // 9. King Crown: Golden Jewel Crown with Sparkles
  void _paintCrown(Canvas canvas, double cx, double cy, double fw, double fh) {
    final crownY = cy - fh * 0.58;
    final crownW = fw * 0.70;
    final crownH = fh * 0.38;

    final crownPath = Path()
      ..moveTo(cx - crownW / 2, crownY)
      ..lineTo(cx - crownW * 0.45, crownY - crownH * 0.6)
      ..lineTo(cx - crownW * 0.22, crownY - crownH * 0.3)
      ..lineTo(cx, crownY - crownH)
      ..lineTo(cx + crownW * 0.22, crownY - crownH * 0.3)
      ..lineTo(cx + crownW * 0.45, crownY - crownH * 0.6)
      ..lineTo(cx + crownW / 2, crownY)
      ..close();

    final goldPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFEA00),
          Color(0xFFFFB300),
          Color(0xFFFF8F00),
        ],
      ).createShader(Rect.fromLTWH(cx - crownW / 2, crownY - crownH, crownW, crownH));
    canvas.drawPath(crownPath, goldPaint);

    // Crown Jewels
    final rubyPaint = Paint()..color = const Color(0xFFFF1744);
    canvas.drawCircle(Offset(cx, crownY - crownH + 6), 7, rubyPaint);
    final emeraldPaint = Paint()..color = const Color(0xFF00E676);
    canvas.drawCircle(Offset(cx - crownW * 0.45, crownY - crownH * 0.6 + 6), 5, emeraldPaint);
    canvas.drawCircle(Offset(cx + crownW * 0.45, crownY - crownH * 0.6 + 6), 5, emeraldPaint);
  }

  // 10. Sunglasses: Dark Cool Shades
  void _paintSunglasses(Canvas canvas, double cx, double cy, double fw, double fh) {
    final glassesY = cy - fh * 0.04;
    final w = fw * 0.38;
    final h = fh * 0.24;

    final glassesPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF263238),
          Color(0xFF102027),
          Colors.black,
        ],
      ).createShader(Rect.fromLTWH(cx - fw * 0.45, glassesY, fw * 0.9, h));

    // Left Lens
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx - fw * 0.24, glassesY), width: w, height: h), const Radius.circular(10)),
      glassesPaint,
    );
    // Right Lens
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx + fw * 0.24, glassesY), width: w, height: h), const Radius.circular(10)),
      glassesPaint,
    );
    // Bridge
    final bridgePaint = Paint()..color = Colors.black..strokeWidth = 6.0;
    canvas.drawLine(Offset(cx - fw * 0.08, glassesY - h * 0.25), Offset(cx + fw * 0.08, glassesY - h * 0.25), bridgePaint);
  }

  @override
  bool shouldRepaint(covariant _ZevArFacePainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.progress != progress;
  }
}
