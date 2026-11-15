import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/zev_call_effects.dart';

/// Real-time AR Face Filter & Morph Overlay Engine for ZEV.
/// Renders high-fidelity, physics-animated facial features, animal filters,
/// comedy morphs, and interactive props at 60 FPS.
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
      duration: const Duration(milliseconds: 1400),
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
    final cy = size.height * 0.42; // Center of head in typical camera view
    final fw = size.width * 0.65;
    final fh = size.height * 0.45;

    switch (type) {
      // ANIMALS
      case ZevFaceOverlayType.dog:
        _paintDog(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.monkey:
        _paintMonkey(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.cat:
        _paintCat(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.lion:
        _paintLion(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.panda:
        _paintPanda(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.bunny:
        _paintBunny(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.fox:
        _paintFox(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.bear:
        _paintBear(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.piggy:
        _paintPiggy(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.koala:
        _paintKoala(canvas, cx, cy, fw, fh);
        break;

      // FACE WARPS / MORPHS
      case ZevFaceOverlayType.bigNose:
        _paintBigNose(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.bigMouth:
        _paintBigMouth(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.chubbyFace:
        _paintChubbyFace(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.alien:
        _paintAlien(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.tinyFace:
        _paintTinyFace(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.fisheye:
        _paintFisheye(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.longChin:
        _paintLongChin(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.squareHead:
        _paintSquareHead(canvas, cx, cy, fw, fh);
        break;

      // PROPS & ACCESSORIES
      case ZevFaceOverlayType.crown:
        _paintCrown(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.disguise:
        _paintDisguise(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.sunglasses:
        _paintSunglasses(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.pirate:
        _paintPirate(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.angel:
        _paintAngel(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.cyberpunk:
        _paintCyberpunk(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.party:
        _paintParty(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.wizard:
        _paintWizard(canvas, cx, cy, fw, fh);
        break;
      case ZevFaceOverlayType.none:
        break;
    }
  }

  // ==========================================================
  // ANIMALS IMPLEMENTATIONS
  // ==========================================================

  void _paintDog(Canvas canvas, double cx, double cy, double fw, double fh) {
    final bounce = math.sin(progress * math.pi) * 8.0;

    final earPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF6D4C41), Color(0xFF8D6E63)],
      ).createShader(Rect.fromLTWH(cx - fw, cy - fh, fw * 2, fh * 2));

    final innerEarPaint = Paint()..color = const Color(0xFFFFCCBC);

    // Left Floppy Ear
    final leftEar = Path()
      ..moveTo(cx - fw * 0.45, cy - fh * 0.45)
      ..cubicTo(
        cx - fw * 0.72, cy - fh * 0.35 + bounce,
        cx - fw * 0.68, cy + fh * 0.20 + bounce,
        cx - fw * 0.45, cy + fh * 0.22 + bounce,
      )
      ..cubicTo(
        cx - fw * 0.35, cy + fh * 0.05,
        cx - fw * 0.32, cy - fh * 0.30,
        cx - fw * 0.45, cy - fh * 0.45,
      );
    canvas.drawPath(leftEar, earPaint);

    final leftInner = Path()
      ..moveTo(cx - fw * 0.46, cy - fh * 0.35)
      ..cubicTo(
        cx - fw * 0.64, cy - fh * 0.25 + bounce,
        cx - fw * 0.60, cy + fh * 0.12 + bounce,
        cx - fw * 0.46, cy + fh * 0.14 + bounce,
      )
      ..close();
    canvas.drawPath(leftInner, innerEarPaint);

    // Right Floppy Ear
    final rightEar = Path()
      ..moveTo(cx + fw * 0.45, cy - fh * 0.45)
      ..cubicTo(
        cx + fw * 0.72, cy - fh * 0.35 - bounce,
        cx + fw * 0.68, cy + fh * 0.20 - bounce,
        cx + fw * 0.45, cy + fh * 0.22 - bounce,
      )
      ..cubicTo(
        cx + fw * 0.35, cy + fh * 0.05,
        cx + fw * 0.32, cy - fh * 0.30,
        cx + fw * 0.45, cy - fh * 0.45,
      );
    canvas.drawPath(rightEar, earPaint);

    final rightInner = Path()
      ..moveTo(cx + fw * 0.46, cy - fh * 0.35)
      ..cubicTo(
        cx + fw * 0.64, cy - fh * 0.25 - bounce,
        cx + fw * 0.60, cy + fh * 0.12 - bounce,
        cx + fw * 0.46, cy + fh * 0.14 - bounce,
      )
      ..close();
    canvas.drawPath(rightInner, innerEarPaint);

    // Snout & Nose
    final snoutPaint = Paint()..color = const Color(0xFFD7CCC8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + fh * 0.18),
        width: fw * 0.40,
        height: fh * 0.28,
      ),
      snoutPaint,
    );

    // Black Nose
    final nosePaint = Paint()..color = const Color(0xFF212121);
    final nosePath = Path()
      ..moveTo(cx - fw * 0.08, cy + fh * 0.12)
      ..quadraticBezierTo(cx, cy + fh * 0.10, cx + fw * 0.08, cy + fh * 0.12)
      ..quadraticBezierTo(cx + fw * 0.06, cy + fh * 0.18, cx, cy + fh * 0.20)
      ..quadraticBezierTo(cx - fw * 0.06, cy + fh * 0.18, cx - fw * 0.08, cy + fh * 0.12);
    canvas.drawPath(nosePath, nosePaint);

    // Nostrils & Gloss
    canvas.drawCircle(Offset(cx - fw * 0.03, cy + fh * 0.13), 2.5, Paint()..color = Colors.white54);

    // Panting Tongue
    final tongueL = fh * (0.16 + progress * 0.06);
    final tonguePaint = Paint()..color = const Color(0xFFFF5252);
    final tonguePath = Path()
      ..moveTo(cx - fw * 0.05, cy + fh * 0.26)
      ..quadraticBezierTo(cx, cy + fh * 0.28, cx + fw * 0.05, cy + fh * 0.26)
      ..cubicTo(
        cx + fw * 0.06, cy + fh * 0.26 + tongueL,
        cx - fw * 0.06, cy + fh * 0.26 + tongueL,
        cx - fw * 0.05, cy + fh * 0.26,
      );
    canvas.drawPath(tonguePath, tonguePaint);

    // Tongue Center Crease
    final creasePaint = Paint()
      ..color = const Color(0xFFD32F2F)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx, cy + fh * 0.27),
      Offset(cx, cy + fh * 0.24 + tongueL),
      creasePaint,
    );
  }

  void _paintMonkey(Canvas canvas, double cx, double cy, double fw, double fh) {
    final wiggle = math.sin(progress * math.pi * 2) * 4.0;

    final outerPaint = Paint()..color = const Color(0xFF5D4037);
    final innerPaint = Paint()..color = const Color(0xFFFFCC80);

    // Left Big Round Ear
    canvas.drawCircle(Offset(cx - fw * 0.52 + wiggle, cy - fh * 0.15), fw * 0.18, outerPaint);
    canvas.drawCircle(Offset(cx - fw * 0.52 + wiggle, cy - fh * 0.15), fw * 0.11, innerPaint);

    // Right Big Round Ear
    canvas.drawCircle(Offset(cx + fw * 0.52 - wiggle, cy - fh * 0.15), fw * 0.18, outerPaint);
    canvas.drawCircle(Offset(cx + fw * 0.52 - wiggle, cy - fh * 0.15), fw * 0.11, innerPaint);

    // Monkey Muzzle
    final muzzlePaint = Paint()..color = const Color(0xFFFFE0B2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + fh * 0.22),
        width: fw * 0.44,
        height: fh * 0.30,
      ),
      muzzlePaint,
    );

    // Two big nostrils
    final nostrilPaint = Paint()..color = const Color(0xFF4E342E);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - fw * 0.05, cy + fh * 0.16), width: 10, height: 14),
      nostrilPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + fw * 0.05, cy + fh * 0.16), width: 10, height: 14),
      nostrilPaint,
    );

    // Big Goofy Smile
    final smilePaint = Paint()
      ..color = const Color(0xFF3E2723)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
    final smilePath = Path()
      ..moveTo(cx - fw * 0.14, cy + fh * 0.25)
      ..quadraticBezierTo(cx, cy + fh * 0.34, cx + fw * 0.14, cy + fh * 0.25);
    canvas.drawPath(smilePath, smilePaint);
  }

  void _paintCat(Canvas canvas, double cx, double cy, double fw, double fh) {
    final earTwitch = math.sin(progress * math.pi) * 6.0;

    final outerPaint = Paint()..color = const Color(0xFF37474F);
    final innerPaint = Paint()..color = const Color(0xFFF48FB1);

    // Left Pointy Cat Ear
    final leftEar = Path()
      ..moveTo(cx - fw * 0.48, cy - fh * 0.20)
      ..lineTo(cx - fw * 0.38, cy - fh * 0.56 + earTwitch)
      ..lineTo(cx - fw * 0.16, cy - fh * 0.35)
      ..close();
    canvas.drawPath(leftEar, outerPaint);

    final leftInner = Path()
      ..moveTo(cx - fw * 0.44, cy - fh * 0.22)
      ..lineTo(cx - fw * 0.37, cy - fh * 0.50 + earTwitch)
      ..lineTo(cx - fw * 0.22, cy - fh * 0.33)
      ..close();
    canvas.drawPath(leftInner, innerPaint);

    // Right Pointy Cat Ear
    final rightEar = Path()
      ..moveTo(cx + fw * 0.48, cy - fh * 0.20)
      ..lineTo(cx + fw * 0.38, cy - fh * 0.56 - earTwitch)
      ..lineTo(cx + fw * 0.16, cy - fh * 0.35)
      ..close();
    canvas.drawPath(rightEar, outerPaint);

    final rightInner = Path()
      ..moveTo(cx + fw * 0.44, cy - fh * 0.22)
      ..lineTo(cx + fw * 0.37, cy - fh * 0.50 - earTwitch)
      ..lineTo(cx + fw * 0.22, cy - fh * 0.33)
      ..close();
    canvas.drawPath(rightInner, innerPaint);

    // Pink Triangle Nose
    final nosePaint = Paint()..color = const Color(0xFFEC407A);
    final nose = Path()
      ..moveTo(cx - fw * 0.04, cy + fh * 0.13)
      ..lineTo(cx + fw * 0.04, cy + fh * 0.13)
      ..lineTo(cx, cy + fh * 0.18)
      ..close();
    canvas.drawPath(nose, nosePaint);

    // Whiskers
    final whiskerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    // Left Whiskers
    canvas.drawLine(Offset(cx - fw * 0.10, cy + fh * 0.15), Offset(cx - fw * 0.42, cy + fh * 0.10), whiskerPaint);
    canvas.drawLine(Offset(cx - fw * 0.10, cy + fh * 0.18), Offset(cx - fw * 0.45, cy + fh * 0.18), whiskerPaint);
    canvas.drawLine(Offset(cx - fw * 0.10, cy + fh * 0.21), Offset(cx - fw * 0.40, cy + fh * 0.26), whiskerPaint);

    // Right Whiskers
    canvas.drawLine(Offset(cx + fw * 0.10, cy + fh * 0.15), Offset(cx + fw * 0.42, cy + fh * 0.10), whiskerPaint);
    canvas.drawLine(Offset(cx + fw * 0.10, cy + fh * 0.18), Offset(cx + fw * 0.45, cy + fh * 0.18), whiskerPaint);
    canvas.drawLine(Offset(cx + fw * 0.10, cy + fh * 0.21), Offset(cx + fw * 0.40, cy + fh * 0.26), whiskerPaint);
  }

  void _paintLion(Canvas canvas, double cx, double cy, double fw, double fh) {
    // Magnificent Golden Mane framing face
    final manePaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFFFB300), const Color(0xFFE65100)],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: fw * 0.65));

    for (int i = 0; i < 18; i++) {
      final angle = (i * 20) * math.pi / 180;
      final rad = fw * 0.52 + math.sin(progress * 4 + i) * 6;
      final x = cx + math.cos(angle) * rad;
      final y = cy + math.sin(angle) * rad;
      canvas.drawCircle(Offset(x, y), fw * 0.14, manePaint);
    }

    // Lion Nose & Whiskers
    final lionNosePaint = Paint()..color = const Color(0xFF212121);
    final lionNose = Path()
      ..moveTo(cx - fw * 0.08, cy + fh * 0.10)
      ..lineTo(cx + fw * 0.08, cy + fh * 0.10)
      ..lineTo(cx, cy + fh * 0.19)
      ..close();
    canvas.drawPath(lionNose, lionNosePaint);
  }

  void _paintPanda(Canvas canvas, double cx, double cy, double fw, double fh) {
    final earPaint = Paint()..color = const Color(0xFF1E1E1E);
    // Left Panda Ear
    canvas.drawCircle(Offset(cx - fw * 0.38, cy - fh * 0.42), fw * 0.14, earPaint);
    // Right Panda Ear
    canvas.drawCircle(Offset(cx + fw * 0.38, cy - fh * 0.42), fw * 0.14, earPaint);

    // Dark Eye Patches
    final patchPaint = Paint()..color = const Color(0xCC212121);
    canvas.save();
    canvas.translate(cx - fw * 0.18, cy - fh * 0.02);
    canvas.rotate(-0.2);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: fw * 0.20, height: fh * 0.22), patchPaint);
    canvas.restore();

    canvas.save();
    canvas.translate(cx + fw * 0.18, cy - fh * 0.02);
    canvas.rotate(0.2);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: fw * 0.20, height: fh * 0.22), patchPaint);
    canvas.restore();

    // Round Black Panda Nose
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + fh * 0.15), width: fw * 0.15, height: fh * 0.10),
      earPaint,
    );
  }

  void _paintBunny(Canvas canvas, double cx, double cy, double fw, double fh) {
    final earHop = math.sin(progress * math.pi) * 10.0;
    final earPaint = Paint()..color = Colors.white;
    final innerPaint = Paint()..color = const Color(0xFFFF80AB);

    // Left Tall Ear
    final leftEar = Path()
      ..moveTo(cx - fw * 0.30, cy - fh * 0.35)
      ..cubicTo(
        cx - fw * 0.40, cy - fh * 0.85 + earHop,
        cx - fw * 0.10, cy - fh * 0.85 + earHop,
        cx - fw * 0.15, cy - fh * 0.35,
      );
    canvas.drawPath(leftEar, earPaint);

    final leftInner = Path()
      ..moveTo(cx - fw * 0.28, cy - fh * 0.35)
      ..cubicTo(
        cx - fw * 0.35, cy - fh * 0.78 + earHop,
        cx - fw * 0.15, cy - fh * 0.78 + earHop,
        cx - fw * 0.18, cy - fh * 0.35,
      );
    canvas.drawPath(leftInner, innerPaint);

    // Right Tall Ear
    final rightEar = Path()
      ..moveTo(cx + fw * 0.30, cy - fh * 0.35)
      ..cubicTo(
        cx + fw * 0.40, cy - fh * 0.85 - earHop,
        cx + fw * 0.10, cy - fh * 0.85 - earHop,
        cx + fw * 0.15, cy - fh * 0.35,
      );
    canvas.drawPath(rightEar, earPaint);

    final rightInner = Path()
      ..moveTo(cx + fw * 0.28, cy - fh * 0.35)
      ..cubicTo(
        cx + fw * 0.35, cy - fh * 0.78 - earHop,
        cx + fw * 0.15, cy - fh * 0.78 - earHop,
        cx + fw * 0.18, cy - fh * 0.35,
      );
    canvas.drawPath(rightInner, innerPaint);

    // Bunny Nose & Cute Teeth
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + fh * 0.14), width: fw * 0.08, height: fh * 0.06),
      innerPaint,
    );

    // White Front Teeth
    final toothPaint = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 10, cy + fh * 0.20, 20, 16),
        const Radius.circular(3),
      ),
      toothPaint,
    );
    canvas.drawLine(
      Offset(cx, cy + fh * 0.20),
      Offset(cx, cy + fh * 0.20 + 16),
      Paint()..color = Colors.black26..strokeWidth = 1.2,
    );
  }

  void _paintFox(Canvas canvas, double cx, double cy, double fw, double fh) {
    final earPaint = Paint()..color = const Color(0xFFE65100);
    final innerPaint = Paint()..color = Colors.white;

    // Left Fox Ear
    final l = Path()
      ..moveTo(cx - fw * 0.48, cy - fh * 0.20)
      ..lineTo(cx - fw * 0.34, cy - fh * 0.58)
      ..lineTo(cx - fw * 0.14, cy - fh * 0.34)
      ..close();
    canvas.drawPath(l, earPaint);
    canvas.drawPath(
      Path()
        ..moveTo(cx - fw * 0.42, cy - fh * 0.22)
        ..lineTo(cx - fw * 0.34, cy - fh * 0.50)
        ..lineTo(cx - fw * 0.20, cy - fh * 0.32)
        ..close(),
      innerPaint,
    );

    // Right Fox Ear
    final r = Path()
      ..moveTo(cx + fw * 0.48, cy - fh * 0.20)
      ..lineTo(cx + fw * 0.34, cy - fh * 0.58)
      ..lineTo(cx + fw * 0.14, cy - fh * 0.34)
      ..close();
    canvas.drawPath(r, earPaint);
    canvas.drawPath(
      Path()
        ..moveTo(cx + fw * 0.42, cy - fh * 0.22)
        ..lineTo(cx + fw * 0.34, cy - fh * 0.50)
        ..lineTo(cx + fw * 0.20, cy - fh * 0.32)
        ..close(),
      innerPaint,
    );
  }

  void _paintBear(Canvas canvas, double cx, double cy, double fw, double fh) {
    final p1 = Paint()..color = const Color(0xFF795548);
    final p2 = Paint()..color = const Color(0xFFD7CCC8);
    canvas.drawCircle(Offset(cx - fw * 0.38, cy - fh * 0.38), fw * 0.15, p1);
    canvas.drawCircle(Offset(cx - fw * 0.38, cy - fh * 0.38), fw * 0.08, p2);
    canvas.drawCircle(Offset(cx + fw * 0.38, cy - fh * 0.38), fw * 0.15, p1);
    canvas.drawCircle(Offset(cx + fw * 0.38, cy - fh * 0.38), fw * 0.08, p2);
  }

  void _paintPiggy(Canvas canvas, double cx, double cy, double fw, double fh) {
    final pink = Paint()..color = const Color(0xFFF48FB1);
    final darkPink = Paint()..color = const Color(0xFFC2185B);

    // Left & Right Floppy Pig Ears
    final l = Path()
      ..moveTo(cx - fw * 0.35, cy - fh * 0.35)
      ..lineTo(cx - fw * 0.50, cy - fh * 0.52)
      ..lineTo(cx - fw * 0.20, cy - fh * 0.42)
      ..close();
    canvas.drawPath(l, pink);

    final r = Path()
      ..moveTo(cx + fw * 0.35, cy - fh * 0.35)
      ..lineTo(cx + fw * 0.50, cy - fh * 0.52)
      ..lineTo(cx + fw * 0.20, cy - fh * 0.42)
      ..close();
    canvas.drawPath(r, pink);

    // Big Oval Pig Snout
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + fh * 0.16), width: fw * 0.32, height: fh * 0.20),
      pink,
    );
    canvas.drawCircle(Offset(cx - fw * 0.06, cy + fh * 0.16), 8, darkPink);
    canvas.drawCircle(Offset(cx + fw * 0.06, cy + fh * 0.16), 8, darkPink);
  }

  void _paintKoala(Canvas canvas, double cx, double cy, double fw, double fh) {
    final grey = Paint()..color = const Color(0xFF9E9E9E);
    final white = Paint()..color = Colors.white70;
    canvas.drawCircle(Offset(cx - fw * 0.44, cy - fh * 0.24), fw * 0.18, grey);
    canvas.drawCircle(Offset(cx - fw * 0.44, cy - fh * 0.24), fw * 0.10, white);
    canvas.drawCircle(Offset(cx + fw * 0.44, cy - fh * 0.24), fw * 0.18, grey);
    canvas.drawCircle(Offset(cx + fw * 0.44, cy - fh * 0.24), fw * 0.10, white);

    // Giant Oval Black Koala Nose
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + fh * 0.12), width: fw * 0.22, height: fh * 0.28),
      Paint()..color = const Color(0xFF212121),
    );
  }

  // ==========================================================
  // FACE WARP / MORPH IMPLEMENTATIONS
  // ==========================================================

  void _paintBigNose(Canvas canvas, double cx, double cy, double fw, double fh) {
    final scale = 1.0 + math.sin(progress * math.pi) * 0.08;
    final noseW = fw * 0.50 * scale;
    final noseH = fh * 0.38 * scale;

    // 3D Shaded Big Comic Nose with Gradient
    final nosePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.3),
        radius: 0.8,
        colors: [
          const Color(0xFFFFCCBC),
          const Color(0xFFFF8A65),
          const Color(0xFFD84315),
        ],
      ).createShader(
        Rect.fromCenter(
          center: Offset(cx, cy + fh * 0.08),
          width: noseW,
          height: noseH,
        ),
      );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + fh * 0.08),
        width: noseW,
        height: noseH,
      ),
      nosePaint,
    );

    // Giant Nostrils
    final nostrilPaint = Paint()..color = const Color(0xFF4E342E);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - noseW * 0.25, cy + fh * 0.16), width: noseW * 0.18, height: noseH * 0.22),
      nostrilPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + noseW * 0.25, cy + fh * 0.16), width: noseW * 0.18, height: noseH * 0.22),
      nostrilPaint,
    );

    // Gloss highlight
    canvas.drawCircle(Offset(cx - noseW * 0.15, cy + fh * 0.02), noseW * 0.08, Paint()..color = Colors.white70);
  }

  void _paintBigMouth(Canvas canvas, double cx, double cy, double fw, double fh) {
    final mouthW = fw * 0.70;
    final mouthH = fh * 0.40;

    // Dark Cavity
    final cavityPaint = Paint()..color = const Color(0xFF260E0E);
    final mouthRect = Rect.fromCenter(
      center: Offset(cx, cy + fh * 0.28),
      width: mouthW,
      height: mouthH,
    );
    canvas.drawOval(mouthRect, cavityPaint);

    // Big Top White Cartoon Teeth
    final toothPaint = Paint()..color = Colors.white;
    for (int i = 0; i < 7; i++) {
      final tx = (cx - mouthW * 0.35) + (i * (mouthW * 0.70 / 7));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(tx + 2, cy + fh * 0.14, mouthW * 0.08, mouthH * 0.30),
          const Radius.circular(4),
        ),
        toothPaint,
      );
    }

    // Cartoon Red Lips Border
    final lipPaint = Paint()
      ..color = const Color(0xFFD32F2F)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke;
    canvas.drawOval(mouthRect, lipPaint);
  }

  void _paintChubbyFace(Canvas canvas, double cx, double cy, double fw, double fh) {
    final puff = math.sin(progress * math.pi) * 8.0;

    // Puffy Cheek Balloons
    final cheekPaint = Paint()
      ..color = const Color(0xFFFFAB91).withValues(alpha: 0.65);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - fw * 0.40 - puff, cy + fh * 0.18),
        width: fw * 0.36,
        height: fh * 0.32,
      ),
      cheekPaint,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + fw * 0.40 + puff, cy + fh * 0.18),
        width: fw * 0.36,
        height: fh * 0.32,
      ),
      cheekPaint,
    );
  }

  void _paintAlien(Canvas canvas, double cx, double cy, double fw, double fh) {
    // Glowing Green Ambient Aura
    final auraPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: 0.25 + progress * 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: fw * 1.1, height: fh * 1.1),
      auraPaint,
    );

    // Giant Tilted Black Extraterrestrial Eyes
    final eyePaint = Paint()..color = const Color(0xFF0A0A0A);
    final reflectionPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);

    // Left Alien Eye
    canvas.save();
    canvas.translate(cx - fw * 0.24, cy - fh * 0.06);
    canvas.rotate(-0.35);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: fw * 0.28, height: fh * 0.42), eyePaint);
    canvas.drawCircle(const Offset(-10, -25), 8, reflectionPaint);
    canvas.drawCircle(const Offset(8, 15), 4, reflectionPaint);
    canvas.restore();

    // Right Alien Eye
    canvas.save();
    canvas.translate(cx + fw * 0.24, cy - fh * 0.06);
    canvas.rotate(0.35);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: fw * 0.28, height: fh * 0.42), eyePaint);
    canvas.drawCircle(const Offset(-10, -25), 8, reflectionPaint);
    canvas.drawCircle(const Offset(8, 15), 4, reflectionPaint);
    canvas.restore();
  }

  void _paintTinyFace(Canvas canvas, double cx, double cy, double fw, double fh) {
    final borderPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Circular Magnification / Pinch Frame Indicator
    canvas.drawCircle(Offset(cx, cy), fw * 0.28, borderPaint);

    // Mini comic eyes and smile
    canvas.drawCircle(Offset(cx - 20, cy - 10), 4, Paint()..color = Colors.black);
    canvas.drawCircle(Offset(cx + 20, cy - 10), 4, Paint()..color = Colors.black);
    final smile = Path()
      ..moveTo(cx - 14, cy + 12)
      ..quadraticBezierTo(cx, cy + 22, cx + 14, cy + 12);
    canvas.drawPath(smile, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2.5);
  }

  void _paintFisheye(Canvas canvas, double cx, double cy, double fw, double fh) {
    // Optical lens reflection circles
    final lensPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(Offset(cx, cy), fw * 0.60, lensPaint);
    canvas.drawCircle(Offset(cx, cy), fw * 0.45, lensPaint);

    // Specular Lens Flare Glint
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + fw * 0.35, cy - fh * 0.30), width: 34, height: 16),
      Paint()..color = Colors.white.withValues(alpha: 0.50),
    );
  }

  void _paintLongChin(Canvas canvas, double cx, double cy, double fw, double fh) {
    final chinPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFCCBC), Color(0xFFFFAB91)],
      ).createShader(Rect.fromLTWH(cx - fw * 0.25, cy + fh * 0.30, fw * 0.50, fh * 0.45));

    final chin = Path()
      ..moveTo(cx - fw * 0.25, cy + fh * 0.30)
      ..cubicTo(
        cx - fw * 0.30, cy + fh * 0.65,
        cx + fw * 0.30, cy + fh * 0.65,
        cx + fw * 0.25, cy + fh * 0.30,
      )
      ..close();
    canvas.drawPath(chin, chinPaint);
  }

  void _paintSquareHead(Canvas canvas, double cx, double cy, double fw, double fh) {
    final border = Paint()
      ..color = const Color(0xFF4CAF50)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: fw * 0.95, height: fh * 0.95),
        const Radius.circular(8),
      ),
      border,
    );
  }

  // ==========================================================
  // PROPS & ACCESSORIES IMPLEMENTATIONS
  // ==========================================================

  void _paintCrown(Canvas canvas, double cx, double cy, double fw, double fh) {
    final shimmer = math.sin(progress * math.pi) * 4.0;
    final crownY = cy - fh * 0.58 + shimmer;

    final goldPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFD700), Color(0xFFFFA000), Color(0xFFFFE082)],
      ).createShader(Rect.fromLTWH(cx - fw * 0.40, crownY, fw * 0.80, fh * 0.35));

    final crown = Path()
      ..moveTo(cx - fw * 0.38, crownY + fh * 0.25)
      ..lineTo(cx - fw * 0.40, crownY)
      ..lineTo(cx - fw * 0.18, crownY + fh * 0.12)
      ..lineTo(cx, crownY - fh * 0.08)
      ..lineTo(cx + fw * 0.18, crownY + fh * 0.12)
      ..lineTo(cx + fw * 0.40, crownY)
      ..lineTo(cx + fw * 0.38, crownY + fh * 0.25)
      ..close();
    canvas.drawPath(crown, goldPaint);

    // Jewels (Rubies and Emeralds)
    canvas.drawCircle(Offset(cx, crownY - fh * 0.06), 7, Paint()..color = const Color(0xFFE91E63));
    canvas.drawCircle(Offset(cx - fw * 0.38, crownY + 2), 6, Paint()..color = const Color(0xFF00E676));
    canvas.drawCircle(Offset(cx + fw * 0.38, crownY + 2), 6, Paint()..color = const Color(0xFF00E676));
  }

  void _paintDisguise(Canvas canvas, double cx, double cy, double fw, double fh) {
    // Glasses
    final rimPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx - fw * 0.20, cy - fh * 0.05), fw * 0.14, rimPaint);
    canvas.drawCircle(Offset(cx + fw * 0.20, cy - fh * 0.05), fw * 0.14, rimPaint);
    canvas.drawLine(Offset(cx - fw * 0.06, cy - fh * 0.05), Offset(cx + fw * 0.06, cy - fh * 0.05), rimPaint);

    // Big Fake Nose
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + fh * 0.08), width: fw * 0.25, height: fh * 0.22),
      Paint()..color = const Color(0xFFFFAB91),
    );

    // Bushy Mustache
    final stachePaint = Paint()..color = const Color(0xFF212121);
    final stache = Path()
      ..moveTo(cx, cy + fh * 0.18)
      ..cubicTo(cx - fw * 0.15, cy + fh * 0.14, cx - fw * 0.35, cy + fh * 0.28, cx - fw * 0.38, cy + fh * 0.35)
      ..cubicTo(cx - fw * 0.25, cy + fh * 0.30, cx - fw * 0.12, cy + fh * 0.26, cx, cy + fh * 0.22)
      ..cubicTo(cx + fw * 0.12, cy + fh * 0.26, cx + fw * 0.25, cy + fh * 0.30, cx + fw * 0.38, cy + fh * 0.35)
      ..cubicTo(cx + fw * 0.35, cy + fh * 0.28, cx + fw * 0.15, cy + fh * 0.14, cx, cy + fh * 0.18);
    canvas.drawPath(stache, stachePaint);
  }

  void _paintSunglasses(Canvas canvas, double cx, double cy, double fw, double fh) {
    final frame = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF212121), Color(0xFF424242)],
      ).createShader(Rect.fromLTWH(cx - fw * 0.45, cy - fh * 0.15, fw * 0.90, fh * 0.30));

    // Left Lens
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx - fw * 0.22, cy - fh * 0.05), width: fw * 0.36, height: fh * 0.22),
        const Radius.circular(12),
      ),
      frame,
    );

    // Right Lens
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + fw * 0.22, cy - fh * 0.05), width: fw * 0.36, height: fh * 0.22),
        const Radius.circular(12),
      ),
      frame,
    );

    // Bridge
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy - fh * 0.08), width: fw * 0.12, height: 6),
      Paint()..color = const Color(0xFF212121),
    );

    // Specular Highlight Glint
    final glint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 3.5;
    canvas.drawLine(Offset(cx - fw * 0.32, cy - fh * 0.12), Offset(cx - fw * 0.18, cy + fh * 0.02), glint);
    canvas.drawLine(Offset(cx + fw * 0.12, cy - fh * 0.12), Offset(cx + fw * 0.26, cy + fh * 0.02), glint);
  }

  void _paintPirate(Canvas canvas, double cx, double cy, double fw, double fh) {
    // Tricorn Pirate Hat
    final hatPaint = Paint()..color = const Color(0xFF1E1E1E);
    final hat = Path()
      ..moveTo(cx - fw * 0.55, cy - fh * 0.40)
      ..quadraticBezierTo(cx, cy - fh * 0.75, cx + fw * 0.55, cy - fh * 0.40)
      ..quadraticBezierTo(cx, cy - fh * 0.30, cx - fw * 0.55, cy - fh * 0.40);
    canvas.drawPath(hat, hatPaint);

    // Skull Icon on Hat
    canvas.drawCircle(Offset(cx, cy - fh * 0.45), 10, Paint()..color = Colors.white);

    // Pirate Eye Patch (Left eye)
    final patchPaint = Paint()..color = const Color(0xFF121212);
    canvas.drawCircle(Offset(cx - fw * 0.20, cy - fh * 0.05), fw * 0.12, patchPaint);

    // Eye Patch Strap
    final strap = Paint()
      ..color = const Color(0xFF121212)
      ..strokeWidth = 3.0;
    canvas.drawLine(Offset(cx - fw * 0.45, cy - fh * 0.20), Offset(cx + fw * 0.40, cy + fh * 0.08), strap);
  }

  void _paintAngel(Canvas canvas, double cx, double cy, double fw, double fh) {
    final float = math.sin(progress * math.pi) * 6.0;

    // Glowing Golden Halo
    final haloPaint = Paint()
      ..color = const Color(0xFFFFD54F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0;

    final glowPaint = Paint()
      ..color = const Color(0xFFFFE082).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final haloRect = Rect.fromCenter(
      center: Offset(cx, cy - fh * 0.65 + float),
      width: fw * 0.65,
      height: fh * 0.20,
    );

    canvas.drawOval(haloRect, glowPaint);
    canvas.drawOval(haloRect, haloPaint);
  }

  void _paintCyberpunk(Canvas canvas, double cx, double cy, double fw, double fh) {
    final neon = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Futuristic Cyber Visor with Scanlines
    final visorRect = Rect.fromCenter(
      center: Offset(cx, cy - fh * 0.06),
      width: fw * 0.85,
      height: fh * 0.22,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(visorRect, const Radius.circular(6)),
      Paint()..color = const Color(0xFF00E5FF).withValues(alpha: 0.25),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(visorRect, const Radius.circular(6)),
      neon,
    );

    // Target Crosshair
    canvas.drawCircle(Offset(cx + fw * 0.20, cy - fh * 0.06), 14, neon);
    canvas.drawLine(Offset(cx + fw * 0.20 - 18, cy - fh * 0.06), Offset(cx + fw * 0.20 + 18, cy - fh * 0.06), neon);
  }

  void _paintParty(Canvas canvas, double cx, double cy, double fw, double fh) {
    // Striped Party Cone Hat
    final hat = Path()
      ..moveTo(cx - fw * 0.25, cy - fh * 0.38)
      ..lineTo(cx, cy - fh * 0.80)
      ..lineTo(cx + fw * 0.25, cy - fh * 0.38)
      ..close();

    canvas.drawPath(
      hat,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFE91E63), Color(0xFFFFEB3B), Color(0xFF00E5FF)],
        ).createShader(Rect.fromLTWH(cx - fw * 0.25, cy - fh * 0.80, fw * 0.50, fh * 0.45)),
    );

    // Pompom on top
    canvas.drawCircle(Offset(cx, cy - fh * 0.80), 10, Paint()..color = const Color(0xFFFFD600));
  }

  void _paintWizard(Canvas canvas, double cx, double cy, double fw, double fh) {
    // Blue Wizard Hat
    final hat = Path()
      ..moveTo(cx - fw * 0.40, cy - fh * 0.38)
      ..quadraticBezierTo(cx, cy - fh * 0.45, cx + fw * 0.40, cy - fh * 0.38)
      ..lineTo(cx + fw * 0.12, cy - fh * 0.82)
      ..lineTo(cx - fw * 0.10, cy - fh * 0.80)
      ..close();

    canvas.drawPath(hat, Paint()..color = const Color(0xFF1A237E));

    // Golden Moon on Hat
    canvas.drawCircle(Offset(cx, cy - fh * 0.60), 12, Paint()..color = const Color(0xFFFFD54F));
  }

  @override
  bool shouldRepaint(covariant _ZevArFacePainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.progress != progress;
  }
}
