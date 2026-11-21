import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_session_manager.dart';
import '../../features/profile/screens/account_restriction_screen.dart';

/// Centralized service for tracking and enforcing account restrictions across ZEV.
///
/// Features disabled during an active restriction:
/// - Creating Feed Posts
/// - Sharing Stories
/// - Publishing Reels
/// - Following or Unfollowing accounts
class RestrictionService {
  RestrictionService._();
  static final RestrictionService instance = RestrictionService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  AccountAccessResult? _cachedStanding;
  DateTime? _lastFetchTime;
  static const Duration _cacheTtl = Duration(seconds: 15);

  /// Clears in-memory standing cache (e.g. after restriction change or appeal).
  void invalidateCache() {
    _cachedStanding = null;
    _lastFetchTime = null;
  }

  /// Retrieves the current signed-in user's standing and restriction status.
  /// Automatically detects if a restriction period has expired and clears it.
  Future<AccountAccessResult> getStanding({bool forceRefresh = false}) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      return const AccountAccessResult(status: AccountStandingStatus.unauthenticated);
    }

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedStanding != null &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!) < _cacheTtl) {
      return _cachedStanding!;
    }

    try {
      final row = await _supabase
          .from('profiles')
          .select(
            'is_banned, banned_until, ban_reason, is_restricted, restricted_until, restriction_reason, account_status, warning_count',
          )
          .eq('id', currentUserId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (row == null) {
        final res = const AccountAccessResult(status: AccountStandingStatus.active);
        _cachedStanding = res;
        _lastFetchTime = now;
        return res;
      }

      final nowUtc = DateTime.now().toUtc();
      final restrictedUntilRaw = row['restricted_until']?.toString();
      final restrictedUntil = restrictedUntilRaw != null
          ? DateTime.tryParse(restrictedUntilRaw)?.toUtc()
          : null;

      final isRestrictedFlag = row['is_restricted'] == true;
      bool isRestrictionActive = false;

      if (isRestrictedFlag) {
        if (restrictedUntil == null) {
          // Indefinite restriction
          isRestrictionActive = true;
        } else if (restrictedUntil.isAfter(nowUtc)) {
          // Time-bound restriction still active
          isRestrictionActive = true;
        } else {
          // Restriction has expired! Automatically lift in background
          isRestrictionActive = false;
          unawaited(_liftExpiredRestriction(currentUserId));
        }
      }

      final res = AccountAccessResult(
        status: AccountStandingStatus.active,
        userId: currentUserId,
        isRestricted: isRestrictionActive,
        restrictedUntil: restrictedUntil,
        restrictionReason: row['restriction_reason']?.toString(),
      );

      _cachedStanding = res;
      _lastFetchTime = now;
      return res;
    } catch (e) {
      debugPrint('[RestrictionService] Fetch error: $e');
      return _cachedStanding ??
          const AccountAccessResult(status: AccountStandingStatus.active);
    }
  }

  /// Quickly checks whether the current user is restricted.
  Future<bool> isRestricted({bool forceRefresh = false}) async {
    final standing = await getStanding(forceRefresh: forceRefresh);
    return standing.isRestricted;
  }

  /// Automatically clears expired restriction in database.
  Future<void> _liftExpiredRestriction(String userId) async {
    try {
      await _supabase
          .from('profiles')
          .update({
            'is_restricted': false,
            'restricted_until': null,
          })
          .eq('id', userId);
      debugPrint('[RestrictionService] Expired restriction lifted automatically for $userId');
    } catch (e) {
      debugPrint('[RestrictionService] Failed to auto-lift expired restriction: $e');
    }
  }

  /// Checks if the user is restricted. If so, opens [AccountRestrictionScreen]
  /// and returns `false`. If unrestricted, returns `true`.
  Future<bool> checkAndEnforce(
    BuildContext context, {
    String actionName = 'perform this action',
  }) async {
    final standing = await getStanding(forceRefresh: true);
    if (!standing.isRestricted) {
      return true;
    }

    if (context.mounted) {
      await AccountRestrictionScreen.open(
        context,
        actionAttempted: actionName,
        standing: standing,
      );
    }
    return false;
  }

  /// Displays an in-app snackbar alert informing the user that the action is blocked.
  void showRestrictionToast(
    BuildContext context, {
    String actionName = 'This action',
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.gpp_bad_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$actionName is currently disabled while your account is restricted.',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        action: SnackBarAction(
          label: 'Details',
          textColor: Colors.white,
          onPressed: () {
            AccountRestrictionScreen.open(context);
          },
        ),
      ),
    );
  }
}
