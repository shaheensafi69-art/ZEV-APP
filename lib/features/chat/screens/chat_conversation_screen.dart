import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/badge_counter_service.dart';
import '../../../core/services/cloudflare_storage_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/services/user_presence_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../profile/screens/profile_screen.dart';
import '../models/direct_message_model.dart';
import '../services/chat_cache_service.dart';
import '../services/chat_service.dart';
import '../widgets/chat_modals.dart';

/// Light Clearmorphic Direct & Group Chat Conversation Screen for ZEV.
class ChatConversationScreen extends StatefulWidget {
  final String conversationId;
  final bool isGroup;
  final String groupTitle;
  final String groupAvatar;
  final String peerId;
  final String peerUsername;
  final String peerFullName;
  final String peerAvatar;
  final bool isPeerVerified;

  const ChatConversationScreen({
    super.key,
    this.conversationId = '',
    this.isGroup = false,
    this.groupTitle = '',
    this.groupAvatar = '',
    this.peerId = '',
    this.peerUsername = 'User',
    this.peerFullName = '',
    this.peerAvatar = '',
    this.isPeerVerified = false,
  });

  static Future<void> open(
    BuildContext context, {
    String conversationId = '',
    bool isGroup = false,
    String groupTitle = '',
    String groupAvatar = '',
    String peerId = '',
    String peerUsername = 'User',
    String peerFullName = '',
    String peerAvatar = '',
    bool isPeerVerified = false,
  }) async {
    String resolvedConvId = conversationId.trim();
    bool resolvedGroup = isGroup;
    String resolvedGroupTitle = groupTitle;
    String resolvedGroupAvatar = groupAvatar;
    String resolvedPeerId = peerId.trim();
    String resolvedUsername = peerUsername;
    String resolvedFullName = peerFullName;
    String resolvedAvatar = peerAvatar;
    bool resolvedVerified = isPeerVerified;

    if (resolvedConvId.isNotEmpty &&
        ((resolvedGroup && resolvedGroupTitle.isEmpty) ||
            (!resolvedGroup && resolvedPeerId.isEmpty))) {
      try {
        final conv = await Supabase.instance.client
            .from('conversations')
            .select('title, avatar_url, is_group')
            .eq('id', resolvedConvId)
            .maybeSingle();
        if (conv != null) {
          resolvedGroup = conv['is_group'] == true;
          if (resolvedGroup) {
            resolvedGroupTitle = conv['title']?.toString() ?? 'Group Chat';
            resolvedGroupAvatar = conv['avatar_url']?.toString() ?? '';
          } else if (resolvedPeerId.isEmpty) {
            final myId = Supabase.instance.client.auth.currentUser?.id ?? '';
            final member = await Supabase.instance.client
                .from('conversation_members')
                .select('user_id')
                .eq('conversation_id', resolvedConvId)
                .neq('user_id', myId)
                .limit(1)
                .maybeSingle();
            if (member != null) {
              resolvedPeerId = member['user_id']?.toString() ?? '';
            }
          }
        }
      } catch (_) {}
    }

    if (!resolvedGroup &&
        resolvedPeerId.isNotEmpty &&
        (resolvedUsername == 'User' || resolvedUsername.isEmpty)) {
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('username, first_name, last_name, avatar_url, is_verified')
            .eq('id', resolvedPeerId)
            .maybeSingle();

        if (profile != null) {
          resolvedUsername = profile['username']?.toString() ?? 'User';
          resolvedFullName =
              '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
                  .trim();
          resolvedAvatar = profile['avatar_url']?.toString() ?? '';
          resolvedVerified = profile['is_verified'] == true;
        }
      } catch (_) {}
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatConversationScreen(
          conversationId: resolvedConvId,
          isGroup: resolvedGroup,
          groupTitle: resolvedGroupTitle,
          groupAvatar: resolvedGroupAvatar,
          peerId: resolvedPeerId,
          peerUsername: resolvedUsername,
          peerFullName: resolvedFullName,
          peerAvatar: resolvedAvatar,
          isPeerVerified: resolvedVerified,
        ),
      ),
    );
  }

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _textCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  String _conversationId = '';
  bool _isGroup = false;
  String _groupTitle = '';
  String _groupAvatar = '';
  GroupConversationDetails? _groupDetails;
  Map<String, GroupMemberInfo> _memberById = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreOlder = true;
  bool _isSending = false;

  List<DirectMessageModel> _messages = [];
  Map<String, List<MessageReactionSummary>> _reactions = {};
  DirectMessageModel? _replyingTo;
  DirectMessageModel? _editingMessage;

  // Search bar within conversation
  bool _showSearchBar = false;
  List<DirectMessageModel> _searchHits = [];
  bool _isSearching = false;
  String? _highlightedMsgId;
  Timer? _searchDebounce;

  // Message Request & Block / Privacy Policy state
  bool _hasPendingRequest = false;
  bool _isBlocked = false;
  bool _iBlockedPeer = false;
  bool _canMessage = true;

  // Presence + Typing indicator
  bool _isPeerOnline = false;
  String _peerStatusText = '';
  bool _peerIsTyping = false;
  String _typingUsername = '';
  DateTime? _lastTypingSentAt;
  Timer? _typingClearTimer;

  RealtimeChannel? _chatChannel;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId.trim();
    _isGroup = widget.isGroup;
    _groupTitle = widget.groupTitle;
    _groupAvatar = widget.groupAvatar;

    if (_conversationId.isNotEmpty) {
      NotificationService.activeChatConversationId = _conversationId;
    }
    if (!_isGroup && widget.peerId.trim().isNotEmpty) {
      NotificationService.activeChatPeerId = widget.peerId.trim();
    }

    _loadFromCacheFirst();
    _scrollCtrl.addListener(_onScrollPagination);
    _bootstrapConversation();
  }

  @override
  void dispose() {
    if (_conversationId.isNotEmpty &&
        NotificationService.activeChatConversationId == _conversationId) {
      NotificationService.activeChatConversationId = null;
    }
    if (widget.peerId.trim().isNotEmpty &&
        NotificationService.activeChatPeerId == widget.peerId.trim()) {
      NotificationService.activeChatPeerId = null;
    }
    _textCtrl.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.removeListener(_onScrollPagination);
    _scrollCtrl.dispose();
    _chatChannel?.unsubscribe();
    _statusTimer?.cancel();
    _recordingTimer?.cancel();
    _typingClearTimer?.cancel();
    _searchDebounce?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _onScrollPagination() {
    if (_isLoadingMore || !_hasMoreOlder || _messages.isEmpty) return;
    if (_scrollCtrl.hasClients &&
        _scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 160) {
      _loadOlderMessages();
    }
  }

  void _loadFromCacheFirst() {
    final key =
        _conversationId.isNotEmpty ? _conversationId : widget.peerId;
    final cached = ChatCacheService.instance.getThread(key);
    if (cached.isNotEmpty) {
      _messages = List.from(cached);
      _isLoading = false;
    }

    if (!_isGroup && widget.peerId.isNotEmpty) {
      final cachedProfile =
          ChatCacheService.instance.getCachedProfile(widget.peerId);
      if (cachedProfile != null) {
        final presence = UserPresenceService.computePresence(cachedProfile);
        _isPeerOnline = presence.isOnline;
        _peerStatusText = presence.statusText;
      }
    }
  }

  Future<void> _bootstrapConversation() async {
    if (_conversationId.isEmpty && widget.peerId.isNotEmpty) {
      final resolved = await ChatService.instance
          .ensureDirectConversation(widget.peerId);
      if (resolved != null && resolved.isNotEmpty) {
        _conversationId = resolved;
        if (mounted) {
          NotificationService.activeChatConversationId = _conversationId;
        }
      }
    }

    await Future.wait([
      _fetchMessages(),
      if (_isGroup && _conversationId.isNotEmpty) _fetchGroupDetails(),
      if (!_isGroup && widget.peerId.isNotEmpty) _fetchPolicyAndRequestState(),
      if (!_isGroup && widget.peerId.isNotEmpty) _fetchPeerStatus(),
    ]);

    await _markIncomingMessagesAsRead();
    await _flushPendingOutbox();
    _subscribeToLiveChat();

    if (!_isGroup && widget.peerId.isNotEmpty) {
      _statusTimer?.cancel();
      _statusTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (mounted) _fetchPeerStatus();
      });
    }
  }

  Future<void> _fetchGroupDetails() async {
    final details =
        await ChatService.instance.fetchGroupDetails(_conversationId);
    if (details != null && mounted) {
      setState(() {
        _groupDetails = details;
        _groupTitle = details.title;
        _groupAvatar = details.avatarUrl;
        _memberById = {for (final m in details.members) m.userId: m};
      });
    }
  }

  Future<void> _fetchPolicyAndRequestState() async {
    final myId = ChatService.instance.currentUserId;
    if (myId == null) return;
    try {
      final policy = await SocialGraphService.instance
          .getInteractionPolicy(widget.peerId);
      final isBlocked = policy['is_blocked'] == true;
      bool iBlocked = false;
      if (isBlocked) {
        final blk = await _supabase
            .from('user_blocks')
            .select('blocked_id')
            .eq('blocker_id', myId)
            .eq('blocked_id', widget.peerId)
            .maybeSingle();
        iBlocked = blk != null;
      }

      bool pendingReq = false;
      if (_conversationId.isNotEmpty) {
        final req = await _supabase
            .from('message_requests')
            .select('status')
            .eq('conversation_id', _conversationId)
            .eq('recipient_id', myId)
            .eq('status', 'pending')
            .maybeSingle();
        pendingReq = req != null;
      }

      if (mounted) {
        setState(() {
          _isBlocked = isBlocked;
          _iBlockedPeer = iBlocked;
          _canMessage = policy['can_message'] != false && !isBlocked;
          _hasPendingRequest = pendingReq;
        });
      }
    } catch (_) {}
  }

  Future<void> _flushPendingOutbox() async {
    if (_conversationId.isEmpty) return;
    final retried = await ChatService.instance.flushOutboxForThread(
      conversationId: _conversationId,
      isGroup: _isGroup,
      peerId: widget.peerId,
    );
    if (retried.isNotEmpty && mounted) {
      await _fetchMessages();
    }
  }

  void _subscribeToLiveChat() {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || _conversationId.isEmpty) return;

    try {
      var ch = _supabase.channel('chat:conv:$_conversationId');

      ch = ch
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'direct_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: _conversationId,
            ),
            callback: _handleRealtimeMessageEvent,
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'message_reactions',
            callback: (_) => _fetchReactions(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'conversations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: _conversationId,
            ),
            callback: (payload) {
              if (!mounted) return;
              final rec = payload.newRecord;
              if (_isGroup && rec['title'] != null) {
                setState(() => _groupTitle = rec['title'].toString());
              }
            },
          );

      if (_isGroup) {
        ch = ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversation_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: _conversationId,
          ),
          callback: (_) => _fetchGroupDetails(),
        );
      } else if (widget.peerId.isNotEmpty) {
        ch = ch.onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.peerId,
          ),
          callback: (_) => _fetchPeerStatus(),
        );
      }

      ch = ch.onBroadcast(
        event: 'typing',
        callback: (raw) {
          final inner = raw['payload'] is Map
              ? Map<String, dynamic>.from(raw['payload'] as Map)
              : raw;
          final sender = inner['user_id']?.toString() ?? '';
          if (sender.isEmpty || sender == myId) return;
          final isTyping = inner['is_typing'] == true;
          final uname = inner['username']?.toString() ?? '';
          if (!mounted) return;
          _typingClearTimer?.cancel();
          setState(() {
            _peerIsTyping = isTyping;
            _typingUsername = uname;
          });
          if (isTyping) {
            _typingClearTimer = Timer(const Duration(milliseconds: 3500), () {
              if (mounted) setState(() => _peerIsTyping = false);
            });
          }
        },
      );

      _chatChannel = ch..subscribe();
    } catch (e) {
      debugPrint('[ChatConversationScreen] Realtime notice: $e');
    }
  }

  void _broadcastTyping(bool isTyping) {
    final myId = ChatService.instance.currentUserId;
    if (myId == null || _chatChannel == null || _conversationId.isEmpty) {
      return;
    }
    final now = DateTime.now();
    if (isTyping &&
        _lastTypingSentAt != null &&
        now.difference(_lastTypingSentAt!).inMilliseconds < 1200) {
      return;
    }
    _lastTypingSentAt = now;
    final myProfile = ChatCacheService.instance.getCachedProfile(myId);
    final myName = myProfile?['username']?.toString() ?? '';

    unawaited(
      _chatChannel!.sendBroadcastMessage(
        event: 'typing',
        payload: {
          'user_id': myId,
          'username': myName,
          'is_typing': isTyping,
        },
      ),
    );
  }

  void _handleRealtimeMessageEvent(PostgresChangePayload payload) {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    if (payload.eventType == PostgresChangeEvent.insert) {
      final rec = Map<String, dynamic>.from(payload.newRecord);
      final msg = DirectMessageModel.fromMap(rec);
      if (msg.isDeletedForUser(myId)) return;

      final existingIdx = _messages.indexWhere((m) => m.id == msg.id);
      if (existingIdx == -1) {
        HapticFeedback.lightImpact();
        setState(() {
          _messages.insert(0, msg);
          if (msg.senderId != myId) _peerIsTyping = false;
        });
        ChatCacheService.instance.addMessage(_conversationId, msg);
        _scrollToBottom();
      }
      if (msg.senderId != myId) {
        _markIncomingMessagesAsRead();
      }
    } else if (payload.eventType == PostgresChangeEvent.update) {
      final rec = Map<String, dynamic>.from(payload.newRecord);
      final updated = DirectMessageModel.fromMap(rec);

      if (updated.isDeletedForUser(myId)) {
        if (mounted) {
          setState(() => _messages.removeWhere((m) => m.id == updated.id));
        }
        ChatCacheService.instance.removeMessage(_conversationId, updated.id);
        return;
      }

      final idx = _messages.indexWhere((m) => m.id == updated.id);
      if (idx != -1 && mounted) {
        setState(() => _messages[idx] = updated);
        ChatCacheService.instance.updateMessage(_conversationId, updated);
      }
    } else if (payload.eventType == PostgresChangeEvent.delete) {
      final oldId = payload.oldRecord['id']?.toString() ?? '';
      if (oldId.isNotEmpty && mounted) {
        setState(() => _messages.removeWhere((m) => m.id == oldId));
        ChatCacheService.instance.removeMessage(_conversationId, oldId);
      }
    }
  }

  Future<void> _markIncomingMessagesAsRead() async {
    final myId = ChatService.instance.currentUserId;
    if (myId == null || _conversationId.isEmpty) return;

    bool changed = false;
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].senderId != myId && !_messages[i].isRead) {
        _messages[i] = _messages[i].copyWith(isRead: true, isDelivered: true);
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});

    await ChatService.instance.markConversationRead(
      conversationId: _conversationId,
      peerId: widget.peerId,
    );
    BadgeCounterService.instance.scheduleRefresh();
  }

  Future<void> _fetchMessages() async {
    if (_conversationId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final list = await ChatService.instance.fetchMessages(
        conversationId: _conversationId,
        limit: 80,
      );
      if (mounted) {
        setState(() {
          _messages = list;
          _hasMoreOlder = list.length >= 80;
          _isLoading = false;
        });
        await _fetchReactions();
      }
    } catch (e) {
      debugPrint('[ChatConversationScreen] _fetchMessages error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingMore || !_hasMoreOlder || _messages.isEmpty) return;
    setState(() => _isLoadingMore = true);
    try {
      final oldest = _messages.last.createdAt;
      final older = await ChatService.instance.fetchMessages(
        conversationId: _conversationId,
        limit: 60,
        before: oldest,
      );
      if (mounted) {
        final existingIds = _messages.map((m) => m.id).toSet();
        final fresh = older.where((m) => !existingIds.contains(m.id)).toList();
        setState(() {
          _messages.addAll(fresh);
          _hasMoreOlder = older.length >= 60;
          _isLoadingMore = false;
        });
        await _fetchReactions();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _fetchPeerStatus() async {
    if (_isGroup || widget.peerId.isEmpty) return;
    final map = await UserPresenceService.instance
        .fetchPresenceMap([widget.peerId]);
    final info = map[widget.peerId];
    if (info != null && mounted) {
      setState(() {
        _isPeerOnline = info.isOnline;
        _peerStatusText = info.isHidden ? '' : info.statusText;
      });
    }
  }

  Future<void> _fetchReactions() async {
    if (_messages.isEmpty) return;
    final ids = _messages.map((m) => m.id).take(80).toList();
    final map = await ChatService.instance.fetchReactionsSummary(ids);
    if (mounted) {
      setState(() => _reactions = map);
    }
  }

  Future<void> _sendTextOrEdit() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    if (_editingMessage != null) {
      final target = _editingMessage!;
      _textCtrl.clear();
      setState(() {
        _editingMessage = null;
        _isSending = true;
      });
      _broadcastTyping(false);

      try {
        final updated = await ChatService.instance.editMessage(
          conversationId: _conversationId,
          messageId: target.id,
          newText: text,
        );
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == updated.id);
            if (idx != -1) _messages[idx] = updated;
            _isSending = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Edit failed: $e')),
          );
        }
      }
      return;
    }

    await _sendAttachmentOrText(messageText: text);
  }

  Future<void> _sendAttachmentOrText({
    String messageText = '',
    String messageType = 'text',
    String? attachmentType,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? localFilePath,
  }) async {
    if (_conversationId.isEmpty && widget.peerId.isNotEmpty) {
      final resolved = await ChatService.instance
          .ensureDirectConversation(widget.peerId);
      if (resolved != null) _conversationId = resolved;
    }
    if (_conversationId.isEmpty) return;

    if (messageType == 'text') {
      _textCtrl.clear();
      _broadcastTyping(false);
    }
    final replyId = _replyingTo?.id;
    setState(() {
      _replyingTo = null;
      if (localFilePath != null) _isSending = true;
    });

    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final myId = ChatService.instance.currentUserId ?? '';
    final optimistic = DirectMessageModel(
      id: tempId,
      conversationId: _conversationId,
      senderId: myId,
      receiverId: _isGroup ? '' : widget.peerId,
      messageText: messageText,
      messageType: messageType,
      attachmentType: attachmentType,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      replyToMessageId: replyId,
      createdAt: DateTime.now().toUtc(),
      localSendState: 'sending',
      localFilePath: localFilePath,
    );

    setState(() => _messages.insert(0, optimistic));
    _scrollToBottom();
    HapticFeedback.lightImpact();

    final result = await ChatService.instance.sendMessage(
      conversationId: _conversationId,
      isGroup: _isGroup,
      peerId: widget.peerId,
      messageText: messageText,
      messageType: messageType,
      attachmentType: attachmentType,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      replyToMessageId: replyId,
      localFilePath: localFilePath,
      existingTempId: tempId,
      isPeerOnline: _isPeerOnline,
    );

    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => m.id == tempId || m.id == result.id);
        _messages.insert(0, result);
        _isSending = false;
      });
    }
  }

  Future<void> _retryFailedMessage(DirectMessageModel failedMsg) async {
    HapticFeedback.lightImpact();
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == failedMsg.id);
      if (idx != -1) {
        _messages[idx] = failedMsg.copyWith(localSendState: 'sending');
      }
    });

    final retried = await ChatService.instance.sendMessage(
      conversationId: _conversationId,
      isGroup: _isGroup,
      peerId: widget.peerId.isNotEmpty ? widget.peerId : failedMsg.receiverId,
      messageText: failedMsg.messageText,
      messageType: failedMsg.messageType,
      attachmentUrl: failedMsg.attachmentUrl,
      attachmentType: failedMsg.attachmentType,
      fileName: failedMsg.fileName,
      fileSize: failedMsg.fileSize,
      mimeType: failedMsg.mimeType,
      replyToMessageId: failedMsg.replyToMessageId,
      forwardedFromId: failedMsg.forwardedFromId,
      localFilePath: failedMsg.localFilePath,
      existingTempId: failedMsg.id,
      isPeerOnline: _isPeerOnline,
    );

    if (mounted) {
      setState(() {
        _messages.removeWhere(
          (m) => m.id == failedMsg.id || m.id == retried.id,
        );
        _messages.insert(0, retried);
      });
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1920,
      );
      if (picked == null) return;
      final file = File(picked.path);
      final size = await file.length();
      await _sendAttachmentOrText(
        messageType: 'image',
        attachmentType: 'image',
        fileName: 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
        fileSize: size,
        mimeType: 'image/jpeg',
        localFilePath: picked.path,
      );
    } catch (e) {
      debugPrint('[ChatConversationScreen] Image pick notice: $e');
    }
  }

  Future<void> _pickAndSendVideo() async {
    try {
      final XFile? picked = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 3),
      );
      if (picked == null) return;
      final file = File(picked.path);
      final size = await file.length();
      if (size > 100 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video exceeds 100 MB limit.')),
          );
        }
        return;
      }
      await _sendAttachmentOrText(
        messageType: 'video',
        attachmentType: 'video',
        fileName: 'video_${DateTime.now().millisecondsSinceEpoch}.mp4',
        fileSize: size,
        mimeType: CloudflareStorageService.inferMimeType(picked.path),
        localFilePath: picked.path,
      );
    } catch (e) {
      debugPrint('[ChatConversationScreen] Video pick notice: $e');
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'txt',
          'csv',
          'json',
          'zip',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
        ],
        withData: false,
      );
      final picked = result?.files.firstOrNull;
      final path = picked?.path;
      if (picked == null || path == null || path.isEmpty) return;

      final file = File(path);
      final size = await file.length();
      if (size > 50 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document exceeds 50 MB limit.')),
          );
        }
        return;
      }

      await _sendAttachmentOrText(
        messageType: 'file',
        attachmentType: 'file',
        fileName: picked.name,
        fileSize: size,
        mimeType: CloudflareStorageService.inferMimeType(path),
        localFilePath: path,
      );
    } catch (e) {
      debugPrint('[ChatConversationScreen] File pick notice: $e');
    }
  }

  Future<void> _startVoiceRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Microphone permission is required to record voice messages.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/zev_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      HapticFeedback.heavyImpact();
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordingDuration += const Duration(seconds: 1));
        }
      });
    } catch (e) {
      debugPrint('[ChatConversationScreen] Voice start error: $e');
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _recordingTimer?.cancel();
    HapticFeedback.mediumImpact();
    try {
      final path = await _audioRecorder.stop();
      if (path != null) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
      });
    }
  }

  Future<void> _stopAndSendVoiceRecording() async {
    _recordingTimer?.cancel();
    HapticFeedback.mediumImpact();

    try {
      final path = await _audioRecorder.stop();
      final recordedSeconds = _recordingDuration.inSeconds;

      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
      });

      if (path == null || recordedSeconds < 1) {
        if (path != null) {
          final f = File(path);
          if (await f.exists()) await f.delete();
        }
        return;
      }

      final file = File(path);
      final size = await file.length();
      final durationText =
          '${recordedSeconds ~/ 60}:${(recordedSeconds % 60).toString().padLeft(2, '0')}';

      await _sendAttachmentOrText(
        messageText: durationText,
        messageType: 'audio',
        attachmentType: 'audio',
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        fileSize: size,
        mimeType: 'audio/m4a',
        localFilePath: path,
      );
    } catch (e) {
      debugPrint('[ChatConversationScreen] Voice send error: $e');
    }
  }

  Future<void> _toggleReaction(
    DirectMessageModel msg,
    String emoji,
  ) async {
    if (msg.isDeletedForEveryone || msg.id.startsWith('temp_')) return;
    HapticFeedback.lightImpact();

    final currentList = List<MessageReactionSummary>.from(
      _reactions[msg.id] ?? const [],
    );
    final idx = currentList.indexWhere((r) => r.emoji == emoji);
    final currentlyReacted = idx != -1 && currentList[idx].reactedByMe;

    setState(() {
      if (currentlyReacted) {
        final existing = currentList[idx];
        if (existing.count <= 1) {
          currentList.removeAt(idx);
        } else {
          currentList[idx] = MessageReactionSummary(
            emoji: emoji,
            count: existing.count - 1,
            reactedByMe: false,
          );
        }
      } else {
        if (idx != -1) {
          currentList[idx] = MessageReactionSummary(
            emoji: emoji,
            count: currentList[idx].count + 1,
            reactedByMe: true,
          );
        } else {
          currentList.add(
            MessageReactionSummary(
              emoji: emoji,
              count: 1,
              reactedByMe: true,
            ),
          );
        }
      }
      _reactions[msg.id] = currentList;
    });

    try {
      await ChatService.instance.toggleReaction(
        messageId: msg.id,
        emoji: emoji,
        currentlyReacted: currentlyReacted,
      );
    } catch (_) {
      await _fetchReactions();
    }
  }

  void _showAttachmentMenu() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: ZevColors.secondaryBlue,
                ),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: ZevColors.primaryBlue,
                ),
                title: const Text(
                  'Photo from Gallery',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.videocam_rounded,
                  color: Color(0xFF8B5CF6),
                ),
                title: const Text(
                  'Video Message',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendVideo();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.insert_drive_file_rounded,
                  color: Color(0xFF0EA5E9),
                ),
                title: const Text(
                  'Document / File (PDF, ZIP, Office)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageActionMenu(DirectMessageModel msg, bool isMine) {
    HapticFeedback.selectionClick();
    final canEdit = isMine &&
        !msg.isDeletedForEveryone &&
        !msg.id.startsWith('temp_') &&
        msg.effectiveType == 'text' &&
        msg.messageText.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: ZevColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 14),
                if (!msg.isDeletedForEveryone && !msg.id.startsWith('temp_'))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: ZevColors.softSurface,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: ['❤️', '😂', '😮', '😢', '👍', '🔥'].map((em) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _toggleReaction(msg, em);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Text(em, style: const TextStyle(fontSize: 25)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 10),
                if (msg.isFailed && isMine)
                  ListTile(
                    leading: const Icon(
                      Icons.refresh_rounded,
                      color: ZevColors.secondaryBlue,
                    ),
                    title: const Text(
                      'Retry Send',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _retryFailedMessage(msg);
                    },
                  ),
                if (!msg.isDeletedForEveryone && !msg.id.startsWith('temp_')) ...[
                  ListTile(
                    leading: const Icon(
                      Icons.reply_rounded,
                      color: ZevColors.deepNavy,
                    ),
                    title: const Text(
                      'Reply',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _editingMessage = null;
                        _replyingTo = msg;
                      });
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.forward_rounded,
                      color: ZevColors.deepNavy,
                    ),
                    title: const Text(
                      'Forward',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      ForwardPickerSheet.show(context, message: msg);
                    },
                  ),
                ],
                if (canEdit)
                  ListTile(
                    leading: const Icon(
                      Icons.edit_outlined,
                      color: ZevColors.deepNavy,
                    ),
                    title: const Text(
                      'Edit Message',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _replyingTo = null;
                        _editingMessage = msg;
                        _textCtrl.text = msg.messageText;
                      });
                    },
                  ),
                if (!msg.isDeletedForEveryone &&
                    msg.messageText.isNotEmpty &&
                    msg.effectiveType != 'audio')
                  ListTile(
                    leading: const Icon(
                      Icons.copy_rounded,
                      color: ZevColors.deepNavy,
                    ),
                    title: const Text(
                      'Copy Text',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: msg.messageText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied to clipboard'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                if (!isMine && !msg.isDeletedForEveryone && !msg.id.startsWith('temp_'))
                  ListTile(
                    leading: const Icon(
                      Icons.flag_outlined,
                      color: ZevColors.errorRed,
                    ),
                    title: const Text(
                      'Report Message',
                      style: TextStyle(
                        color: ZevColors.errorRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      SocialGraphService.instance.showReportSheet(
                        context,
                        targetType: 'message',
                        targetId: msg.id,
                        reportedUserId: msg.senderId,
                        targetLabel: 'Message',
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: ZevColors.deepNavy,
                  ),
                  title: const Text(
                    'Delete for Me',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _messages.removeWhere((m) => m.id == msg.id));
                    await ChatService.instance.deleteMessageForMe(
                      conversationId: _conversationId,
                      messageId: msg.id,
                    );
                  },
                ),
                if (isMine && !msg.isDeletedForEveryone)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_forever_rounded,
                      color: ZevColors.errorRed,
                    ),
                    title: const Text(
                      'Delete for Everyone',
                      style: TextStyle(
                        color: ZevColors.errorRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ChatService.instance.deleteMessageForEveryone(
                        conversationId: _conversationId,
                        message: msg,
                      );
                      if (mounted) {
                        setState(() {
                          final idx =
                              _messages.indexWhere((m) => m.id == msg.id);
                          if (idx != -1) {
                            if (msg.id.startsWith('temp_')) {
                              _messages.removeAt(idx);
                            } else {
                              _messages[idx] = _messages[idx].copyWith(
                                deletedAt: DateTime.now().toUtc(),
                                messageText: '',
                                attachmentUrl: null,
                              );
                            }
                          }
                        });
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onSearchQueryChanged(String q) {
    _searchDebounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchHits = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final hits = await ChatService.instance.searchInConversation(
        conversationId: _conversationId,
        query: trimmed,
      );
      if (mounted) {
        setState(() {
          _searchHits = hits;
          _isSearching = false;
        });
      }
    });
  }

  void _jumpToMessage(String targetId) {
    final idx = _messages.indexWhere((m) => m.id == targetId);
    if (idx == -1) return;
    setState(() {
      _highlightedMsgId = targetId;
      _showSearchBar = false;
    });
    if (_scrollCtrl.hasClients) {
      final approxOffset = (idx * 76.0)
          .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
      _scrollCtrl.animateTo(
        approxOffset,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlightedMsgId == targetId) {
        setState(() => _highlightedMsgId = null);
      }
    });
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutQuad,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _supabase.auth.currentUser?.id ?? '';
    final msgById = {for (final m in _messages) m.id: m};

    return Scaffold(
      backgroundColor: ZevColors.softSurface,
      appBar: _buildChatAppBar(),
      body: Column(
        children: [
          if (_showSearchBar) _buildInChatSearchBar(),
          if (_hasPendingRequest) _buildMessageRequestBanner(),
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: ZevColors.primaryBlue,
                    ),
                  )
                : _messages.isEmpty
                    ? _buildEmptyConversationView()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        itemCount:
                            _messages.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isLoadingMore && index == _messages.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: ZevColors.primaryBlue,
                                  ),
                                ),
                              ),
                            );
                          }

                          final msg = _messages[index];
                          final isMine = msg.isMine(myId);
                          final reactions = _reactions[msg.id] ?? const [];
                          final parentMsg = msg.replyToMessageId != null
                              ? msgById[msg.replyToMessageId!]
                              : null;

                          final showDate = index == _messages.length - 1 ||
                              !_isSameDay(
                                msg.createdAt,
                                _messages[index + 1].createdAt,
                              );

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showDate) _buildDateSeparator(msg.createdAt),
                              _buildMessageBubble(
                                msg,
                                isMine,
                                reactions,
                                parentMsg,
                              ),
                            ],
                          );
                        },
                      ),
          ),
          if (_peerIsTyping) _buildTypingRow(),
          if (_replyingTo != null) _buildReplyOrEditBanner(isEdit: false),
          if (_editingMessage != null) _buildReplyOrEditBanner(isEdit: true),
          if (!_canMessage)
            _buildBlockedOrRestrictedFooter()
          else
            _isRecording
                ? _buildRecordingInputBar()
                : _buildBottomInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildChatAppBar() {
    final titleText = _isGroup
        ? (_groupTitle.isNotEmpty ? _groupTitle : 'Group Chat')
        : (widget.peerFullName.isNotEmpty
            ? widget.peerFullName
            : '@${widget.peerUsername}');
    final subtitleText = _peerIsTyping
        ? (_isGroup && _typingUsername.isNotEmpty
            ? '@$_typingUsername is typing...'
            : 'typing...')
        : (_isGroup
            ? '${_groupDetails?.members.length ?? 2} members'
            : _peerStatusText);

    final avatar = _isGroup ? _groupAvatar : widget.peerAvatar;

    return AppBar(
      backgroundColor: Colors.white.withValues(alpha: 0.96),
      elevation: 0,
      scrolledUnderElevation: 1,
      leadingWidth: 38,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: ZevColors.deepNavy,
          size: 20,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: GestureDetector(
        onTap: () {
          if (_isGroup && _conversationId.isNotEmpty) {
            GroupInfoSheet.show(
              context,
              conversationId: _conversationId,
              onGroupUpdated: _fetchGroupDetails,
              onLeftGroup: () => Navigator.of(context).pop(),
            );
          } else if (widget.peerId.isNotEmpty) {
            ProfileScreen.open(context, userId: widget.peerId);
          }
        },
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: _isGroup
                      ? ZevColors.primaryBlue.withValues(alpha: 0.14)
                      : ZevColors.border,
                  backgroundImage: avatar.isNotEmpty
                      ? CachedNetworkImageProvider(avatar)
                      : null,
                  child: avatar.isEmpty
                      ? Icon(
                          _isGroup
                              ? Icons.groups_rounded
                              : Icons.person_rounded,
                          color: _isGroup
                              ? ZevColors.secondaryBlue
                              : ZevColors.textMuted,
                          size: 20,
                        )
                      : null,
                ),
                if (!_isGroup && _isPeerOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: ZevColors.successGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          titleText,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: ZevColors.deepNavy,
                          ),
                        ),
                      ),
                      if (!_isGroup && widget.isPeerVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: ZevColors.primaryBlue,
                        ),
                      ],
                    ],
                  ),
                  if (subtitleText.isNotEmpty)
                    Text(
                      subtitleText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: (_peerIsTyping || _isPeerOnline)
                            ? ZevColors.successGreen
                            : ZevColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Search Messages',
          icon: const Icon(
            Icons.search_rounded,
            color: ZevColors.deepNavy,
            size: 21,
          ),
          onPressed: () {
            setState(() {
              _showSearchBar = !_showSearchBar;
              if (!_showSearchBar) {
                _searchCtrl.clear();
                _searchHits = [];
              }
            });
          },
        ),
        if (_isGroup)
          IconButton(
            tooltip: 'Group Info',
            icon: const Icon(
              Icons.info_outline_rounded,
              color: ZevColors.deepNavy,
              size: 21,
            ),
            onPressed: () {
              if (_conversationId.isNotEmpty) {
                GroupInfoSheet.show(
                  context,
                  conversationId: _conversationId,
                  onGroupUpdated: _fetchGroupDetails,
                  onLeftGroup: () => Navigator.of(context).pop(),
                );
              }
            },
          )
        else
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: ZevColors.deepNavy,
            ),
            onSelected: (val) async {
              if (val == 'profile') {
                ProfileScreen.open(context, userId: widget.peerId);
              } else if (val == 'block') {
                final ok = _iBlockedPeer
                    ? await SocialGraphService.instance
                        .unblockUser(widget.peerId)
                    : await SocialGraphService.instance
                        .blockUser(widget.peerId);
                if (ok) await _fetchPolicyAndRequestState();
              } else if (val == 'report') {
                await SocialGraphService.instance.showReportSheet(
                  context,
                  targetType: 'user',
                  targetId: widget.peerId,
                  reportedUserId: widget.peerId,
                  targetLabel: '@${widget.peerUsername}',
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'profile',
                child: Text('View Profile'),
              ),
              PopupMenuItem(
                value: 'block',
                child: Text(
                  _iBlockedPeer ? 'Unblock User' : 'Block User',
                  style: TextStyle(
                    color: _iBlockedPeer
                        ? ZevColors.secondaryBlue
                        : ZevColors.errorRed,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Text(
                  'Report User',
                  style: TextStyle(color: ZevColors.errorRed),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildInChatSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: ZevColors.softSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ZevColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: ZevColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchQueryChanged,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search in conversation...',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (_isSearching)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 17),
                    onPressed: () {
                      setState(() {
                        _showSearchBar = false;
                        _searchCtrl.clear();
                        _searchHits = [];
                      });
                    },
                  ),
              ],
            ),
          ),
          if (_searchHits.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(top: 6),
                itemCount: _searchHits.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (ctx, idx) {
                  final hit = _searchHits[idx];
                  return ActionChip(
                    backgroundColor: ZevColors.softSurface,
                    label: Text(
                      hit.messageText.isNotEmpty
                          ? hit.messageText
                          : (hit.fileName ?? 'Attachment'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _jumpToMessage(hit.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageRequestBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ZevColors.primaryBlue.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '@${widget.peerUsername} wants to send you a message',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: ZevColors.deepNavy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'They will only see that you read their message once you accept or reply.',
            style: TextStyle(fontSize: 12, color: ZevColors.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await ChatService.instance.respondMessageRequest(
                      conversationId: _conversationId,
                      accept: false,
                    );
                    if (mounted) Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZevColors.errorRed,
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    await ChatService.instance.respondMessageRequest(
                      conversationId: _conversationId,
                      accept: true,
                    );
                    if (mounted) setState(() => _hasPendingRequest = false);
                  },
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypingRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ZevColors.border),
          ),
          child: Text(
            _isGroup && _typingUsername.isNotEmpty
                ? '@$_typingUsername is typing...'
                : 'Typing...',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ZevColors.secondaryBlue,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedOrRestrictedFooter() {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _iBlockedPeer
                  ? 'You blocked @${widget.peerUsername}. Unblock to message.'
                  : (_isBlocked
                      ? 'You cannot reply to this conversation.'
                      : 'This account limits who can send direct messages.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ZevColors.textSecondary,
              ),
            ),
            if (_iBlockedPeer) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final ok = await SocialGraphService.instance
                      .unblockUser(widget.peerId);
                  if (ok) await _fetchPolicyAndRequestState();
                },
                child: const Text('Unblock'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    String text;
    if (_isSameDay(date, now)) {
      text = 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      text = 'Yesterday';
    } else {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      text =
          '${date.day} ${months[date.month - 1]}${date.year != now.year ? ' ${date.year}' : ''}';
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4.5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: ZevColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    DirectMessageModel msg,
    bool isMine,
    List<MessageReactionSummary> reactions,
    DirectMessageModel? parentMsg,
  ) {
    final type = msg.effectiveType;
    final isAudio = type == 'audio';
    final isHighlighted = _highlightedMsgId == msg.id;
    final senderInfo = _isGroup ? _memberById[msg.senderId] : null;
    final senderAvatar =
        _isGroup ? (senderInfo?.avatarUrl ?? '') : widget.peerAvatar;

    return Padding(
      padding: EdgeInsets.only(bottom: reactions.isNotEmpty ? 16 : 7),
      child: GestureDetector(
        onLongPress: () => _showMessageActionMenu(msg, isMine),
        onDoubleTap: () => _toggleReaction(msg, '❤️'),
        child: Row(
          mainAxisAlignment:
              isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine) ...[
              GestureDetector(
                onTap: () {
                  if (msg.senderId.isNotEmpty) {
                    ProfileScreen.open(context, userId: msg.senderId);
                  }
                },
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: ZevColors.border,
                  backgroundImage: senderAvatar.isNotEmpty
                      ? CachedNetworkImageProvider(senderAvatar)
                      : null,
                  child: senderAvatar.isEmpty
                      ? const Icon(
                          Icons.person,
                          size: 14,
                          color: ZevColors.textMuted,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.76,
                    minWidth: isAudio ? 240 : 68,
                  ),
                  padding: isAudio
                      ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
                      : (msg.attachmentUrl != null && !msg.isDeletedForEveryone
                          ? const EdgeInsets.all(6)
                          : const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            )),
                  decoration: isMine
                      ? BoxDecoration(
                          gradient: msg.isDeletedForEveryone
                              ? null
                              : ZevColors.brandGradient,
                          color: msg.isDeletedForEveryone
                              ? Colors.white.withValues(alpha: 0.75)
                              : null,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(22),
                            topRight: Radius.circular(22),
                            bottomLeft: Radius.circular(22),
                            bottomRight: Radius.circular(5),
                          ),
                          border: Border.all(
                            color: isHighlighted
                                ? ZevColors.warningAmber
                                : Colors.white.withValues(alpha: 0.4),
                            width: isHighlighted ? 2.2 : 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: ZevColors.secondaryBlue
                                  .withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        )
                      : BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.96),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(22),
                            topRight: Radius.circular(22),
                            bottomLeft: Radius.circular(5),
                            bottomRight: Radius.circular(22),
                          ),
                          border: Border.all(
                            color: isHighlighted
                                ? ZevColors.warningAmber
                                : Colors.white,
                            width: isHighlighted ? 2.2 : 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  ZevColors.deepNavy.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                  child: Column(
                    crossAxisAlignment: isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (_isGroup && !isMine && senderInfo != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '@${senderInfo.username}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: ZevColors.secondaryBlue,
                            ),
                          ),
                        ),
                      if (msg.isForwarded && !msg.isDeletedForEveryone)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.forward_rounded,
                                size: 12,
                                color: isMine
                                    ? Colors.white.withValues(alpha: 0.85)
                                    : ZevColors.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Forwarded',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontStyle: FontStyle.italic,
                                  color: isMine
                                      ? Colors.white.withValues(alpha: 0.85)
                                      : ZevColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (parentMsg != null && !msg.isDeletedForEveryone)
                        GestureDetector(
                          onTap: () => _jumpToMessage(parentMsg.id),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isMine
                                  ? Colors.white.withValues(alpha: 0.18)
                                  : ZevColors.softSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border(
                                left: BorderSide(
                                  color: isMine
                                      ? Colors.white
                                      : ZevColors.primaryBlue,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Text(
                              parentMsg.messageText.isNotEmpty
                                  ? parentMsg.messageText
                                  : (parentMsg.fileName ?? 'Attachment'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isMine
                                    ? Colors.white.withValues(alpha: 0.92)
                                    : ZevColors.textSecondary,
                              ),
                            ),
                          ),
                        ),

                      if (msg.isDeletedForEveryone)
                        Text(
                          'This message was deleted',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontStyle: FontStyle.italic,
                            color: ZevColors.textMuted,
                          ),
                        )
                      else ...[
                        if (type == 'image' &&
                            (msg.attachmentUrl ?? '').isNotEmpty) ...[
                          GestureDetector(
                            onTap: () =>
                                _openFullScreenImage(msg.attachmentUrl!),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: CachedNetworkImage(
                                imageUrl: msg.attachmentUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => Container(
                                  height: 180,
                                  color: ZevColors.border,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (msg.messageText.isNotEmpty)
                            const SizedBox(height: 6),
                        ] else if (type == 'video' &&
                            (msg.attachmentUrl ?? '').isNotEmpty) ...[
                          VideoMessageBubblePlayer(
                            videoUrl: msg.attachmentUrl!,
                            isMine: isMine,
                          ),
                        ] else if (type == 'audio' &&
                            (msg.attachmentUrl ?? '').isNotEmpty) ...[
                          VoiceMessageBubblePlayer(
                            audioUrl: msg.attachmentUrl!,
                            durationText: msg.messageText.isNotEmpty
                                ? msg.messageText
                                : '0:05',
                            isMine: isMine,
                          ),
                        ] else if (type == 'file') ...[
                          FileMessageCard(
                            fileName: msg.fileName ?? 'Document',
                            fileSize: msg.fileSize,
                            url: msg.attachmentUrl,
                            isMine: isMine,
                          ),
                        ] else if (type == 'post_share' ||
                            type == 'reel_share') ...[
                          SharedContentMessageCard(
                            message: msg,
                            isMine: isMine,
                          ),
                        ],

                        if (msg.messageText.isNotEmpty &&
                            !isAudio &&
                            type != 'post_share' &&
                            type != 'reel_share')
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: msg.attachmentUrl != null ? 6 : 0,
                              vertical: msg.attachmentUrl != null ? 4 : 0,
                            ),
                            child: Text(
                              msg.messageText,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color:
                                    isMine ? Colors.white : ZevColors.deepNavy,
                                height: 1.35,
                              ),
                            ),
                          ),
                      ],

                      if (msg.isFailed && isMine) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _retryFailedMessage(msg),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: ZevColors.errorRed,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Failed • Tap to Retry',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (msg.isEdited && !msg.isDeletedForEveryone) ...[
                            Text(
                              'Edited • ',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isMine
                                    ? Colors.white.withValues(alpha: 0.82)
                                    : ZevColors.textMuted,
                              ),
                            ),
                          ],
                          Text(
                            _formatTime(msg.createdAt),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: isMine && !msg.isDeletedForEveryone
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : ZevColors.textMuted,
                            ),
                          ),
                          if (isMine && !msg.isDeletedForEveryone) ...[
                            const SizedBox(width: 4),
                            _buildTickStatus(msg),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                if (reactions.isNotEmpty)
                  Positioned(
                    bottom: -12,
                    right: isMine ? 8 : null,
                    left: isMine ? null : 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: ZevColors.border, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: ZevColors.deepNavy.withValues(alpha: 0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: reactions.map((r) {
                          return GestureDetector(
                            onTap: () => _toggleReaction(msg, r.emoji),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2.5),
                              child: Text(
                                r.count > 1
                                    ? '${r.emoji} ${r.count}'
                                    : r.emoji,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: r.reactedByMe
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: r.reactedByMe
                                      ? ZevColors.secondaryBlue
                                      : ZevColors.deepNavy,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTickStatus(DirectMessageModel msg) {
    if (msg.isFailed) {
      return const Icon(
        Icons.error_outline_rounded,
        size: 14,
        color: Color(0xFFFEE2E2),
      );
    }
    if (msg.isPending) {
      return Icon(
        Icons.schedule_rounded,
        size: 13,
        color: Colors.white.withValues(alpha: 0.75),
      );
    }
    if (msg.isRead) {
      return const Icon(
        Icons.done_all_rounded,
        size: 15,
        color: Colors.white,
      );
    } else if (msg.isDelivered) {
      return Icon(
        Icons.done_all_rounded,
        size: 15,
        color: Colors.white.withValues(alpha: 0.72),
      );
    }
    return Icon(
      Icons.done_rounded,
      size: 15,
      color: Colors.white.withValues(alpha: 0.72),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  Widget _buildReplyOrEditBanner({required bool isEdit}) {
    final target = isEdit ? _editingMessage! : _replyingTo!;
    final preview = target.effectiveType == 'audio'
        ? '🎙️ Voice message (${target.messageText})'
        : (target.messageText.isNotEmpty
            ? target.messageText
            : (target.fileName ?? 'Attachment'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 34,
            decoration: BoxDecoration(
              color: isEdit ? ZevColors.secondaryBlue : ZevColors.primaryBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEdit ? 'Editing message' : 'Replying to',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isEdit
                        ? ZevColors.secondaryBlue
                        : ZevColors.primaryBlue,
                  ),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: ZevColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: ZevColors.textMuted,
            ),
            onPressed: () {
              setState(() {
                if (isEdit) {
                  _editingMessage = null;
                  _textCtrl.clear();
                } else {
                  _replyingTo = null;
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingInputBar() {
    final durationStr =
        '${_recordingDuration.inMinutes}:${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: ZevColors.errorRed,
                size: 24,
              ),
              tooltip: 'Cancel Recording',
              onPressed: _cancelVoiceRecording,
            ),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFFFE4E6)),
                ),
                child: Row(
                  children: [
                    const _PulsingRedDot(),
                    const SizedBox(width: 8),
                    Text(
                      durationStr,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFE11D48),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(child: _LiveRecordingWaveform()),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _stopAndSendVoiceRecording,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  gradient: ZevColors.brandGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomInputBar() {
    final hasText = _textCtrl.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(7.5),
                decoration: BoxDecoration(
                  color: ZevColors.softSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: ZevColors.border),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: ZevColors.deepNavy,
                  size: 20,
                ),
              ),
              tooltip: 'Attach Photo, Video or File',
              onPressed: _showAttachmentMenu,
            ),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(7.5),
                decoration: BoxDecoration(
                  color: ZevColors.softSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: ZevColors.border),
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: ZevColors.deepNavy,
                  size: 18,
                ),
              ),
              tooltip: 'Gallery',
              onPressed: () => _pickAndSendImage(ImageSource.gallery),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: ZevColors.softSurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: ZevColors.border, width: 1.2),
                ),
                child: TextField(
                  controller: _textCtrl,
                  onChanged: (val) {
                    setState(() {});
                    _broadcastTyping(val.trim().isNotEmpty);
                  },
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 4,
                  minLines: 1,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: ZevColors.deepNavy,
                  ),
                  decoration: InputDecoration(
                    hintText: _editingMessage != null
                        ? 'Edit message...'
                        : 'Message...',
                    hintStyle: const TextStyle(
                      color: ZevColors.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (_isSending)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ZevColors.primaryBlue,
                  ),
                ),
              )
            else if (hasText)
              GestureDetector(
                onTap: _sendTextOrEdit,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    gradient: ZevColors.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _editingMessage != null
                        ? Icons.check_rounded
                        : Icons.send_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
              )
            else
              GestureDetector(
                onLongPressStart: (_) => _startVoiceRecording(),
                onLongPressMoveUpdate: (details) {
                  if (details.offsetFromOrigin.dx < -70) {
                    _cancelVoiceRecording();
                  }
                },
                onLongPressEnd: (_) => _stopAndSendVoiceRecording(),
                onTap: _startVoiceRecording,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: ZevColors.softSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: ZevColors.border, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: ZevColors.deepNavy,
                    size: 21,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openFullScreenImage(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyConversationView() {
    final avatar = _isGroup ? _groupAvatar : widget.peerAvatar;
    final title = _isGroup
        ? (_groupTitle.isNotEmpty ? _groupTitle : 'Group Chat')
        : (widget.peerFullName.isNotEmpty
            ? widget.peerFullName
            : '@${widget.peerUsername}');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: _isGroup
                  ? ZevColors.primaryBlue.withValues(alpha: 0.14)
                  : ZevColors.border,
              backgroundImage:
                  avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
              child: avatar.isEmpty
                  ? Icon(
                      _isGroup ? Icons.groups_rounded : Icons.person_rounded,
                      color: ZevColors.textMuted,
                      size: 42,
                    )
                  : null,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ZevColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Say hi, share a file, or send a voice message to start chatting.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ZevColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingRedDot extends StatefulWidget {
  const _PulsingRedDot();

  @override
  State<_PulsingRedDot> createState() => _PulsingRedDotState();
}

class _PulsingRedDotState extends State<_PulsingRedDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: ZevColors.errorRed
                .withValues(alpha: 0.4 + (_ctrl.value * 0.6)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class _LiveRecordingWaveform extends StatefulWidget {
  const _LiveRecordingWaveform();

  @override
  State<_LiveRecordingWaveform> createState() => _LiveRecordingWaveformState();
}

class _LiveRecordingWaveformState extends State<_LiveRecordingWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(14, (i) {
            final t = (_controller.value + (i * 0.15)) % 1.0;
            final height = 4.0 + (16.0 * (0.5 - (t - 0.5).abs()) * 2.0);
            return Container(
              width: 2.5,
              height: height,
              decoration: BoxDecoration(
                color: const Color(0xFFE11D48),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

/// In-Bubble Voice Message Player
class VoiceMessageBubblePlayer extends StatefulWidget {
  final String audioUrl;
  final String durationText;
  final bool isMine;

  const VoiceMessageBubblePlayer({
    super.key,
    required this.audioUrl,
    required this.durationText,
    required this.isMine,
  });

  @override
  State<VoiceMessageBubblePlayer> createState() =>
      _VoiceMessageBubblePlayerState();
}

class _VoiceMessageBubblePlayerState extends State<VoiceMessageBubblePlayer> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;

  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _completeSub;

  static const List<double> _waveBars = [
    0.35, 0.65, 0.90, 0.45, 0.75, 1.00, 0.60, 0.40,
    0.80, 0.95, 0.50, 0.70, 0.85, 0.55, 0.35, 0.70,
    0.90, 0.60, 0.80, 0.50, 0.65, 0.40, 0.55, 0.30,
  ];

  @override
  void initState() {
    super.initState();
    _parseInitialDuration();

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _posSub = _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _currentPosition = pos);
    });
    _durSub = _player.onDurationChanged.listen((dur) {
      if (mounted && dur.inMilliseconds > 0) {
        setState(() => _totalDuration = dur);
      }
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playerState = PlayerState.stopped;
          _currentPosition = Duration.zero;
        });
      }
    });
  }

  void _parseInitialDuration() {
    final parts = widget.durationText.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      _totalDuration = Duration(minutes: m, seconds: s);
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    HapticFeedback.selectionClick();
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.audioUrl));
      await _player.setPlaybackRate(_playbackSpeed);
    }
  }

  void _toggleSpeed() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 1.0;
      }
    });
    _player.setPlaybackRate(_playbackSpeed);
  }

  void _seekToRatio(double ratio) {
    if (_totalDuration.inMilliseconds > 0) {
      final targetMs = (_totalDuration.inMilliseconds * ratio).round();
      _player.seek(Duration(milliseconds: targetMs));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _playerState == PlayerState.playing;
    final totalMs = _totalDuration.inMilliseconds;
    final currMs = _currentPosition.inMilliseconds;
    final progressRatio =
        totalMs > 0 ? (currMs / totalMs).clamp(0.0, 1.0) : 0.0;

    final displayTime = isPlaying || currMs > 0
        ? '${_currentPosition.inMinutes}:${(_currentPosition.inSeconds % 60).toString().padLeft(2, '0')}'
        : widget.durationText;

    final activeColor = widget.isMine ? Colors.white : ZevColors.primaryBlue;
    final inactiveColor = widget.isMine
        ? Colors.white.withValues(alpha: 0.4)
        : ZevColors.border;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.isMine ? Colors.white : ZevColors.primaryBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color:
                    widget.isMine ? ZevColors.secondaryBlue : Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box != null) {
                      final ratio =
                          (details.localPosition.dx / box.size.width)
                              .clamp(0.0, 1.0);
                      _seekToRatio(ratio);
                    }
                  },
                  onTapDown: (details) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box != null) {
                      final ratio =
                          (details.localPosition.dx / box.size.width)
                              .clamp(0.0, 1.0);
                      _seekToRatio(ratio);
                    }
                  },
                  child: SizedBox(
                    height: 26,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(_waveBars.length, (idx) {
                        final barRatio = idx / _waveBars.length;
                        final isPassed = barRatio <= progressRatio;
                        final barHeight = 6.0 + (18.0 * _waveBars[idx]);

                        return Container(
                          width: 2.6,
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: isPassed ? activeColor : inactiveColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayTime,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: widget.isMine
                        ? Colors.white.withValues(alpha: 0.9)
                        : ZevColors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _toggleSpeed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: widget.isMine
                    ? Colors.white.withValues(alpha: 0.25)
                    : ZevColors.softSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_playbackSpeed == 1.0 ? '1' : _playbackSpeed}x',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: widget.isMine ? Colors.white : ZevColors.deepNavy,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
