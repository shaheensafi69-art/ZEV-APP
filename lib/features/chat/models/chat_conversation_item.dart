/// Data model representing a 1-on-1 or Group conversation in the ZEV Inbox.
class ChatConversationItem {
  final String conversationId;
  final bool isGroup;
  final String groupTitle;
  final String groupAvatar;
  final int memberCount;

  // 1:1 peer metadata (empty for group chats)
  final String peerId;
  final String peerUsername;
  final String peerFullName;
  final String peerAvatar;
  final bool isPeerVerified;
  final bool isPeerOnline;
  final String? peerNote;

  // Last message summary
  final String lastMessageId;
  final String lastMessageText;
  final String lastMessageType; // 'text', 'image', 'video', 'audio', 'file', 'post_share', 'reel_share', 'deleted', 'system'
  final String? lastAttachmentUrl;
  final String? lastAttachmentType;
  final String? lastSenderId;
  final String? lastSenderName;
  final bool isLastMessageMine;
  final bool isLastMessageDelivered;
  final bool isLastMessageRead;
  final DateTime lastMessageAt;

  // Conversation state
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final DateTime? mutedUntil;
  final bool isRequest;

  const ChatConversationItem({
    this.conversationId = '',
    this.isGroup = false,
    this.groupTitle = '',
    this.groupAvatar = '',
    this.memberCount = 2,
    required this.peerId,
    required this.peerUsername,
    this.peerFullName = '',
    this.peerAvatar = '',
    this.isPeerVerified = false,
    this.isPeerOnline = false,
    this.peerNote,
    required this.lastMessageId,
    required this.lastMessageText,
    this.lastMessageType = 'text',
    this.lastAttachmentUrl,
    this.lastAttachmentType,
    this.lastSenderId,
    this.lastSenderName,
    this.isLastMessageMine = false,
    this.isLastMessageDelivered = false,
    this.isLastMessageRead = true,
    required this.lastMessageAt,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.mutedUntil,
    this.isRequest = false,
  });

  /// Stable cache & routing key (`conversationId` when present, otherwise `peerId`).
  String get threadKey => conversationId.isNotEmpty ? conversationId : peerId;

  /// Human-friendly display title.
  String get displayTitle {
    if (isGroup) {
      return groupTitle.isNotEmpty ? groupTitle : 'Group Chat';
    }
    if (peerFullName.isNotEmpty) return peerFullName;
    return '@$peerUsername';
  }

  /// Subtitle handle / member summary.
  String get displayHandle {
    if (isGroup) return '$memberCount members';
    return '@$peerUsername';
  }

  String get displayAvatar => isGroup ? groupAvatar : peerAvatar;

  /// Status of the last outgoing message:
  /// - 'read': 2 blue ticks
  /// - 'delivered': 2 grey ticks
  /// - 'sent': 1 grey tick
  String get deliveryStatus {
    if (isLastMessageRead) return 'read';
    if (isLastMessageDelivered) return 'delivered';
    return 'sent';
  }

  ChatConversationItem copyWith({
    String? conversationId,
    bool? isGroup,
    String? groupTitle,
    String? groupAvatar,
    int? memberCount,
    String? peerId,
    String? peerUsername,
    String? peerFullName,
    String? peerAvatar,
    bool? isPeerVerified,
    bool? isPeerOnline,
    String? peerNote,
    String? lastMessageId,
    String? lastMessageText,
    String? lastMessageType,
    String? lastAttachmentUrl,
    String? lastAttachmentType,
    String? lastSenderId,
    String? lastSenderName,
    bool? isLastMessageMine,
    bool? isLastMessageDelivered,
    bool? isLastMessageRead,
    DateTime? lastMessageAt,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
    DateTime? mutedUntil,
    bool? isRequest,
  }) {
    return ChatConversationItem(
      conversationId: conversationId ?? this.conversationId,
      isGroup: isGroup ?? this.isGroup,
      groupTitle: groupTitle ?? this.groupTitle,
      groupAvatar: groupAvatar ?? this.groupAvatar,
      memberCount: memberCount ?? this.memberCount,
      peerId: peerId ?? this.peerId,
      peerUsername: peerUsername ?? this.peerUsername,
      peerFullName: peerFullName ?? this.peerFullName,
      peerAvatar: peerAvatar ?? this.peerAvatar,
      isPeerVerified: isPeerVerified ?? this.isPeerVerified,
      isPeerOnline: isPeerOnline ?? this.isPeerOnline,
      peerNote: peerNote ?? this.peerNote,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastAttachmentUrl: lastAttachmentUrl ?? this.lastAttachmentUrl,
      lastAttachmentType: lastAttachmentType ?? this.lastAttachmentType,
      lastSenderId: lastSenderId ?? this.lastSenderId,
      lastSenderName: lastSenderName ?? this.lastSenderName,
      isLastMessageMine: isLastMessageMine ?? this.isLastMessageMine,
      isLastMessageDelivered:
          isLastMessageDelivered ?? this.isLastMessageDelivered,
      isLastMessageRead: isLastMessageRead ?? this.isLastMessageRead,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      mutedUntil: mutedUntil ?? this.mutedUntil,
      isRequest: isRequest ?? this.isRequest,
    );
  }
}
