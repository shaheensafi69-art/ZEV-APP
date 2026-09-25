import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class TelegramOrderService {
  TelegramOrderService._();
  static final TelegramOrderService instance = TelegramOrderService._();

  String get botToken =>
      dotenv.env['NEXT_PUBLIC_TELEGRAM_BOT_TOKEN2'] ??
      '8994358206:AAHUpoHpMpqdnTxA_J30-xMipDg4l0vhBV8';

  String get chatId =>
      dotenv.env['NEXT_PUBLIC_TELEGRAM_CHAT_ID2'] ?? '5195615040';

  Future<bool> sendOrderNotification({
    required String orderId,
    required String productName,
    required double priceUsd,
    required String localPriceFormatted,
    required String paymentMethod,
    required String senderPhone,
    required String transactionReference,
    required String buyerName,
    required String buyerEmail,
    required String note,
  }) async {
    try {
      final token = botToken;
      final targetChat = chatId;
      if (token.isEmpty || targetChat.isEmpty) return false;

      final message = '''
🛍️ *New Order on ZEV Store*
━━━━━━━━━━━━━━━━━━━━
🆔 *Order ID:* `$orderId`
📦 *Product:* $productName
💰 *USD Price:* \$$priceUsd
💱 *Local Price:* $localPriceFormatted

💳 *Payment Method:* $paymentMethod
📱 *Phone / Account:* `$senderPhone`
🔖 *Transaction Ref:* `$transactionReference`

👤 *Buyer Name:* $buyerName
📧 *Buyer Email:* $buyerEmail
📝 *Notes:* ${note.isNotEmpty ? note : 'None'}
⏰ *Timestamp:* ${DateTime.now().toUtc().toString()}
━━━━━━━━━━━━━━━━━━━━
''';

      final url = Uri.parse('https://api.telegram.org/bot$token/sendMessage');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'chat_id': targetChat,
          'text': message,
          'parse_mode': 'Markdown',
        }),
      );

      debugPrint('[TelegramOrderService] Telegram response status: ${res.statusCode}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[TelegramOrderService] Failed to send Telegram alert: $e');
      return false;
    }
  }
}
