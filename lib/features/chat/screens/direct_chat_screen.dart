import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/app_media_picker.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../feed/screens/user_profile_screen.dart';

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

  String _resolvedPeerName = "";
  String _resolvedPeerAvatar = "";
  bool _isUploadingAttachment = false;
  String _uploadStatusText = "";

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
  final FocusNode _inputFocusNode = FocusNode();
  bool _isFirstLoad = true;
  bool _isFetching = false;
  int _consecutiveFailures = 0;
  int _pollIntervalSeconds = 4;
  DateTime? _peerLastSeen;
  bool _isPeerOnline = false;

  String _formatLastSeen(DateTime? dt, BuildContext context) {
    if (dt == null) return "Offline";
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    final minutes = diff.inMinutes.abs();
    if (minutes < 1) return "Just now";
    if (minutes < 60) return "Last seen ${minutes}m ago";
    final hours = diff.inHours.abs();
    if (hours < 24) return "Last seen ${hours}h ago";
    final days = diff.inDays.abs();
    if (days == 1) return "Last seen yesterday";
    if (days < 7) return "Last seen ${days}d ago";
    return "Last seen ${dt.day}/${dt.month}/${dt.year}";
  }

  void _setupPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: _pollIntervalSeconds), (_) {
      if (mounted && !_isFetching) {
        _fetchMessages(showLoading: false);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _resolvedPeerName = (widget.peerName.isNotEmpty && widget.peerName != 'ZEV User')
        ? widget.peerName
        : '';
    _resolvedPeerAvatar = widget.peerAvatar;
    _fetchPeerProfile();
    _fetchMessages();
    _subscribeToRealtimeChat();
    _setupPollTimer();
  }

  Future<void> _fetchPeerProfile() async {
    try {
      final res = await supabase
          .from('profiles')
          .select('id, first_name, last_name, avatar_url, role, bio')
          .eq('id', widget.peerId)
          .maybeSingle();
      if (res != null) {
        final f = (res['first_name'] ?? '').toString().trim();
        final l = (res['last_name'] ?? '').toString().trim();
        final full = "$f $l".trim();
        final av = (res['avatar_url'] ?? '').toString().trim();
        if (mounted) {
          setState(() {
            if (full.isNotEmpty) _resolvedPeerName = full;
            if (av.isNotEmpty) _resolvedPeerAvatar = av;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching peer profile in direct chat: $e");
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputFocusNode.dispose();
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

  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;
    try {
      final position = _scrollController.position;
      // Only auto-scroll if forced (e.g. user sent a message), on initial load,
      // or if the user is already at the bottom (within 120 pixels).
      // If user is scrolled up reading previous history, NEVER jump them down!
      final isNearBottom = (position.maxScrollExtent - position.pixels) < 120;
      if (force || _isFirstLoad || isNearBottom) {
        _scrollController.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {}
  }

  bool isFriend = false;
  bool isMutualFollow = false;
  bool isRequestAccepted = false;

  Future<void> _fetchMessages({bool showLoading = true}) async {
    if (_isFetching) return;
    _isFetching = true;
    if (showLoading) setState(() => isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _isFetching = false;
        return;
      }
      final currentUserId = user.id;

      // Verify peer profile presence safely
      try {
        if (_resolvedPeerName.isEmpty) {
          _fetchPeerProfile();
        }
      } catch (_) {}

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
          final isDelivered =
              m['is_delivered'] == true || isRead || _isPeerOnline;

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

      // Connection succeeded, restore fast polling if backed off
      if (_consecutiveFailures > 0) {
        _consecutiveFailures = 0;
        _pollIntervalSeconds = 4;
        _setupPollTimer();
      }

      if (mounted) {
        final previousCount = messages.length;
        setState(() {
          isFriend = friendStatus;
          isMutualFollow = mutualStatus;
          messages = loadedMessages;
          isLoading = false;
        });

        if (_isFirstLoad) {
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) {
              _scrollToBottom(force: true);
              _isFirstLoad = false;
            }
          });
        } else if (loadedMessages.length > previousCount) {
          // Only scroll if already at bottom, don't hijack user's scroll up
          _scrollToBottom(force: false);
        }
      }
    } catch (e) {
      debugPrint("Error fetching direct messages: $e");
      _consecutiveFailures++;
      // If network fails (e.g. offline/poor connection in Afghanistan), back off polling to prevent UI freezing
      if (_consecutiveFailures >= 2 && _pollIntervalSeconds < 16) {
        _pollIntervalSeconds = 12;
        _setupPollTimer();
      }
      if (mounted) setState(() => isLoading = false);
    } finally {
      _isFetching = false;
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
    if (kIsWeb) {
      _inputFocusNode.requestFocus();
    }
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
    _scrollToBottom(force: true);

    try {
      final inserted = await supabase
          .from("direct_messages")
          .insert({
            'sender_id': user.id,
            'receiver_id': widget.peerId,
            'message_text': textToSend,
            'is_delivered':
                _isPeerOnline, // Delivered immediately if recipient is online
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
              status: _isPeerOnline
                  ? MessageStatus.delivered
                  : MessageStatus
                        .sent, // 2 checks if peer online, 1 check if offline
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryBg = isDark ? const Color(0xFF0B0F19) : surfaceWhite;
    final appbarBg = isDark ? const Color(0xFF131926) : surfaceWhite;
    final titleTextColor = isDark ? Colors.white : textDark;
    final iconColor = isDark ? Colors.white : textDark;

    return Scaffold(
      backgroundColor: primaryBg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: appbarBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: !widget.isEmbedded,
        leading: widget.isEmbedded
            ? null
            : IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: iconColor,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
        title: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(userId: widget.peerId),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: isDark
                          ? const Color(0xFF1E293B)
                          : lightPinkBg,
                      backgroundImage: (_resolvedPeerAvatar.isNotEmpty
                              ? _resolvedPeerAvatar
                              : widget.peerAvatar)
                          .isNotEmpty
                          ? NetworkImage(_resolvedPeerAvatar.isNotEmpty
                              ? _resolvedPeerAvatar
                              : widget.peerAvatar)
                          : null,
                      child: (_resolvedPeerAvatar.isEmpty && widget.peerAvatar.isEmpty)
                          ? Text(
                              (_resolvedPeerName.isNotEmpty
                                      ? _resolvedPeerName[0]
                                      : (widget.peerName.isNotEmpty && widget.peerName != 'ZEV User'
                                          ? widget.peerName[0]
                                          : 'Z'))
                                  .toUpperCase(),
                              style: TextStyle(
                                color: isDark ? Colors.white : primaryPink,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: _isPeerOnline
                              ? const Color(0xFF10B981)
                              : (isDark
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF94A3B8)),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? const Color(0xFF131926) : Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _resolvedPeerName.isNotEmpty
                            ? _resolvedPeerName
                            : (widget.peerName.isNotEmpty && widget.peerName != 'ZEV User'
                                ? widget.peerName
                                : 'ZEV Member'),
                        style: TextStyle(
                          color: titleTextColor,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _isPeerOnline
                            ? context.l10n.onlineNow
                            : _formatLastSeen(_peerLastSeen, context),
                        style: TextStyle(
                          color: _isPeerOnline
                              ? const Color(0xFF10B981)
                              : (isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B)),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            icon: Icon(Icons.more_vert_rounded, color: iconColor, size: 22),
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

          // ================= Modern Reply Preview Box =================
          if (replyingToMessage != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 3.5,
                    height: 34,
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
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getCleanMessageText(replyingToMessage!.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : textDark,
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
                    if (_isUploadingAttachment)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                          border: Border(
                            top: BorderSide(color: primaryPink.withValues(alpha: 0.3)),
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: primaryPink,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _uploadStatusText.isNotEmpty ? _uploadStatusText : "Uploading attachment...",
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF1E40AF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131926) : surfaceWhite,
                        border: Border(
                          top: BorderSide(
                            color: isDark ? Colors.white12 : cardBorder,
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: primaryPink.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: primaryPink,
                                size: 20,
                              ),
                            ),
                            tooltip: "Send Photo, Video, or File",
                            onPressed: _showAttachmentOptionsSheet,
                          ),
                          IconButton(
                            icon: Icon(
                              showEmojiPicker
                                  ? Icons.keyboard_rounded
                                  : Icons.emoji_emotions_outlined,
                              color: isDark ? Colors.white70 : textGrey,
                              size: 22,
                            ),
                            onPressed: () => setState(
                              () => showEmojiPicker = !showEmojiPicker,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              focusNode: _inputFocusNode,
                              style: TextStyle(
                                color: isDark ? Colors.white : textDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText: context.l10n.chatInputHint,
                                hintStyle: TextStyle(
                                  color: isDark ? Colors.white38 : textGrey,
                                  fontSize: 12,
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF1E293B)
                                    : cardBorder.withValues(alpha: 0.5),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide(
                                    color: isDark ? Colors.white12 : cardBorder,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide(
                                    color: isDark ? Colors.white12 : cardBorder,
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

  // ================= Attachment Sheet & Pickers =================
  void _showAttachmentOptionsSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131926) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: isDark ? const Color(0xFF232D42) : const Color(0xFFE2E8F0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachmentOption(
                  icon: Icons.camera_alt_rounded,
                  label: "Camera",
                  gradient: const [Color(0xFF3B82F6), Color(0xFF2563EB)],
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendMedia(isCamera: true, isVideo: false);
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.photo_library_rounded,
                  label: "Photo",
                  gradient: const [Color(0xFFEC4899), Color(0xFFDB2777)],
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendMedia(isCamera: false, isVideo: false);
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.videocam_rounded,
                  label: "Video",
                  gradient: const [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendMedia(isCamera: false, isVideo: true);
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.insert_drive_file_rounded,
                  label: "File",
                  gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendFile();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: gradient.first.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendMedia({
    required bool isCamera,
    required bool isVideo,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      AppPickedMedia? picked;
      if (isCamera) {
        picked = await AppMediaPicker.instance.pickUniversalMedia(
          allowImages: true,
          allowVideos: false,
          source: ImageSource.camera,
        );
      } else {
        picked = await AppMediaPicker.instance.pickUniversalMedia(
          allowImages: !isVideo,
          allowVideos: isVideo,
        );
      }

      if (picked == null || (picked.bytes == null && picked.file == null)) return;

      setState(() {
        _isUploadingAttachment = true;
        _uploadStatusText = isVideo ? "Uploading video..." : "Uploading photo...";
      });

      final ext = picked.name.contains('.') ? picked.name.split('.').last : (isVideo ? 'mp4' : 'jpg');
      final fileName = "${DateTime.now().millisecondsSinceEpoch}.$ext";
      final uploadPath = "direct/${user.id}/$fileName";

      final publicUrl = await CloudflareStorageService.instance.upload(
        bucket: 'chat_attachments',
        path: uploadPath,
        file: picked.file,
        bytes: picked.bytes,
        contentType: picked.mimeType,
      );

      final inserted = await supabase
          .from("direct_messages")
          .insert({
            'sender_id': user.id,
            'receiver_id': widget.peerId,
            'message_text': isVideo ? '🎬 Video' : '📷 Photo',
            'attachment_url': publicUrl,
            'attachment_type': isVideo ? 'video' : 'image',
            'is_delivered': _isPeerOnline,
          })
          .select()
          .single();

      if (mounted) {
        setState(() {
          messages.add(
            DirectChatMessage(
              id: inserted['id'].toString(),
              senderId: user.id,
              text: inserted['message_text'] ?? '',
              attachmentUrl: publicUrl,
              attachmentType: isVideo ? 'video' : 'image',
              createdAt: inserted['created_at'] ?? DateTime.now().toIso8601String(),
              isMe: true,
              status: _isPeerOnline ? MessageStatus.delivered : MessageStatus.sent,
            ),
          );
          _isUploadingAttachment = false;
        });
        _scrollToBottom(force: true);
      }
    } catch (e) {
      debugPrint("Error sending media: $e");
      if (mounted) {
        setState(() => _isUploadingAttachment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error uploading attachment: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendFile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final res = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (res == null || res.files.isEmpty) return;
      final pf = res.files.single;

      File? file;
      Uint8List? bytes = pf.bytes;
      if (!kIsWeb && pf.path != null && pf.path!.isNotEmpty) {
        file = File(pf.path!);
        if (bytes == null && await file.exists()) {
          bytes = await file.readAsBytes();
        }
      }

      if (bytes == null && file == null) return;

      setState(() {
        _isUploadingAttachment = true;
        _uploadStatusText = "Uploading ${pf.name}...";
      });

      final safeName = pf.name.replaceAll(' ', '_');
      final uploadPath = "direct/${user.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName";

      final publicUrl = await CloudflareStorageService.instance.upload(
        bucket: 'chat_attachments',
        path: uploadPath,
        file: file,
        bytes: bytes,
        skipCompression: true,
      );

      final inserted = await supabase
          .from("direct_messages")
          .insert({
            'sender_id': user.id,
            'receiver_id': widget.peerId,
            'message_text': '📄 ${pf.name}',
            'attachment_url': publicUrl,
            'attachment_type': 'file',
            'is_delivered': _isPeerOnline,
          })
          .select()
          .single();

      if (mounted) {
        setState(() {
          messages.add(
            DirectChatMessage(
              id: inserted['id'].toString(),
              senderId: user.id,
              text: inserted['message_text'] ?? '',
              attachmentUrl: publicUrl,
              attachmentType: 'file',
              createdAt: inserted['created_at'] ?? DateTime.now().toIso8601String(),
              isMe: true,
              status: _isPeerOnline ? MessageStatus.delivered : MessageStatus.sent,
            ),
          );
          _isUploadingAttachment = false;
        });
        _scrollToBottom(force: true);
      }
    } catch (e) {
      debugPrint("Error sending file: $e");
      if (mounted) {
        setState(() => _isUploadingAttachment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error uploading file: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.92),
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (c, w, p) => p == null
                      ? w
                      : const Center(
                          child: CircularProgressIndicator(color: primaryPink),
                        ),
                  errorBuilder: (c, e, s) => const Center(
                    child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentBubbleContent(DirectChatMessage msg, bool isMe, bool isDark) {
    final url = msg.attachmentUrl!;
    final type = msg.attachmentType ?? '';
    final isImage = type == 'image' ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.png') ||
        url.endsWith('.webp') ||
        url.endsWith('.gif');
    final isVideo = type == 'video' ||
        url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.webm');

    if (isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          onTap: () => _showFullScreenImage(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  width: 240,
                  height: 180,
                  loadingBuilder: (c, w, p) => p == null
                      ? w
                      : Container(
                          width: 240,
                          height: 180,
                          color: isDark ? const Color(0xFF0F172A) : Colors.black12,
                          child: const Center(
                            child: CircularProgressIndicator(color: primaryPink, strokeWidth: 2),
                          ),
                        ),
                  errorBuilder: (c, e, s) => Container(
                    width: 240,
                    height: 120,
                    color: isDark ? const Color(0xFF0F172A) : Colors.black12,
                    child: const Center(
                      child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 36),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isVideo) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          onTap: () async {
            final uri = Uri.tryParse(url);
            if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Container(
            width: 240,
            height: 140,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.black87,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: primaryPink.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                ),
                Positioned(
                  bottom: 8,
                  left: 10,
                  child: Row(
                    children: const [
                      Icon(Icons.videocam_rounded, color: Colors.white70, size: 14),
                      SizedBox(width: 4),
                      Text("Video", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Default: Document / File
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.black.withValues(alpha: 0.15)
                : (isDark ? const Color(0xFF0F172A) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isMe ? Colors.white24 : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF10B981), size: 22),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      msg.text.isNotEmpty ? msg.text.replaceFirst('📄 ', '') : "Document",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isMe ? Colors.white : (isDark ? Colors.white : const Color(0xFF0F172A)),
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Tap to open / download",
                      style: TextStyle(
                        color: isMe ? Colors.white70 : (isDark ? Colors.white54 : textGrey),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.download_rounded,
                color: isMe ? Colors.white70 : (isDark ? Colors.white54 : textGrey),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build chat bubble and status icons (sent, delivered, read) with Reels support
  Widget _buildChatBubble(DirectChatMessage msg) {
    bool isMe = msg.isMe;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        // Single grey check (sent to server, recipient offline)
        statusIcon = const Icon(
          Icons.check_rounded,
          color: Color(0xFF94A3B8),
          size: 13,
        );
        break;
      case MessageStatus.delivered:
        // Double grey check (delivered to recipient)
        statusIcon = const Icon(
          Icons.done_all_rounded,
          color: Color(0xFF94A3B8),
          size: 14,
        );
        break;
      case MessageStatus.read:
        // Double bright blue check (seen/read by recipient)
        statusIcon = const Icon(
          Icons.done_all_rounded,
          color: Color(0xFF00B0FF),
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

    return Dismissible(
      key: ValueKey("swipe_reply_${msg.id}"),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        setState(() {
          replyingToMessage = msg;
        });
        return false; // Prevent removing from list
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: primaryPink.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.reply_rounded, color: primaryPink, size: 20),
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
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76,
            ),
            decoration: BoxDecoration(
              gradient: isMe
                  ? const LinearGradient(
                      colors: [Color(0xFFFC466B), Color(0xFFFF5E62)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isMe
                  ? null
                  : (isDark
                        ? const Color(0xFF161F30)
                        : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 20),
              ),
              border: isMe
                  ? null
                  : Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                    ),
              boxShadow: [
                BoxShadow(
                  color: isMe
                      ? const Color(0xFFFC466B).withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (msg.attachmentUrl != null && msg.attachmentUrl!.isNotEmpty)
                  _buildAttachmentBubbleContent(msg, isMe, isDark),
                if (msg.text.isNotEmpty && !msg.text.startsWith('📷') && !msg.text.startsWith('🎬') && !msg.text.startsWith('📄'))
                  _buildBubbleText(msg.text, isMe, isDark),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _formatTime(msg.createdAt),
                      style: TextStyle(
                        color: isMe
                            ? Colors.white.withValues(alpha: 0.8)
                            : (isDark ? Colors.white54 : textGrey),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
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

  Widget _buildBubbleText(String raw, bool isMe, bool isDark) {
    String? quotedAuthor;
    String? quotedText;
    String actualText = raw;

    if (raw.startsWith('↩️')) {
      final firstNewline = raw.indexOf('\n');
      if (firstNewline != -1) {
        final header = raw.substring(0, firstNewline);
        actualText = raw.substring(firstNewline + 1).trim();

        final colonIdx = header.indexOf(':');
        if (colonIdx != -1) {
          quotedAuthor = header
              .substring(2, colonIdx)
              .replaceFirst('Replying to ', '')
              .replaceFirst('Replying to', '')
              .trim();
          var q = header.substring(colonIdx + 1).trim();
          if (q.startsWith('"') && q.endsWith('"') && q.length >= 2) {
            q = q.substring(1, q.length - 1);
          }
          quotedText = q;
        } else {
          quotedText = header.substring(2).trim();
        }
      }
    }

    return Column(
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (quotedText != null && quotedText!.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.black.withValues(alpha: 0.14)
                  : (isDark
                        ? Colors.black26
                        : const Color(0xFFE2E8F0).withValues(alpha: 0.8)),
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: isMe ? Colors.white : primaryPink,
                  width: 3.5,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (quotedAuthor != null && quotedAuthor!.isNotEmpty)
                  Text(
                    quotedAuthor!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? Colors.white : primaryPink,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 1),
                Text(
                  quotedText!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.85)
                        : (isDark ? Colors.white70 : const Color(0xFF475569)),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
        Text(
          actualText,
          style: TextStyle(
            color: isMe
                ? Colors.white
                : (isDark ? Colors.white : const Color(0xFF0F172A)),
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
      ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131926) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: isDark ? const Color(0xFF232D42) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
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
    ),
  );
}

  // ================= Pin Message Duration Picker (24h, 7d, 30d) =================
  void _showPinMessageDurationPicker(DirectChatMessage msg) {
    final cleanText = _getCleanMessageText(msg.text);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131926) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: isDark ? const Color(0xFF232D42) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  context.zevTr('pinDurationTitle'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDark ? Colors.white : textDark,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryPink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.timer_outlined, color: primaryPink, size: 20),
                  ),
                  title: Text(
                    context.zevTr('pin24h'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : textDark,
                    ),
                  ),
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
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calendar_today_outlined, color: Color(0xFF3B82F6), size: 20),
                  ),
                  title: Text(
                    context.zevTr('pin7d'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : textDark,
                    ),
                  ),
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
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.date_range_outlined, color: Color(0xFF10B981), size: 20),
                  ),
                  title: Text(
                    context.zevTr('pin30d'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : textDark,
                    ),
                  ),
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
