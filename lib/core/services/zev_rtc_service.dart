import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/calls/screens/call_screen.dart';
import '../../main.dart';
import '../config/app_config.dart';
import 'api_client.dart';

class ZevAgoraCredentials {
  final String appId;
  final String channelName;
  final String token;
  final int uid;
  final String role;
  final DateTime? expiresAt;

  const ZevAgoraCredentials({
    required this.appId,
    required this.channelName,
    required this.token,
    required this.uid,
    required this.role,
    this.expiresAt,
  });

  bool get isPublisher => role == 'publisher';

  factory ZevAgoraCredentials.fromJson(Map<String, dynamic> json) {
    return ZevAgoraCredentials(
      appId: (json['appId'] ?? '').toString().trim(),
      channelName: (json['channelName'] ?? '').toString().trim(),
      token: (json['token'] ?? '').toString().trim(),
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      role: (json['role'] ?? 'subscriber').toString().trim(),
      expiresAt: DateTime.tryParse((json['expiresAt'] ?? '').toString()),
    );
  }
}

class ZevCallSession {
  final String id;
  final String callerId;
  final String calleeId;
  final String? conversationId;
  final String callType;
  final String status;
  final String agoraChannel;
  final int durationSeconds;
  final bool isGroup;
  final String? title;
  final int maxParticipants;
  final DateTime? startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  const ZevCallSession({
    required this.id,
    required this.callerId,
    required this.calleeId,
    this.conversationId,
    required this.callType,
    required this.status,
    required this.agoraChannel,
    this.durationSeconds = 0,
    this.isGroup = false,
    this.title,
    this.maxParticipants = 8,
    this.startedAt,
    this.answeredAt,
    this.endedAt,
  });

  bool get isVideo => callType == 'video';
  bool get isRinging => status == 'ringing';
  bool get isAccepted => status == 'accepted';
  bool get isActive => status == 'ringing' || status == 'accepted';

  factory ZevCallSession.fromMap(Map<String, dynamic> map) {
    return ZevCallSession(
      id: (map['id'] ?? '').toString(),
      callerId: (map['caller_id'] ?? '').toString(),
      calleeId: (map['callee_id'] ?? '').toString(),
      conversationId: map['conversation_id']?.toString(),
      callType: (map['call_type'] ?? 'voice').toString(),
      status: (map['status'] ?? 'ringing').toString(),
      agoraChannel: (map['agora_channel'] ?? '').toString(),
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      isGroup: map['is_group'] == true,
      title: map['title']?.toString(),
      maxParticipants: (map['max_participants'] as num?)?.toInt() ?? 8,
      startedAt: DateTime.tryParse((map['started_at'] ?? '').toString()),
      answeredAt: DateTime.tryParse((map['answered_at'] ?? '').toString()),
      endedAt: DateTime.tryParse((map['ended_at'] ?? '').toString()),
    );
  }
}

class ZevCallParticipant {
  final String id;
  final String callSessionId;
  final String userId;
  final String role;
  final String status;
  final DateTime? joinedAt;
  final DateTime? leftAt;
  final Map<String, dynamic> profile;

  const ZevCallParticipant({
    required this.id,
    required this.callSessionId,
    required this.userId,
    required this.role,
    required this.status,
    this.joinedAt,
    this.leftAt,
    this.profile = const {},
  });

  bool get isJoined => status == 'joined';
  bool get isRinging => status == 'ringing';
  bool get isHost => role == 'host';

  factory ZevCallParticipant.fromMap(
    Map<String, dynamic> map, {
    Map<String, dynamic>? profile,
  }) {
    return ZevCallParticipant(
      id: (map['id'] ?? '').toString(),
      callSessionId: (map['call_session_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      role: (map['role'] ?? 'participant').toString(),
      status: (map['status'] ?? 'invited').toString(),
      joinedAt: DateTime.tryParse((map['joined_at'] ?? '').toString()),
      leftAt: DateTime.tryParse((map['left_at'] ?? '').toString()),
      profile: profile ??
          (map['profiles'] is Map
              ? Map<String, dynamic>.from(map['profiles'])
              : const {}),
    );
  }
}

/// Client-side signaling, global incoming-call listener & Agora RTC token service
/// for ZEV Voice Calls, Video Calls, Group Calls, and Interactive Live Broadcasting.
class ZevRtcService {
  ZevRtcService._();
  static final ZevRtcService instance = ZevRtcService._();

  final _supabase = Supabase.instance.client;

  RealtimeChannel? _incomingChannel;
  String? _listeningUserId;
  String? activeCallId;
  final Set<String> _handledCallIds = {};

  // Token cache to eliminate RTC connection latency
  final Map<String, ZevAgoraCredentials> _tokenCache = {};

  // Pre-warmed Agora RTC Engine instance
  RtcEngine? _warmEngine;
  bool _isEngineInitializing = false;

  // Persistent in-app minimized floating call bar state
  final ValueNotifier<ZevCallSession?> minimizedCallNotifier = ValueNotifier(null);
  Map<String, dynamic>? minimizedPeerProfile;
  int minimizedDurationSeconds = 0;
  bool isMinimizedMicMuted = false;

  void setActiveCall(String? callId) {
    activeCallId = (callId != null && callId.trim().isNotEmpty)
        ? callId.trim()
        : null;
  }

  void clearActiveCall(String callId) {
    if (activeCallId == callId) {
      activeCallId = null;
    }
  }

  /// Obtains or initializes the pre-warmed Agora RTC Engine.
  /// Eliminates the 1.5s cold-start initialization delay during call pickup.
  Future<RtcEngine> getOrInitializeEngine({String? appId}) async {
    if (_warmEngine != null) {
      return _warmEngine!;
    }
    if (_isEngineInitializing) {
      while (_isEngineInitializing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_warmEngine != null) return _warmEngine!;
    }

    _isEngineInitializing = true;
    try {
      final resolvedAppId = (appId != null && appId.isNotEmpty)
          ? appId
          : AppConfig.agoraAppId;
      final engine = createAgoraRtcEngine();
      await engine.initialize(
        RtcEngineContext(
          appId: resolvedAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          audioScenario: AudioScenarioType.audioScenarioDefault,
        ),
      );
      _warmEngine = engine;
      return engine;
    } finally {
      _isEngineInitializing = false;
    }
  }

  Future<void> releaseWarmEngine() async {
    final eng = _warmEngine;
    _warmEngine = null;
    if (eng != null) {
      try {
        await eng.leaveChannel();
      } catch (_) {}
      try {
        await eng.release();
      } catch (_) {}
    }
  }

  /// Subscribes to live incoming calls (`public.call_sessions`) for the
  /// signed-in user and opens `CallScreen` automatically when ringing.
  void startIncomingCallListener() {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      stopIncomingCallListener();
      return;
    }
    if (_listeningUserId == uid && _incomingChannel != null) {
      unawaited(checkPendingIncomingCalls());
      return;
    }

    stopIncomingCallListener();
    _listeningUserId = uid;

    try {
      _incomingChannel = _supabase
          .channel('incoming_calls:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'call_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'callee_id',
              value: uid,
            ),
            callback: (payload) {
              final rec = payload.newRecord;
              if (rec.isNotEmpty) {
                unawaited(_handleIncomingRow(Map<String, dynamic>.from(rec)));
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[ZevRtcService] incoming listener notice: $e');
    }

    unawaited(checkPendingIncomingCalls());
  }

  void stopIncomingCallListener() {
    final ch = _incomingChannel;
    _incomingChannel = null;
    _listeningUserId = null;
    if (ch != null) {
      unawaited(ch.unsubscribe());
    }
  }

  /// Checks for any fresh incoming call ringing right now (useful on cold start / app resume).
  Future<void> checkPendingIncomingCalls() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    try {
      final cutoff =
          DateTime.now().toUtc().subtract(const Duration(seconds: 65)).toIso8601String();
      final res = await _supabase
          .from('call_sessions')
          .select()
          .eq('callee_id', uid)
          .eq('status', 'ringing')
          .gte('started_at', cutoff)
          .order('started_at', ascending: false)
          .limit(1);

      final list = (res as List).whereType<Map>().toList();
      if (list.isNotEmpty) {
        await _handleIncomingRow(Map<String, dynamic>.from(list.first));
      }
    } catch (e) {
      debugPrint('[ZevRtcService] checkPendingIncomingCalls notice: $e');
    }
  }

  Future<void> _handleIncomingRow(Map<String, dynamic> raw) async {
    final session = ZevCallSession.fromMap(raw);
    if (session.id.isEmpty || !session.isRinging) return;

    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || session.calleeId != myId) return;

    final started = session.startedAt;
    if (started != null &&
        DateTime.now().toUtc().difference(started).inSeconds > 75) {
      return;
    }

    if (activeCallId == session.id || _handledCallIds.contains(session.id)) {
      return;
    }

    // Pre-warm Agora engine and pre-fetch token immediately in background!
    // This allows near-instant connection when receiver taps Accept!
    unawaited(
      fetchCallToken(callSessionId: session.id)
          .then<void>((_) {})
          .catchError((_) {}),
    );
    unawaited(
      getOrInitializeEngine()
          .then<void>((_) {})
          .catchError((_) {}),
    );

    // If user is already busy on another active call, signal busy cleanly.
    if (activeCallId != null && activeCallId != session.id) {
      _handledCallIds.add(session.id);
      unawaited(
        respondCall(
          callId: session.id,
          action: 'busy',
          reason: 'busy_on_other_call',
        ).catchError((_) => session),
      );
      return;
    }

    final navState = appNavigatorKey.currentState;
    if (navState == null || !navState.mounted) return;

    _handledCallIds.add(session.id);
    if (_handledCallIds.length > 50) {
      _handledCallIds.remove(_handledCallIds.first);
    }

    final peerProfile = await fetchProfileSummary(session.callerId);

    // Re-verify row is still ringing before presenting incoming screen.
    final latest = await fetchCallById(session.id);
    if (latest == null || !latest.isRinging) return;
    if (activeCallId != null) return;

    final currentNav = appNavigatorKey.currentState;
    if (currentNav == null || !currentNav.mounted) return;

    await CallScreen.openIncoming(
      currentNav,
      session: latest,
      peerProfile: peerProfile,
    );
  }

  Future<ZevCallSession?> fetchCallById(String callSessionId) async {
    final cleanId = callSessionId.trim();
    if (cleanId.isEmpty) return null;
    try {
      final res = await _supabase
          .from('call_sessions')
          .select()
          .eq('id', cleanId)
          .maybeSingle();
      if (res == null) return null;
      return ZevCallSession.fromMap(Map<String, dynamic>.from(res));
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchProfileSummary(String userId) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty) return const <String, dynamic>{};
    try {
      final res = await _supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified')
          .eq('id', cleanId)
          .maybeSingle();
      if (res != null) return Map<String, dynamic>.from(res);
    } catch (_) {}
    return <String, dynamic>{'id': cleanId};
  }

  /// Requests a short-lived Agora RTC token from `/api/v1/agora/token`.
  Future<ZevAgoraCredentials> fetchLiveToken({required String streamId}) async {
    final json = await ApiClient.instance.post(
      '/api/v1/agora/token',
      data: {
        'mode': 'live',
        'streamId': streamId,
      },
      requireAuth: true,
    );
    return ZevAgoraCredentials.fromJson(json);
  }

  /// Requests a short-lived Agora RTC token for a 1-to-1 or group call.
  /// Automatically caches tokens to prevent redundant network handshakes.
  Future<ZevAgoraCredentials> fetchCallToken({
    required String callSessionId,
  }) async {
    final cleanId = callSessionId.trim();
    if (_tokenCache.containsKey(cleanId)) {
      final cached = _tokenCache[cleanId]!;
      if (cached.expiresAt == null ||
          cached.expiresAt!.isAfter(
            DateTime.now().add(const Duration(minutes: 5)),
          )) {
        return cached;
      }
      _tokenCache.remove(cleanId);
    }

    final json = await ApiClient.instance.post(
      '/api/v1/agora/token',
      data: {
        'mode': 'call',
        'callSessionId': cleanId,
      },
      requireAuth: true,
    );
    final creds = ZevAgoraCredentials.fromJson(json);
    _tokenCache[cleanId] = creds;
    return creds;
  }

  /// Creates a ringing `call_sessions` row via Supabase RPC and dispatches
  /// an incoming-call FCM push notification.
  Future<ZevCallSession> initiateCall({
    required String calleeId,
    required String callType,
    required String callerDisplayName,
    String? conversationId,
    bool isGroup = false,
    String? title,
  }) async {
    final res = await _supabase.rpc(
      'initiate_call_session',
      params: {
        'p_callee_id': calleeId,
        'p_call_type': callType,
        'p_conversation_id': conversationId,
      },
    );
    final session = ZevCallSession.fromMap(
      Map<String, dynamic>.from(res as Map),
    );

    unawaited(
      ApiClient.instance
          .post(
            '/api/v1/push/send',
            data: {
              'recipientUserId': calleeId,
              'title': session.isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
              'body': '$callerDisplayName is calling you on ZEV',
              'notificationType': session.isVideo ? 'video_call' : 'voice_call',
              'deepLink': '/call/${session.id}',
            },
            requireAuth: true,
          )
          .catchError((Object e) {
            debugPrint('[ZevRtcService] incoming call push notice: $e');
            return <String, dynamic>{};
          }),
    );

    return session;
  }

  /// Accepts, rejects, cancels, or ends a `call_sessions` row atomically.
  Future<ZevCallSession> respondCall({
    required String callId,
    required String action,
    String? reason,
  }) async {
    final res = await _supabase.rpc(
      'respond_call_session',
      params: {
        'p_call_id': callId,
        'p_action': action,
        'p_reason': reason,
      },
    );
    return ZevCallSession.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// Invites a new participant to an active call (converting to a group call).
  Future<ZevCallParticipant?> inviteParticipant({
    required String callId,
    required String userId,
    String? inviterDisplayName,
  }) async {
    try {
      final res = await _supabase.rpc(
        'invite_call_participant',
        params: {
          'p_call_id': callId,
          'p_user_id': userId,
        },
      );
      final participant = ZevCallParticipant.fromMap(
        Map<String, dynamic>.from(res as Map),
      );

      unawaited(
        ApiClient.instance.post(
          '/api/v1/push/send',
          data: {
            'recipientUserId': userId,
            'title': 'Group Call Invitation',
            'body': '${inviterDisplayName ?? "A friend"} invited you to join a call',
            'notificationType': 'group_call',
            'deepLink': '/call/$callId',
          },
          requireAuth: true,
        ).catchError((_) => <String, dynamic>{}),
      );

      return participant;
    } catch (e) {
      debugPrint('[ZevRtcService] inviteParticipant error: $e');
      return null;
    }
  }

  /// Updates current user's participant status in a group call.
  Future<void> updateParticipantStatus({
    required String callId,
    required String status,
  }) async {
    try {
      await _supabase.rpc(
        'update_participant_call_status',
        params: {
          'p_call_id': callId,
          'p_status': status,
        },
      );
    } catch (e) {
      debugPrint('[ZevRtcService] updateParticipantStatus error: $e');
    }
  }

  /// Fetches all active participants for a call session.
  Future<List<ZevCallParticipant>> fetchParticipants(
    String callSessionId,
  ) async {
    try {
      final res = await _supabase
          .from('call_participants')
          .select('*, profiles:user_id(id, username, first_name, last_name, avatar_url, is_verified)')
          .eq('call_session_id', callSessionId);
      final list = (res as List).whereType<Map>().toList();
      return list.map((m) {
        final raw = Map<String, dynamic>.from(m);
        final prof = raw['profiles'] is Map
            ? Map<String, dynamic>.from(raw['profiles'])
            : null;
        return ZevCallParticipant.fromMap(raw, profile: prof);
      }).toList();
    } catch (e) {
      debugPrint('[ZevRtcService] fetchParticipants error: $e');
      return [];
    }
  }
}
