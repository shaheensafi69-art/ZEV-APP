import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/calls/screens/call_screen.dart';
import '../../main.dart';
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
      startedAt: DateTime.tryParse((map['started_at'] ?? '').toString()),
      answeredAt: DateTime.tryParse((map['answered_at'] ?? '').toString()),
      endedAt: DateTime.tryParse((map['ended_at'] ?? '').toString()),
    );
  }
}

/// Client-side signaling, global incoming-call listener & Agora RTC token service
/// for ZEV Voice Calls, Video Calls, and Interactive Live Broadcasting.
class ZevRtcService {
  ZevRtcService._();
  static final ZevRtcService instance = ZevRtcService._();

  final _supabase = Supabase.instance.client;

  RealtimeChannel? _incomingChannel;
  String? _listeningUserId;
  String? activeCallId;
  final Set<String> _handledCallIds = {};

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

    // If user is already busy on another active call, signal busy cleanly.
    if (activeCallId != null && activeCallId != session.id) {
      _handledCallIds.add(session.id);
      unawaited(
        respondCall(callId: session.id, action: 'busy', reason: 'busy_on_other_call')
            .catchError((_) => session),
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

  /// Requests a short-lived Agora RTC token for a 1-to-1 Voice or Video call.
  Future<ZevAgoraCredentials> fetchCallToken({required String callSessionId}) async {
    final json = await ApiClient.instance.post(
      '/api/v1/agora/token',
      data: {
        'mode': 'call',
        'callSessionId': callSessionId,
      },
      requireAuth: true,
    );
    return ZevAgoraCredentials.fromJson(json);
  }

  /// Creates a ringing `call_sessions` row via Supabase RPC and dispatches
  /// an incoming-call FCM push notification to wake the callee when offline/backgrounded.
  Future<ZevCallSession> initiateCall({
    required String calleeId,
    required String callType,
    required String callerDisplayName,
    String? conversationId,
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
}
