import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/language_service.dart';
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

  const DirectChatScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
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

  final List<String> quickEmojis = ["❤️", "🔥", "👍", "🚀", "😍", "🎯", "👏", "💡"];

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
            .or("and(follower_id.eq.$currentUserId,following_id.eq.${widget.peerId}),and(follower_id.eq.${widget.peerId},following_id.eq.$currentUserId)");

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

          loadedMessages.add(DirectChatMessage(
            id: m['id']?.toString() ?? '',
            senderId: senderId,
            text: m['message_text'] ?? '',
            attachmentUrl: m['attachment_url'],
            attachmentType: m['attachment_type']?.toString(),
            createdAt: m['created_at'] ?? DateTime.now().toIso8601String(),
            isMe: senderId == currentUserId,
            status: status,
          ));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.friendRequestSent)),
        );
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
      final replyAuthor = replyingToMessage!.isMe ? context.l10n.yourself : widget.peerName;
      final preview = replyingToMessage!.text.replaceAll('\n', ' ');
      final shortPreview =
          preview.length > 35 ? '${preview.substring(0, 35)}...' : preview;
      textToSend = "↩️ ${context.l10n.replyingTo} $replyAuthor: \"$shortPreview\"\n$rawText";
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
          messages.add(DirectChatMessage(
            id: inserted['id'].toString(),
            senderId: user.id,
            text: inserted['message_text'],
            attachmentUrl: inserted['attachment_url'],
            attachmentType: inserted['attachment_type']?.toString(),
            createdAt: inserted['created_at'],
            isMe: true,
            status: MessageStatus.sent, // Single grey check
          ));
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: textDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: lightPinkBg,
                  backgroundImage: widget.peerAvatar.isNotEmpty ? NetworkImage(widget.peerAvatar) : null,
                  child: widget.peerAvatar.isEmpty
                      ? Text(widget.peerName.isNotEmpty ? widget.peerName[0] : 'U', style: const TextStyle(color: primaryPink, fontWeight: FontWeight.bold))
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
                Text(widget.peerName, style: const TextStyle(color: textDark, fontSize: 14, fontWeight: FontWeight.w900)),
                Text(context.l10n.onlineNow, style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        actions: const [
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const Divider(color: cardBorder, height: 1),

          // ================= Messages List =================
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: primaryPink, strokeWidth: 2.5))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          if (replyingToMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                border: Border(
                  top: BorderSide(color: cardBorder, width: 1),
                  bottom: BorderSide(color: cardBorder, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 32,
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
                        Text(
                          "${context.l10n.replyingTo} ${replyingToMessage!.isMe ? context.l10n.yourself : widget.peerName}",
                          style: const TextStyle(
                            color: primaryPink,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          replyingToMessage!.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: textDark,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: textGrey),
                    onPressed: () => setState(() => replyingToMessage = null),
                  ),
                ],
              ),
            ),

          // ================= Message Input or Follow Status Request =================
          SafeArea(
            top: false,
            child: Builder(
              builder: (context) {
                final bool hasPeerReplied = messages.any((m) => !m.isMe);
                final int mySentCount = messages.where((m) => m.isMe).length;
                final bool isUnlocked = isMutualFollow || hasPeerReplied || isRequestAccepted;
                final bool isRecipientWithRequest = !isUnlocked && messages.isNotEmpty && !messages.first.isMe && mySentCount == 0;
                final bool isSenderWaitingApproval = !isUnlocked && mySentCount >= 1;

                if (isRecipientWithRequest) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: surfaceWhite,
                      border: Border(top: BorderSide(color: cardBorder, width: 1.5)),
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
                          style: const TextStyle(color: textDark, fontSize: 13, fontWeight: FontWeight.bold),
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
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: _declineMessageRequest,
                                child: const Text("Decline", style: TextStyle(color: textGrey, fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryPink,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: _acceptMessageRequest,
                                child: const Text("Accept", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(top: BorderSide(color: cardBorder, width: 1.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: lightPinkBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.hourglass_top_rounded, color: primaryPink, size: 18),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                        border: Border(top: BorderSide(color: cardBorder, width: 1.5)),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(showEmojiPicker ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined, color: textGrey, size: 22),
                            onPressed: () => setState(() => showEmojiPicker = !showEmojiPicker),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              style: const TextStyle(color: textDark, fontSize: 13, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                hintText: context.l10n.chatInputHint,
                                hintStyle: const TextStyle(color: textGrey, fontSize: 12),
                                filled: true,
                                fillColor: cardBorder.withValues(alpha: 0.5),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: cardBorder)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: cardBorder)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: primaryPink, width: 1.5)),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _sendMessage,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(color: primaryPink, shape: BoxShape.circle),
                              child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
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
        statusIcon = const Icon(Icons.access_time_rounded, color: Colors.white70, size: 12);
        break;
      case MessageStatus.sent:
        // Single grey check (sent to server)
        statusIcon = const Icon(Icons.check_rounded, color: Colors.white70, size: 13);
        break;
      case MessageStatus.delivered:
        // Double grey check (delivered to recipient device)
        statusIcon = const Icon(Icons.done_all_rounded, color: Colors.white70, size: 14);
        break;
      case MessageStatus.read:
        // Double blue check (read by recipient)
        statusIcon = const Icon(Icons.done_all_rounded, color: Color(0xFF80DEEA), size: 14);
        break;
    }

    final bool isReel = msg.attachmentType == 'reel' ||
        msg.text.contains("safiacademy.org/en/feed/reels") ||
        msg.text.contains("safiacademy.org/reel/") ||
        msg.text.contains("media.safiacademy.org/reel/") ||
        (msg.attachmentUrl != null && msg.attachmentUrl!.contains("/reels/"));

    String? reelId;
    if (isReel) {
      final queryMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(msg.text);
      final pathMatch = RegExp(r'safiacademy\.org/reel/([a-zA-Z0-9_-]+)').firstMatch(msg.text);
      if (queryMatch != null && queryMatch.groupCount >= 1) {
        reelId = queryMatch.group(1);
      } else if (pathMatch != null && pathMatch.groupCount >= 1) {
        reelId = pathMatch.group(1);
      } else if (msg.attachmentUrl != null && msg.attachmentUrl!.contains('/reels/')) {
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: primaryPink.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.video_collection_rounded, color: primaryPink, size: 16),
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
                      msg.text.replaceAll(RegExp(r'https?://\S+'), '').trim().isNotEmpty
                          ? msg.text.replaceAll(RegExp(r'https?://\S+'), '').trim()
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
                              builder: (_) => StudentReelsScreen(targetReelId: reelId),
                            ),
                          );
                        },
                        icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              replyingToMessage = msg;
                            });
                          },
                          child: Row(
                            children: [
                              const Icon(Icons.reply_rounded, color: Colors.white60, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                context.l10n.reply,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              _formatTime(msg.createdAt),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              statusIcon,
                            ],
                          ],
                        ),
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

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          setState(() {
            replyingToMessage = msg;
          });
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: isMe ? primaryPink : lightPinkBg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isMe ? 20 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                msg.text,
                style: TextStyle(
                  color: isMe ? Colors.white : textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        replyingToMessage = msg;
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.reply_rounded,
                          color: isMe ? Colors.white60 : textGrey,
                          size: 13,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          context.l10n.reply,
                          style: TextStyle(
                            color: isMe ? Colors.white70 : textGrey,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(msg.createdAt),
                        style: TextStyle(
                          color: isMe ? Colors.white.withValues(alpha: 0.8) : textGrey,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        statusIcon,
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
