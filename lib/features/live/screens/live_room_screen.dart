import 'dart:async';
import 'dart:math' as math;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/social_graph_service.dart';
import '../../../core/services/zev_rtc_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../profile/screens/profile_screen.dart';

class _FloatingReaction {
  final String id;
  final String emoji;
  final double leftFraction;

  _FloatingReaction({
    required this.id,
    required this.emoji,
    required this.leftFraction,
  });
}

/// Interactive ZEV Live Video, Audio & Real-Time Chat Room (Agora RTC + Supabase Realtime).
/// 100% Light Clearmorphic interface with live Agora broadcasting, audience playback,
/// real-time comments, emoji reactions, live participant presence, and host termination.
class LiveRoomScreen extends StatefulWidget {
  final Map<String, dynamic> stream;
  final Map<String, dynamic> hostProfile;
  final bool isHost;

  const LiveRoomScreen({
    super.key,
    required this.stream,
    required this.hostProfile,
    this.isHost = false,
  });

  static Future<void> open(
    BuildContext context, {
    required Map<String, dynamic> stream,
    required Map<String, dynamic> hostProfile,
    bool isHost = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveRoomScreen(
          stream: stream,
          hostProfile: hostProfile,
          isHost: isHost,
        ),
      ),
    );
  }

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  final _supabase = Supabase.instance.client;
  final _commentCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _random = math.Random();

  late final String _streamId;
  late String _status;
  late int _viewerCount;
  late int _peakViewerCount;
  String? _joinError;

  bool _isLoadingComments = true;
  bool _isSendingComment = false;
  bool _isEndingRoom = false;
  bool _allowHostPop = false;
  int _reactionTotal = 0;

  final List<Map<String, dynamic>> _comments = [];
  final Set<String> _commentIds = {};
  final Map<String, Map<String, dynamic>> _profileCache = {};
  final Set<String> _pendingProfileFetches = {};
  Set<String> _blockedUserIds = {};
  final List<_FloatingReaction> _floatingReactions = [];

  RealtimeChannel? _roomChannel;

  // Agora RTC Interactive Live Broadcasting state
  RtcEngine? _rtcEngine;
  RtcEngineEventHandler? _rtcHandler;
  VideoViewController? _localBroadcasterController;
  VideoViewController? _remoteHostController;
  int? _remoteHostUid;
  bool _remoteHostVideoOn = true;
  bool _rtcJoined = false;
  bool _isRtcConnecting = false;
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isVideoExpanded = false;
  String? _rtcError;

  static const List<String> _quickEmojis = [
    '❤️',
    '🔥',
    '👏',
    '😂',
    '😮',
    '💯',
  ];

  bool get _isEnded => _status != 'live';

  @override
  void initState() {
    super.initState();
    _streamId = widget.stream['id']?.toString() ?? '';
    _status = (widget.stream['status'] ?? 'live').toString();
    _viewerCount = (widget.stream['viewer_count'] as num?)?.toInt() ?? 1;
    _peakViewerCount =
        (widget.stream['peak_viewer_count'] as num?)?.toInt() ?? _viewerCount;

    final hostId = widget.hostProfile['id']?.toString() ??
        widget.stream['host_id']?.toString() ??
        '';
    if (hostId.isNotEmpty && widget.hostProfile.isNotEmpty) {
      _profileCache[hostId] = Map<String, dynamic>.from(widget.hostProfile);
    }

    _bootstrapRoom();
  }

  @override
  void dispose() {
    final channel = _roomChannel;
    _roomChannel = null;
    if (channel != null) {
      unawaited(channel.unsubscribe());
    }
    unawaited(_teardownAgora());
    if (!widget.isHost && _streamId.isNotEmpty) {
      unawaited(_leaveStreamQuietly());
    }
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _teardownAgora() async {
    _localBroadcasterController?.dispose();
    _localBroadcasterController = null;
    _remoteHostController?.dispose();
    _remoteHostController = null;

    final eng = _rtcEngine;
    final handler = _rtcHandler;
    _rtcEngine = null;
    _rtcHandler = null;
    if (eng != null) {
      try {
        if (handler != null) eng.unregisterEventHandler(handler);
      } catch (_) {}
      try {
        await eng.leaveChannel();
      } catch (_) {}
      try {
        await eng.release();
      } catch (_) {}
    }
  }

  Future<void> _leaveStreamQuietly() async {
    try {
      await _supabase.rpc(
        'leave_live_stream',
        params: {'p_stream_id': _streamId},
      );
    } catch (_) {}
  }

  Future<void> _bootstrapRoom() async {
    if (_streamId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
          _joinError = 'Invalid live room identifier.';
        });
      }
      return;
    }

    final safety = await SocialGraphService.instance.fetchSafetyFilters();
    _blockedUserIds = safety.blockedUserIds;

    if (!widget.isHost) {
      try {
        final cnt = await _supabase.rpc(
          'join_live_stream',
          params: {'p_stream_id': _streamId},
        );
        if (mounted && cnt is num) {
          setState(() {
            _viewerCount = cnt.toInt();
            _peakViewerCount = math.max(_peakViewerCount, _viewerCount);
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _status = 'ended';
            _joinError = e.toString().replaceFirst('Exception: ', '');
          });
        }
      }
    }

    await _loadInitialComments();
    _subscribeRealtime();
    if (!_isEnded) {
      unawaited(_initAgoraLive());
    }
  }

  Future<bool> _requestBroadcastPermissions() async {
    if (!widget.isHost) return true;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return true;
    }
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    return cam.isGranted && mic.isGranted;
  }

  Future<void> _initAgoraLive() async {
    if (_streamId.isEmpty || _isEnded || _isRtcConnecting || _rtcEngine != null) {
      return;
    }
    if (mounted) {
      setState(() {
        _isRtcConnecting = true;
        _rtcError = null;
      });
    }

    try {
      final permsOk = await _requestBroadcastPermissions();
      if (!permsOk) {
        if (mounted) {
          setState(() {
            _isRtcConnecting = false;
            _rtcError = 'Camera & Microphone permission required to broadcast video.';
          });
        }
        return;
      }

      final creds = await ZevRtcService.instance.fetchLiveToken(streamId: _streamId);
      if (!mounted || _isEnded) return;

      final resolvedAppId =
          creds.appId.isNotEmpty ? creds.appId : AppConfig.agoraAppId;
      if (resolvedAppId.isEmpty || creds.token.isEmpty) {
        throw Exception('Agora Live credentials unavailable.');
      }

      final engine = createAgoraRtcEngine();
      await engine.initialize(
        RtcEngineContext(
          appId: resolvedAppId,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );

      final hostRole = (widget.isHost && creds.isPublisher)
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience;

      final handler = RtcEngineEventHandler(
        onError: (ErrorCodeType err, String msg) {
          debugPrint('[LiveRoomScreen][Agora] onError $err $msg');
        },
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          if (!mounted) return;
          setState(() {
            _rtcJoined = true;
            _isRtcConnecting = false;
          });
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          if (!mounted || widget.isHost || remoteUid == 0) return;
          setState(() {
            _remoteHostUid = remoteUid;
            _remoteHostVideoOn = true;
            _remoteHostController?.dispose();
            _remoteHostController = VideoViewController.remote(
              rtcEngine: engine,
              canvas: VideoCanvas(
                uid: remoteUid,
                renderMode: RenderModeType.renderModeHidden,
              ),
              connection: connection,
            );
          });
        },
        onUserOffline: (
          RtcConnection connection,
          int remoteUid,
          UserOfflineReasonType reason,
        ) {
          if (!mounted) return;
          if (_remoteHostUid == remoteUid) {
            setState(() {
              _remoteHostUid = null;
              _remoteHostController?.dispose();
              _remoteHostController = null;
            });
          }
        },
        onUserMuteVideo: (RtcConnection connection, int remoteUid, bool muted) {
          if (!mounted) return;
          if (_remoteHostUid == remoteUid) {
            setState(() => _remoteHostVideoOn = !muted);
          }
        },
      );

      engine.registerEventHandler(handler);
      _rtcEngine = engine;
      _rtcHandler = handler;

      await engine.enableVideo();
      await engine.enableAudio();
      await engine.setClientRole(role: hostRole);

      if (hostRole == ClientRoleType.clientRoleBroadcaster) {
        try {
          await engine.setVideoEncoderConfiguration(
            const VideoEncoderConfiguration(
              dimensions: VideoDimensions(width: 720, height: 1280),
              frameRate: 24,
              bitrate: 1500,
            ),
          );
        } catch (_) {}
        try {
          await engine.startPreview();
        } catch (_) {}
        if (mounted) {
          setState(() {
            _localBroadcasterController = VideoViewController(
              rtcEngine: engine,
              canvas: const VideoCanvas(
                uid: 0,
                renderMode: RenderModeType.renderModeHidden,
              ),
            );
          });
        }
      }

      await engine.joinChannel(
        token: creds.token,
        channelId: creds.channelName,
        uid: creds.uid,
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: hostRole,
          publishCameraTrack: hostRole == ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack:
              hostRole == ClientRoleType.clientRoleBroadcaster,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );
    } catch (e) {
      debugPrint('[LiveRoomScreen] Agora init notice: $e');
      if (mounted) {
        setState(() {
          _isRtcConnecting = false;
          _rtcError = e.toString().replaceFirst('Exception: ', '').trim();
        });
      }
    }
  }

  Future<void> _toggleLiveMic() async {
    HapticFeedback.selectionClick();
    final next = !_isMicMuted;
    setState(() => _isMicMuted = next);
    try {
      await _rtcEngine?.muteLocalAudioStream(next);
    } catch (_) {}
  }

  Future<void> _toggleLiveCam() async {
    HapticFeedback.selectionClick();
    final nextOff = !_isCameraOff;
    setState(() => _isCameraOff = nextOff);
    try {
      await _rtcEngine?.muteLocalVideoStream(nextOff);
      await _rtcEngine?.enableLocalVideo(!nextOff);
    } catch (_) {}
  }

  Future<void> _switchLiveCamera() async {
    HapticFeedback.selectionClick();
    try {
      await _rtcEngine?.switchCamera();
    } catch (_) {}
  }

  Future<void> _loadInitialComments() async {
    try {
      final [commentsRes, reactRes] = await Future.wait<dynamic>([
        _supabase
            .from('live_comments')
            .select('id, stream_id, user_id, comment_text, created_at')
            .eq('stream_id', _streamId)
            .order('created_at', ascending: true)
            .limit(80),
        _supabase
            .from('live_reactions')
            .select('id')
            .eq('stream_id', _streamId),
      ]);

      final rows = (commentsRes as List)
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .where((r) {
            final uid = r['user_id']?.toString() ?? '';
            return !_blockedUserIds.contains(uid);
          })
          .toList();

      await _ensureProfilesLoaded(
        rows.map((r) => r['user_id']?.toString() ?? ''),
      );

      if (!mounted) return;
      setState(() {
        _comments.clear();
        _commentIds.clear();
        for (final row in rows) {
          final id = row['id']?.toString() ?? '';
          if (id.isNotEmpty) _commentIds.add(id);
          _comments.add(row);
        }
        _reactionTotal = (reactRes as List).length;
        _isLoadingComments = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('[LiveRoomScreen] loadInitialComments notice: $e');
      if (mounted) setState(() => _isLoadingComments = false);
    }
  }

  Future<void> _ensureProfilesLoaded(Iterable<String> userIds) async {
    final missing = userIds
        .map((id) => id.trim())
        .where(
          (id) =>
              id.isNotEmpty &&
              !_profileCache.containsKey(id) &&
              !_pendingProfileFetches.contains(id),
        )
        .toSet()
        .toList();
    if (missing.isEmpty) return;

    _pendingProfileFetches.addAll(missing);
    try {
      final res = await _supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified')
          .inFilter('id', missing);
      for (final item in (res as List)) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final id = map['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            _profileCache[id] = map;
          }
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[LiveRoomScreen] ensureProfilesLoaded notice: $e');
    } finally {
      _pendingProfileFetches.removeAll(missing);
    }
  }

  void _subscribeRealtime() {
    if (_streamId.isEmpty) return;
    _roomChannel?.unsubscribe();
    try {
      _roomChannel = _supabase
          .channel('live_room:$_streamId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'live_streams',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: _streamId,
            ),
            callback: (payload) {
              final next = payload.newRecord;
              if (!mounted || next.isEmpty) return;
              final nextStatus = next['status']?.toString();
              setState(() {
                if (nextStatus != null) {
                  _status = nextStatus;
                }
                if (next['viewer_count'] is num) {
                  _viewerCount = (next['viewer_count'] as num).toInt();
                }
                if (next['peak_viewer_count'] is num) {
                  _peakViewerCount = math.max(
                    _peakViewerCount,
                    (next['peak_viewer_count'] as num).toInt(),
                  );
                }
              });
              if (nextStatus != null && nextStatus != 'live') {
                unawaited(_teardownAgora());
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'live_comments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'stream_id',
              value: _streamId,
            ),
            callback: (payload) {
              final row = Map<String, dynamic>.from(payload.newRecord);
              final id = row['id']?.toString() ?? '';
              final uid = row['user_id']?.toString() ?? '';
              if (uid.isEmpty || _blockedUserIds.contains(uid)) return;
              if (id.isNotEmpty && _commentIds.contains(id)) return;
              unawaited(_ensureProfilesLoaded([uid]));
              if (!mounted) return;
              setState(() {
                if (id.isNotEmpty) _commentIds.add(id);
                _comments.add(row);
              });
              _scrollToBottom();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'live_reactions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'stream_id',
              value: _streamId,
            ),
            callback: (payload) {
              final row = payload.newRecord;
              final uid = row['user_id']?.toString() ?? '';
              if (_blockedUserIds.contains(uid)) return;
              final emoji = (row['emoji'] ?? '❤️').toString();
              _spawnFloatingEmoji(emoji, incrementCounter: true);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[LiveRoomScreen] subscribeRealtime notice: $e');
    }
  }

  void _spawnFloatingEmoji(String emoji, {bool incrementCounter = false}) {
    if (!mounted) return;
    final key = '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(999)}';
    final particle = _FloatingReaction(
      id: key,
      emoji: emoji,
      leftFraction: 0.15 + _random.nextDouble() * 0.70,
    );
    setState(() {
      if (incrementCounter) _reactionTotal += 1;
      _floatingReactions.add(particle);
      if (_floatingReactions.length > 20) {
        _floatingReactions.removeAt(0);
      }
    });
    Future.delayed(const Duration(milliseconds: 1650), () {
      if (!mounted) return;
      setState(() {
        _floatingReactions.removeWhere((p) => p.id == key);
      });
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    final me = _supabase.auth.currentUser?.id;
    if (text.isEmpty || me == null || _isSendingComment || _isEnded) return;
    if (text.length > 500) {
      _showToast('Message must be 500 characters or fewer.', isError: true);
      return;
    }

    HapticFeedback.selectionClick();
    setState(() => _isSendingComment = true);
    _commentCtrl.clear();

    try {
      final inserted = await _supabase
          .from('live_comments')
          .insert({
            'stream_id': _streamId,
            'user_id': me,
            'comment_text': text,
          })
          .select()
          .single();

      final row = Map<String, dynamic>.from(inserted);
      final id = row['id']?.toString() ?? '';
      unawaited(_ensureProfilesLoaded([me]));
      if (mounted) {
        setState(() {
          if (id.isNotEmpty && !_commentIds.contains(id)) {
            _commentIds.add(id);
            _comments.add(row);
          }
          _isSendingComment = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        _commentCtrl.text = text;
        setState(() => _isSendingComment = false);
        _showToast('Could not post message: $e', isError: true);
      }
    }
  }

  Future<void> _sendReaction(String emoji) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null || _isEnded) return;
    HapticFeedback.lightImpact();
    try {
      await _supabase.from('live_reactions').insert({
        'stream_id': _streamId,
        'user_id': me,
        'emoji': emoji,
      });
    } catch (e) {
      if (mounted) {
        _showToast('Could not send reaction: $e', isError: true);
      }
    }
  }

  Future<bool> _confirmAndEndRoom() async {
    if (!widget.isHost || _isEnded || _isEndingRoom) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ZevColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'End Live Room?',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: ZevColors.deepNavy,
          ),
        ),
        content: const Text(
          'Ending this interactive ZEV Live Chat & Presence Room will disconnect active viewers and archive chat input.',
          style: TextStyle(
            color: ZevColors.textSecondary,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text(
              'Stay Live',
              style: TextStyle(
                color: ZevColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ZevColors.errorRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'End Room',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    setState(() => _isEndingRoom = true);
    try {
      await _teardownAgora();
      await _supabase.rpc(
        'end_live_stream',
        params: {'p_stream_id': _streamId},
      );
      if (mounted) {
        setState(() {
          _status = 'ended';
          _viewerCount = 0;
          _isEndingRoom = false;
          _allowHostPop = true;
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _isEndingRoom = false);
        _showToast('Could not end room: $e', isError: true);
      }
      return false;
    }
  }

  Widget _buildLiveVideoStage({
    required String hostAvatar,
    required String hostUsername,
    required String thumbnailUrl,
  }) {
    final screenH = MediaQuery.sizeOf(context).height;
    final stageHeight = _isVideoExpanded
        ? (screenH * 0.42).clamp(240.0, 380.0)
        : 205.0;

    final showHostLocal = widget.isHost &&
        _localBroadcasterController != null &&
        !_isCameraOff;
    final showRemoteVideo = !widget.isHost &&
        _remoteHostController != null &&
        _remoteHostVideoOn;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      height: stageHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0A101E),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showHostLocal)
              AgoraVideoView(
                key: const ValueKey('live_host_local'),
                controller: _localBroadcasterController!,
              )
            else if (showRemoteVideo)
              AgoraVideoView(
                key: ValueKey('live_remote_$_remoteHostUid'),
                controller: _remoteHostController!,
              )
            else
              Stack(
                fit: StackFit.expand,
                children: [
                  if (thumbnailUrl.isNotEmpty)
                    Opacity(
                      opacity: 0.35,
                      child: ZevCachedImage(
                        imageUrl: thumbnailUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF0F172A).withValues(alpha: 0.65),
                          const Color(0xFF090D16).withValues(alpha: 0.9),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ZevCachedImage.avatar(imageUrl: hostAvatar, size: 58),
                        const SizedBox(height: 10),
                        Text(
                          _rtcError != null
                              ? _rtcError!
                              : _isRtcConnecting
                                  ? 'Connecting live broadcast...'
                                  : widget.isHost && _isCameraOff
                                      ? 'Your camera is turned off'
                                      : (_rtcJoined
                                          ? 'Waiting for @$hostUsername video...'
                                          : 'Joining live stream...'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

            // Top-left Live signal badge
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _rtcJoined
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      widget.isHost ? 'BROADCASTING' : 'LIVE VIDEO',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Top-right Expand & Host Media Controls
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isHost) ...[
                    _stageControlIcon(
                      icon: _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      active: !_isMicMuted,
                      onTap: _toggleLiveMic,
                    ),
                    const SizedBox(width: 6),
                    _stageControlIcon(
                      icon: _isCameraOff
                          ? Icons.videocam_off_rounded
                          : Icons.videocam_rounded,
                      active: !_isCameraOff,
                      onTap: _toggleLiveCam,
                    ),
                    const SizedBox(width: 6),
                    _stageControlIcon(
                      icon: Icons.cameraswitch_rounded,
                      active: true,
                      onTap: _switchLiveCamera,
                    ),
                    const SizedBox(width: 6),
                  ],
                  _stageControlIcon(
                    icon: _isVideoExpanded
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    active: true,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isVideoExpanded = !_isVideoExpanded);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stageControlIcon({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: active
              ? Colors.black.withValues(alpha: 0.56)
              : ZevColors.errorRed.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 17),
      ),
    );
  }

  void _showParticipantsSheet() {
    HapticFeedback.lightImpact();
    bool loadedOnce = false;
    bool loading = true;
    List<Map<String, dynamic>> participants = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          if (!loadedOnce) {
            loadedOnce = true;
            Future(() async {
              List<Map<String, dynamic>> combined = [];
              try {
                final vRes = await _supabase
                    .from('live_viewers')
                    .select('user_id, joined_at')
                    .eq('stream_id', _streamId)
                    .eq('is_active', true)
                    .order('joined_at', ascending: false);
                final rows = (vRes as List)
                    .whereType<Map>()
                    .map((r) => Map<String, dynamic>.from(r))
                    .toList();
                final uids = rows
                    .map((r) => r['user_id']?.toString() ?? '')
                    .where((id) => id.isNotEmpty)
                    .toSet()
                    .toList();
                await _ensureProfilesLoaded(uids);
                combined = rows.map((r) {
                  final uid = r['user_id']?.toString() ?? '';
                  final p = _profileCache[uid] ?? const <String, dynamic>{};
                  return {
                    'user_id': uid,
                    'joined_at': r['joined_at']?.toString(),
                    ...p,
                  };
                }).toList();
              } catch (e) {
                debugPrint('[LiveRoomScreen] load participants notice: $e');
              }
              if (ctx.mounted) {
                setSheetState(() {
                  participants = combined;
                  loading = false;
                });
              }
            });
          }

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: ZevColors.softSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white, width: 1.5),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: ZevColors.secondaryBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.groups_rounded,
                            color: ZevColors.secondaryBlue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Active Participants',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: ZevColors.deepNavy,
                                ),
                              ),
                              Text(
                                '$_viewerCount in room • Peak $_peakViewerCount',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: ZevColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: ZevColors.primaryBlue,
                          ),
                        ),
                      )
                    else if (participants.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: ZevColors.border),
                        ),
                        child: const Text(
                          'No active participants currently listed.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: ZevColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: participants.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, idx) {
                            final p = participants[idx];
                            final uid = p['user_id']?.toString() ?? '';
                            final uname = (p['username'] ?? 'user').toString();
                            final full =
                                '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'
                                    .trim();
                            final avatar = (p['avatar_url'] ?? '').toString();
                            final verified = p['is_verified'] == true;
                            final isRoomHost =
                                uid == widget.stream['host_id']?.toString();

                            return GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                if (uid.isNotEmpty) {
                                  ProfileScreen.open(context, userId: uid);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: ZevColors.border),
                                ),
                                child: Row(
                                  children: [
                                    ZevCachedImage.avatar(
                                      imageUrl: avatar,
                                      size: 40,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  full.isNotEmpty
                                                      ? full
                                                      : '@$uname',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: ZevColors.deepNavy,
                                                  ),
                                                ),
                                              ),
                                              if (verified) ...[
                                                const SizedBox(width: 4),
                                                const Icon(
                                                  Icons.verified_rounded,
                                                  size: 14,
                                                  color: ZevColors.primaryBlue,
                                                ),
                                              ],
                                            ],
                                          ),
                                          Text(
                                            '@$uname • ${TimeAgo.fromIsoString(p['joined_at']?.toString())}',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: ZevColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isRoomHost)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: ZevColors.primaryBlue
                                              .withValues(alpha: 0.16),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          'HOST',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: ZevColors.deepNavy,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: isError ? ZevColors.errorRed : ZevColors.deepNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hostId = widget.stream['host_id']?.toString() ?? '';
    final hostUsername = (widget.hostProfile['username'] ?? 'host').toString();
    final hostFullName =
        '${widget.hostProfile['first_name'] ?? ''} ${widget.hostProfile['last_name'] ?? ''}'
            .trim();
    final hostAvatar = (widget.hostProfile['avatar_url'] ?? '').toString();
    final hostVerified = widget.hostProfile['is_verified'] == true;
    final roomTitle = (widget.stream['title'] ?? 'Live Room').toString();
    final category = (widget.stream['category'] ?? 'General').toString();
    final thumbnailUrl = (widget.stream['thumbnail_url'] ?? '').toString();
    final startedAt = widget.stream['started_at']?.toString();

    return PopScope(
      canPop: !widget.isHost || _isEnded || _allowHostPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final ended = await _confirmAndEndRoom();
        if (ended && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: ZevColors.softSurface,
        appBar: AppBar(
          backgroundColor: ZevColors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: ZevColors.deepNavy,
              size: 20,
            ),
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (widget.isHost && !_isEnded) {
                final ended = await _confirmAndEndRoom();
                if (ended && mounted) navigator.pop();
              } else {
                navigator.pop();
              }
            },
          ),
          titleSpacing: 0,
          title: GestureDetector(
            onTap: hostId.isNotEmpty
                ? () => ProfileScreen.open(context, userId: hostId)
                : null,
            child: Row(
              children: [
                ZevCachedImage.avatar(imageUrl: hostAvatar, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              hostFullName.isNotEmpty
                                  ? hostFullName
                                  : '@$hostUsername',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: ZevColors.deepNavy,
                              ),
                            ),
                          ),
                          if (hostVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: ZevColors.primaryBlue,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'Live Video Broadcast • $category',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ZevColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            GestureDetector(
              onTap: _showParticipantsSheet,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _isEnded
                      ? const Color(0xFFE2E8F0)
                      : ZevColors.errorRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _isEnded
                        ? ZevColors.border
                        : ZevColors.errorRed.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isEnded
                            ? ZevColors.textMuted
                            : ZevColors.errorRed,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isEnded ? 'ENDED' : 'LIVE • $_viewerCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: _isEnded
                            ? ZevColors.textSecondary
                            : ZevColors.errorRed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.isHost && !_isEnded)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 12),
                child: TextButton(
                  onPressed: _isEndingRoom ? null : _confirmAndEndRoom,
                  style: TextButton.styleFrom(
                    backgroundColor: ZevColors.errorRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'End',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              )
            else
              const SizedBox(width: 10),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // Clearmorphic Topic & Presence Header Card
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: ZevColors.deepNavy.withValues(alpha: 0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Agora Real-Time Live Video Stage
                      if (!_isEnded) ...[
                        _buildLiveVideoStage(
                          hostAvatar: hostAvatar,
                          hostUsername: hostUsername,
                          thumbnailUrl: thumbnailUrl,
                        ),
                        const SizedBox(height: 10),
                      ] else if (thumbnailUrl.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: double.infinity,
                            height: 132,
                            child: ZevCachedImage(
                              imageUrl: thumbnailUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: ZevColors.primaryBlue.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.bolt_rounded,
                                  size: 13,
                                  color: ZevColors.secondaryBlue,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  category.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    color: ZevColors.secondaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: _showParticipantsSheet,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.visibility_outlined,
                                  size: 15,
                                  color: ZevColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Peak $_peakViewerCount',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: ZevColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(
                                  Icons.favorite_rounded,
                                  size: 14,
                                  color: Color(0xFFFF3040),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$_reactionTotal',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: ZevColors.deepNavy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        roomTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: ZevColors.deepNavy,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Live Video & Interactive Chat • Started ${TimeAgo.fromIsoString(startedAt)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: ZevColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isEnded)
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: ZevColors.errorRed,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _joinError ??
                                'This live room has ended. Past chat messages remain visible below.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: ZevColors.errorRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Live Comments Feed
                Expanded(
                  child: _isLoadingComments
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: ZevColors.primaryBlue,
                          ),
                        )
                      : _comments.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Container(
                                  padding: const EdgeInsets.all(22),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(color: ZevColors.border),
                                  ),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.forum_outlined,
                                        size: 36,
                                        color: ZevColors.secondaryBlue,
                                      ),
                                      SizedBox(height: 10),
                                      Text(
                                        'No messages yet',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: ZevColors.deepNavy,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Start the conversation in real time or drop a reaction below.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: ZevColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: _scrollCtrl,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                6,
                                14,
                                18,
                              ),
                              itemCount: _comments.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, idx) {
                                final c = _comments[idx];
                                final uid = c['user_id']?.toString() ?? '';
                                final prof = _profileCache[uid];
                                final uname =
                                    (prof?['username'] ?? 'user').toString();
                                final avatar =
                                    (prof?['avatar_url'] ?? '').toString();
                                final verified = prof?['is_verified'] == true;
                                final isAuthorHost = uid == hostId;
                                final body =
                                    (c['comment_text'] ?? '').toString();
                                final when = TimeAgo.fromIsoString(
                                  c['created_at']?.toString(),
                                );

                                return Container(
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: ZevColors.border),
                                    boxShadow: [
                                      BoxShadow(
                                        color: ZevColors.deepNavy.withValues(
                                          alpha: 0.03,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: uid.isNotEmpty
                                            ? () => ProfileScreen.open(
                                                  context,
                                                  userId: uid,
                                                )
                                            : null,
                                        child: ZevCachedImage.avatar(
                                          imageUrl: avatar,
                                          size: 34,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: GestureDetector(
                                                    onTap: uid.isNotEmpty
                                                        ? () =>
                                                            ProfileScreen.open(
                                                              context,
                                                              userId: uid,
                                                            )
                                                        : null,
                                                    child: Text(
                                                      '@$uname',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 12.5,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color:
                                                            ZevColors.deepNavy,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                if (verified) ...[
                                                  const SizedBox(width: 3),
                                                  const Icon(
                                                    Icons.verified_rounded,
                                                    size: 13,
                                                    color:
                                                        ZevColors.primaryBlue,
                                                  ),
                                                ],
                                                if (isAuthorHost) ...[
                                                  const SizedBox(width: 5),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: ZevColors
                                                          .secondaryBlue
                                                          .withValues(
                                                        alpha: 0.12,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        6,
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'HOST',
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color: ZevColors
                                                            .secondaryBlue,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                const Spacer(),
                                                Text(
                                                  when,
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    color: ZevColors.textMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              body,
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w500,
                                                color: ZevColors.deepNavy,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),

                // Quick Reaction + Interactive Composer Bar
                if (!_isEnded)
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    decoration: BoxDecoration(
                      color: ZevColors.white,
                      border: const Border(
                        top: BorderSide(color: ZevColors.border, width: 1.2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.deepNavy.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 38,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _quickEmojis.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, idx) {
                                final emoji = _quickEmojis[idx];
                                return GestureDetector(
                                  onTap: () => _sendReaction(emoji),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ZevColors.softSurface,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: ZevColors.border,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        emoji,
                                        style: const TextStyle(fontSize: 17),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ZevColors.softSurface,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(color: ZevColors.border),
                                  ),
                                  child: TextField(
                                    controller: _commentCtrl,
                                    maxLength: 500,
                                    maxLines: 3,
                                    minLines: 1,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _sendComment(),
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: ZevColors.deepNavy,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Write a live message...',
                                      hintStyle: TextStyle(
                                        fontSize: 13,
                                        color: ZevColors.textMuted,
                                      ),
                                      border: InputBorder.none,
                                      counterText: '',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _isSendingComment ? null : _sendComment,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: ZevColors.brandGradient,
                                  ),
                                  child: Center(
                                    child: _isSendingComment
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.send_rounded,
                                            color: Colors.white,
                                            size: 19,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            // Floating Realtime Emoji Reactions Layer
            Positioned.fill(
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: _floatingReactions.map((r) {
                        return _AnimatedReactionParticle(
                          key: ValueKey(r.id),
                          emoji: r.emoji,
                          left: constraints.maxWidth * r.leftFraction,
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedReactionParticle extends StatelessWidget {
  final String emoji;
  final double left;

  const _AnimatedReactionParticle({
    super.key,
    required this.emoji,
    required this.left,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1550),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final bottom = 110 + (t * 210);
        final opacity = t < 0.7 ? 1.0 : (1.0 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
        final scale = 0.8 + (math.sin(t * math.pi) * 0.45);
        return Positioned(
          left: left,
          bottom: bottom,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: ZevColors.deepNavy.withValues(alpha: 0.1),
              blurRadius: 8,
            ),
          ],
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}
