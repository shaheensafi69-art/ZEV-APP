import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/zev_localizations.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/chat_pin_service.dart';
import '../../../core/services/chat_block_report_service.dart';
import '../../feed/screens/reels_viewer_screen.dart';

enum MessageStatus { sending, sent, delivered, read }

class DirectChatMessage {
  final String id;
  final String senderId;
  final String text;
  final String? attachmentUrl;
  final String? attachmentType;
  final String createdAt;
  final bool isMe;
  final MessageStatus status;

  DirectChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.attachmentUrl,
    this.attachmentType,
    required this.createdAt,
    required this.isMe,
    this.status = MessageStatus.sent,
  });
}

class DirectChatScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String peerAvatar;
  final bool isEmbedded;
  final VoidCallback? onEmbeddedClose;

  const DirectChatScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
    this.isEmbedded = false,
    this.onEmbeddedClose,
  });

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool isLoading = true;
  bool isSending = false;
  bool showEmojiPicker = false;
  List<DirectChatMessage> messages = [];
  RealtimeChannel? _chatChannel;
  DirectChatMessage? replyingToMessage;

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color lightPinkBg = Color(0xFFFAF4F6);
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color cardBorder = Color(0xFFF3F4F6);

  final List<String> quickEmojis = [
    "❤️",
    "🔥",
    "👍",
    "🚀",
    "😍",
    "🎯",
    "👏",
    "💡",
  ];

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _subscribeToRealtimeChat();
    // Ultra-fast 400ms polling refresh to receive incoming messages instantly
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) _fetchMessages(showLoading: false);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_chatChannel != null) {
      supabase.removeChannel(_chatChannel!);
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _subscribeToRealtimeChat() {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      _chatChannel = supabase
          .channel('direct_messages_${widget.peerId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'direct_messages',
            callback: (payload) {
              _fetchMessages(showLoading: false);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint("Realtime channel subscription error: $e");
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  bool isFriend = false;
  bool isMutualFollow = false;
  bool isRequestAccepted = false;

  Future<void> _fetchMessages({bool showLoading = true}) async {
    if (showLoading) setState(() => isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final currentUserId = user.id;

      // Check mutual follow status in user_follows table
      bool mutualStatus = false;
      try {
        final fRes = await supabase
            .from("user_follows")
            .select("follower_id, following_id")
            .or(
              "and(follower_id.eq.$currentUserId,following_id.eq.${widget.peerId}),and(follower_id.eq.${widget.peerId},following_id.eq.$currentUserId)",
            );

        bool iFollow = false;
        bool peerFollows = false;
        for (var row in (fRes as List)) {
          final fId = row['follower_id']?.toString() ?? '';
          final tgId = row['following_id']?.toString() ?? '';
          if (fId == currentUserId && tgId == widget.peerId) iFollow = true;
          if (fId == widget.peerId && tgId == currentUserId) peerFollows = true;
        }
        mutualStatus = iFollow && peerFollows;
      } catch (_) {}

      // Check friend status in student_friends table for backward compatibility
      bool friendStatus = false;
      try {
        final friendCheck = await supabase
            .from("student_friends")
            .select("sender_id, receiver_id, status")
            .or("sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId");

        for (var f in (friendCheck as List)) {
          final sId = f['sender_id']?.toString() ?? '';
          final rId = f['receiver_id']?.toString() ?? '';
          final stat = f['status']?.toString() ?? '';
          if (((sId == currentUserId && rId == widget.peerId) ||
                  (sId == widget.peerId && rId == currentUserId)) &&
              stat == 'accepted') {
            friendStatus = true;
            break;
          }
        }
      } catch (_) {}

      if (!mutualStatus) {
        mutualStatus = friendStatus;
      }

      // Fetch direct messages from direct_messages table
      final res = await supabase
          .from("direct_messages")
          .select("*")
          .or("sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId")
          .order("created_at", ascending: true);

      List<DirectChatMessage> loadedMessages = [];

      for (var m in (res as List)) {
        final senderId = m['sender_id']?.toString() ?? '';
        final receiverId = m['receiver_id']?.toString() ?? '';

        // Filter messages between current user and peerId
        if ((senderId == currentUserId && receiverId == widget.peerId) ||
            (senderId == widget.peerId && receiverId == currentUserId)) {
          final isRead = m['is_read'] == true;
          final isDelivered = m['is_delivered'] == true || isRead;

          MessageStatus status = MessageStatus.sent;
          if (isRead) {
            status = MessageStatus.read; // Double blue check
          } else if (isDelivered) {
            status = MessageStatus.delivered; // Double grey check
          } else {
            status = MessageStatus.sent; // Single grey check
          }

          loadedMessages.add(
            DirectChatMessage(
              id: m['id']?.toString() ?? '',
              senderId: senderId,
              text: m['message_text'] ?? '',
              attachmentUrl: m['attachment_url'],
              attachmentType: m['attachment_type']?.toString(),
              createdAt: m['created_at'] ?? DateTime.now().toIso8601String(),
              isMe: senderId == currentUserId,
              status: status,
            ),
          );
        }
      }

      // Mark unread messages as read (blue check)
      try {
        await supabase
            .from("direct_messages")
            .update({
              'is_read': true,
              'is_delivered': true,
              'read_at': DateTime.now().toIso8601String(),
            })
            .eq("sender_id", widget.peerId)
            .eq("receiver_id", currentUserId)
            .eq("is_read", false);
      } catch (_) {}

      if (mounted) {
        setState(() {
          isFriend = friendStatus;
          isMutualFollow = mutualStatus;
          messages = loadedMessages;
          isLoading = false;
        });
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    } catch (e) {
      debugPrint("Error fetching direct messages: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _acceptMessageRequest() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    setState(() => isRequestAccepted = true);
    _messageController.text = "👋 Hello! Message request accepted.";
    await _sendMessage();
  }

  Future<void> _declineMessageRequest() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase
          .from("direct_messages")
          .delete()
          .eq("sender_id", widget.peerId)
          .eq("receiver_id", user.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _sendFriendRequest() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from("student_friends").insert({
        'sender_id': user.id,
        'receiver_id': widget.peerId,
        'status': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.friendRequestSent)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${context.l10n.friendRequestError}: $e")),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final rawText = _messageController.text.trim();
    if (rawText.isEmpty || isSending) return;

    String textToSend = rawText;
    if (replyingToMessage != null) {
      final replyAuthor = replyingToMessage!.isMe
          ? context.l10n.yourself
          : widget.peerName;
      final preview = replyingToMessage!.text.replaceAll('\n', ' ');
      final shortPreview = preview.length > 35
          ? '${preview.substring(0, 35)}...'
          : preview;
      textToSend =
          "↩️ ${context.l10n.replyingTo} $replyAuthor: \"$shortPreview\"\n$rawText";
    }

    _messageController.clear();
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final tempMsg = DirectChatMessage(
      id: "temp-${DateTime.now().millisecondsSinceEpoch}",
      senderId: user.id,
      text: textToSend,
      createdAt: DateTime.now().toIso8601String(),
      isMe: true,
      status: MessageStatus.sending, // Sending (clock icon)
    );

    setState(() {
      replyingToMessage = null;
      messages.add(tempMsg);
      isSending = true;
      showEmojiPicker = false;
    });
    _scrollToBottom();

    try {
      final inserted = await supabase
          .from("direct_messages")
          .insert({
            'sender_id': user.id,
            'receiver_id': widget.peerId,
            'message_text': textToSend,
            'is_delivered': true, // Delivered to server
          })
          .select()
          .single();

      // Send in-app notification for recipient
      try {
        await supabase.from("user_notifications").insert({
          'user_id': widget.peerId,
          'sender_id': user.id,
          'title': "💬 New Message",
          'message': textToSend,
          'notification_type': "direct_message",
          'link_url': "/chat/${user.id}",
          'is_read': false,
        });
      } catch (_) {}

      if (mounted) {
        setState(() {
          messages.removeWhere((m) => m.id == tempMsg.id);
          messages.add(
            DirectChatMessage(
              id: inserted['id'].toString(),
              senderId: user.id,
              text: inserted['message_text'],
              attachmentUrl: inserted['attachment_url'],
              attachmentType: inserted['attachment_type']?.toString(),
              createdAt: inserted['created_at'],
              isMe: true,
              status: MessageStatus.sent, // Single grey check
            ),
          );
          isSending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("Error sending direct message: $e");
      if (mounted) {
        setState(() {
          messages.removeWhere((m) => m.id == tempMsg.id);
          isSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error sending message: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _formatTime(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceWhite,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: !widget.isEmbedded,
        leading: widget.isEmbedded
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: textDark,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: lightPinkBg,
                  backgroundImage: widget.peerAvatar.isNotEmpty
                      ? NetworkImage(widget.peerAvatar)
                      : null,
                  child: widget.peerAvatar.isEmpty
                      ? Text(
                          widget.peerName.isNotEmpty ? widget.peerName[0] : 'U',
                          style: const TextStyle(
                            color: primaryPink,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.peerName,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  context.l10n.onlineNow,
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: textDark,
              size: 22,
            ),
            onSelected: (val) {
              if (val == 'delete_chat') {
                _deleteConversation();
              } else if (val == 'block') {
                _toggleBlockUser();
              } else if (val == 'report') {
                _showReportUserDialog();
              }
            },
            itemBuilder: (ctx) {
              final isBlocked = ChatBlockReportService.instance.isBlocked(
                widget.peerId,
              );
              return [
                PopupMenuItem(
                  value: 'delete_chat',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.zevTr('deleteChat'),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(
                        isBlocked
                            ? Icons.check_circle_outline_rounded
                            : Icons.block_flipped,
                        color: Colors.orange.shade800,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isBlocked
                            ? context.zevTr('unblockUser')
                            : context.zevTr('blockUser'),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.report_problem_outlined,
                        color: Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(context.zevTr('reportUser')),
                    ],
                  ),
                ),
              ];
            },
          ),
          if (widget.isEmbedded && widget.onEmbeddedClose != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: textDark, size: 22),
              tooltip: "Close",
              onPressed: widget.onEmbeddedClose,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const Divider(color: cardBorder, height: 1),

          // ================= Pinned Message Banner =================
          Builder(
            builder: (_) {
              final pinned = ChatPinService.instance.getPinnedMessageForPeer(
                widget.peerId,
              );
              if (pinned != null) return _buildPinnedMessageBanner(pinned);
              return const SizedBox.shrink();
            },
          ),

          // ================= Messages List =================
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: primaryPink,
                      strokeWidth: 2.5,
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _buildChatBubble(msg);
                    },
                  ),
          ),

          // ================= Quick Emoji Bar =================
          if (showEmojiPicker)
            Container(
              color: cardBorder.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: quickEmojis.map((emoji) {
                  return GestureDetector(
                    onTap: () {
                      _messageController.text += emoji;
                    },
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  );
                }).toList(),
              ),
            ),

          // ================= Reply Preview Box =================
          // ================= Luxury Reply Preview Box =================
          if (replyingToMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1E2230)
                    : const Color(0xFFF1F5F9),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  top: BorderSide(
                    color: primaryPink.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3.5,
                    height: 36,
                    decoration: BoxDecoration(
                      color: primaryPink,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.reply_rounded,
                              size: 13,
                              color: primaryPink,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "${context.l10n.replyingTo} ${replyingToMessage!.isMe ? context.l10n.yourself : widget.peerName}",
                              style: const TextStyle(
                                color: primaryPink,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getCleanMessageText(replyingToMessage!.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white70
                                : textDark,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: textGrey,
                    ),
                    onPressed: () => setState(() => replyingToMessage = null),
                  ),
                ],
              ),
            ),

          // ================= Message Input or Blocked Banner =================
          SafeArea(
            top: false,
            child: Builder(
              builder: (context) {
                final isBlocked = ChatBlockReportService.instance.isBlocked(
                  widget.peerId,
                );
                if (isBlocked) {
                  return _buildBlockedUserBanner();
                }

                final bool hasPeerReplied = messages.any((m) => !m.isMe);
                final int mySentCount = messages.where((m) => m.isMe).length;
                final bool isUnlocked =
                    isMutualFollow || hasPeerReplied || isRequestAccepted;
                final bool isRecipientWithRequest =
                    !isUnlocked &&
                    messages.isNotEmpty &&
                    !messages.first.isMe &&
                    mySentCount == 0;
                final bool isSenderWaitingApproval =
                    !isUnlocked && mySentCount >= 1;

                if (isRecipientWithRequest) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: surfaceWhite,
                      border: Border(
                        top: BorderSide(color: cardBorder, width: 1.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "${widget.peerName} sent you a message request.",
                          style: const TextStyle(
                            color: textDark,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "They don't follow you back or you don't follow them. If you accept, you can message each other freely.",
                          style: TextStyle(color: textGrey, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  side: const BorderSide(
                                    color: Color(0xFFCBD5E1),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _declineMessageRequest,
                                child: const Text(
                                  "Decline",
                                  style: TextStyle(
                                    color: textGrey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryPink,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _acceptMessageRequest,
                                child: const Text(
                                  "Accept",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }

                if (isSenderWaitingApproval) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(
                        top: BorderSide(color: cardBorder, width: 1.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: lightPinkBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.hourglass_top_rounded,
                            color: primaryPink,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Message request sent. You can send more messages once ${widget.peerName} accepts your request.",
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isUnlocked && mySentCount == 0)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        color: lightPinkBg,
                        child: const Text(
                          "ℹ️ You don't mutually follow each other. You can send 1 message request.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: primaryPink,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: surfaceWhite,
                        border: Border(
                          top: BorderSide(color: cardBorder, width: 1.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              showEmojiPicker
                                  ? Icons.keyboard_rounded
                                  : Icons.emoji_emotions_outlined,
                              color: textGrey,
                              size: 22,
                            ),
                            onPressed: () => setState(
                              () => showEmojiPicker = !showEmojiPicker,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              style: const TextStyle(
                                color: textDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText: context.l10n.chatInputHint,
                                hintStyle: const TextStyle(
                                  color: textGrey,
                                  fontSize: 12,
                                ),
                                filled: true,
                                fillColor: cardBorder.withValues(alpha: 0.5),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: const BorderSide(
                                    color: cardBorder,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: const BorderSide(
                                    color: cardBorder,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: const BorderSide(
                                    color: primaryPink,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _sendMessage,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: primaryPink,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build chat bubble and status icons (sent, delivered, read) with Reels support
  Widget _buildChatBubble(DirectChatMessage msg) {
    bool isMe = msg.isMe;

    Widget statusIcon;
    switch (msg.status) {
      case MessageStatus.sending:
        statusIcon = const Icon(
          Icons.access_time_rounded,
          color: Colors.white70,
          size: 12,
        );
        break;
      case MessageStatus.sent:
        // Single grey check (sent to server)
        statusIcon = const Icon(
          Icons.check_rounded,
          color: Colors.white70,
          size: 13,
        );
        break;
      case MessageStatus.delivered:
        // Double grey check (delivered to recipient device)
        statusIcon = const Icon(
          Icons.done_all_rounded,
          color: Colors.white70,
          size: 14,
        );
        break;
      case MessageStatus.read:
        // Double blue check (read by recipient)
        statusIcon = const Icon(
          Icons.done_all_rounded,
          color: Color(0xFF80DEEA),
          size: 14,
        );
        break;
    }

    final bool isReel =
        msg.attachmentType == 'reel' ||
        msg.text.contains("safiacademy.org/en/feed/reels") ||
        msg.text.contains("safiacademy.org/reel/") ||
        msg.text.contains("media.safiacademy.org/reel/") ||
        (msg.attachmentUrl != null && msg.attachmentUrl!.contains("/reels/"));

    String? reelId;
    if (isReel) {
      final queryMatch = RegExp(
        r'[?&]id=([a-zA-Z0-9_-]+)',
      ).firstMatch(msg.text);
      final pathMatch = RegExp(
        r'safiacademy\.org/reel/([a-zA-Z0-9_-]+)',
      ).firstMatch(msg.text);
      if (queryMatch != null && queryMatch.groupCount >= 1) {
        reelId = queryMatch.group(1);
      } else if (pathMatch != null && pathMatch.groupCount >= 1) {
        reelId = pathMatch.group(1);
      } else if (msg.attachmentUrl != null &&
          msg.attachmentUrl!.contains('/reels/')) {
        final segments = Uri.tryParse(msg.attachmentUrl!)?.pathSegments;
        if (segments != null && segments.isNotEmpty) {
          reelId = segments.last.replaceAll('.mp4', '');
        }
      }
    }

    if (isReel) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1F2937), Color(0xFF111827)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isMe ? 20 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 20),
            ),
            border: Border.all(
              color: primaryPink.withValues(alpha: 0.4),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Reels card top bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: primaryPink.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.video_collection_rounded,
                      color: primaryPink,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.educationalReel,
                      style: const TextStyle(
                        color: primaryPink,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      msg.text
                              .replaceAll(RegExp(r'https?://\S+'), '')
                              .trim()
                              .isNotEmpty
                          ? msg.text
                                .replaceAll(RegExp(r'https?://\S+'), '')
                                .trim()
                          : context.l10n.checkOutReel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Watch Reel button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryPink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  StudentReelsScreen(targetReelId: reelId),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.play_circle_fill_rounded,
                          size: 18,
                        ),
                        label: Text(
                          context.l10n.watchReel,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _formatTime(msg.createdAt),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isMe) ...[const SizedBox(width: 4), statusIcon],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Parse embedded reply quote if message is a reply
    String? replyAuthor;
    String? replySnippet;
    String actualText = msg.text;

    if (actualText.startsWith('↩️')) {
      final firstLineEnd = actualText.indexOf('\n');
      if (firstLineEnd != -1) {
        final headerLine = actualText.substring(0, firstLineEnd);
        actualText = actualText.substring(firstLineEnd + 1).trim();
        final colonIdx = headerLine.indexOf(':');
        if (colonIdx != -1) {
          replyAuthor = headerLine.substring(0, colonIdx).replaceFirst('↩️', '').trim();
          final quotePart = headerLine.substring(colonIdx + 1).trim();
          replySnippet = quotePart.replaceAll('"', '').trim();
        } else {
          replyAuthor = headerLine.replaceFirst('↩️', '').trim();
        }
      }
    }

    Widget buildRepliedQuoteBox() {
      final quoteBg = isMe
          ? Colors.black.withValues(alpha: 0.18)
          : (isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFE2E8F0));
      final accentColor = isMe ? Colors.white : primaryPink;

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: quoteBg,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
              color: accentColor,
              width: 3.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.reply_rounded,
                  size: 13,
                  color: isMe ? Colors.white : primaryPink,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    replyAuthor ?? "Replying",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isMe ? Colors.white : primaryPink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (replySnippet != null && replySnippet!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                replySnippet!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.85)
                      : (isDark ? Colors.white70 : textGrey),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Dismissible(
      key: ValueKey("swipe_reply_${msg.id}"),
      direction: isMe ? DismissDirection.endToStart : DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        setState(() {
          replyingToMessage = msg;
        });
        return false; // Never dismiss or remove item from chat list
      },
      background: Container(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: primaryPink.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.reply_rounded,
            color: primaryPink,
            size: 20,
          ),
        ),
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: () => _showMessageActionsModal(msg),
          onDoubleTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              replyingToMessage = msg;
            });
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              gradient: isMe
                  ? const LinearGradient(
                      colors: [primaryPink, Color(0xFFFF5E7E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isMe
                  ? null
                  : (isDark ? const Color(0xFF1E2230) : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 18),
              ),
              border: isMe
                  ? null
                  : Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05),
                      width: 1,
                    ),
              boxShadow: [
                BoxShadow(
                  color: isMe
                      ? primaryPink.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: isMe ? 10 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quoted reply block if present
                if (replyAuthor != null) buildRepliedQuoteBox(),

                // Message Text
                Text(
                  actualText,
                  style: TextStyle(
                    color: isMe
                        ? Colors.white
                        : (isDark ? Colors.white : const Color(0xFF0F172A)),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _formatTime(msg.createdAt),
                      style: TextStyle(
                        color: isMe
                            ? Colors.white.withValues(alpha: 0.8)
                            : textGrey,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isMe) ...[const SizedBox(width: 4), statusIcon],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= Clean Message Text (Only pure text, no author or timestamp) =================
  String _getCleanMessageText(String raw) {
    String text = raw;
    if (text.startsWith('↩️ Replying to') || text.startsWith('↩️')) {
      final firstNewline = text.indexOf('\n');
      if (firstNewline != -1 && firstNewline + 1 < text.length) {
        text = text.substring(firstNewline + 1).trim();
      }
    }
    return text.trim();
  }

  // ================= Message Options Modal =================
  void _showMessageActionsModal(DirectChatMessage msg) {
    final cleanText = _getCleanMessageText(msg.text);
    final isPinned = ChatPinService.instance.isMessagePinned(msg.id);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply_rounded, color: primaryPink),
                title: Text(
                  context.l10n.reply,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => replyingToMessage = msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: textDark),
                title: Text(
                  context.zevTr('copyMessage'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  cleanText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: textGrey, fontSize: 11),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Clipboard.setData(ClipboardData(text: cleanText));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.zevTr('copiedToClipboard')),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  color: primaryPink,
                ),
                title: Text(
                  isPinned
                      ? context.zevTr('unpinChat')
                      : context.zevTr('pinChat'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (isPinned) {
                    await ChatPinService.instance.unpinMessage(msg.id);
                    setState(() {});
                  } else {
                    _showPinMessageDurationPicker(msg);
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.forward_to_inbox_rounded,
                  color: Colors.blue,
                ),
                title: Text(
                  context.zevTr('forwardMessage'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showForwardMessageDialog(cleanText);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                title: Text(
                  context.zevTr('deleteMessage'),
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteSingleMessage(msg);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= Pin Message Duration Picker (24h, 7d, 30d) =================
  void _showPinMessageDurationPicker(DirectChatMessage msg) {
    final cleanText = _getCleanMessageText(msg.text);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.zevTr('pinDurationTitle'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: primaryPink),
                title: Text(context.zevTr('pin24h')),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ChatPinService.instance.pinMessage(
                    peerId: widget.peerId,
                    messageId: msg.id,
                    messageText: cleanText,
                    duration: PinDuration.hours24,
                  );
                  setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.calendar_today_outlined,
                  color: primaryPink,
                ),
                title: Text(context.zevTr('pin7d')),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ChatPinService.instance.pinMessage(
                    peerId: widget.peerId,
                    messageId: msg.id,
                    messageText: cleanText,
                    duration: PinDuration.days7,
                  );
                  setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.date_range_outlined,
                  color: primaryPink,
                ),
                title: Text(context.zevTr('pin30d')),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ChatPinService.instance.pinMessage(
                    peerId: widget.peerId,
                    messageId: msg.id,
                    messageText: cleanText,
                    duration: PinDuration.days30,
                  );
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= Forward Message Dialog =================
  Future<void> _showForwardMessageDialog(String textToForward) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final res = await supabase
          .from('profiles')
          .select('id, first_name, last_name, avatar_url')
          .neq('id', user.id)
          .limit(20);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(context.zevTr('forwardMessage')),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView.separated(
              itemCount: (res as List).length,
              separatorBuilder: (_, _) =>
                  const Divider(color: cardBorder, height: 1),
              itemBuilder: (context, index) {
                final p = res[index];
                final pId = p['id'].toString();
                final fName = p['first_name'] ?? '';
                final lName = p['last_name'] ?? '';
                final name = "$fName $lName".trim().isEmpty
                    ? "ZEV User"
                    : "$fName $lName".trim();
                final avatar = p['avatar_url'] ?? '';

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: lightPinkBg,
                    backgroundImage: avatar.isNotEmpty
                        ? NetworkImage(avatar)
                        : null,
                    child: avatar.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0] : 'U',
                            style: const TextStyle(color: primaryPink),
                          )
                        : null,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.send_rounded,
                    color: primaryPink,
                    size: 20,
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _sendForwardedMessage(
                      targetPeerId: pId,
                      text: textToForward,
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint("Error loading forward recipients: $e");
    }
  }

  Future<void> _sendForwardedMessage({
    required String targetPeerId,
    required String text,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      await supabase.from('direct_messages').insert({
        'sender_id': user.id,
        'receiver_id': targetPeerId,
        'message_text': text,
        'is_read': false,
        'is_delivered': false,
        'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.zevTr('messageForwarded'))),
        );
      }
    } catch (e) {
      debugPrint("Error forwarding message: $e");
    }
  }

  // ================= Delete Single Message =================
  Future<void> _deleteSingleMessage(DirectChatMessage msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.zevTr('deleteMessage')),
        content: Text(context.zevTr('deleteMessageConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.zevTr('delete'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.from('direct_messages').delete().eq('id', msg.id);
      setState(() {
        messages.removeWhere((m) => m.id == msg.id);
      });
      await ChatPinService.instance.unpinMessage(msg.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.zevTr('messageDeleted'))),
        );
      }
    } catch (e) {
      debugPrint("Error deleting message: $e");
    }
  }

  // ================= Delete / Clear Entire Conversation =================
  Future<void> _deleteConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.zevTr('deleteChat')),
        content: Text(context.zevTr('deleteChatConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.zevTr('delete'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      await supabase
          .from("direct_messages")
          .delete()
          .or(
            "and(sender_id.eq.${user.id},receiver_id.eq.${widget.peerId}),and(sender_id.eq.${widget.peerId},receiver_id.eq.${user.id})",
          );

      setState(() {
        messages.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.zevTr('chatDeleted'))));
        if (!widget.isEmbedded && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint("Error deleting conversation: $e");
    }
  }

  // ================= Block / Unblock User =================
  Future<void> _toggleBlockUser() async {
    final isBlocked = ChatBlockReportService.instance.isBlocked(widget.peerId);
    await ChatBlockReportService.instance.toggleBlock(
      widget.peerId,
      peerName: widget.peerName,
    );
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBlocked
                ? context.zevTr('unblockedSuccessfully')
                : context.zevTr('blockedSuccessfully'),
          ),
        ),
      );
    }
  }

  // ================= Report User Dialog =================
  void _showReportUserDialog() {
    final reasons = [
      {'key': 'spam', 'label': context.zevTr('reportReasonSpam')},
      {'key': 'harassment', 'label': context.zevTr('reportReasonHarassment')},
      {
        'key': 'inappropriate',
        'label': context.zevTr('reportReasonInappropriate'),
      },
      {'key': 'scam', 'label': context.zevTr('reportReasonScam')},
      {'key': 'other', 'label': context.zevTr('reportReasonOther')},
    ];
    String selectedReason = 'spam';
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text("${context.zevTr('reportUser')}: ${widget.peerName}"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.zevTr('selectReportReason'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                for (var r in reasons)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(r['label']!),
                    value: r['key']!,
                    groupValue: selectedReason,
                    onChanged: (val) {
                      if (val != null) setDlgState(() => selectedReason = val);
                    },
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: context.zevTr('reportDetailsOptional'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryPink),
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await ChatBlockReportService.instance
                    .reportUser(
                      reportedUserId: widget.peerId,
                      reason: selectedReason,
                      details: descController.text.trim(),
                    );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? context.zevTr('reportSubmitted')
                            : context.zevTr('errorOccurred'),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                context.zevTr('submit'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= Pinned Message Banner Widget =================
  Widget _buildPinnedMessageBanner(PinnedItem pin) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: lightPinkBg,
        border: Border(bottom: BorderSide(color: primaryPink.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          const Icon(Icons.push_pin_rounded, color: primaryPink, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.zevTr('pinnedMessage'),
                  style: const TextStyle(
                    color: primaryPink,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  pin.messageText ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: textDark, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16, color: textGrey),
            tooltip: context.zevTr('unpinChat'),
            onPressed: () async {
              if (pin.messageId != null) {
                await ChatPinService.instance.unpinMessage(pin.messageId!);
              }
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  // ================= Blocked User Banner =================
  Widget _buildBlockedUserBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        border: Border(top: BorderSide(color: Colors.red.shade200)),
      ),
      child: Row(
        children: [
          const Icon(Icons.block_rounded, color: Colors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.zevTr('userIsBlockedNotice'),
              style: const TextStyle(
                color: Colors.red,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              await ChatBlockReportService.instance.unblockUser(widget.peerId);
              setState(() {});
            },
            child: Text(
              context.zevTr('unblockUser'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
