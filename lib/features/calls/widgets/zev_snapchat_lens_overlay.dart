import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Next-Generation Interactive Snapchat AR Lens Overlay for ZEV Calls.
/// Emulates official Snapchat Creative Library lenses (Dog, Monkey, Big Mouth,
/// Anime, Cyberpunk, Animals, Funny Distortions, VHS) with smooth continuous
/// physics micro-animations and zero hardware overhead across Android, iOS, and Web.
class ZevSnapchatLensOverlay extends StatefulWidget {
  final String lensType;
  final bool isSmall; // True when rendering inside a small PIP window

  const ZevSnapchatLensOverlay({
    super.key,
    required this.lensType,
    this.isSmall = false,
  });

  @override
  State<ZevSnapchatLensOverlay> createState() => _ZevSnapchatLensOverlayState();
}

class _ZevSnapchatLensOverlayState extends State<ZevSnapchatLensOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lensType == 'none' || widget.lensType.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        final progress = _animCtrl.value; // 0.0 to 1.0
        final wave = math.sin(progress * math.pi);
        final scale = widget.isSmall ? 0.45 : 1.0;

        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // 1. Classic Dog Lens (Ears + Nose + Tongue)
              if (widget.lensType == 'dog') ...[
                _buildDogEars(wave, scale),
                _buildDogNose(wave, scale),
                _buildDogTongue(wave, scale),
              ],

              // 2. Monkey & Ape Face Lens (Big Rounded Ears + Snout)
              if (widget.lensType == 'monkey') ...[
                _buildMonkeyEars(wave, scale),
                _buildMonkeyMuzzle(wave, scale),
              ],

              // 3. Big Mouth & Googly Eyes Lens
              if (widget.lensType == 'big_mouth') ...[
                _buildGooglyEyes(wave, scale),
                _buildBigMouth(wave, scale),
              ],

              // 4. Giant Nose & Shrunken Caricature Lens
              if (widget.lensType == 'giant_nose') ...[
                _buildGiantNose(wave, scale),
              ],

              // 5. Anime & Manga Face Lens
              if (widget.lensType == 'anime') ...[
                _buildAnimeStars(wave, scale),
                _buildAnimeBlush(scale),
              ],

              // 6. Cyberpunk Neon HUD Visor Lens
              if (widget.lensType == 'cyberpunk') ...[
                _buildCyberpunkVisor(wave, scale),
              ],

              // 7. Playful Cat / Kitty Whiskers Lens
              if (widget.lensType == 'cat') ...[
                _buildCatEars(wave, scale),
                _buildCatWhiskers(scale),
              ],

              // 8. Alien Extraterrestrial Lens
              if (widget.lensType == 'alien') ...[
                _buildAlienAntennae(wave, scale),
                _buildAlienAura(wave),
              ],

              // 9. Dramatic Comedy Crying Lens
              if (widget.lensType == 'crying') ...[
                _buildCryingStreams(wave, scale),
              ],

              // 10. Neon Devil Horns & Angel Halo
              if (widget.lensType == 'devil_angel') ...[
                _buildDevilHorns(wave, scale),
              ],

              // 11. Fluffy Bunny Rabbit Lens
              if (widget.lensType == 'bunny') ...[
                _buildBunnyEars(wave, scale),
                _buildBunnyNose(scale),
              ],

              // 12. Teddy Panda Bear Lens
              if (widget.lensType == 'panda') ...[
                _buildPandaEars(scale),
              ],

              // 13. Bambi Fawn Deer Lens
              if (widget.lensType == 'deer') ...[
                _buildDeerAntlers(wave, scale),
              ],

              // 14. Retro VHS 90s Camcorder OSD
              if (widget.lensType == 'vhs') ...[
                _buildVhsOverlay(wave),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- Lens Subcomponents ---

  // 1. Dog Lens
  Widget _buildDogEars(double wave, double scale) {
    return Positioned(
      top: 50 * scale,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Transform.rotate(
            angle: -0.15 + (wave * 0.08),
            child: Container(
              width: 80 * scale,
              height: 120 * scale,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5A2B),
                borderRadius: BorderRadius.circular(40 * scale),
                border: Border.all(color: const Color(0xFF5C3A1E), width: 3 * scale),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10 * scale,
                  ),
                ],
              ),
            ),
          ),
          Transform.rotate(
            angle: 0.15 - (wave * 0.08),
            child: Container(
              width: 80 * scale,
              height: 120 * scale,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5A2B),
                borderRadius: BorderRadius.circular(40 * scale),
                border: Border.all(color: const Color(0xFF5C3A1E), width: 3 * scale),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10 * scale,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDogNose(double wave, double scale) {
    return Positioned(
      top: 240 * scale,
      child: Container(
        width: 50 * scale,
        height: 38 * scale,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20 * scale),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 6 * scale,
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 14 * scale,
            height: 6 * scale,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(3 * scale),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDogTongue(double wave, double scale) {
    final tongueStretch = 1.0 + (wave * 0.35);
    return Positioned(
      top: 295 * scale,
      child: Transform.scale(
        scaleY: tongueStretch,
        child: Container(
          width: 44 * scale,
          height: 60 * scale,
          decoration: BoxDecoration(
            color: const Color(0xFFFF69B4),
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(26 * scale),
            ),
            border: Border.all(color: const Color(0xFFC71585), width: 2 * scale),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF1493).withValues(alpha: 0.4),
                blurRadius: 8 * scale,
              ),
            ],
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: 3 * scale,
              height: 40 * scale,
              color: const Color(0xFFC71585),
            ),
          ),
        ),
      ),
    );
  }

  // 2. Monkey Lens
  Widget _buildMonkeyEars(double wave, double scale) {
    return Positioned(
      top: 130 * scale,
      left: 10 * scale,
      right: 10 * scale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSingleMonkeyEar(scale, isLeft: true),
          _buildSingleMonkeyEar(scale, isLeft: false),
        ],
      ),
    );
  }

  Widget _buildSingleMonkeyEar(double scale, {required bool isLeft}) {
    return Container(
      width: 75 * scale,
      height: 75 * scale,
      decoration: BoxDecoration(
        color: const Color(0xFF795548),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF4E342E), width: 3 * scale),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10 * scale,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 45 * scale,
          height: 45 * scale,
          decoration: const BoxDecoration(
            color: Color(0xFFFFCCBC),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildMonkeyMuzzle(double wave, double scale) {
    return Positioned(
      top: 250 * scale,
      child: Container(
        width: 140 * scale,
        height: 90 * scale,
        decoration: BoxDecoration(
          color: const Color(0xFFFFCCBC),
          borderRadius: BorderRadius.circular(45 * scale),
          border: Border.all(color: const Color(0xFF795548), width: 2.5 * scale),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8 * scale,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10 * scale,
                  height: 12 * scale,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4E342E),
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 18 * scale),
                Container(
                  width: 10 * scale,
                  height: 12 * scale,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4E342E),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8 * scale),
            Container(
              width: 50 * scale,
              height: 16 * scale,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFF4E342E),
                    width: 3 * scale,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 3. Big Mouth & Googly Eyes Lens
  Widget _buildGooglyEyes(double wave, double scale) {
    final pupilOffset = (wave - 0.5) * 12 * scale;
    return Positioned(
      top: 150 * scale,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildGooglyEye(pupilOffset, scale),
          SizedBox(width: 25 * scale),
          _buildGooglyEye(-pupilOffset, scale),
        ],
      ),
    );
  }

  Widget _buildGooglyEye(double pupilOffset, double scale) {
    return Container(
      width: 65 * scale,
      height: 65 * scale,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 3.5 * scale),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8 * scale,
          ),
        ],
      ),
      child: Transform.translate(
        offset: Offset(pupilOffset, pupilOffset * 0.5),
        child: Center(
          child: Container(
            width: 24 * scale,
            height: 24 * scale,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBigMouth(double wave, double scale) {
    final stretch = 1.0 + (wave * 0.25);
    return Positioned(
      top: 280 * scale,
      child: Transform.scale(
        scale: stretch,
        child: Container(
          width: 170 * scale,
          height: 80 * scale,
          decoration: BoxDecoration(
            color: const Color(0xFF990000),
            borderRadius: BorderRadius.circular(40 * scale),
            border: Border.all(color: const Color(0xFFFF2A2A), width: 3 * scale),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.4),
                blurRadius: 16 * scale,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Teeth Top
              Positioned(
                top: 2 * scale,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    7,
                    (_) => Container(
                      width: 16 * scale,
                      height: 18 * scale,
                      margin: EdgeInsets.symmetric(horizontal: 1 * scale),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(5 * scale),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Funny Red Tongue
              Positioned(
                bottom: 4 * scale,
                child: Container(
                  width: 55 * scale,
                  height: 30 * scale,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5252),
                    borderRadius: BorderRadius.circular(20 * scale),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 4. Giant Nose Lens
  Widget _buildGiantNose(double wave, double scale) {
    final wobble = (wave - 0.5) * 6 * scale;
    return Positioned(
      top: 210 * scale,
      child: Transform.translate(
        offset: Offset(wobble, 0),
        child: Container(
          width: 110 * scale,
          height: 90 * scale,
          decoration: BoxDecoration(
            gradient: const RadialGradient(
              colors: [Color(0xFFFF8A80), Color(0xFFD32F2F)],
              center: Alignment(-0.2, -0.2),
            ),
            borderRadius: BorderRadius.circular(50 * scale),
            border: Border.all(color: const Color(0xFFB71C1C), width: 3 * scale),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 18 * scale,
                offset: Offset(0, 8 * scale),
              ),
            ],
          ),
          child: Align(
            alignment: const Alignment(-0.4, -0.4),
            child: Container(
              width: 25 * scale,
              height: 15 * scale,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10 * scale),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 5. Anime Lens
  Widget _buildAnimeStars(double wave, double scale) {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            top: 100 * scale,
            left: 40 * scale,
            child: Transform.rotate(
              angle: wave * 0.5,
              child: Icon(Icons.star_rounded, size: 36 * scale, color: const Color(0xFFFFEB3B)),
            ),
          ),
          Positioned(
            top: 120 * scale,
            right: 40 * scale,
            child: Transform.rotate(
              angle: -wave * 0.5,
              child: Icon(Icons.auto_awesome, size: 32 * scale, color: const Color(0xFFFF4081)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimeBlush(double scale) {
    return Positioned(
      top: 240 * scale,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBlushPatch(scale),
          SizedBox(width: 160 * scale),
          _buildBlushPatch(scale),
        ],
      ),
    );
  }

  Widget _buildBlushPatch(double scale) {
    return Container(
      width: 50 * scale,
      height: 25 * scale,
      decoration: BoxDecoration(
        color: const Color(0xFFFF4081).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20 * scale),
      ),
    );
  }

  // 6. Cyberpunk Visor Lens
  Widget _buildCyberpunkVisor(double wave, double scale) {
    return Positioned(
      top: 170 * scale,
      child: Container(
        width: 240 * scale,
        height: 60 * scale,
        decoration: BoxDecoration(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12 * scale),
          border: Border.all(color: const Color(0xFF00E5FF), width: 2.5 * scale),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
              blurRadius: 18 * scale,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 10 * scale,
              top: 8 * scale,
              child: Text(
                'TARGET LOCKED // 98.4%',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10 * scale,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Positioned(
              right: 10 * scale,
              bottom: 8 * scale,
              child: Container(
                width: 14 * scale,
                height: 14 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: wave > 0.5 ? const Color(0xFFFF1744) : Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 7. Cat Lens
  Widget _buildCatEars(double wave, double scale) {
    return Positioned(
      top: 70 * scale,
      left: 30 * scale,
      right: 30 * scale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSingleCatEar(scale, isLeft: true),
          _buildSingleCatEar(scale, isLeft: false),
        ],
      ),
    );
  }

  Widget _buildSingleCatEar(double scale, {required bool isLeft}) {
    return Container(
      width: 60 * scale,
      height: 60 * scale,
      decoration: BoxDecoration(
        color: const Color(0xFF212121),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isLeft ? 45 * scale : 10 * scale),
          topRight: Radius.circular(isLeft ? 10 * scale : 45 * scale),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8 * scale,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 30 * scale,
          height: 30 * scale,
          decoration: const BoxDecoration(
            color: Color(0xFFFF80AB),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
      ),
    );
  }

  Widget _buildCatWhiskers(double scale) {
    return Positioned(
      top: 240 * scale,
      left: 20 * scale,
      right: 20 * scale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            children: [
              _buildWhiskerLine(scale, angle: -0.15),
              SizedBox(height: 6 * scale),
              _buildWhiskerLine(scale, angle: 0.0),
              SizedBox(height: 6 * scale),
              _buildWhiskerLine(scale, angle: 0.15),
            ],
          ),
          Column(
            children: [
              _buildWhiskerLine(scale, angle: 0.15),
              SizedBox(height: 6 * scale),
              _buildWhiskerLine(scale, angle: 0.0),
              SizedBox(height: 6 * scale),
              _buildWhiskerLine(scale, angle: -0.15),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWhiskerLine(double scale, {required double angle}) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: 55 * scale,
        height: 2.5 * scale,
        color: Colors.white.withValues(alpha: 0.8),
      ),
    );
  }

  // 8. Alien Lens
  Widget _buildAlienAntennae(double wave, double scale) {
    return Positioned(
      top: 50 * scale,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAntenna(wave, scale, isLeft: true),
          SizedBox(width: 80 * scale),
          _buildAntenna(wave, scale, isLeft: false),
        ],
      ),
    );
  }

  Widget _buildAntenna(double wave, double scale, {required bool isLeft}) {
    final bend = isLeft ? -0.2 : 0.2;
    return Transform.rotate(
      angle: bend + (wave * 0.1),
      child: Column(
        children: [
          Container(
            width: 26 * scale,
            height: 26 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF00E676),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.8),
                  blurRadius: 14 * scale,
                  spreadRadius: 2 * scale,
                ),
              ],
            ),
          ),
          Container(
            width: 5 * scale,
            height: 60 * scale,
            color: const Color(0xFF00E676),
          ),
        ],
      ),
    );
  }

  Widget _buildAlienAura(double wave) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF00E676).withValues(alpha: 0.15 * wave),
            width: 8,
          ),
        ),
      ),
    );
  }

  // 9. Crying Lens
  Widget _buildCryingStreams(double wave, double scale) {
    final tearY = (wave * 80 * scale);
    return Positioned(
      top: 190 * scale,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTearStream(tearY, scale),
          SizedBox(width: 140 * scale),
          _buildTearStream(tearY, scale),
        ],
      ),
    );
  }

  Widget _buildTearStream(double tearY, double scale) {
    return Column(
      children: [
        Container(
          width: 8 * scale,
          height: 90 * scale,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00B0FF), Color(0xFF80D8FF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(4 * scale),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00B0FF).withValues(alpha: 0.6),
                blurRadius: 10 * scale,
              ),
            ],
          ),
        ),
        Transform.translate(
          offset: Offset(0, tearY * 0.3),
          child: Container(
            width: 18 * scale,
            height: 24 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF00B0FF),
              borderRadius: BorderRadius.circular(12 * scale),
            ),
          ),
        ),
      ],
    );
  }

  // 10. Devil Horns
  Widget _buildDevilHorns(double wave, double scale) {
    return Positioned(
      top: 60 * scale,
      left: 50 * scale,
      right: 50 * scale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSingleHorn(scale, isLeft: true),
          _buildSingleHorn(scale, isLeft: false),
        ],
      ),
    );
  }

  Widget _buildSingleHorn(double scale, {required bool isLeft}) {
    return Transform.rotate(
      angle: isLeft ? -0.3 : 0.3,
      child: Container(
        width: 35 * scale,
        height: 60 * scale,
        decoration: BoxDecoration(
          color: const Color(0xFFFF1744),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isLeft ? 30 * scale : 5 * scale),
            topRight: Radius.circular(isLeft ? 5 * scale : 30 * scale),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF1744).withValues(alpha: 0.75),
              blurRadius: 16 * scale,
            ),
          ],
        ),
      ),
    );
  }

  // 11. Bunny Lens
  Widget _buildBunnyEars(double wave, double scale) {
    return Positioned(
      top: 30 * scale,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: -0.1 + (wave * 0.05),
            child: _buildBunnyEar(scale),
          ),
          SizedBox(width: 40 * scale),
          Transform.rotate(
            angle: 0.1 - (wave * 0.05),
            child: _buildBunnyEar(scale),
          ),
        ],
      ),
    );
  }

  Widget _buildBunnyEar(double scale) {
    return Container(
      width: 45 * scale,
      height: 140 * scale,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25 * scale),
        border: Border.all(color: const Color(0xFFFCE4EC), width: 3 * scale),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10 * scale,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 22 * scale,
          height: 100 * scale,
          decoration: BoxDecoration(
            color: const Color(0xFFF8BBD0),
            borderRadius: BorderRadius.circular(15 * scale),
          ),
        ),
      ),
    );
  }

  Widget _buildBunnyNose(double scale) {
    return Positioned(
      top: 240 * scale,
      child: Container(
        width: 24 * scale,
        height: 18 * scale,
        decoration: BoxDecoration(
          color: const Color(0xFFF48FB1),
          borderRadius: BorderRadius.circular(10 * scale),
        ),
      ),
    );
  }

  // 12. Panda Ears
  Widget _buildPandaEars(double scale) {
    return Positioned(
      top: 70 * scale,
      left: 35 * scale,
      right: 35 * scale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 65 * scale,
            height: 65 * scale,
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 65 * scale,
            height: 65 * scale,
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  // 13. Deer Antlers
  Widget _buildDeerAntlers(double wave, double scale) {
    return Positioned(
      top: 40 * scale,
      left: 40 * scale,
      right: 40 * scale,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(Icons.nature, size: 70 * scale, color: const Color(0xFF8D6E63)),
          Icon(Icons.nature, size: 70 * scale, color: const Color(0xFF8D6E63)),
        ],
      ),
    );
  }

  // 14. Retro VHS Camcorder
  Widget _buildVhsOverlay(double wave) {
    return Positioned.fill(
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: wave > 0.4 ? Colors.red : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'REC',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const Text(
                  'SP 0:02:45',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PLAY  ▶',
                  style: TextStyle(
                    color: Color(0xFF00E676),
                    fontFamily: 'monospace',
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '1994-08-15 14:22:05',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

