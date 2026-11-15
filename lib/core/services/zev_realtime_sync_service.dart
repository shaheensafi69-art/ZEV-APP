import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'badge_counter_service.dart';
import 'zev_rtc_service.dart';

/// Realtime Post Like change event
class ZevPostLikeUpdate {
  final String postId;
  final String userId;
  final bool isLiked; // true = liked, false = unliked

  const ZevPostLikeUpdate({
    required this.postId,
    required this.userId,
    required this.isLiked,
  });
}

/// Realtime Post Comment change event
class ZevPostCommentUpdate {
  final String postId;
  final String commentId;
  final bool isAdded; // true = added, false = deleted

  const ZevPostCommentUpdate({
    required this.postId,
    required this.commentId,
    required this.isAdded,
  });
}

/// Realtime Follow change event
class ZevFollowUpdate {
  final String followerId;
  final String followingId;
  final bool isFollowing; // true = followed, false = unfollowed

  const ZevFollowUpdate({
    required this.followerId,
    required this.followingId,
    required this.isFollowing,
  });
}

/// Realtime Post lifecycle event (created, updated, deleted)
class ZevPostLifecycleUpdate {
  final String postId;
  final String authorId;
  final String action; // 'insert', 'update', 'delete'

  const ZevPostLifecycleUpdate({
    required this.postId,
    required this.authorId,
    required this.action,
  });
}

/// Realtime Call Session event
class ZevCallSessionUpdate {
  final String sessionId;
  final String callerId;
  final String calleeId;
  final String status;
  final bool isVideo;

  const ZevCallSessionUpdate({
    required this.sessionId,
    required this.callerId,
    required this.calleeId,
    required this.status,
    required this.isVideo,
  });
}

/// Realtime Direct Message event
class ZevMessageUpdate {
  final String messageId;
  final String conversationId;
  final String senderId;
  final String receiverId;
  final String messageType;
  final String messageText;

  const ZevMessageUpdate({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.receiverId,
    required this.messageType,
    required this.messageText,
  });
}

/// Centralized Full-Database Realtime Synchronization Engine for ZEV.
/// Listens to all interactive database tables (notifications, likes, comments,
/// calls, messages, follows, posts, stories, live streams) and dispatches typed
/// broadcast events across Android, iOS, and Web seamlessly.
class ZevRealtimeSyncService {
  ZevRealtimeSyncService._();
  static final ZevRealtimeSyncService instance = ZevRealtimeSyncService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  // Broadcast stream controllers
  final _likeCtrl = StreamController<ZevPostLikeUpdate>.broadcast();
  final _commentCtrl = StreamController<ZevPostCommentUpdate>.broadcast();
  final _followCtrl = StreamController<ZevFollowUpdate>.broadcast();
  final _postCtrl = StreamController<ZevPostLifecycleUpdate>.broadcast();
  final _callCtrl = StreamController<ZevCallSessionUpdate>.broadcast();
  final _messageCtrl = StreamController<ZevMessageUpdate>.broadcast();
  final _storyCtrl = StreamController<void>.broadcast();
  final _liveCtrl = StreamController<void>.broadcast();

  // Public Streams
  Stream<ZevPostLikeUpdate> get onLikeUpdate => _likeCtrl.stream;
  Stream<ZevPostCommentUpdate> get onCommentUpdate => _commentCtrl.stream;
  Stream<ZevFollowUpdate> get onFollowUpdate => _followCtrl.stream;
  Stream<ZevPostLifecycleUpdate> get onPostUpdate => _postCtrl.stream;
  Stream<ZevCallSessionUpdate> get onCallUpdate => _callCtrl.stream;
  Stream<ZevMessageUpdate> get onMessageUpdate => _messageCtrl.stream;
  Stream<void> get onStoryUpdate => _storyCtrl.stream;
  Stream<void> get onLiveStreamUpdate => _liveCtrl.stream;

  // Global pulse notifier for screens observing overall database state changes
  final ValueNotifier<int> globalSyncTick = ValueNotifier<int>(0);

  RealtimeChannel? _userChannel;
  RealtimeChannel? _socialChannel;
  String? _currentSubscribedUid;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    // Listen to authentication changes
    _supabase.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) {
        startSync(user.id);
      } else {
        stopSync();
      }
    });

    final currentUid = _supabase.auth.currentUser?.id;
    if (currentUid != null && currentUid.isNotEmpty) {
      startSync(currentUid);
    }
  }

  void startSync(String uid) {
    if (_currentSubscribedUid == uid && _userChannel != null) {
      return;
    }
    stopSync();
    _currentSubscribedUid = uid;

    _subscribeUserScopedChannel(uid);
    _subscribeGlobalSocialChannel();
  }

  void stopSync() {
    _currentSubscribedUid = null;
    final uc = _userChannel;
    _userChannel = null;
    if (uc != null) {
      unawaited(uc.unsubscribe());
    }
    final sc = _socialChannel;
    _socialChannel = null;
    if (sc != null) {
      unawaited(sc.unsubscribe());
    }
  }

  /// 1. User-Scoped Channel: Notifications, Calls, Direct Messages, Follows
  void _subscribeUserScopedChannel(String uid) {
    try {
      _userChannel = _supabase
          .channel('zev_user_sync:$uid')
          // Notifications
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'user_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: (payload) {
              _notifyTick();
              BadgeCounterService.instance.scheduleRefresh();
            },
          )
          // Call Sessions (as Callee)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'call_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'callee_id',
              value: uid,
            ),
            callback: (payload) {
              _handleCallSessionPayload(payload);
            },
          )
          // Call Sessions (as Caller)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'call_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'caller_id',
              value: uid,
            ),
            callback: (payload) {
              _handleCallSessionPayload(payload);
            },
          )
          // Group Call Participants
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'call_participants',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: (_) {
              _notifyTick();
              unawaited(ZevRtcService.instance.checkPendingIncomingCalls());
            },
          )
          // Direct Messages (Incoming)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'direct_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'receiver_id',
              value: uid,
            ),
            callback: (payload) {
              _handleMessagePayload(payload);
            },
          )
          // Follows (Someone followed me)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'user_follows',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'following_id',
              value: uid,
            ),
            callback: (payload) {
              _handleFollowPayload(payload, isTargetMe: true);
            },
          )
          // Follows (I followed someone)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'user_follows',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'follower_id',
              value: uid,
            ),
            callback: (payload) {
              _handleFollowPayload(payload, isTargetMe: false);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[ZevRealtimeSyncService] user sync notice: $e');
    }
  }

  /// 2. Global Social Channel: Likes, Comments, Posts, Stories, Live Streams
  void _subscribeGlobalSocialChannel() {
    try {
      _socialChannel = _supabase
          .channel('zev_social_sync')
          // Discussion Likes
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'discussion_likes',
            callback: (payload) {
              _handleLikePayload(payload);
            },
          )
          // Discussion Comments
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'discussion_comments',
            callback: (payload) {
              _handleCommentPayload(payload);
            },
          )
          // Discussion Posts
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'discussion_posts',
            callback: (payload) {
              _handlePostPayload(payload);
            },
          )
          // Stories
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'user_stories',
            callback: (_) {
              _notifyTick();
              _storyCtrl.add(null);
            },
          )
          // Live Streams
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'live_streams',
            callback: (_) {
              _notifyTick();
              _liveCtrl.add(null);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[ZevRealtimeSyncService] social sync notice: $e');
    }
  }

  void _handleLikePayload(PostgresChangePayload payload) {
    try {
      final isInsert = payload.eventType == PostgresChangeEvent.insert;
      final isDelete = payload.eventType == PostgresChangeEvent.delete;
      if (!isInsert && !isDelete) return;

      final record = isInsert ? payload.newRecord : payload.oldRecord;
      final postId = (record['post_id'] ?? '').toString().trim();
      final userId = (record['student_id'] ?? record['user_id'] ?? '').toString().trim();

      if (postId.isNotEmpty) {
        _likeCtrl.add(ZevPostLikeUpdate(
          postId: postId,
          userId: userId,
          isLiked: isInsert,
        ));
        _notifyTick();
      }
    } catch (e) {
      debugPrint('[ZevRealtimeSyncService] like payload error: $e');
    }
  }

  void _handleCommentPayload(PostgresChangePayload payload) {
    try {
      final isInsert = payload.eventType == PostgresChangeEvent.insert;
      final isDelete = payload.eventType == PostgresChangeEvent.delete;
      if (!isInsert && !isDelete) return;

      final record = isInsert ? payload.newRecord : payload.oldRecord;
      final postId = (record['post_id'] ?? '').toString().trim();
      final commentId = (record['id'] ?? '').toString().trim();

      if (postId.isNotEmpty) {
        _commentCtrl.add(ZevPostCommentUpdate(
          postId: postId,
          commentId: commentId,
          isAdded: isInsert,
        ));
        _notifyTick();
      }
    } catch (e) {
      debugPrint('[ZevRealtimeSyncService] comment payload error: $e');
    }
  }

  void _handleFollowPayload(PostgresChangePayload payload, {required bool isTargetMe}) {
    try {
      final isInsert = payload.eventType == PostgresChangeEvent.insert;
      final isDelete = payload.eventType == PostgresChangeEvent.delete;
      if (!isInsert && !isDelete) return;

      final record = isInsert ? payload.newRecord : payload.oldRecord;
      final followerId = (record['follower_id'] ?? '').toString().trim();
      final followingId = (record['following_id'] ?? '').toString().trim();

      if (followerId.isNotEmpty && followingId.isNotEmpty) {
        _followCtrl.add(ZevFollowUpdate(
          followerId: followerId,
          followingId: followingId,
          isFollowing: isInsert,
        ));
        _notifyTick();
      }
    } catch (e) {
      debugPrint('[ZevRealtimeSyncService] follow payload error: $e');
    }
  }

  void _handlePostPayload(PostgresChangePayload payload) {
    try {
      final record = payload.eventType == PostgresChangeEvent.delete
          ? payload.oldRecord
          : payload.newRecord;
      final postId = (record['id'] ?? '').toString().trim();
      final authorId = (record['student_id'] ?? '').toString().trim();
      final action = payload.eventType.name.toLowerCase();

      if (postId.isNotEmpty) {
        _postCtrl.add(ZevPostLifecycleUpdate(
          postId: postId,
          authorId: authorId,
          action: action,
        ));
        _notifyTick();
      }
    } catch (e) {
      debugPrint('[ZevRealtimeSyncService] post payload error: $e');
    }
  }

  void _handleCallSessionPayload(PostgresChangePayload payload) {
    try {
      final record = payload.newRecord;
      if (record.isEmpty) return;

      final sessionId = (record['id'] ?? '').toString().trim();
      final callerId = (record['caller_id'] ?? '').toString().trim();
      final calleeId = (record['callee_id'] ?? '').toString().trim();
      final status = (record['status'] ?? '').toString().trim();
      final isVideo = (record['call_type'] ?? 'video').toString().toLowerCase() == 'video';

      _callCtrl.add(ZevCallSessionUpdate(
        sessionId: sessionId,
        callerId: callerId,
        calleeId: calleeId,
        status: status,
        isVideo: isVideo,
      ));
      _notifyTick();

      // Proactively notify RTC engine of pending calls
      if (status == 'ringing' || status == 'initiated') {
        unawaited(ZevRtcService.instance.checkPendingIncomingCalls());
      }
    } catch (e) {
      debugPrint('[ZevRealtimeSyncService] call payload error: $e');
    }
  }

  void _handleMessagePayload(PostgresChangePayload payload) {
    try {
      final record = payload.newRecord;
      if (record.isEmpty) return;

      final msgId = (record['id'] ?? '').toString().trim();
      final convId = (record['conversation_id'] ?? '').toString().trim();
      final senderId = (record['sender_id'] ?? '').toString().trim();
      final receiverId = (record['receiver_id'] ?? '').toString().trim();
      final msgType = (record['message_type'] ?? 'text').toString();
      final msgText = (record['message_text'] ?? '').toString();

      _messageCtrl.add(ZevMessageUpdate(
        messageId: msgId,
        conversationId: convId,
        senderId: senderId,
        receiverId: receiverId,
        messageType: msgType,
        messageText: msgText,
      ));
      _notifyTick();
      BadgeCounterService.instance.scheduleRefresh();
    } catch (e) {
      debugPrint('[ZevRealtimeSyncService] message payload error: $e');
    }
  }

  void _notifyTick() {
    globalSyncTick.value++;
  }
}

