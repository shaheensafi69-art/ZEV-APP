import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/zev_alert.dart';
import '../../../core/widgets/responsive_layout.dart';

class ZevDeviceActivitiesScreen extends StatefulWidget {
  const ZevDeviceActivitiesScreen({super.key});

  @override
  State<ZevDeviceActivitiesScreen> createState() =>
      _ZevDeviceActivitiesScreenState();
}

class _ZevDeviceActivitiesScreenState extends State<ZevDeviceActivitiesScreen> {
  final supabase = Supabase.instance.client;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFFF0F5);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  List<Map<String, dynamic>> _deviceActivities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchActivities();
  }

  Future<void> _fetchActivities() async {
    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final res = await supabase
          .from('device_activities')
          .select('*')
          .eq('student_id', user.id)
          .order('logged_in_at', ascending: false)
          .limit(25);

      if (mounted) {
        setState(() {
          _deviceActivities = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching device activities: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logoutAllOtherDevices() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Log Out Other Sessions?"),
        content: const Text(
          "This will end all active sessions on other phones, tablets, or computers.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text("Log Out Others"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase
            .from('device_activities')
            .delete()
            .eq('student_id', user.id)
            .neq(
              'id',
              _deviceActivities.isNotEmpty ? _deviceActivities.first['id'] : '',
            );
      }
      if (!mounted) return;
      ZevAlert.success(context, "All other sessions have been terminated.");
      _fetchActivities();
    } catch (e) {
      if (!mounted) return;
      ZevAlert.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceWhite,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Device Activity",
          style: TextStyle(
            color: textDark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ResponsiveLayout.feedConstraint(
        maxWidth: 600,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: primaryPink,
                  strokeWidth: 2.5,
                ),
              )
            : RefreshIndicator(
                color: primaryPink,
                onRefresh: _fetchActivities,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Header card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: lightPinkBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: primaryPink.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.devices_rounded,
                              color: primaryPink,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Where You're Logged In",
                                  style: TextStyle(
                                    color: textDark,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Manage your active ZEV accounts across your phones, tablets, and computers.",
                                  style: TextStyle(
                                    color: textGrey.withOpacity(0.9),
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Section title
                    const Text(
                      "LOGIN SESSIONS",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textGrey,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_deviceActivities.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cardBorder,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text(
                            "No recent login history recorded yet.",
                            style: TextStyle(
                              color: textGrey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                    else
                      for (int i = 0; i < _deviceActivities.length; i++) ...[
                        _buildDeviceItem(
                          _deviceActivities[i],
                          isCurrent: i == 0,
                        ),
                        const SizedBox(height: 12),
                      ],

                    const SizedBox(height: 24),

                    // Log Out From Other Devices Button
                    if (_deviceActivities.length > 1)
                      OutlinedButton.icon(
                        onPressed: _logoutAllOtherDevices,
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text(
                          "Log Out of All Other Sessions",
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(
                            color: Colors.redAccent,
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDeviceItem(Map<String, dynamic> act, {required bool isCurrent}) {
    final devName = act['device_name']?.toString() ?? 'Mobile Device';
    final city = act['city']?.toString() ?? '';
    final country = act['country']?.toString() ?? '';
    final ip = act['ip_address']?.toString() ?? '';
    final loggedAt = act['logged_in_at']?.toString() ?? '';

    String loc = [city, country].where((s) => s.isNotEmpty).join(', ');
    if (loc.isEmpty) loc = ip.isNotEmpty ? ip : 'Unknown Location';

    IconData devIcon = Icons.smartphone_rounded;
    if (devName.toLowerCase().contains('mac') ||
        devName.toLowerCase().contains('windows') ||
        devName.toLowerCase().contains('pc')) {
      devIcon = Icons.laptop_mac_rounded;
    } else if (devName.toLowerCase().contains('ipad') ||
        devName.toLowerCase().contains('tablet')) {
      devIcon = Icons.tablet_mac_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrent ? primaryPink.withOpacity(0.4) : cardBorder,
          width: isCurrent ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
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
              color: isCurrent ? lightPinkBg : cardBorder,
              shape: BoxShape.circle,
            ),
            child: Icon(
              devIcon,
              color: isCurrent ? primaryPink : textDark,
              size: 24,
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
                        devName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textDark,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          "This Device",
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  loc,
                  style: const TextStyle(
                    fontSize: 13,
                    color: textGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (loggedAt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    "Logged in: ${loggedAt.split('T').first} ${loggedAt.contains('T') ? loggedAt.split('T')[1].split('.').first : ''}",
                    style: TextStyle(
                      fontSize: 11,
                      color: textGrey.withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
