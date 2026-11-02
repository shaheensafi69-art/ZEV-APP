/// Lightweight and reliable time-ago formatter.
class TimeAgo {
  TimeAgo._();

  static String format(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 45) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '${minutes}m ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '${hours}h ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '${days}d ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '${months}mo ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '${years}y ago';
    }
  }

  static String fromIsoString(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final parsed = DateTime.parse(iso).toLocal();
      return format(parsed);
    } catch (_) {
      return '';
    }
  }
}
