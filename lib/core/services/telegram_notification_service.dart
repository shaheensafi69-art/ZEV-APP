import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';

class SupportTicketResult {
  final bool ok;
  final String? ticketId;
  final String? dbId;
  final String? error;

  const SupportTicketResult({
    required this.ok,
    this.ticketId,
    this.dbId,
    this.error,
  });
}

class VerificationRequestResult {
  final bool ok;
  final String? error;
  final bool preservedExistingActiveSubscription;

  const VerificationRequestResult({
    required this.ok,
    this.error,
    this.preservedExistingActiveSubscription = false,
  });
}

/// Administrative & Support Dispatch Service routed strictly through `zev-web`
/// server endpoints (`/api/v1/verification/request` and `/api/v1/support/ticket`).
/// Zero Telegram bot tokens or chat IDs exist in client code.
class TelegramNotificationService {
  TelegramNotificationService._();

  /// Submits a ZEV Blue Verification subscription request cleanly via the server.
  static Future<VerificationRequestResult> submitVerificationOrder({
    required String fullName,
    required String phone,
    required String planKey,
    required String planName,
    required String planPrice,
    double? numericAmount,
    String? email,
    String? notes,
    String? paymentMethod,
  }) async {
    try {
      final res = await ApiClient.instance.post(
        '/api/v1/verification/request',
        data: {
          'mode': 'subscription',
          'fullName': fullName.trim(),
          'phone': phone.trim(),
          'planKey': planKey.trim().toLowerCase(),
          'planName': planName,
          'planPrice': planPrice,
          'numericAmount': ?numericAmount,
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
          if (paymentMethod != null && paymentMethod.trim().isNotEmpty)
            'paymentMethod': paymentMethod.trim(),
        },
      );

      return VerificationRequestResult(
        ok: res['ok'] == true,
        preservedExistingActiveSubscription:
            res['preservedExistingActiveSubscription'] == true,
      );
    } on ApiException catch (e) {
      return VerificationRequestResult(ok: false, error: e.message);
    } catch (e) {
      return VerificationRequestResult(ok: false, error: e.toString());
    }
  }

  /// Backwards-compatible helper delegating to [submitVerificationOrder].
  static Future<bool> sendVerificationOrderNotification({
    required String userId,
    required String username,
    required String fullName,
    required String phone,
    required String planName,
    required String planPrice,
    String planKey = 'monthly',
    double? numericAmount,
    String? email,
    String? notes,
    String? paymentMethod,
    String? referralCode,
    int? currentReferrals,
  }) async {
    final result = await submitVerificationOrder(
      fullName: fullName,
      phone: phone,
      planKey: planKey,
      planName: planName,
      planPrice: planPrice,
      numericAmount: numericAmount,
      email: email,
      notes: notes,
      paymentMethod: paymentMethod,
    );
    return result.ok;
  }

  /// Claims a 100-referral Lifetime ZEV Blue milestone securely via the server.
  static Future<bool> sendReferralMilestoneNotification({
    required String userId,
    required String username,
    required String fullName,
    required int totalReferrals,
  }) async {
    try {
      final res = await ApiClient.instance.post(
        '/api/v1/verification/request',
        data: {
          'mode': 'referral_milestone',
          'fullName': fullName.trim(),
        },
      );
      return res['ok'] == true;
    } catch (e) {
      debugPrint('[TelegramNotificationService] milestone notice: $e');
      return false;
    }
  }

  /// Submits a persistent support ticket to `user_support_tickets` + Admin Telegram.
  static Future<SupportTicketResult> submitSupportTicket({
    required String category,
    required String description,
    String? subject,
    String? email,
    String? phone,
  }) async {
    try {
      final res = await ApiClient.instance.post(
        '/api/v1/support/ticket',
        data: {
          'category': category.trim(),
          'subject': (subject ?? category).trim(),
          'description': description.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      );

      return SupportTicketResult(
        ok: res['ok'] == true,
        ticketId: res['ticketId']?.toString(),
        dbId: res['id']?.toString(),
      );
    } on ApiException catch (e) {
      return SupportTicketResult(ok: false, error: e.message);
    } catch (e) {
      return SupportTicketResult(ok: false, error: e.toString());
    }
  }

  /// Backwards-compatible helper delegating to [submitSupportTicket].
  static Future<bool> sendSupportTicketNotification({
    required String ticketId,
    required String userId,
    required String username,
    required String category,
    required String description,
    String? email,
  }) async {
    final res = await submitSupportTicket(
      category: category,
      description: description,
      email: email,
    );
    return res.ok;
  }

  /// Dispatches instant Telegram notification to admins whenever a creator requests a payout.
  /// Broadcasts across all active bot tokens and chat IDs configured in Supabase.
  static Future<bool> sendPayoutRequestNotification({
    required String requestId,
    required String userId,
    required String username,
    required String fullName,
    required int coinsDeducted,
    required double amountUsd,
    required String targetCurrency,
    required double amountTargetCurrency,
    required String payoutMethod,
    required String destinationAccount,
    required Map<String, dynamic> accountDetails,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      // 1. Fetch active payout bot tokens (with default fallback to primary bot token)
      List<String> tokens = ['9230056079:AAF-BC37YODbYF-EyK_f2ImYm2dEWw32x6w'];
      try {
        final configs = await supabase
            .from('telegram_bot_configs')
            .select('bot_token')
            .eq('bot_type', 'payout_bot')
            .eq('is_active', true);
        if (configs.isNotEmpty) {
          final fetched = configs
              .map((c) => (c['bot_token'] ?? '').toString().trim())
              .where((t) => t.isNotEmpty)
              .toList();
          if (fetched.isNotEmpty) tokens = fetched;
        }
      } catch (e) {
        debugPrint('[Telegram Payout] DB config fetch fallback: $e');
      }

      // 2. Fetch active subscriber chat IDs
      List<String> chatIds = [];
      try {
        final subs = await supabase
            .from('telegram_bot_subscribers')
            .select('chat_id')
            .eq('bot_type', 'payout_bot')
            .eq('is_active', true);
        if (subs.isNotEmpty) {
          chatIds = subs
              .map((s) => (s['chat_id'] ?? '').toString().trim())
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList();
        }
      } catch (e) {
        debugPrint('[Telegram Payout] DB subscriber fetch fallback: $e');
      }

      // 3. Fallback: Check getUpdates on the bot if no chat IDs exist yet
      if (chatIds.isEmpty) {
        for (final token in tokens) {
          try {
            final uri = Uri.parse('https://api.telegram.org/bot$token/getUpdates?offset=-10');
            final resp = await http.get(uri);
            if (resp.statusCode == 200) {
              final json = jsonDecode(resp.body);
              if (json['ok'] == true && json['result'] is List) {
                for (final upd in json['result']) {
                  final msg = upd['message'] ?? upd['channel_post'];
                  final cid = msg?['chat']?['id']?.toString();
                  if (cid != null && !chatIds.contains(cid)) {
                    chatIds.add(cid);
                    // Save to DB
                    await supabase.from('telegram_bot_subscribers').upsert({
                      'bot_type': 'payout_bot',
                      'chat_id': cid,
                      'username': msg?['chat']?['username'] ?? msg?['from']?['username'],
                      'first_name': msg?['chat']?['first_name'] ?? msg?['from']?['first_name'] ?? 'Admin',
                      'is_active': true,
                    }, onConflict: 'bot_type,chat_id');
                  }
                }
              }
            }
          } catch (_) {}
        }
      }

      // Format details nicely
      final methodTitle = payoutMethod.toUpperCase();
      final nowStr = '${DateTime.now().toUtc().toString().split('.').first} UTC';

      String specificDetails = '';
      if (payoutMethod == 'hesabpay') {
        final phone = accountDetails['phone_number'] ?? destinationAccount;
        final name = accountDetails['account_name'] ?? fullName;
        specificDetails = '📱 <b>HesabPay Phone:</b> <code>$phone</code>\n'
            '👤 <b>Account Name:</b> $name';
      } else if (payoutMethod == 'crypto') {
        final net = accountDetails['network'] ?? 'TRC-20';
        final memo = accountDetails['memo_tag'];
        specificDetails = '⛓ <b>Network:</b> <b>$net</b>\n'
            '💼 <b>Wallet Address:</b> <code>$destinationAccount</code>'
            '${memo != null && memo.toString().isNotEmpty ? '\n🏷 <b>Memo/Tag:</b> <code>$memo</code>' : ''}';
      } else if (payoutMethod == 'bank') {
        final region = (accountDetails['region'] ?? 'Europe').toString().toUpperCase();
        final bankName = accountDetails['bank_name'] ?? 'Bank';
        final holder = accountDetails['account_holder'] ?? fullName;
        final iban = accountDetails['iban'] ?? destinationAccount;
        final swift = accountDetails['swift_bic'];
        final routing = accountDetails['routing_number'];
        specificDetails = '🌍 <b>Region:</b> $region\n'
            '🏦 <b>Bank Name:</b> $bankName\n'
            '👤 <b>Holder:</b> $holder\n'
            '💳 <b>IBAN / Account:</b> <code>$iban</code>'
            '${swift != null && swift.toString().isNotEmpty ? '\n🌐 <b>SWIFT/BIC:</b> <code>$swift</code>' : ''}'
            '${routing != null && routing.toString().isNotEmpty ? '\n🔢 <b>Routing/Sort:</b> <code>$routing</code>' : ''}';
      } else if (payoutMethod == 'paypal') {
        final email = accountDetails['email'] ?? destinationAccount;
        specificDetails = '📧 <b>PayPal Email:</b> <code>$email</code>';
      } else {
        specificDetails = '📌 <b>Destination:</b> <code>$destinationAccount</code>';
      }

      final message = '🚨 <b>NEW PAYOUT REQUEST</b> 🚨\n'
          '━━━━━━━━━━━━━━━━━━━━━\n'
          '👤 <b>User:</b> $fullName (@$username)\n'
          '🆔 <b>User ID:</b> <code>$userId</code>\n'
          '🪙 <b>Coins Redeemed:</b> <b>${coinsDeducted.toString()} Coins</b>\n'
          '💵 <b>USD Value:</b> <b>\$${amountUsd.toStringAsFixed(2)} USD</b>\n'
          '🎯 <b>Payout Amount:</b> <b>${amountTargetCurrency.toStringAsFixed(2)} $targetCurrency</b>\n'
          '💳 <b>Method:</b> <b>$methodTitle</b>\n'
          '$specificDetails\n'
          '🧾 <b>Request ID:</b> <code>$requestId</code>\n'
          '⏱ <b>Time:</b> $nowStr\n'
          '━━━━━━━━━━━━━━━━━━━━━\n'
          '⏳ <b>Status:</b> <b>PENDING ADMIN DISPATCH</b>';

      // Send to each token and chat ID
      for (final token in tokens) {
        for (final cid in chatIds) {
          try {
            await http.post(
              Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'chat_id': cid,
                'text': message,
                'parse_mode': 'HTML',
                'disable_web_page_preview': true,
              }),
            );
          } catch (sendErr) {
            debugPrint('[Telegram Send Err] $sendErr');
          }
        }
      }
      return true;
    } catch (e) {
      debugPrint('[Telegram Payout Error] $e');
      return false;
    }
  }
}
