import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Comprehensive Specification and Registry for ZEV Cross-Platform Notification Channels.
/// Supports Samsung One UI, Xiaomi HyperOS, Google Pixel, and iOS 15-18 notification standards.
enum ZevNotificationCategoryType {
  messages,
  voiceCalls,
  videoCalls,
  likes,
  comments,
  followers,
  friendRequests,
  stories,
  shares,
  groups,
  security,
  general,
}

class ZevNotificationChannelConfig {
  final ZevNotificationCategoryType type;
  final String channelId;
  final String channelName;
  final String channelDescription;
  final Importance importance;
  final Priority priority;
  final String smallIcon;
  final String groupKey;
  final String darwinCategory;
  final AudioAttributesUsage? audioAttributesUsage;
  final AndroidNotificationCategory? androidCategory;
  final bool fullScreenIntent;

  const ZevNotificationChannelConfig({
    required this.type,
    required this.channelId,
    required this.channelName,
    required this.channelDescription,
    required this.importance,
    required this.priority,
    required this.smallIcon,
    required this.groupKey,
    required this.darwinCategory,
    this.audioAttributesUsage,
    this.androidCategory,
    this.fullScreenIntent = false,
  });

  AndroidNotificationChannel toAndroidChannel() {
    return AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: importance,
      enableVibration: true,
      playSound: true,
      audioAttributesUsage: audioAttributesUsage ?? AudioAttributesUsage.notification,
    );
  }
}

class ZevNotificationChannels {
  ZevNotificationChannels._();

  static const ZevNotificationChannelConfig messages = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.messages,
    channelId: 'zev_channel_messages',
    channelName: 'Direct Messages & Chats',
    channelDescription: 'Incoming direct messages, replies, and conversation threads.',
    importance: Importance.max,
    priority: Priority.high,
    smallIcon: '@drawable/ic_notif_message',
    groupKey: 'com.zevapp.app.MESSAGES',
    darwinCategory: 'zev_category_message',
    androidCategory: AndroidNotificationCategory.message,
  );

  static const ZevNotificationChannelConfig voiceCalls = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.voiceCalls,
    channelId: 'zev_channel_voice_calls',
    channelName: 'Incoming Voice Calls',
    channelDescription: 'High-priority incoming voice call alerts and ringing notifications.',
    importance: Importance.max,
    priority: Priority.max,
    smallIcon: '@drawable/ic_notif_call',
    groupKey: 'com.zevapp.app.CALLS',
    darwinCategory: 'zev_category_call',
    audioAttributesUsage: AudioAttributesUsage.voiceCommunication,
    androidCategory: AndroidNotificationCategory.call,
    fullScreenIntent: true,
  );

  static const ZevNotificationChannelConfig videoCalls = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.videoCalls,
    channelId: 'zev_channel_video_calls',
    channelName: 'Incoming Video Calls',
    channelDescription: 'High-priority incoming video call alerts and ringing notifications.',
    importance: Importance.max,
    priority: Priority.max,
    smallIcon: '@drawable/ic_notif_video',
    groupKey: 'com.zevapp.app.CALLS',
    darwinCategory: 'zev_category_call',
    audioAttributesUsage: AudioAttributesUsage.voiceCommunication,
    androidCategory: AndroidNotificationCategory.call,
    fullScreenIntent: true,
  );

  static const ZevNotificationChannelConfig likes = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.likes,
    channelId: 'zev_channel_likes',
    channelName: 'Likes & Reactions',
    channelDescription: 'Notifications when someone likes your post, reel, or story.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    smallIcon: '@drawable/ic_notif_like',
    groupKey: 'com.zevapp.app.LIKES',
    darwinCategory: 'zev_category_social',
    androidCategory: AndroidNotificationCategory.social,
  );

  static const ZevNotificationChannelConfig comments = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.comments,
    channelId: 'zev_channel_comments',
    channelName: 'Comments & Replies',
    channelDescription: 'Comments on your posts, reels, and replies to your comments.',
    importance: Importance.high,
    priority: Priority.high,
    smallIcon: '@drawable/ic_notif_comment',
    groupKey: 'com.zevapp.app.COMMENTS',
    darwinCategory: 'zev_category_comment',
    androidCategory: AndroidNotificationCategory.social,
  );

  static const ZevNotificationChannelConfig followers = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.followers,
    channelId: 'zev_channel_followers',
    channelName: 'New Followers',
    channelDescription: 'Alerts when someone starts following your ZEV profile.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    smallIcon: '@drawable/ic_notif_follower',
    groupKey: 'com.zevapp.app.FOLLOWERS',
    darwinCategory: 'zev_category_social',
    androidCategory: AndroidNotificationCategory.social,
  );

  static const ZevNotificationChannelConfig friendRequests = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.friendRequests,
    channelId: 'zev_channel_friend_requests',
    channelName: 'Friend Requests',
    channelDescription: 'Friend requests and contact connection invitations.',
    importance: Importance.high,
    priority: Priority.high,
    smallIcon: '@drawable/ic_notif_friend',
    groupKey: 'com.zevapp.app.FRIENDS',
    darwinCategory: 'zev_category_friend_request',
    androidCategory: AndroidNotificationCategory.social,
  );

  static const ZevNotificationChannelConfig stories = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.stories,
    channelId: 'zev_channel_stories',
    channelName: 'Stories & Mentions',
    channelDescription: 'Story tags, mentions, and updates from people you follow.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    smallIcon: '@drawable/ic_notif_story',
    groupKey: 'com.zevapp.app.STORIES',
    darwinCategory: 'zev_category_social',
    androidCategory: AndroidNotificationCategory.social,
  );

  static const ZevNotificationChannelConfig shares = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.shares,
    channelId: 'zev_channel_shares',
    channelName: 'Shares & Forwards',
    channelDescription: 'When other users share your posts, reels, or profile.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    smallIcon: '@drawable/ic_notif_share',
    groupKey: 'com.zevapp.app.SHARES',
    darwinCategory: 'zev_category_social',
    androidCategory: AndroidNotificationCategory.social,
  );

  static const ZevNotificationChannelConfig groups = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.groups,
    channelId: 'zev_channel_groups',
    channelName: 'Group Chats & Communities',
    channelDescription: 'Conversations, mentions, and activity from group chats.',
    importance: Importance.high,
    priority: Priority.high,
    smallIcon: '@drawable/ic_notif_group',
    groupKey: 'com.zevapp.app.GROUPS',
    darwinCategory: 'zev_category_message',
    androidCategory: AndroidNotificationCategory.message,
  );

  static const ZevNotificationChannelConfig security = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.security,
    channelId: 'zev_channel_security',
    channelName: 'Account & Security Alerts',
    channelDescription: 'Critical login alerts, password changes, and account notices.',
    importance: Importance.max,
    priority: Priority.max,
    smallIcon: '@drawable/ic_notif_security',
    groupKey: 'com.zevapp.app.SECURITY',
    darwinCategory: 'zev_category_social',
    androidCategory: AndroidNotificationCategory.status,
  );

  static const ZevNotificationChannelConfig general = ZevNotificationChannelConfig(
    type: ZevNotificationCategoryType.general,
    channelId: 'zev_notifications_channel',
    channelName: 'General Activity & Announcements',
    channelDescription: 'General platform activity, announcements, and milestones.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    smallIcon: '@drawable/ic_notification',
    groupKey: 'com.zevapp.app.GENERAL',
    darwinCategory: 'zev_category_social',
    androidCategory: AndroidNotificationCategory.social,
  );

  static const List<ZevNotificationChannelConfig> all = [
    messages,
    voiceCalls,
    videoCalls,
    likes,
    comments,
    followers,
    friendRequests,
    stories,
    shares,
    groups,
    security,
    general,
  ];

  /// Resolves the dedicated channel configuration given a raw notification type string.
  static ZevNotificationChannelConfig resolve(String rawType) {
    final t = rawType.toLowerCase().trim();
    if (t == 'voice_call') return voiceCalls;
    if (t == 'video_call') return videoCalls;
    if (t == 'message' ||
        t == 'chat' ||
        t == 'direct_message' ||
        t == 'dm' ||
        t.contains('chat')) {
      return messages;
    }
    if (t == 'group_message' ||
        t == 'group_chat' ||
        t == 'group_invitation' ||
        t.contains('group')) {
      return groups;
    }
    if (t.contains('like')) return likes;
    if (t.contains('comment') || t.contains('reply')) return comments;
    if (t == 'friend_request' || t == 'follow_request') return friendRequests;
    if (t.contains('follow')) return followers;
    if (t.contains('story') || t.contains('mention') || t.contains('tag')) {
      return stories;
    }
    if (t.contains('share') || t.contains('repost')) return shares;
    if (t.contains('security') ||
        t.contains('login') ||
        t.contains('password') ||
        t.contains('verify') ||
        t.contains('auth')) {
      return security;
    }
    return general;
  }
}
