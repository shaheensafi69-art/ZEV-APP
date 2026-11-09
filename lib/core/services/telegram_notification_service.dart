import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Dedicated Telegram Bot Notification Dispatcher for ZEV.
/// Sends instant, rich HTML notifications to the administrative Telegram channel
/// whenever a user requests ZEV Blue Verification, purchases a subscription,
/// or achieves referral milestones.
class TelegramNotificationService {
  TelegramNotificationService._();

  static const String _defaultBotToken1 =
      '8668673040:AAEI6Q4r28KWiTAGwvQrT0Y9j6S92KhtwiI';
  static const String _defaultChatId = '5195615040';
  static const String _defaultBotToken2 =
      '8994358206:AAHUpoHpMpqdnTxA_J30-xMipDg4l0vhBV8';

  /// Dispatches a high-priority ZEV Blue verification request notification.
  static Future<bool> sendVerificationOrderNotification({
    required String userId,
    required String username,
    required String fullName,
    required String phone,
    required String planName,
    required String planPrice,
    String? email,
    String? notes,
    String? referralCode,
    int? currentReferrals,
  }) async {
    final now = DateTime.now().toUtc();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} UTC";

    final safeFullName = _escapeHtml(fullName.trim());
    final safeUsername = _escapeHtml(username.trim());
    final safeEmail = _escapeHtml(email?.trim() ?? 'Not provided');
    final safePhone = _escapeHtml(phone.trim());
    final safeNotes = _escapeHtml(notes?.trim() ?? 'None');
    final safeRefCode = _escapeHtml(referralCode ?? username);
    final refCount = currentReferrals ?? 0;

    final message = '''
💎 <b>NEW ZEV BLUE VERIFICATION REQUEST</b> 💎
━━━━━━━━━━━━━━━━━━━━━━
👤 <b>Full Name:</b> ${safeFullName.isNotEmpty ? safeFullName : 'Not provided'}
🔖 <b>Username:</b> @$safeUsername
📧 <b>Email:</b> $safeEmail
📞 <b>Phone / WhatsApp:</b> <code>$safePhone</code>
🆔 <b>User UUID:</b> <code>$userId</code>

📦 <b>Selected Plan:</b> <b>$planName</b>
💰 <b>Price:</b> <b>$planPrice</b>
🔗 <b>Referral Code:</b> <code>$safeRefCode</code>
👥 <b>Current Referrals:</b> <b>$refCount / 100</b>

📝 <b>Notes / Message:</b>
<i>$safeNotes</i>

📅 <b>Date:</b> $dateStr
⏰ <b>Time:</b> $timeStr
━━━━━━━━━━━━━━━━━━━━━━
⚡ <i>Action Required: Review details and verify payment on Admin Panel.</i>
''';

    return await _sendMessage(message);
  }

  /// Dispatches a notification when a user qualifies for Free Lifetime Blue via 100 referrals.
  static Future<bool> sendReferralMilestoneNotification({
    required String userId,
    required String username,
    required String fullName,
    required int totalReferrals,
  }) async {
    final safeFullName = _escapeHtml(fullName.trim());
    final safeUsername = _escapeHtml(username.trim());

    final message = '''
🎉 <b>100 REFERRALS REACHED - LIFETIME BLUE UNLOCKED!</b> 🎉
━━━━━━━━━━━━━━━━━━━━━━
👤 <b>Full Name:</b> $safeFullName
🔖 <b>Username:</b> @$safeUsername
🆔 <b>User UUID:</b> <code>$userId</code>
🏆 <b>Total Qualified Referrals:</b> <b>$totalReferrals / 100</b>

🌟 <b>Status:</b> Automatically eligible for Free Lifetime Blue Tick Accreditation!
━━━━━━━━━━━━━━━━━━━━━━
⚡ <i>Action: Please review and confirm badge activation in Admin Panel.</i>
''';

    return await _sendMessage(message);
  }

  /// Dispatches a high-priority Support Ticket / Bug Report notification to the Admin Telegram channel.
  static Future<bool> sendSupportTicketNotification({
    required String ticketId,
    required String userId,
    required String username,
    required String category,
    required String description,
    String? email,
  }) async {
    final now = DateTime.now().toUtc();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} UTC";

    final safeUsername = _escapeHtml(username.trim());
    final safeCategory = _escapeHtml(category.trim());
    final safeDesc = _escapeHtml(description.trim());
    final safeEmail = _escapeHtml(email?.trim() ?? 'Not provided');

    final message = '''
🛠 <b>NEW SUPPORT TICKET SUBMITTED</b> 🛠
━━━━━━━━━━━━━━━━━━━━━━
🎫 <b>Ticket ID:</b> <code>#$ticketId</code>
🔖 <b>User:</b> @$safeUsername
📧 <b>Contact Email:</b> $safeEmail
🆔 <b>User UUID:</b> <code>$userId</code>

📁 <b>Category / Topic:</b> <b>$safeCategory</b>
📅 <b>Reported At:</b> $dateStr

📝 <b>Issue Description:</b>
<i>$safeDesc</i>
━━━━━━━━━━━━━━━━━━━━━━
⚡ <i>Action: Please review and assist user if response is required.</i>
''';

    return await _sendMessage(message);
  }

  /// Core HTTP dispatch function with automatic failover between Bot 1 and Bot 2.
  static Future<bool> _sendMessage(String htmlText) async {
    final token1 = dotenv.env['NEXT_PUBLIC_TELEGRAM_BOT_TOKEN']?.isNotEmpty == true
        ? dotenv.env['NEXT_PUBLIC_TELEGRAM_BOT_TOKEN']!
        : _defaultBotToken1;

    final chatId = dotenv.env['NEXT_PUBLIC_TELEGRAM_CHAT_ID']?.isNotEmpty == true
        ? dotenv.env['NEXT_PUBLIC_TELEGRAM_CHAT_ID']!
        : _defaultChatId;

    final token2 = dotenv.env['NEXT_PUBLIC_TELEGRAM_BOT_TOKEN2']?.isNotEmpty == true
        ? dotenv.env['NEXT_PUBLIC_TELEGRAM_BOT_TOKEN2']!
        : _defaultBotToken2;

    // Attempt with Primary Bot
    bool sent = await _sendWithToken(token1, chatId, htmlText);
    if (!sent && token2.isNotEmpty && token2 != token1) {
      debugPrint("Primary Telegram Bot failed. Attempting with Secondary Bot...");
      sent = await _sendWithToken(token2, chatId, htmlText);
    }

    return sent;
  }

  static Future<bool> _sendWithToken(
    String token,
    String chatId,
    String htmlText,
  ) async {
    try {
      final url = Uri.parse("https://api.telegram.org/bot$token/sendMessage");
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': chatId,
              'text': htmlText,
              'parse_mode': 'HTML',
              'disable_web_page_preview': true,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint("Telegram notification dispatched successfully.");
        return true;
      } else {
        debugPrint(
          "Telegram dispatch error: ${response.statusCode} - ${response.body}",
        );
        return false;
      }
    } catch (e) {
      debugPrint("Telegram notification exception: $e");
      return false;
    }
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}

