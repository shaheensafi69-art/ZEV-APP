import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TwoFactorAuthScreen extends StatefulWidget {
  const TwoFactorAuthScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TwoFactorAuthScreen()),
    );
  }

  @override
  State<TwoFactorAuthScreen> createState() => _TwoFactorAuthScreenState();
}

class _TwoFactorAuthScreenState extends State<TwoFactorAuthScreen> {
  final _client = Supabase.instance.client;
  bool _isEnabled = false;
  List<String> _backupCodes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      setState(() => _isLoading = true);
      final row = await _client
          .from('user_two_factor_auth')
          .select('is_enabled, backup_codes')
          .eq('user_id', userId)
          .maybeSingle();

      if (row != null) {
        _isEnabled = row['is_enabled'] == true;
        _backupCodes = (row['backup_codes'] as List?)?.cast<String>() ?? [];
      }
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[TwoFactorAuthScreen] check error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSetPinDialog() {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161F30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          "Set 6-Digit Security PIN",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "You will be asked to enter this security PIN whenever signing in on a new device or changing sensitive security settings.",
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, letterSpacing: 6, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: "••••••",
                hintStyle: const TextStyle(color: Color(0xFF64748B), letterSpacing: 6),
                counterText: "",
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, letterSpacing: 6, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: "Confirm PIN",
                hintStyle: const TextStyle(color: Color(0xFF64748B), letterSpacing: 0, fontSize: 13),
                counterText: "",
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            onPressed: () async {
              final pin = pinController.text.trim();
              final confirm = confirmController.text.trim();
              if (pin.length < 4 || pin != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("PINs do not match or are too short (min 4 digits)"), backgroundColor: Colors.red),
                );
                return;
              }
              Navigator.pop(ctx);

              try {
                final res = await _client.rpc('setup_two_factor_pin', params: {'p_pin': pin});
                if (res is Map && res['success'] == true) {
                  _checkStatus();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Two-Step Verification activated successfully!"),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B2FF)),
            child: const Text("Activate", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDisableDialog() {
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161F30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text("Disable Two-Step Verification?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Enter your current Security PIN to turn off two-step verification:",
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, letterSpacing: 6, fontSize: 18),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: "••••••",
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                counterText: "",
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            onPressed: () async {
              final pin = pinController.text.trim();
              if (pin.isEmpty) return;
              Navigator.pop(ctx);

              try {
                await _client.rpc('disable_two_factor', params: {'p_pin': pin});
                _checkStatus();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Two-step verification has been disabled.")),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Invalid PIN: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("Disable", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          "Two-Step Verification",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00B2FF)))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                // Hero Status Banner
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isEnabled
                          ? [const Color(0xFF065F46), const Color(0xFF047857)]
                          : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isEnabled ? Icons.verified_user_rounded : Icons.shield_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isEnabled ? "Two-Step Verification is ON" : "Protect Your ZEV Account",
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _isEnabled
                                  ? "Account is secured with a secondary PIN code."
                                  : "Add an extra layer of defense against unauthorized logins.",
                              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161F30),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00B2FF).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.pin_rounded, color: Color(0xFF00B2FF), size: 22),
                        ),
                        title: const Text(
                          "Security PIN Password",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
                        ),
                        subtitle: Text(
                          _isEnabled ? "PIN is configured and active" : "Require a secondary PIN on new devices",
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                        trailing: ElevatedButton(
                          onPressed: _isEnabled ? _showDisableDialog : _showSetPinDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isEnabled ? const Color(0xFF334155) : const Color(0xFF00B2FF),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          child: Text(
                            _isEnabled ? "Disable" : "Turn On",
                            style: TextStyle(
                              color: _isEnabled ? Colors.redAccent : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Recovery Codes (if enabled)
                if (_isEnabled && _backupCodes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.key_rounded, color: Color(0xFFF59E0B), size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        "ONE-TIME RECOVERY CODES",
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Color(0xFF00B2FF), size: 16),
                        tooltip: "Copy All Codes",
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _backupCodes.join('\n')));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Recovery codes copied to clipboard")),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161F30),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Save these emergency recovery codes in a safe place. You can use each code once if you ever forget your PIN:",
                          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _backupCodes.map((code) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(
                                code,
                                style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
