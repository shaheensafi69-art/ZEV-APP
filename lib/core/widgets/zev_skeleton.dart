import 'package:flutter/material.dart';
import '../theme/zev_theme.dart';

/// Light Clearmorphic animated skeleton shimmer block for ZEV loading states.
/// Eliminates dark flashes and jarring spinners across feeds, grids, and thumbnails.
class ZevSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final Widget? child;

  const ZevSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.child,
  });

  @override
  State<ZevSkeleton> createState() => _ZevSkeletonState();
}

class _ZevSkeletonState extends State<ZevSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.shape == BoxShape.circle
        ? null
        : (widget.borderRadius ?? BorderRadius.circular(14));

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final slide = -1.2 + (t * 2.4);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.shape,
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.85),
              width: 1,
            ),
            gradient: LinearGradient(
              begin: Alignment(slide - 0.6, -0.3),
              end: Alignment(slide + 0.6, 0.3),
              colors: const [
                Color(0xFFEEF3F9),
                Color(0xFFFAFBFD),
                Color(0xFFE7EFF8),
              ],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Light Clearmorphic feed card loading skeleton placeholder.
class ZevFeedCardSkeleton extends StatelessWidget {
  const ZevFeedCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.045),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              ZevSkeleton(width: 42, height: 42, shape: BoxShape.circle),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ZevSkeleton(width: 128, height: 13),
                  SizedBox(height: 6),
                  ZevSkeleton(width: 82, height: 10),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const ZevSkeleton(width: double.infinity, height: 13),
          const SizedBox(height: 8),
          const ZevSkeleton(width: 220, height: 13),
          const SizedBox(height: 14),
          ZevSkeleton(
            width: double.infinity,
            height: 220,
            borderRadius: BorderRadius.circular(18),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              ZevSkeleton(width: 58, height: 24),
              SizedBox(width: 10),
              ZevSkeleton(width: 58, height: 24),
              SizedBox(width: 10),
              ZevSkeleton(width: 58, height: 24),
            ],
          ),
        ],
      ),
    );
  }
}
