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
  final String notificationType; // 'follow' | 'like' | 'post_like' | 'reel_like' | 'comment' | 'post_comment' | 'reel_comment' | 'mention' | 'repost' | 'system'
  final String? linkUrl;
  final String? mediaThumbnail;
  final bool isRead;
  final DateTime createdAt;
  final bool isFollowingSender;
  final String? additionalText; // e.g. comment text or post excerpt

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
    this.additionalText,
  });

  bool get isLike =>
      notificationType.contains('like');

  bool get isComment =>
      notificationType.contains('comment') || notificationType.contains('reply');

  bool get isFollow =>
      notificationType == 'follow';

  bool get isMention =>
      notificationType.contains('mention') || notificationType.contains('tag');

  bool get isReel =>
      notificationType.contains('reel');

  bool get isSystem =>
      notificationType == 'system' ||
      notificationType == 'milestone' ||
      notificationType == 'welcome' ||
      notificationType == 'verified';

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
    String? additionalText,
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
      additionalText: additionalText ?? this.additionalText,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'senderId': senderId,
      'senderUsername': senderUsername,
      'senderFullName': senderFullName,
      'senderAvatar': senderAvatar,
      'isSenderVerified': isSenderVerified,
      'title': title,
      'message': message,
      'notificationType': notificationType,
      'linkUrl': linkUrl,
      'mediaThumbnail': mediaThumbnail,
      'isRead': isRead,
      'createdAt': createdAt.toIso8601String(),
      'isFollowingSender': isFollowingSender,
      'additionalText': additionalText,
    };
  }

  factory NotificationItem.fromMap(Map<String, dynamic> map) {
    return NotificationItem(
      id: map['id']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      senderId: map['senderId']?.toString() ?? '',
      senderUsername: map['senderUsername']?.toString() ?? 'user',
      senderFullName: map['senderFullName']?.toString() ?? '',
      senderAvatar: map['senderAvatar']?.toString() ?? '',
      isSenderVerified: map['isSenderVerified'] == true,
      title: map['title']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      notificationType: map['notificationType']?.toString() ?? 'like',
      linkUrl: map['linkUrl']?.toString(),
      mediaThumbnail: map['mediaThumbnail']?.toString(),
      isRead: map['isRead'] == true,
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      isFollowingSender: map['isFollowingSender'] == true,
      additionalText: map['additionalText']?.toString(),
    );
  }
}
