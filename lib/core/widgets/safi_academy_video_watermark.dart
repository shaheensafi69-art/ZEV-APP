import 'dart:ui';
import 'package:flutter/material.dart';

/// Stylized "ZEV" text watermark dedicated strictly for video playback
/// (Reels & Video Stories).
class ZevVideoWatermark extends StatelessWidget {
  final double scale;
  final bool showBorder;

  const ZevVideoWatermark({
    super.key,
    this.scale = 1.0,
    this.showBorder = true,
  });

  static const Color primaryPink = Color(0xFFFC466B);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16 * scale),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 10 * scale,
              vertical: 4 * scale,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(16 * scale),
              border: showBorder
                  ? Border.all(
                      color: primaryPink.withValues(alpha: 0.55),
                      width: 1.0 * scale,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6 * scale,
                  offset: Offset(0, 2 * scale),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Small pink luxury dot
                Container(
                  width: 5 * scale,
                  height: 5 * scale,
                  margin: EdgeInsets.only(right: 6 * scale),
                  decoration: const BoxDecoration(
                    color: primaryPink,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  'ZEV',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.0 * scale,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0 * scale,
                    fontFamily: 'serif',
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.8),
                        blurRadius: 4 * scale,
                        offset: Offset(0, 1 * scale),
                      ),
                      Shadow(
                        color: primaryPink.withValues(alpha: 0.4),
                        blurRadius: 6 * scale,
                        offset: const Offset(0, 0),
                      ),
                    ],
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

typedef SafiAcademyVideoWatermark = ZevVideoWatermark;
