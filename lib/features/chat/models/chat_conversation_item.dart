/// Data model representing a 1-on-1 direct message conversation in ZEV.
class ChatConversationItem {
  final String peerId;
  final String peerUsername;
  final String peerFullName;
  final String peerAvatar;
  final bool isPeerVerified;
  final bool isPeerOnline;
  final String lastMessageId;
  final String lastMessageText;
  final String? lastAttachmentUrl;
  final String? lastAttachmentType;
  final bool isLastMessageMine;
  final bool isLastMessageDelivered;
  final bool isLastMessageRead;
  final DateTime lastMessageAt;
  final int unreadCount;
  final String? peerNote;

  const ChatConversationItem({
    required this.peerId,
    required this.peerUsername,
    this.peerFullName = '',
    this.peerAvatar = '',
    this.isPeerVerified = false,
    this.isPeerOnline = false,
    required this.lastMessageId,
    required this.lastMessageText,
    this.lastAttachmentUrl,
    this.lastAttachmentType,
    this.isLastMessageMine = false,
    this.isLastMessageDelivered = false,
    this.isLastMessageRead = true,
    required this.lastMessageAt,
    this.unreadCount = 0,
    this.peerNote,
  });

  ChatConversationItem copyWith({
    String? peerId,
    String? peerUsername,
    String? peerFullName,
    String? peerAvatar,
    bool? isPeerVerified,
    bool? isPeerOnline,
    String? lastMessageId,
    String? lastMessageText,
    String? lastAttachmentUrl,
    String? lastAttachmentType,
    bool? isLastMessageMine,
    bool? isLastMessageDelivered,
    bool? isLastMessageRead,
    DateTime? lastMessageAt,
    int? unreadCount,
    String? peerNote,
  }) {
    return ChatConversationItem(
      peerId: peerId ?? this.peerId,
      peerUsername: peerUsername ?? this.peerUsername,
      peerFullName: peerFullName ?? this.peerFullName,
      peerAvatar: peerAvatar ?? this.peerAvatar,
      isPeerVerified: isPeerVerified ?? this.isPeerVerified,
      isPeerOnline: isPeerOnline ?? this.isPeerOnline,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastAttachmentUrl: lastAttachmentUrl ?? this.lastAttachmentUrl,
      lastAttachmentType: lastAttachmentType ?? this.lastAttachmentType,
      isLastMessageMine: isLastMessageMine ?? this.isLastMessageMine,
      isLastMessageDelivered:
          isLastMessageDelivered ?? this.isLastMessageDelivered,
      isLastMessageRead: isLastMessageRead ?? this.isLastMessageRead,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      peerNote: peerNote ?? this.peerNote,
    );
  }
}
