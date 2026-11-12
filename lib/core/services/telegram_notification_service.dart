import 'package:flutter/foundation.dart';

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
}
