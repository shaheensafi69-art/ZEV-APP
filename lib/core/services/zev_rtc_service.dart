import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Client-side signaling & Agora RTC token service for ZEV Voice Calls,
/// Video Calls, and Interactive Live Streaming.
class ZevRtcService {
  ZevRtcService._();
  static final ZevRtcService instance = ZevRtcService._();

  final _supabase = Supabase.instance.client;

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
