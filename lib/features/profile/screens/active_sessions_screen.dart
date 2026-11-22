import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/zev_theme.dart';

class ActiveSessionsScreen extends StatefulWidget {
  const ActiveSessionsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActiveSessionsScreen()),
    );
  }

  @override
  State<ActiveSessionsScreen> createState() => _ActiveSessionsScreenState();
}

class _ActiveSessionsScreenState extends State<ActiveSessionsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      setState(() => _isLoading = true);
      final res = await _client
          .from('user_sessions')
          .select()
          .eq('user_id', userId)
          .order('last_active_at', ascending: false);

      setState(() {
        _sessions = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[ActiveSessionsScreen] error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _terminateSession(String sessionId) async {
    try {
      await _client.rpc('terminate_user_session', params: {'p_session_id': sessionId});
      setState(() {
        _sessions.removeWhere((s) => s['id'] == sessionId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session revoked successfully.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _terminateAllOtherSessions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161F30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Log Out All Other Devices?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: const Text(
          "This will immediately terminate all active logins on other phones, tablets, and computers. You will stay signed in on this device.",
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel", style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("Log Out Others", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _client.rpc('terminate_all_other_sessions');
      _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("All other sessions have been logged out.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  IconData _getDeviceIcon(String? platform) {
    final p = platform?.toLowerCase() ?? '';
    if (p.contains('android')) return Icons.android_rounded;
    if (p.contains('ios') || p.contains('iphone') || p.contains('ipad')) return Icons.phone_iphone_rounded;
    if (p.contains('mac') || p.contains('darwin')) return Icons.laptop_mac_rounded;
    if (p.contains('win')) return Icons.laptop_windows_rounded;
    if (p.contains('web')) return Icons.language_rounded;
    return Icons.devices_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final otherSessions = _sessions.skip(1).toList();
    final currentSession = _sessions.isNotEmpty ? _sessions.first : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0B101B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B101B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Active Sessions & Devices",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00B2FF)))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              children: [
                // Info Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161F30),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: Color(0xFF00B2FF), size: 24),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          "You can monitor all devices logged into your ZEV account and revoke access remotely if you notice any unrecognized activity.",
                          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Current Device Section
                const Text(
                  "THIS DEVICE (CURRENT)",
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                ),
                const SizedBox(height: 10),

                if (currentSession != null) _buildCurrentDeviceCard(currentSession),

                const SizedBox(height: 24),

                // Other Devices Section
                if (otherSessions.isNotEmpty) ...[
                  Row(
                    children: [
                      const Text(
                        "OTHER ACTIVE SESSIONS",
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _terminateAllOtherSessions,
                        child: const Text("Log Out All", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...otherSessions.map((s) => _buildOtherDeviceCard(s)),
                ] else ...[
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        "No other active sessions. Your account is only signed in on this device.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildCurrentDeviceCard(Map<String, dynamic> s) {
    final devName = s['device_name'] ?? s['platform'] ?? 'This Device';
    final platform = s['platform'] ?? '';
    final ip = s['ip_address'] ?? 'Protected IP';
    final activeStr = s['last_active_at'] != null ? DateTime.parse(s['last_active_at']).toLocal().toString().substring(0, 16) : 'Now';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161F30),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_getDeviceIcon(platform), color: const Color(0xFF10B981), size: 24),
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
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14.5),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: Color(0xFF10B981), size: 7),
                          SizedBox(width: 5),
                          Text("Active Now", style: TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text("$platform • IP: $ip", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
                Text("Last active: $activeStr", style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherDeviceCard(Map<String, dynamic> s) {
    final sessionId = s['id'];
    final devName = s['device_name'] ?? s['platform'] ?? 'Remote Device';
    final platform = s['platform'] ?? '';
    final ip = s['ip_address'] ?? 'Protected IP';
    final activeStr = s['last_active_at'] != null ? DateTime.parse(s['last_active_at']).toLocal().toString().substring(0, 16) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161F30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_getDeviceIcon(platform), color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  devName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text("$platform • $ip", style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                Text("Last active: $activeStr", style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 20),
            tooltip: "Revoke Access",
            onPressed: () => _terminateSession(sessionId),
          ),
        ],
      ),
    );
  }
}
