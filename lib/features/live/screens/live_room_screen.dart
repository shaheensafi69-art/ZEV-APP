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

class _LiveRoomScreenState extends State<LiveRoomScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _commentCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _random = math.Random();

  late final AnimationController _pulseCtrl;
  final Map<int, VideoViewController> _remoteBroadcasters = {};
  bool _isPkMatchActive = false;
  int _pkRedScore = 37;
  int _pkBlueScore = 12;
  int _pkTimeRemaining = 199; // 03:19
  Timer? _pkTimer;
  bool _isFollowingHost = false;

  // Stage Guest & Multi-Guest state (100+ room capacity)
  bool _isGuestOnStage = false;
  bool _hasPendingStageRequest = false;
  final List<Map<String, dynamic>> _stageRequests = [];
  final List<Map<String, dynamic>> _audioGuests = [];

  // Realtime Gift Celebration Banner
  Map<String, dynamic>? _activeGiftBanner;
  Timer? _giftBannerTimer;

  static const List<Map<String, dynamic>> _availableGifts = [
    {
      'id': 'rose',
      'name': 'Rose',
      'emoji': '🌹',
      'coins': 1,
    },
    {
      'id': 'heart',
      'name': 'Heart Gem',
      'emoji': '💖',
      'coins': 5,
    },
    {
      'id': 'diamond',
      'name': 'Diamond',
      'emoji': '💎',
      'coins': 20,
    },
    {
      'id': 'car',
      'name': 'Supercar',
      'emoji': '🏎️',
      'coins': 100,
    },
    {
      'id': 'crown',
      'name': 'Royal Crown',
      'emoji': '👑',
      'coins': 250,
    },
    {
      'id': 'rocket',
      'name': 'Space Rocket',
      'emoji': '🚀',
      'coins': 500,
    },
    {
      'id': 'lion',
      'name': 'Golden Lion',
      'emoji': '🦁',
      'coins': 1000,
    },
    {
      'id': 'dragon',
      'name': 'Mythic Dragon',
      'emoji': '🐉',
      'coins': 2500,
    },
  ];

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

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    final hostId = widget.hostProfile['id']?.toString() ??
        widget.stream['host_id']?.toString() ??
        '';
    if (hostId.isNotEmpty && widget.hostProfile.isNotEmpty) {
      _profileCache[hostId] = Map<String, dynamic>.from(widget.hostProfile);
    }

    _bootstrapRoom();
    _startPkTimer();
    _checkFollowingHost();
  }

  void _startPkTimer() {
    _pkTimer?.cancel();
    _pkTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_pkTimeRemaining > 0) {
        setState(() => _pkTimeRemaining--);
      }
    });
  }

  String _formatPkTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _checkFollowingHost() async {
    final hostId = widget.hostProfile['id']?.toString() ??
        widget.stream['host_id']?.toString() ??
        '';
    if (hostId.isEmpty || widget.isHost) return;
    try {
      final myId = _supabase.auth.currentUser?.id;
      if (myId == null) return;
      final res = await _supabase
          .from('user_follows')
          .select('follower_id')
          .eq('follower_id', myId)
          .eq('following_id', hostId)
          .maybeSingle();
      if (mounted) setState(() => _isFollowingHost = res != null);
    } catch (_) {}
  }

  Future<void> _toggleFollowHost() async {
    final hostId = widget.hostProfile['id']?.toString() ??
        widget.stream['host_id']?.toString() ??
        '';
    if (hostId.isEmpty || widget.isHost) return;
    HapticFeedback.selectionClick();
    try {
      final status = await SocialGraphService.instance.toggleFollow(hostId);
      if (mounted) {
        setState(() {
          _isFollowingHost = status == FollowToggleStatus.following ||
              status == FollowToggleStatus.requested;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _pkTimer?.cancel();
    _giftBannerTimer?.cancel();
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
    for (final ctrl in _remoteBroadcasters.values) {
      ctrl.dispose();
    }
    _remoteBroadcasters.clear();

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
          if (!mounted || remoteUid == 0) return;
          setState(() {
            if (!widget.isHost && _remoteHostUid == null) {
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
            } else {
              // Remote Co-Host / Multi-guest broadcaster
              _remoteBroadcasters[remoteUid]?.dispose();
              _remoteBroadcasters[remoteUid] = VideoViewController.remote(
                rtcEngine: engine,
                canvas: VideoCanvas(
                  uid: remoteUid,
                  renderMode: RenderModeType.renderModeHidden,
                ),
                connection: connection,
              );
              _isPkMatchActive = true;
            }
          });
        },
        onUserOffline: (
          RtcConnection connection,
          int remoteUid,
          UserOfflineReasonType reason,
        ) {
          if (!mounted) return;
          setState(() {
            if (_remoteHostUid == remoteUid) {
              _remoteHostUid = null;
              _remoteHostController?.dispose();
              _remoteHostController = null;
            }
            if (_remoteBroadcasters.containsKey(remoteUid)) {
              _remoteBroadcasters[remoteUid]?.dispose();
              _remoteBroadcasters.remove(remoteUid);
            }
            if (_remoteBroadcasters.isEmpty) {
              _isPkMatchActive = false;
            }
          });
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
          .onBroadcast(
            event: 'pk_update',
            callback: (raw) {
              final payload = raw['payload'] is Map
                  ? Map<String, dynamic>.from(raw['payload'] as Map)
                  : raw;
              if (!mounted) return;
              setState(() {
                if (payload['red'] is num) {
                  _pkRedScore = (payload['red'] as num).toInt();
                }
                if (payload['blue'] is num) {
                  _pkBlueScore = (payload['blue'] as num).toInt();
                }
                if (payload['time'] is num) {
                  _pkTimeRemaining = (payload['time'] as num).toInt();
                }
              });
            },
          )
          .onBroadcast(
            event: 'stage_request',
            callback: (raw) {
              if (!widget.isHost || !mounted) return;
              final payload = raw['payload'] is Map
                  ? Map<String, dynamic>.from(raw['payload'] as Map)
                  : raw;
              final uid = payload['user_id']?.toString() ?? '';
              if (uid.isEmpty) return;
              final uname = payload['username']?.toString() ?? 'User';
              final avatar = payload['avatar_url']?.toString() ?? '';
              setState(() {
                _stageRequests.removeWhere((r) => r['user_id'] == uid);
                _stageRequests.add({
                  'user_id': uid,
                  'username': uname,
                  'avatar_url': avatar,
                  'requested_at': DateTime.now().toIso8601String(),
                });
              });
              _showToast('@$uname requested to join the stage!');
            },
          )
          .onBroadcast(
            event: 'stage_accepted',
            callback: (raw) {
              final payload = raw['payload'] is Map
                  ? Map<String, dynamic>.from(raw['payload'] as Map)
                  : raw;
              final uid = payload['user_id']?.toString() ?? '';
              final myUid = _supabase.auth.currentUser?.id;
              if (uid == myUid && mounted) {
                _becomeStageGuest();
              }
            },
          )
          .onBroadcast(
            event: 'stage_kicked',
            callback: (raw) {
              final payload = raw['payload'] is Map
                  ? Map<String, dynamic>.from(raw['payload'] as Map)
                  : raw;
              final uid = payload['user_id']?.toString() ?? '';
              final myUid = _supabase.auth.currentUser?.id;
              if (uid == myUid && mounted) {
                _leaveStageGuest();
              }
            },
          )
          .onBroadcast(
            event: 'gift_sent',
            callback: (raw) {
              if (!mounted) return;
              final payload = raw['payload'] is Map
                  ? Map<String, dynamic>.from(raw['payload'] as Map)
                  : raw;
              final senderName = payload['sender_name']?.toString() ?? 'Fan';
              final senderAvatar = payload['sender_avatar']?.toString() ?? '';
              final giftName = payload['gift_name']?.toString() ?? 'Rose';
              final giftEmoji = payload['gift_emoji']?.toString() ?? '🌹';
              final points = (payload['points'] as num?)?.toInt() ?? 1;

              _showGiftCelebration(
                senderName: senderName,
                senderAvatar: senderAvatar,
                giftName: giftName,
                giftEmoji: giftEmoji,
                points: points,
              );
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

  Widget _buildFullscreenVideoStage({
    required String hostAvatar,
    required String hostUsername,
    required String thumbnailUrl,
  }) {
    final showHostLocal = widget.isHost &&
        _localBroadcasterController != null &&
        !_isCameraOff;
    final showRemoteVideo = !widget.isHost &&
        _remoteHostController != null &&
        _remoteHostVideoOn;
    final hasRemoteGuest = _remoteBroadcasters.isNotEmpty;
    if (_isPkMatchActive) {
      return _buildPkBattleStage(
        hostAvatar: hostAvatar,
        hostUsername: hostUsername,
        showHostLocal: showHostLocal,
        showRemoteVideo: showRemoteVideo,
        hasRemoteGuest: hasRemoteGuest,
      );
    }

    if (_remoteBroadcasters.length >= 2) {
      return _buildMultiGuestGridStage(
        hostAvatar: hostAvatar,
        hostUsername: hostUsername,
        showHostLocal: showHostLocal,
        showRemoteVideo: showRemoteVideo,
      );
    }

    if (hasRemoteGuest) {
      return _buildCoHostSplitStage(
        hostAvatar: hostAvatar,
        hostUsername: hostUsername,
        showHostLocal: showHostLocal,
        showRemoteVideo: showRemoteVideo,
      );
    }

    // Single Broadcaster: Full Screen 100% video
    if (showHostLocal) {
      return Stack(
        fit: StackFit.expand,
        children: [
          AgoraVideoView(
            key: const ValueKey('live_host_local_full'),
            controller: _localBroadcasterController!,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 330,
            child: _buildAudioGuestSeatsRow(),
          ),
        ],
      );
    }
    if (showRemoteVideo) {
      return Stack(
        fit: StackFit.expand,
        children: [
          AgoraVideoView(
            key: ValueKey('live_remote_full_$_remoteHostUid'),
            controller: _remoteHostController!,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 330,
            child: _buildAudioGuestSeatsRow(),
          ),
        ],
      );
    }

    // Waiting / Connecting / Camera Off Full Screen View
    return Stack(
      fit: StackFit.expand,
      children: [
        if (thumbnailUrl.isNotEmpty)
          Opacity(
            opacity: 0.4,
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
                const Color(0xFF0F172A).withValues(alpha: 0.75),
                const Color(0xFF050811).withValues(alpha: 0.95),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (context, child) {
                    final glow = 14.0 + (_pulseCtrl.value * 18.0);
                    return Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.6),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: ZevColors.primaryBlue.withValues(alpha: 0.4),
                            blurRadius: glow,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: ZevCachedImage.avatar(imageUrl: hostAvatar, size: 90),
                ),
                const SizedBox(height: 14),
                Text(
                  '@$hostUsername',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _rtcError != null
                      ? _rtcError!
                      : _isRtcConnecting
                          ? 'Connecting to live room...'
                          : widget.isHost && _isCameraOff
                              ? 'Your camera is off'
                              : (_rtcJoined
                                  ? 'Waiting for @$hostUsername...'
                                  : 'Joining live stream...'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 330,
          child: _buildAudioGuestSeatsRow(),
        ),
      ],
    );
  }

  Widget _buildWaitingPlaceholder({
    required String avatar,
    required String username,
    required String label,
  }) {
    return Container(
      color: const Color(0xFF0B1120),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ZevCachedImage.avatar(imageUrl: avatar, size: 54),
            const SizedBox(height: 8),
            Text(
              '@$username',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPkBattleStage({
    required String hostAvatar,
    required String hostUsername,
    required bool showHostLocal,
    required bool showRemoteVideo,
    required bool hasRemoteGuest,
  }) {
    final opponentUid = _remoteBroadcasters.isNotEmpty
        ? _remoteBroadcasters.keys.first
        : null;
    final opponentController = opponentUid != null
        ? _remoteBroadcasters[opponentUid]
        : null;

    final totalScore = math.max(1, _pkRedScore + _pkBlueScore);
    final redFlex = math.max(1, (_pkRedScore * 100) ~/ totalScore);
    final blueFlex = math.max(1, 100 - redFlex);

    final screenHeight = MediaQuery.of(context).size.height;
    final stageHeight = (screenHeight * 0.44).clamp(310.0, 420.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Spacing from top HUD
        SizedBox(height: MediaQuery.of(context).padding.top + 76),

        // 1. PK Battle Score Bar matching reference exactly
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dynamic Tug-of-War Score Bar
              Container(
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Row(
                    children: [
                      // Red Side (Host)
                      Expanded(
                        flex: redFlex,
                        child: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 14),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFFF1E56), Color(0xFFFF5252)],
                            ),
                          ),
                          child: Text(
                            '$_pkRedScore',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      // Center VS Capsule with Countdown Timer
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        color: const Color(0xFF0F172A),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '⚡ VS',
                              style: TextStyle(
                                color: Color(0xFFFFD600),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatPkTime(_pkTimeRemaining),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Blue Side (Opponent)
                      Expanded(
                        flex: blueFlex,
                        child: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 14),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0072FF), Color(0xFF00C6FF)],
                            ),
                          ),
                          child: Text(
                            '$_pkBlueScore',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // Win Streak Badges directly under scores
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB800).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'WIN × 0',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB800).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'WIN × 1',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        // 2. Side-by-Side Video Frames
        SizedBox(
          height: stageHeight,
          child: Row(
            children: [
              // Left Video: Host
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(left: 8, right: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFF2D55).withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (showHostLocal)
                          AgoraVideoView(
                            key: const ValueKey('live_host_local_split'),
                            controller: _localBroadcasterController!,
                          )
                        else if (showRemoteVideo)
                          AgoraVideoView(
                            key: ValueKey('live_remote_split_$_remoteHostUid'),
                            controller: _remoteHostController!,
                          )
                        else
                          _buildWaitingPlaceholder(
                            avatar: hostAvatar,
                            username: hostUsername,
                            label: 'Host',
                          ),

                        // Host Bottom Sub-Bar: Medals + Name
                        Positioned(
                          bottom: 8,
                          left: 8,
                          right: 8,
                          child: Row(
                            children: [
                              _buildMiniMedalAvatar(
                                'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=120&q=80',
                                1,
                              ),
                              const SizedBox(width: 3),
                              _buildMiniMedalAvatar(
                                'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=120&q=80',
                                2,
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '@$hostUsername',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Right Video: Opponent / Co-Host
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(left: 3, right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF0072FF).withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (opponentController != null)
                          AgoraVideoView(
                            key: ValueKey('live_remote_guest_$opponentUid'),
                            controller: opponentController,
                          )
                        else
                          _buildWaitingPlaceholder(
                            avatar: 'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&w=400&q=80',
                            username: 'دگروال میر...',
                            label: 'Opponent',
                          ),

                        // Opponent Bottom Sub-Bar: Medals + Name with + Follow Button
                        Positioned(
                          bottom: 8,
                          left: 8,
                          right: 8,
                          child: Row(
                            children: [
                              _buildMiniMedalAvatar(
                                'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=120&q=80',
                                1,
                              ),
                              const SizedBox(width: 3),
                              _buildMiniMedalAvatar(
                                'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=120&q=80',
                                2,
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'دگروال میر...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.add_rounded,
                                      color: Color(0xFFFF2D55),
                                      size: 13,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Audio Guest Seats Dock
        _buildAudioGuestSeatsRow(),
      ],
    );
  }

  Widget _buildCoHostSplitStage({
    required String hostAvatar,
    required String hostUsername,
    required bool showHostLocal,
    required bool showRemoteVideo,
  }) {
    final opponentUid = _remoteBroadcasters.keys.first;
    final opponentController = _remoteBroadcasters[opponentUid];

    return Stack(
      fit: StackFit.expand,
      children: [
        Row(
          children: [
            // Broadcaster 1 (Left Tile: Host)
            Expanded(
              child: Container(
                color: const Color(0xFF0F172A),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (showHostLocal)
                      AgoraVideoView(
                        key: const ValueKey('live_host_local_split'),
                        controller: _localBroadcasterController!,
                      )
                    else if (showRemoteVideo)
                      AgoraVideoView(
                        key: ValueKey('live_remote_split_$_remoteHostUid'),
                        controller: _remoteHostController!,
                      )
                    else
                      _buildWaitingPlaceholder(
                        avatar: hostAvatar,
                        username: hostUsername,
                        label: 'Host',
                      ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '@$hostUsername',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(width: 1.5, color: Colors.black.withValues(alpha: 0.5)),
            // Broadcaster 2 (Right Tile: Guest)
            Expanded(
              child: Container(
                color: const Color(0xFF1E293B),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (opponentController != null)
                      AgoraVideoView(
                        key: ValueKey('live_remote_guest_$opponentUid'),
                        controller: opponentController,
                      )
                    else
                      _buildWaitingPlaceholder(
                        avatar: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=400&q=80',
                        username: 'Co-Host',
                        label: 'Guest',
                      ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Co-Host',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 330,
          child: _buildAudioGuestSeatsRow(),
        ),
      ],
    );
  }

  Widget _buildMultiGuestGridStage({
    required String hostAvatar,
    required String hostUsername,
    required bool showHostLocal,
    required bool showRemoteVideo,
  }) {
    final guestUids = _remoteBroadcasters.keys.toList();

    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top + 70),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(4),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              // Host tile
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (showHostLocal)
                        AgoraVideoView(
                          key: const ValueKey('grid_host_local'),
                          controller: _localBroadcasterController!,
                        )
                      else if (showRemoteVideo)
                        AgoraVideoView(
                          key: ValueKey('grid_remote_$_remoteHostUid'),
                          controller: _remoteHostController!,
                        )
                      else
                        _buildWaitingPlaceholder(
                          avatar: hostAvatar,
                          username: hostUsername,
                          label: 'Host',
                        ),
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '@$hostUsername (Host)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Remote guest tiles
              ...guestUids.take(3).map((uid) {
                final ctrl = _remoteBroadcasters[uid];
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (ctrl != null)
                          AgoraVideoView(
                            key: ValueKey('grid_guest_$uid'),
                            controller: ctrl,
                          )
                        else
                          _buildWaitingPlaceholder(
                            avatar: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=400&q=80',
                            username: 'Guest $uid',
                            label: 'Co-Host',
                          ),
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Guest $uid',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        _buildAudioGuestSeatsRow(),
      ],
    );
  }

  Widget _buildAudioGuestSeatsRow() {
    return Container(
      height: 70,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, idx) {
          final isOccupied = idx < _audioGuests.length;
          final guest = isOccupied ? _audioGuests[idx] : null;

          if (isOccupied && guest != null) {
            final avatar = (guest['avatar_url'] ?? '').toString();
            final name = (guest['username'] ?? 'Guest').toString();
            final isMuted = guest['is_muted'] == true;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (context, child) {
                        return Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(
                                alpha: 0.4 + (_pulseCtrl.value * 0.4),
                              ),
                              width: 2.0,
                            ),
                          ),
                          child: child,
                        );
                      },
                      child: ZevCachedImage.avatar(imageUrl: avatar, size: 38),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isMuted
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF10B981),
                        ),
                        child: Icon(
                          isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          size: 9,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: 52,
                  child: Text(
                    '@$name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          }

          // Empty seat inviting audience to join
          return GestureDetector(
            onTap: _onTapEmptyStageSeat,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.45),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.add_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Seat ${idx + 1}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMiniMedalAvatar(String imageUrl, int rank) {
    Color ringColor;
    if (rank == 1) {
      ringColor = const Color(0xFFFFD700); // Gold
    } else if (rank == 2) {
      ringColor = const Color(0xFFE2E8F0); // Silver
    } else {
      ringColor = const Color(0xFFCD7F32); // Bronze
    }

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 1.5),
      ),
      child: ClipOval(
        child: ZevCachedImage.avatar(
          imageUrl: imageUrl,
          size: 20,
        ),
      ),
    );
  }

  void _onTapEmptyStageSeat() {
    HapticFeedback.lightImpact();
    if (widget.isHost) {
      _openStageManagementSheet();
      return;
    }

    if (_isGuestOnStage) {
      _showToast('You are already on stage!');
      return;
    }

    if (_hasPendingStageRequest) {
      _showToast('Request already sent • منتظر تایید میزبان باشید');
      return;
    }

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
        title: const Text(
          'Join Stage • بالا آمدن در استیج',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        content: const Text(
          'Do you want to send a request to the host to join as a co-host / stage guest?',
          style: TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dCtx);
              _requestJoinStage();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Send Request',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  void _requestJoinStage() {
    HapticFeedback.mediumImpact();
    final myProfile = _supabase.auth.currentUser;
    final myUid = myProfile?.id ?? '';
    if (myUid.isEmpty) return;

    final uname = (myProfile?.userMetadata?['username'] ??
            myProfile?.userMetadata?['full_name'] ??
            'User')
        .toString();
    final avatar = (myProfile?.userMetadata?['avatar_url'] ?? '').toString();

    setState(() => _hasPendingStageRequest = true);

    try {
      _roomChannel?.sendBroadcastMessage(
        event: 'stage_request',
        payload: {
          'user_id': myUid,
          'username': uname,
          'avatar_url': avatar,
        },
      );
    } catch (_) {}

    _showToast('Stage request sent to host • درخواست برای استیج ارسال شد');
  }

  Future<void> _becomeStageGuest() async {
    final eng = _rtcEngine;
    if (eng == null) return;
    HapticFeedback.heavyImpact();

    try {
      await eng.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await eng.enableLocalAudio(true);
      await eng.enableLocalVideo(true);
      try {
        await eng.startPreview();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isGuestOnStage = true;
          _hasPendingStageRequest = false;
          _localBroadcasterController = VideoViewController(
            rtcEngine: eng,
            canvas: const VideoCanvas(
              uid: 0,
              renderMode: RenderModeType.renderModeHidden,
            ),
          );
        });
        _showToast('You are now live on stage! • شما در استیج هستید');
      }
    } catch (e) {
      debugPrint('[LiveRoomScreen] Error becoming stage guest: $e');
    }
  }

  Future<void> _leaveStageGuest() async {
    final eng = _rtcEngine;
    if (eng == null) return;
    HapticFeedback.mediumImpact();

    try {
      await eng.stopPreview();
      await eng.enableLocalVideo(false);
      await eng.setClientRole(role: ClientRoleType.clientRoleAudience);
      if (mounted) {
        setState(() {
          _isGuestOnStage = false;
          _localBroadcasterController?.dispose();
          _localBroadcasterController = null;
        });
        _showToast('You left the stage • از استیج خارج شدید');
      }
    } catch (e) {
      debugPrint('[LiveRoomScreen] Error leaving stage: $e');
    }
  }

  void _openStageManagementSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.98),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.groups_rounded,
                          color: Color(0xFF38BDF8),
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isHost ? 'Stage Guests & Queue' : 'Stage Co-host',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            'Room: $_viewerCount viewers (100+ cap)',
                            style: const TextStyle(
                              color: Color(0xFF6EE7B7),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Stage content
                    Expanded(
                      child: widget.isHost
                          ? _buildHostStageContent(setSheetState)
                          : _buildViewerStageContent(setSheetState),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHostStageContent(StateSetter setSheetState) {
    if (_stageRequests.isEmpty && _remoteBroadcasters.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_add_disabled_rounded,
              color: Colors.white38,
              size: 40,
            ),
            const SizedBox(height: 10),
            const Text(
              'No pending stage requests',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Viewers from the 100+ audience will appear here when they request to join.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        if (_remoteBroadcasters.isNotEmpty) ...[
          const Text(
            'ACTIVE CO-HOSTS ON STAGE',
            style: TextStyle(
              color: Color(0xFF6EE7B7),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ..._remoteBroadcasters.keys.map((uid) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.videocam_rounded,
                    color: Color(0xFF10B981),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'UID $uid (Co-Host)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      _roomChannel?.sendBroadcastMessage(
                        event: 'stage_kicked',
                        payload: {'user_id': '$uid'},
                      );
                      setState(() {
                        _remoteBroadcasters[uid]?.dispose();
                        _remoteBroadcasters.remove(uid);
                      });
                      setSheetState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFEF4444)),
                      ),
                      child: const Text(
                        'Remove',
                        style: TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 14),
        ],

        if (_stageRequests.isNotEmpty) ...[
          Text(
            'PENDING REQUESTS (${_stageRequests.length})',
            style: const TextStyle(
              color: Color(0xFFFFD600),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ..._stageRequests.map((req) {
            final uid = req['user_id']?.toString() ?? '';
            final uname = req['username']?.toString() ?? 'User';
            final avatar = req['avatar_url']?.toString() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  ZevCachedImage.avatar(imageUrl: avatar, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '@$uname',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() => _stageRequests.removeWhere((r) => r['user_id'] == uid));
                      setSheetState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Decline',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _roomChannel?.sendBroadcastMessage(
                        event: 'stage_accepted',
                        payload: {'user_id': uid},
                      );
                      setState(() {
                        _stageRequests.removeWhere((r) => r['user_id'] == uid);
                      });
                      setSheetState(() {});
                      _showToast('Accepted @$uname to stage!');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Accept',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildViewerStageContent(StateSetter setSheetState) {
    if (_isGuestOnStage) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
              ),
              child: const Icon(
                Icons.videocam_rounded,
                color: Color(0xFF10B981),
                size: 40,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You are live on stage!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your video and mic are active in the live room.',
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _leaveStageGuest();
              },
              icon: const Icon(Icons.logout_rounded, size: 16),
              label: const Text('Leave Stage • خروج از استیج'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_hasPendingStageRequest) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.hourglass_top_rounded,
              color: Color(0xFFFFD600),
              size: 36,
            ),
            const SizedBox(height: 10),
            const Text(
              'Request Sent • در انتظار تایید میزبان',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'The host has been notified. You will join the stage once approved.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() => _hasPendingStageRequest = false);
                setSheetState(() {});
                _showToast('Request canceled');
              },
              child: const Text(
                'Cancel Request',
                style: TextStyle(color: Color(0xFFFCA5A5)),
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.person_add_alt_1_rounded,
            color: Color(0xFF38BDF8),
            size: 40,
          ),
          const SizedBox(height: 12),
          const Text(
            'Request to Join Stage',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Go live with the host in split screen or audio seats in front of 100+ viewers.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestJoinStage();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Send Stage Request • درخواست استیج',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  void _openGiftSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sheet Handle
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),

                // Coins Header
                Row(
                  children: [
                    const Text(
                      'Send Gift',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB800).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFFFB800).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🪙', style: TextStyle(fontSize: 13)),
                          SizedBox(width: 4),
                          Text(
                            '1,250 Coins',
                            style: TextStyle(
                              color: Color(0xFFFFD600),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Gift Grid (8 gifts)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _availableGifts.length,
                  itemBuilder: (ctx, idx) {
                    final gift = _availableGifts[idx];
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendGift(gift);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              gift['emoji'] as String,
                              style: const TextStyle(fontSize: 32),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              gift['name'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🪙', style: TextStyle(fontSize: 9)),
                                const SizedBox(width: 2),
                                Text(
                                  '${gift['coins']}',
                                  style: const TextStyle(
                                    color: Color(0xFFFFD600),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _sendGift(Map<String, dynamic> gift) {
    HapticFeedback.heavyImpact();
    final myProfile = _supabase.auth.currentUser;
    final senderName = (myProfile?.userMetadata?['username'] ??
            myProfile?.userMetadata?['full_name'] ??
            'Viewer')
        .toString();
    final senderAvatar =
        (myProfile?.userMetadata?['avatar_url'] ?? '').toString();

    final giftName = gift['name'] as String;
    final giftEmoji = gift['emoji'] as String;
    final points = (gift['coins'] as num).toInt();

    // Trigger local animation & haptics
    _showGiftCelebration(
      senderName: senderName,
      senderAvatar: senderAvatar,
      giftName: giftName,
      giftEmoji: giftEmoji,
      points: points,
    );

    // Broadcast realtime event to everyone in the room
    try {
      _roomChannel?.sendBroadcastMessage(
        event: 'gift_sent',
        payload: {
          'sender_name': senderName,
          'sender_avatar': senderAvatar,
          'gift_name': giftName,
          'gift_emoji': giftEmoji,
          'points': points,
        },
      );
    } catch (_) {}

    // Add gift message to comment stream
    final giftComment = {
      'id': 'gift_${DateTime.now().millisecondsSinceEpoch}',
      'user_id': myProfile?.id ?? '',
      'comment_text': 'sent $giftName $giftEmoji',
      'created_at': DateTime.now().toIso8601String(),
    };
    if (mounted) {
      setState(() {
        _comments.add(giftComment);
      });
      _scrollToBottom();
    }
    _showToast('Sent $giftName $giftEmoji to support the creator!');
  }

  void _showGiftCelebration({
    required String senderName,
    required String senderAvatar,
    required String giftName,
    required String giftEmoji,
    required int points,
  }) {
    HapticFeedback.heavyImpact();
    _spawnFloatingEmoji(giftEmoji, incrementCounter: true);
    for (int i = 0; i < 6; i++) {
      Future.delayed(Duration(milliseconds: i * 80), () {
        if (mounted) _spawnFloatingEmoji(giftEmoji);
      });
    }

    if (_isPkMatchActive) {
      setState(() {
        _pkRedScore += points;
      });
    }

    setState(() {
      _reactionTotal += points;
      _activeGiftBanner = {
        'sender': senderName,
        'avatar': senderAvatar,
        'gift': giftName,
        'emoji': giftEmoji,
        'points': points,
      };
    });

    _giftBannerTimer?.cancel();
    _giftBannerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _activeGiftBanner = null);
      }
    });
  }

  Widget _buildGiftCelebrationBanner() {
    final banner = _activeGiftBanner;
    if (banner == null) return const SizedBox.shrink();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 16,
      right: 16,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 350),
        curve: Curves.elasticOut,
        builder: (context, val, child) {
          return Transform.scale(
            scale: 0.8 + (0.2 * val),
            child: Opacity(
              opacity: val.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFFF2D55),
                Color(0xFFFF8A00),
                Color(0xFFFFD600),
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2D55).withValues(alpha: 0.6),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ZevCachedImage.avatar(
                imageUrl: banner['avatar']?.toString() ?? '',
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${banner['sender']} sent ${banner['gift']}!',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                    Text(
                      '+${banner['points']} points to host',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${banner['emoji']}',
                style: const TextStyle(fontSize: 26),
              ),
            ],
          ),
        ),
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
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Fullscreen Agora Live Video Stage (or 50/50 Multi-Live PK split screen)
            Positioned.fill(
              child: _buildFullscreenVideoStage(
                hostAvatar: hostAvatar,
                hostUsername: hostUsername,
                thumbnailUrl: thumbnailUrl,
              ),
            ),

            // 2. Dark Vignette Gradients for clear text/control readability over video
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 180,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.75),
                        Colors.black.withValues(alpha: 0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 380,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.92),
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Top Overlay Header (Host Pill, Follow, Contributors, Viewers & Close)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopOverlayHeader(
                hostId: hostId,
                hostUsername: hostUsername,
                hostFullName: hostFullName,
                hostAvatar: hostAvatar,
                hostVerified: hostVerified,
                roomTitle: roomTitle,
                category: category,
                startedAt: startedAt,
              ),
            ),

            // 4. Floating Realtime Live Comments Stream (TikTok / Instagram style)
            Positioned(
              left: 12,
              right: 84,
              bottom: 74,
              height: _isPkMatchActive ? 210 : 250,
              child: _buildFloatingChatOverlay(hostId: hostId),
            ),

            // Realtime Fullscreen Gift Celebration Banner
            _buildGiftCelebrationBanner(),

            // 5. Floating Realtime Animated Emoji Reactions Layer
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

            // 6. Bottom Actions Dock (Comment Trigger, Quick Reactions, Rose/Gift, Share & Host Controls)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomActionsBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopOverlayHeader({
    required String hostId,
    required String hostUsername,
    required String hostFullName,
    required String hostAvatar,
    required bool hostVerified,
    required String roomTitle,
    required String category,
    required String? startedAt,
  }) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Host pill with gradient story ring & follow button
                GestureDetector(
                  onTap: hostId.isNotEmpty
                      ? () => ProfileScreen.open(context, userId: hostId)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFFFF007A),
                                Color(0xFFFF5400),
                                Color(0xFFFFD600),
                              ],
                            ),
                          ),
                          child: ZevCachedImage.avatar(
                            imageUrl: hostAvatar,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 105),
                                  child: Text(
                                    hostFullName.isNotEmpty
                                        ? hostFullName
                                        : '@$hostUsername',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                if (hostVerified) ...[
                                  const SizedBox(width: 3),
                                  const Icon(
                                    Icons.verified_rounded,
                                    color: Color(0xFF38BDF8),
                                    size: 13,
                                  ),
                                ],
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.favorite_rounded,
                                  color: Color(0xFFFF2D55),
                                  size: 11,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _reactionTotal > 1000
                                      ? '${(_reactionTotal / 1000).toStringAsFixed(1)}K'
                                      : '$_reactionTotal',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (!widget.isHost) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _toggleFollowHost,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4.5,
                              ),
                              decoration: BoxDecoration(
                                gradient: _isFollowingHost
                                    ? null
                                    : const LinearGradient(
                                        colors: [
                                          Color(0xFFFF2D55),
                                          Color(0xFFFF5252),
                                        ],
                                      ),
                                color: _isFollowingHost
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : null,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isFollowingHost
                                        ? Icons.check_rounded
                                        : Icons.add_rounded,
                                    color: Colors.white,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    _isFollowingHost ? 'Following' : 'Follow',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Top Contributor mini bubbles (Gold, Silver, Bronze medals)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMiniMedalAvatar(
                      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=120&q=80',
                      1,
                    ),
                    const SizedBox(width: 4),
                    _buildMiniMedalAvatar(
                      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=120&q=80',
                      2,
                    ),
                    const SizedBox(width: 4),
                    _buildMiniMedalAvatar(
                      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=120&q=80',
                      3,
                    ),
                  ],
                ),
                const SizedBox(width: 6),

                // Viewers Pill
                GestureDetector(
                  onTap: _showParticipantsSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.people_alt_rounded,
                          color: Colors.white70,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_viewerCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Close Button
                GestureDetector(
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    if (widget.isHost && !_isEnded) {
                      final ended = await _confirmAndEndRoom();
                      if (ended && mounted) navigator.pop();
                    } else {
                      navigator.pop();
                    }
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Daily Rank and LIVE Badges matching TikTok UI
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.40),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🔥', style: TextStyle(fontSize: 10.5)),
                      SizedBox(width: 3),
                      Text(
                        'Daily No. 84',
                        style: TextStyle(
                          color: Color(0xFFFFD600),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'ZEV LIVE FEST',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (_isEnded || _joinError != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _joinError ?? 'ENDED',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingChatOverlay({required String hostId}) {
    if (_isLoadingComments) {
      return const SizedBox.shrink();
    }

    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white],
          stops: [0.0, 0.28],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: _comments.length + (_isPkMatchActive ? 1 : 0),
        itemBuilder: (context, idx) {
          // Highlight banner at top when PK battle is active
          if (_isPkMatchActive && idx == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF2D55).withValues(alpha: 0.65),
                    const Color(0xFF6366F1).withValues(alpha: 0.65),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, color: Color(0xFFFFD600), size: 16),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'LIVE Match has started! Cheer on your host, like the match, and send Gifts.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final commentIndex = _isPkMatchActive ? idx - 1 : idx;
          final c = _comments[commentIndex];
          final uid = c['user_id']?.toString() ?? '';
          final prof = _profileCache[uid];
          final uname = (prof?['username'] ?? 'user').toString();
          final avatar = (prof?['avatar_url'] ?? '').toString();
          final isAuthorHost = uid == hostId;
          final body = (c['comment_text'] ?? '').toString();

          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: uid.isNotEmpty
                        ? () => ProfileScreen.open(context, userId: uid)
                        : null,
                    child: ZevCachedImage.avatar(imageUrl: avatar, size: 22),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '@$uname ',
                            style: TextStyle(
                              color: isAuthorHost
                                  ? const Color(0xFFFFD600)
                                  : const Color(0xFF67E8F9),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (isAuthorHost)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Container(
                                margin: const EdgeInsets.only(right: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF2D55),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'HOST',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          TextSpan(
                            text: body,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomActionsBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            // Comment input pill
            Expanded(
              child: GestureDetector(
                onTap: _openCommentSheet,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.50),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Comment...',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.sentiment_satisfied_alt_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Quick Rose Button matching TikTok reference
            _buildRoundActionButton(
              icon: Icons.local_florist_rounded,
              iconColor: const Color(0xFFFF2D55),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF2D55), Color(0xFFFF758C)],
              ),
              badge: 'Rose',
              onTap: () {
                _sendGift(_availableGifts[0]);
              },
            ),
            const SizedBox(width: 8),

            // Gift Box Button opening TikTok style gifts sheet
            _buildRoundActionButton(
              icon: Icons.card_giftcard_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
              ),
              badge: 'Gift',
              onTap: _openGiftSheet,
            ),
            const SizedBox(width: 8),

            // Stage Guest Request / Co-Host Seats Button
            _buildRoundActionButton(
              icon: widget.isHost
                  ? Icons.groups_rounded
                  : Icons.person_add_alt_1_rounded,
              iconColor:
                  _isGuestOnStage ? const Color(0xFF10B981) : Colors.white,
              backgroundColor: _isGuestOnStage
                  ? const Color(0xFF10B981).withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.50),
              badge: widget.isHost && _stageRequests.isNotEmpty
                  ? '${_stageRequests.length}'
                  : (_isGuestOnStage ? 'Live' : null),
              onTap: _openStageManagementSheet,
            ),
            const SizedBox(width: 8),

            // Share Button matching TikTok reference (with share count badge)
            _buildRoundActionButton(
              icon: Icons.reply_rounded,
              iconColor: Colors.white,
              backgroundColor: Colors.black.withValues(alpha: 0.50),
              badge: '46',
              onTap: () {
                HapticFeedback.lightImpact();
                Clipboard.setData(
                  ClipboardData(text: 'https://web.zevapp.com/live/$_streamId'),
                );
                _showToast('Live stream link copied to clipboard!');
              },
            ),

            // Host Media Controls (Flip Cam, Camera Toggle, Mute Mic, PK Battle)
            if (widget.isHost && !_isEnded) ...[
              const SizedBox(width: 8),
              _buildRoundActionButton(
                icon: Icons.sports_kabaddi_rounded,
                iconColor:
                    _isPkMatchActive ? const Color(0xFFFFD600) : Colors.white,
                gradient: _isPkMatchActive
                    ? const LinearGradient(
                        colors: [Color(0xFFFF2D55), Color(0xFF6366F1)],
                      )
                    : null,
                backgroundColor: _isPkMatchActive
                    ? null
                    : Colors.black.withValues(alpha: 0.50),
                badge: 'PK',
                onTap: _togglePkMatch,
              ),
              const SizedBox(width: 8),
              _buildRoundActionButton(
                icon: Icons.flip_camera_ios_rounded,
                iconColor: Colors.white,
                backgroundColor: Colors.black.withValues(alpha: 0.50),
                onTap: _switchLiveCamera,
              ),
              const SizedBox(width: 8),
              _buildRoundActionButton(
                icon: _isCameraOff
                    ? Icons.videocam_off_rounded
                    : Icons.videocam_rounded,
                iconColor:
                    _isCameraOff ? const Color(0xFFFF2D55) : Colors.white,
                backgroundColor: Colors.black.withValues(alpha: 0.50),
                onTap: _toggleLiveCam,
              ),
              const SizedBox(width: 8),
              _buildRoundActionButton(
                icon: _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                iconColor: _isMicMuted ? const Color(0xFFFF2D55) : Colors.white,
                backgroundColor: Colors.black.withValues(alpha: 0.50),
                onTap: _toggleLiveMic,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoundActionButton({
    required IconData icon,
    Color iconColor = Colors.white,
    Color? backgroundColor,
    Gradient? gradient,
    String? badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: gradient == null
                  ? (backgroundColor ?? Colors.black.withValues(alpha: 0.45))
                  : null,
              gradient: gradient,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, color: iconColor, size: 20),
            ),
          ),
          if (badge != null && badge.isNotEmpty)
            Positioned(
              top: -4,
              right: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF2D55), Color(0xFFFF5252)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _togglePkMatch() {
    HapticFeedback.heavyImpact();
    setState(() {
      _isPkMatchActive = !_isPkMatchActive;
      if (_isPkMatchActive) {
        _pkRedScore = 37;
        _pkBlueScore = 12;
        _pkTimeRemaining = 199;
        _startPkTimer();
        _showToast('PK Battle Match started! Cheer on your host!');
      } else {
        _pkTimer?.cancel();
        _showToast('PK Battle Match ended');
      }
    });
  }

  void _openCommentSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.96),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Quick emojis bar
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _quickEmojis.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, idx) {
                        final emoji = _quickEmojis[idx];
                        return GestureDetector(
                          onTap: () {
                            _sendReaction(emoji);
                            _commentCtrl.text = '${_commentCtrl.text}$emoji';
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: TextField(
                            controller: _commentCtrl,
                            autofocus: true,
                            maxLength: 500,
                            maxLines: 2,
                            minLines: 1,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) {
                              Navigator.pop(ctx);
                              _sendComment();
                            },
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Say something nice...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: Colors.white54,
                              ),
                              border: InputBorder.none,
                              counterText: '',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _sendComment();
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: ZevColors.brandGradient,
                          ),
                          child: const Center(
                            child: Icon(
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
        );
      },
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
