/// Data model representing a single direct message between two users on ZEV.
class DirectMessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String messageText;
  final String? attachmentUrl;
  final String? attachmentType; // 'image', 'video', 'audio', 'file'
  final bool isDelivered;
  final bool isRead;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime createdAt;

  const DirectMessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.messageText,
    this.attachmentUrl,
    this.attachmentType,
    this.isDelivered = true,
    this.isRead = false,
    this.deliveredAt,
    this.readAt,
    required this.createdAt,
  });

  bool isMine(String currentUserId) => senderId == currentUserId;

  factory DirectMessageModel.fromMap(Map<String, dynamic> map) {
    return DirectMessageModel(
      id: map['id']?.toString() ?? '',
      senderId: map['sender_id']?.toString() ?? '',
      receiverId: map['receiver_id']?.toString() ?? '',
      messageText: map['message_text']?.toString() ?? '',
      attachmentUrl: map['attachment_url']?.toString(),
      attachmentType: map['attachment_type']?.toString(),
      isDelivered: map['is_delivered'] == true,
      isRead: map['is_read'] == true,
      deliveredAt: DateTime.tryParse(map['delivered_at']?.toString() ?? ''),
      readAt: DateTime.tryParse(map['read_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_text': messageText,
      'attachment_url': attachmentUrl,
      'attachment_type': attachmentType,
      'is_delivered': isDelivered,
      'is_read': isRead,
      'delivered_at': deliveredAt?.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

