import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme_service.dart';

class SelectAppColorSheet extends StatefulWidget {
  const SelectAppColorSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SelectAppColorSheet(),
    );
  }

  @override
  State<SelectAppColorSheet> createState() => _SelectAppColorSheetState();
}

class _SelectAppColorSheetState extends State<SelectAppColorSheet> {
  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return ValueListenableBuilder<LuxuryPalette>(
      valueListenable: AppThemeService.instance.currentPaletteNotifier,
      builder: (context, activePalette, _) {
        final isDark = activePalette.isDark;
        final textPrimary = activePalette.textPrimary;
        final textSecondary = activePalette.textSecondary;

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: activePalette.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: activePalette.cardBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: activePalette.primary.withValues(alpha: isDark ? 0.25 : 0.12),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: textSecondary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: activePalette.gradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: activePalette.primary.withValues(alpha: 0.4),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.palette_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Text(
                                'App Theme & Color Palette',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isRtl
                                    ? 'Default Pink & White + 5 Luxury Palettes'
                                    : 'Default Pink & White + 5 Luxury Palettes',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Palettes List
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: List.generate(
                            AppThemeService.luxuryPalettes.length,
                            (index) {
                              final palette = AppThemeService.luxuryPalettes[index];
                              final isSelected = palette.id == activePalette.id;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: InkWell(
                                  onTap: () {
                                    AppThemeService.instance.setPalette(index);
                                    setState(() {});
                                  },
                                  borderRadius: BorderRadius.circular(20),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? palette.primary.withValues(alpha: 0.12)
                                          : (isDark
                                              ? Colors.white.withValues(alpha: 0.03)
                                              : const Color(0xFFF8FAFC)),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSelected
                                            ? palette.primary
                                            : (isDark
                                                ? Colors.white.withValues(alpha: 0.08)
                                                : const Color(0xFFE2E8F0)),
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        // Palette Gradient Circle
                                        Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                            gradient: palette.gradient,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white.withValues(alpha: 0.8),
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: palette.primary.withValues(alpha: 0.35),
                                                blurRadius: 10,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                          child: isSelected
                                              ? const Icon(Icons.check, color: Colors.white, size: 22)
                                              : null,
                                        ),
                                        const SizedBox(width: 14),

                                        // Title and description
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: isRtl
                                                ? CrossAxisAlignment.end
                                                : CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: isRtl
                                                    ? MainAxisAlignment.end
                                                    : MainAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    palette.name,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.bold,
                                                      color: isSelected
                                                          ? palette.primary
                                                          : textPrimary,
                                                    ),
                                                  ),
                                                  if (isSelected) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: palette.primary.withValues(alpha: 0.2),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        'Active',
                                                        style: TextStyle(
                                                          color: palette.primary,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                palette.description,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(width: 8),

                                        // 3 Small Color dots
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _colorDot(palette.primary),
                                            const SizedBox(width: 4),
                                            _colorDot(palette.secondary),
                                            const SizedBox(width: 4),
                                            _colorDot(palette.accent),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    // Close button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: activePalette.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Apply Theme',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _colorDot(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1),
      ),
    );
  }
}
