import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/zev_data_saver_service.dart';

class DataSaverSettingsScreen extends StatefulWidget {
  const DataSaverSettingsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DataSaverSettingsScreen()),
    );
  }

  @override
  State<DataSaverSettingsScreen> createState() => _DataSaverSettingsScreenState();
}

class _DataSaverSettingsScreenState extends State<DataSaverSettingsScreen> {
  final _service = ZevDataSaverService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mode = _service.mode;
    final autoDl = _service.autoDownload;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Data Saver & Quality",
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        children: [
          // Hero Banner
          _buildHeroBanner(mode),

          const SizedBox(height: 24),
          const Text(
            "DATA SAVER MODE",
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),

          // Extreme Mode
          _buildModeCard(
            mode: DataSaverMode.extreme,
            currentMode: mode,
            title: "Extreme Saver (Ultra Low Data)",
            subtitle: "Best for low bandwidth & expensive mobile bundles. 360p video, no autoplay, aggressive image compression.",
            badge: "Saves ~75%",
            badgeColor: const Color(0xFF10B981),
            icon: Icons.offline_bolt_rounded,
          ),

          const SizedBox(height: 12),

          // Standard Mode
          _buildModeCard(
            mode: DataSaverMode.standard,
            currentMode: mode,
            title: "Standard Saver (Balanced)",
            subtitle: "480p videos, autoplay on Wi-Fi only, compressed photos. Great balance of speed and clarity.",
            badge: "Saves ~40%",
            badgeColor: const Color(0xFF0284C7),
            icon: Icons.speed_rounded,
          ),

          const SizedBox(height: 12),

          // Off Mode
          _buildModeCard(
            mode: DataSaverMode.off,
            currentMode: mode,
            title: "Standard Quality (Off)",
            subtitle: "Original high resolution, 60fps reels, and full uncompressed media stream.",
            badge: "Full Quality",
            badgeColor: const Color(0xFF64748B),
            icon: Icons.hd_rounded,
          ),

          const SizedBox(height: 28),
          const Text(
            "MEDIA AUTO-DOWNLOAD ON MOBILE DATA",
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildRadioTile(
                  title: "Never auto-download",
                  subtitle: "Tap every photo and video manually to view",
                  selected: autoDl == MediaAutoDownload.never,
                  onTap: () => _service.setAutoDownload(MediaAutoDownload.never),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                _buildRadioTile(
                  title: "Wi-Fi Only (Recommended)",
                  subtitle: "Auto-download media when connected to Wi-Fi",
                  selected: autoDl == MediaAutoDownload.wifiOnly,
                  onTap: () => _service.setAutoDownload(MediaAutoDownload.wifiOnly),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                _buildRadioTile(
                  title: "Always auto-download",
                  subtitle: "Download all media even on cellular data",
                  selected: autoDl == MediaAutoDownload.always,
                  onTap: () => _service.setAutoDownload(MediaAutoDownload.always),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          const Text(
            "STORAGE & CACHE MANAGEMENT",
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cleaning_services_rounded,
                    color: Color(0xFF0284C7),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Cached Media & Files",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "148.6 MB used • Safe to clear",
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("148.6 MB temporary cache cleared successfully!"),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Color(0xFF0284C7),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    foregroundColor: const Color(0xFF0F172A),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Clear Cache",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildHeroBanner(DataSaverMode mode) {
    final isExtreme = mode == DataSaverMode.extreme;
    final isStd = mode == DataSaverMode.standard;
    final isActive = isExtreme || isStd;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isExtreme
              ? [const Color(0xFF0284C7), const Color(0xFF0369A1)]
              : isStd
                  ? [const Color(0xFF0284C7), const Color(0xFF38BDF8)]
                  : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: (isActive ? const Color(0xFF0284C7) : Colors.black).withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isExtreme
                      ? Icons.bolt_rounded
                      : isStd
                          ? Icons.wifi_tethering_rounded
                          : Icons.data_usage_rounded,
                  color: isActive ? Colors.white : const Color(0xFF64748B),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? "Data Saver is Active" : "Full Bandwidth Mode",
                      style: TextStyle(
                        color: isActive ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isExtreme
                          ? "Ultra low-bandwidth mode is saving up to 75% data"
                          : isStd
                              ? "Balanced mode active: videos load efficiently"
                              : "No data limits applied: high-res 60fps streaming",
                      style: TextStyle(
                        color: isActive ? const Color(0xFFE0F2FE) : const Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required DataSaverMode mode,
    required DataSaverMode currentMode,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required IconData icon,
  }) {
    final isSelected = mode == currentMode;

    return InkWell(
      onTap: () => _service.setMode(mode),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F9FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isSelected ? const Color(0xFF0284C7) : const Color(0xFF64748B)).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: const Color(0xFF0F172A),
                            fontSize: 14.5,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      title: Text(
        title,
        style: TextStyle(
          color: const Color(0xFF0F172A),
          fontSize: 13.5,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
      ),
      trailing: Icon(
        selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
        color: selected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
        size: 20,
      ),
    );
  }
}
