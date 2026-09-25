import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/localization/l10n_extensions.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/services/auth_helper.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _reasonController = TextEditingController();

  bool _isConfirmed = false;
  bool _isLoading = false;
  bool _isFetchingUser = true;
  Map<String, dynamic>? _userProfile;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);
  static const Color dangerRed = Color(0xFFDC2626);

  final String telegramBotToken =
      dotenv.env['NEXT_PUBLIC_TELEGRAM_BOT_TOKEN2'] ??
      "8994358206:AAHUpoHpMpqdnTxA_J30-xMipDg4l0vhBV8";
  final String telegramChatId =
      dotenv.env['NEXT_PUBLIC_TELEGRAM_CHAT_ID2'] ?? "5195615040";

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _userProfile = profile ?? {};
          _isFetchingUser = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching profile: $e");
      if (mounted) {
        setState(() => _isFetchingUser = false);
      }
    }
  }

  Future<void> _openWebPolicy() async {
    final Uri url = Uri.parse('https://zevapp.com/delete-account');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        debugPrint("Could not launch web policy url");
      }
    } catch (e) {
      debugPrint("Error opening web policy url: $e");
    }
  }

  Future<void> _sendTelegramAlert(Map<String, dynamic> profile, String reason) async {
    try {
      final user = supabase.auth.currentUser;
      final device = await ActivityLogService.instance.getDeviceDetails();
      final loc = await ActivityLogService.instance.getApproximateLocation();

      final String userId = user?.id ?? "—";
      final String email = user?.email ?? profile['email'] ?? "—";
      final String firstName = profile['first_name'] ?? "";
      final String lastName = profile['last_name'] ?? "";
      final String fatherName = profile['father_name'] ?? "—";
      final String phone = profile['phone_number'] ?? "—";
      final String role = profile['role'] ?? "student";
      final String country = profile['country'] ?? loc['country'] ?? "—";
      final String wallet = "${profile['wallet_balance'] ?? 0} USD";
      final String score = "${profile['total_score'] ?? 0}";
      final String refCode = profile['referral_code'] ?? "—";
      final String devName = "${device['model']} (${device['os']})";
      final String userIp = loc['ip'] ?? "—";
      final String userLoc = loc['location'] ?? "—";
      final String timeStr = DateTime.now().toUtc().toString();

      final String messageText = """
🚨 <b>ACCOUNT DELETION REQUEST</b> 🚨
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
👤 <b>Name:</b> $firstName $lastName
👨‍👦 <b>Father Name:</b> $fatherName
📧 <b>Email:</b> $email
📱 <b>Phone:</b> $phone
🆔 <b>User ID:</b> <code>$userId</code>
🎭 <b>Role:</b> $role
🌍 <b>Country / Location:</b> $country ($userLoc)
🌐 <b>IP Address:</b> $userIp
💰 <b>Wallet Balance:</b> $wallet
🏆 <b>Total Score:</b> $score
🔗 <b>Referral Code:</b> $refCode
📱 <b>Device & OS:</b> $devName
📝 <b>Reason:</b> ${reason.trim().isEmpty ? "Not specified" : reason.trim()}
⏰ <b>Timestamp (UTC):</b> $timeStr
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ <b>Required Action:</b> Please verify and delete this user account in Supabase console.
""";

      final url = Uri.parse("https://api.telegram.org/bot$telegramBotToken/sendMessage");
      await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "chat_id": telegramChatId,
          "text": messageText,
          "parse_mode": "HTML",
        }),
      );
      debugPrint("Telegram deletion alert sent successfully");
    } catch (e) {
      debugPrint("Error sending Telegram deletion alert: $e");
    }
  }

  Future<void> _submitDeletionRequest() async {
    if (!_isConfirmed) return;

    setState(() => _isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final reason = _reasonController.text.trim();

        // 1. Send detailed alert to admin Telegram with full details
        await _sendTelegramAlert(_userProfile ?? {}, reason);

        // 2. Record official ticket in database for tracking
        try {
          await supabase.from('tickets').insert({
            'student_id': user.id,
            'subject': 'ACCOUNT_DELETION_REQUEST',
            'department': 'Account Security',
            'status': 'pending',
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (ticketErr) {
          debugPrint("Notice: Ticket insertion for deletion: $ticketErr");
        }
      }

      if (!mounted) return;

      // Show success dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: surfaceWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.deleteAccount,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: textDark),
                ),
              ),
            ],
          ),
          content: Text(
            context.l10n.accountDeletionSubmitted,
            style: const TextStyle(color: textGrey, fontSize: 13, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryPink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                if (mounted) {
                  await AuthHelper.logout(context);
                }
              },
              child: Text(context.l10n.logout, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: dangerRed),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final email = user?.email ?? _userProfile?['email'] ?? "—";
    final fullName = "${_userProfile?['first_name'] ?? ''} ${_userProfile?['last_name'] ?? ''}".trim();
    final role = (_userProfile?['role'] ?? 'student').toString().toUpperCase();

    return Scaffold(
      backgroundColor: surfaceWhite,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        centerTitle: true,
        title: Text(
          context.l10n.deleteAccount,
          style: const TextStyle(color: textDark, fontWeight: FontWeight.w900, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: textDark),
      ),
      body: _isFetchingUser
          ? const Center(child: CircularProgressIndicator(color: primaryPink))
          : SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Red warning header
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                dangerRed.withValues(alpha: 0.08),
                                lightPinkBg.withValues(alpha: 0.6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: dangerRed.withValues(alpha: 0.3), width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: dangerRed.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(Icons.warning_amber_rounded, color: dangerRed, size: 30),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.l10n.deleteAccountSubtitle,
                                      style: const TextStyle(
                                        color: dangerRed,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      context.l10n.deleteAccountWarning,
                                      style: TextStyle(
                                        color: textDark.withValues(alpha: 0.8),
                                        fontSize: 11,
                                        height: 1.4,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // User details card
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: surfaceWhite,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: cardBorder, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: lightPinkBg,
                                backgroundImage: (_userProfile?['avatar_url'] != null &&
                                        _userProfile!['avatar_url'].toString().isNotEmpty)
                                    ? NetworkImage(_userProfile!['avatar_url'])
                                    : null,
                                child: (_userProfile?['avatar_url'] == null ||
                                        _userProfile!['avatar_url'].toString().isEmpty)
                                    ? const Icon(Icons.person_outline_rounded, color: primaryPink)
                                    : null,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fullName.isEmpty ? "ZEV Member" : fullName,
                                      style: const TextStyle(
                                        color: textDark,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      email,
                                      style: const TextStyle(color: textGrey, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: lightPinkBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: primaryPink.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  role,
                                  style: const TextStyle(
                                    color: primaryPink,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Deletion reason field
                        Text(
                          context.l10n.deleteAccountReasonHint,
                          style: const TextStyle(
                            color: textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _reasonController,
                          maxLines: 4,
                          cursorColor: primaryPink,
                          style: const TextStyle(fontSize: 13, color: textDark),
                          decoration: InputDecoration(
                            hintText: context.l10n.deleteAccountReasonHint,
                            hintStyle: const TextStyle(color: textGrey, fontSize: 12),
                            filled: true,
                            fillColor: lightPinkBg.withValues(alpha: 0.4),
                            contentPadding: const EdgeInsets.all(16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: cardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: primaryPink, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Confirmation checkbox
                        InkWell(
                          onTap: () => setState(() => _isConfirmed = !_isConfirmed),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(
                                  value: _isConfirmed,
                                  activeColor: dangerRed,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                  onChanged: (val) => setState(() => _isConfirmed = val ?? false),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Text(
                                      context.l10n.deleteAccountConfirmCheck,
                                      style: TextStyle(
                                        color: _isConfirmed ? dangerRed : textDark,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Submit deletion request button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: dangerRed,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: dangerRed.withValues(alpha: 0.3),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: _isLoading
                                ? const SizedBox.shrink()
                                : const Icon(Icons.delete_forever_rounded, size: 20),
                            label: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(
                                    context.l10n.requestAccountDeletion,
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                                  ),
                            onPressed: (_isConfirmed && !_isLoading) ? _submitDeletionRequest : null,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // View official policy on website button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textGrey,
                              side: const BorderSide(color: cardBorder, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                            label: Text(
                              context.l10n.deleteAccountWebPolicy,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            onPressed: _openWebPolicy,
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
