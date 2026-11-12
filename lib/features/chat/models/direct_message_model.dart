/// Data model representing a single direct or group message in ZEV.
/// Mirrors `public.direct_messages` plus client-side offline outbox state.
class DirectMessageModel {
  final String id;
  final String? conversationId;
  final String senderId;
  final String receiverId; // Empty string for group messages
  final String messageText;
  final String messageType; // 'text', 'image', 'video', 'audio', 'file', 'post_share', 'reel_share'
  final String? attachmentUrl;
  final String? attachmentType; // 'image', 'video', 'audio', 'file'
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? replyToMessageId;
  final String? forwardedFromId;
  final bool isDelivered;
  final bool isRead;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final List<String> deletedForUserIds;
  final DateTime createdAt;

  // Client-only offline queue / retry metadata
  final String localSendState; // 'sending' | 'sent' | 'failed'
  final String? localFilePath;
  final String? localError;

  const DirectMessageModel({
    required this.id,
    this.conversationId,
    required this.senderId,
    this.receiverId = '',
    required this.messageText,
    this.messageType = 'text',
    this.attachmentUrl,
    this.attachmentType,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.replyToMessageId,
    this.forwardedFromId,
    this.isDelivered = false,
    this.isRead = false,
    this.deliveredAt,
    this.readAt,
    this.editedAt,
    this.deletedAt,
    this.deletedForUserIds = const [],
    required this.createdAt,
    this.localSendState = 'sent',
    this.localFilePath,
    this.localError,
  });

  bool isMine(String currentUserId) => senderId == currentUserId;
  bool get isDeletedForEveryone => deletedAt != null;
  bool isDeletedForUser(String userId) => deletedForUserIds.contains(userId);
  bool get isEdited => editedAt != null;
  bool get isForwarded => forwardedFromId != null && forwardedFromId!.isNotEmpty;
  bool get isPending => localSendState == 'sending';
  bool get isFailed => localSendState == 'failed';

  /// Effective media/content kind.
  String get effectiveType {
    if (isDeletedForEveryone) return 'deleted';
    if (attachmentType != null && attachmentType!.isNotEmpty) {
      return attachmentType!;
    }
    return messageType.isNotEmpty ? messageType : 'text';
  }

  /// Delivery status helper:
  /// - 'failed': failed offline send
  /// - 'sending': currently queued / uploading
  /// - 'read': 2 blue/bright ticks
  /// - 'delivered': 2 grey ticks
  /// - 'sent': 1 grey tick
  String get status {
    if (isFailed) return 'failed';
    if (isPending) return 'sending';
    if (isRead) return 'read';
    if (isDelivered) return 'delivered';
    return 'sent';
  }

  DirectMessageModel copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? receiverId,
    String? messageText,
    String? messageType,
    String? attachmentUrl,
    String? attachmentType,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? replyToMessageId,
    String? forwardedFromId,
    bool? isDelivered,
    bool? isRead,
    DateTime? deliveredAt,
    DateTime? readAt,
    DateTime? editedAt,
    DateTime? deletedAt,
    List<String>? deletedForUserIds,
    DateTime? createdAt,
    String? localSendState,
    String? localFilePath,
    String? localError,
  }) {
    return DirectMessageModel(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      messageText: messageText ?? this.messageText,
      messageType: messageType ?? this.messageType,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      attachmentType: attachmentType ?? this.attachmentType,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      forwardedFromId: forwardedFromId ?? this.forwardedFromId,
      isDelivered: isDelivered ?? this.isDelivered,
      isRead: isRead ?? this.isRead,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedForUserIds: deletedForUserIds ?? this.deletedForUserIds,
      createdAt: createdAt ?? this.createdAt,
      localSendState: localSendState ?? this.localSendState,
      localFilePath: localFilePath ?? this.localFilePath,
      localError: localError ?? this.localError,
    );
  }

  factory DirectMessageModel.fromMap(Map<String, dynamic> map) {
    final rawDeletedFor = map['deleted_for_user_ids'];
    final List<String> deletedFor = [];
    if (rawDeletedFor is List) {
      for (final item in rawDeletedFor) {
        final s = item?.toString() ?? '';
        if (s.isNotEmpty) deletedFor.add(s);
      }
    }

    final rawFileSize = map['file_size'];
    final int? parsedSize = rawFileSize is int
        ? rawFileSize
        : (rawFileSize is num ? rawFileSize.toInt() : int.tryParse(rawFileSize?.toString() ?? ''));

    return DirectMessageModel(
      id: map['id']?.toString() ?? '',
      conversationId: map['conversation_id']?.toString(),
      senderId: map['sender_id']?.toString() ?? '',
      receiverId: map['receiver_id']?.toString() ?? '',
      messageText: map['message_text']?.toString() ?? '',
      messageType: map['message_type']?.toString() ??
          (map['attachment_type']?.toString() ?? 'text'),
      attachmentUrl: map['attachment_url']?.toString(),
      attachmentType: map['attachment_type']?.toString(),
      fileName: map['file_name']?.toString(),
      fileSize: parsedSize,
      mimeType: map['mime_type']?.toString(),
      replyToMessageId: map['reply_to_message_id']?.toString(),
      forwardedFromId: map['forwarded_from_id']?.toString(),
      isDelivered: map['is_delivered'] == true,
      isRead: map['is_read'] == true,
      deliveredAt: DateTime.tryParse(map['delivered_at']?.toString() ?? ''),
      readAt: DateTime.tryParse(map['read_at']?.toString() ?? ''),
      editedAt: DateTime.tryParse(map['edited_at']?.toString() ?? ''),
      deletedAt: DateTime.tryParse(map['deleted_at']?.toString() ?? ''),
      deletedForUserIds: deletedFor,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      localSendState: map['local_send_state']?.toString() ?? 'sent',
      localFilePath: map['local_file_path']?.toString(),
      localError: map['local_error']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      'sender_id': senderId,
      if (receiverId.isNotEmpty) 'receiver_id': receiverId,
      'message_text': messageText,
      'message_type': messageType,
      'attachment_url': attachmentUrl,
      'attachment_type': attachmentType,
      'file_name': fileName,
      'file_size': fileSize,
      'mime_type': mimeType,
      'reply_to_message_id': replyToMessageId,
      'forwarded_from_id': forwardedFromId,
      'is_delivered': isDelivered,
      'is_read': isRead,
      'delivered_at': deliveredAt?.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'edited_at': editedAt?.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'deleted_for_user_ids': deletedForUserIds,
      'created_at': createdAt.toIso8601String(),
      'local_send_state': localSendState,
      if (localFilePath != null) 'local_file_path': localFilePath,
      if (localError != null) 'local_error': localError,
    };
  }
}
