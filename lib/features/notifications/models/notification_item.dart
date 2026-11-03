/// Data model representing an activity / notification item in ZEV.
class NotificationItem {
  final String id;
  final String userId;
  final String senderId;
  final String senderUsername;
  final String senderFullName;
  final String senderAvatar;
  final bool isSenderVerified;
  final String title;
  final String message;
  final String notificationType; // 'follow' | 'like' | 'reel_like' | 'story_like' | 'comment' | 'repost'
  final String? linkUrl;
  final String? mediaThumbnail;
  final bool isRead;
  final DateTime createdAt;
  final bool isFollowingSender;

  const NotificationItem({
    required this.id,
    required this.userId,
    required this.senderId,
    required this.senderUsername,
    this.senderFullName = '',
    this.senderAvatar = '',
    this.isSenderVerified = false,
    required this.title,
    required this.message,
    required this.notificationType,
    this.linkUrl,
    this.mediaThumbnail,
    this.isRead = false,
    required this.createdAt,
    this.isFollowingSender = false,
  });

  NotificationItem copyWith({
    String? id,
    String? userId,
    String? senderId,
    String? senderUsername,
    String? senderFullName,
    String? senderAvatar,
    bool? isSenderVerified,
    String? title,
    String? message,
    String? notificationType,
    String? linkUrl,
    String? mediaThumbnail,
    bool? isRead,
    DateTime? createdAt,
    bool? isFollowingSender,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      senderId: senderId ?? this.senderId,
      senderUsername: senderUsername ?? this.senderUsername,
      senderFullName: senderFullName ?? this.senderFullName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      isSenderVerified: isSenderVerified ?? this.isSenderVerified,
      title: title ?? this.title,
      message: message ?? this.message,
      notificationType: notificationType ?? this.notificationType,
      linkUrl: linkUrl ?? this.linkUrl,
      mediaThumbnail: mediaThumbnail ?? this.mediaThumbnail,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      isFollowingSender: isFollowingSender ?? this.isFollowingSender,
    );
  }
}

