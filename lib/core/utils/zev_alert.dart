import 'package:flutter/material.dart';

class ZevAlert {
  /// Transforms raw technical system exceptions into friendly human messages
  static String humanizeError(dynamic error) {
    if (error == null) return "An unexpected error occurred. Please try again.";
    final raw = error.toString();

    if (raw.contains('FragmentActivity') || raw.contains('uiUnavailable')) {
      return "Biometric service is preparing. Please restart the app or use your PIN.";
    }
    if (raw.contains('SocketException') ||
        raw.contains('Failed host lookup') ||
        raw.contains('Network is unreachable') ||
        raw.contains('ClientException')) {
      return "Network connection issue. Please check your internet connection.";
    }
    if (raw.contains('Invalid login credentials') ||
        raw.contains('invalid_grant')) {
      return "Incorrect email or password. Please check and try again.";
    }
    if (raw.contains('User already registered')) {
      return "This email is already registered. Please sign in or use another email.";
    }
    if (raw.contains('Password should be')) {
      return "Password must be at least 6 characters long.";
    }
    if (raw.contains('JWT') ||
        raw.contains('token') ||
        raw.contains('expired')) {
      return "Session expired. Please sign in again.";
    }
    if (raw.contains('not_found') || raw.contains('PGRST116')) {
      return "Requested item could not be found.";
    }
    if (raw.contains('TimeoutException') || raw.contains('timed out')) {
      return "Connection timed out. Please try again.";
    }
    if (raw.contains('permission') || raw.contains('PermissionDenied')) {
      return "Permission required to complete this action.";
    }

    // Clean out typical class prefixes like 'Exception: ', 'AuthException: ', etc.
    String cleaned = raw
        .replaceAll(RegExp(r'^[A-Za-z0-9_]*Exception:\s*'), '')
        .replaceAll(RegExp(r'^[A-Za-z0-9_]*Error:\s*'), '')
        .replaceAll(RegExp(r'AuthRetryableFetchException:\s*'), '')
        .replaceAll(RegExp(r'PostgrestException\([^)]*\):\s*'), '')
        .trim();

    if (cleaned.isEmpty || cleaned.contains('{') || cleaned.contains('code:')) {
      return "An unexpected issue occurred. Please try again shortly.";
    }

    // Capitalize first letter
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  /// Displays an elegant, premium 5-second popup banner floating above the navigation bar
  static void show(
    BuildContext context,
    dynamic messageOrError, {
    bool isError = true,
    String? title,
    IconData? icon,
    Duration duration = const Duration(seconds: 5),
  }) {
    if (!context.mounted) return;

    final String message = isError
        ? humanizeError(messageOrError)
        : messageOrError.toString();

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.hideCurrentSnackBar();

    scaffoldMessenger.showSnackBar(
      SnackBar(
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(
          16,
          0,
          16,
          96,
        ), // Positioned smoothly above bottom bar
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isError ? const Color(0xFF1E1E24) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isError
                  ? const Color(0xFFFC466B).withValues(alpha: 0.4)
                  : const Color(0xFF10B981).withValues(alpha: 0.4),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isError
                      ? const Color(0xFFFC466B).withValues(alpha: 0.15)
                      : const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon ??
                      (isError
                          ? Icons.info_outline_rounded
                          : Icons.check_circle_outline_rounded),
                  color: isError
                      ? const Color(0xFFFC466B)
                      : const Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null && title.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Color(0xFFF1F5F9),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Convenience method for success messages
  static void success(BuildContext context, String message, {String? title}) {
    show(
      context,
      message,
      isError: false,
      title: title,
      icon: Icons.check_circle_rounded,
    );
  }

  /// Convenience method for errors
  static void error(BuildContext context, dynamic err, {String? title}) {
    show(
      context,
      err,
      isError: true,
      title: title,
      icon: Icons.error_outline_rounded,
    );
  }
}
