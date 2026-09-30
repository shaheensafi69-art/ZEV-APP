import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../localization/zev_localizations.dart';

/// Facebook-style interactive media customization and framing preview dialog.
/// Allows users to pan, zoom, toggle fit/fill, and align their avatar or cover photo
/// before uploading to Cloudflare R2 / Supabase.
class MediaFramePreviewDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final bool isCircle; // true for profile avatar, false for cover photo
  final String? title;

  const MediaFramePreviewDialog({
    super.key,
    required this.imageBytes,
    this.isCircle = true,
    this.title,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    required bool isCircle,
    String? title,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => MediaFramePreviewDialog(
        imageBytes: imageBytes,
        isCircle: isCircle,
        title: title,
      ),
    );
  }

  @override
  State<MediaFramePreviewDialog> createState() =>
      _MediaFramePreviewDialogState();
}

class _MediaFramePreviewDialogState extends State<MediaFramePreviewDialog> {
  final TransformationController _transController =
      TransformationController();
  BoxFit _currentFit = BoxFit.contain;
  static const Color primaryPink = Color(0xFFFC466B);

  @override
  void dispose() {
    _transController.dispose();
    super.dispose();
  }

  void _resetTransform() {
    setState(() {
      _transController.value = Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxDialogWidth = size.width > 560 ? 520.0 : size.width * 0.94;
    final frameHeight = widget.isCircle ? 320.0 : 240.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: maxDialogWidth,
        constraints: BoxConstraints(maxHeight: size.height * 0.88),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryPink.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.isCircle
                          ? Icons.account_circle_outlined
                          : Icons.panorama_rounded,
                      color: primaryPink,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title ??
                              (widget.isCircle
                                  ? context.zevTr('profile')
                                  : 'Cover Photo'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          widget.isCircle
                              ? 'Drag & zoom to align avatar'
                              : 'Drag & zoom to fit your cover photo',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 1),

            // Interactive Preview Stage
            Container(
              height: frameHeight,
              width: double.infinity,
              color: const Color(0xFF05070B),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Interactive Zoom & Pan Image
                  InteractiveViewer(
                    transformationController: _transController,
                    minScale: 0.5,
                    maxScale: 4.0,
                    boundaryMargin: const EdgeInsets.all(100),
                    child: Center(
                      child: Image.memory(
                        widget.imageBytes,
                        fit: _currentFit,
                      ),
                    ),
                  ),

                  // Framing Overlay Mask
                  IgnorePointer(
                    child: widget.isCircle
                        ? _buildCircleMask(frameHeight)
                        : _buildBannerMask(frameHeight),
                  ),

                  // Reset zoom pill button
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: InkWell(
                      onTap: _resetTransform,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Reset',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Controls: Fit vs Fill Toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Text(
                    'Fit Mode:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : const Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildFitOption(
                    label: 'Contain (Full)',
                    fit: BoxFit.contain,
                    icon: Icons.aspect_ratio_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildFitOption(
                    label: 'Fill (Crop)',
                    fit: BoxFit.cover,
                    icon: Icons.crop_free_rounded,
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 1),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(
                          color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        context.zevTr('cancel'),
                        style: TextStyle(
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.pop(context, true),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [primaryPink, Color(0xFFFF5E8A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: primaryPink.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'Save & Apply',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleMask(double frameHeight) {
    const radius = 105.0;
    return Stack(
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.55),
            BlendMode.srcOut,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  height: radius * 2,
                  width: radius * 2,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: Container(
            height: radius * 2,
            width: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: primaryPink, width: 2.2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBannerMask(double frameHeight) {
    const bannerHeight = 170.0;
    return Stack(
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.55),
            BlendMode.srcOut,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  height: bannerHeight,
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: Container(
            height: bannerHeight,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primaryPink, width: 2.2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFitOption({
    required String label,
    required BoxFit fit,
    required IconData icon,
  }) {
    final isSelected = _currentFit == fit;
    return InkWell(
      onTap: () => setState(() => _currentFit = fit),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryPink.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? primaryPink : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? primaryPink : Colors.grey,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? primaryPink : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
