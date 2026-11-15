import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/zev_call_audio_service.dart';
import '../../../core/services/zev_pip_service.dart';
import '../../../core/services/zev_rtc_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../main.dart';
import '../models/zev_call_effects.dart';
import '../widgets/zev_snapchat_lens_overlay.dart';

/// Production-Grade ZEV Calling System 2.0 Screen.
/// Supports 1-to-1 and Group Calls, instant WebRTC connection, draggable
/// self-view with snap-to-corners, ambient camera-off states, background
/// multitasking, independent hardware video filters, and granular beauty tuning.
class CallScreen extends StatefulWidget {
  final ZevCallSession? initialSession;
  final bool isOutgoing;
  final bool isVideo;
  final String peerId;
  final String peerUsername;
  final String peerFullName;
  final String peerAvatar;
  final bool isPeerVerified;
  final String? conversationId;
  final bool resumedFromMinimized;

  const CallScreen({
    super.key,
    this.initialSession,
    required this.isOutgoing,
    required this.isVideo,
    required this.peerId,
    this.peerUsername = 'User',
    this.peerFullName = '',
    this.peerAvatar = '',
    this.isPeerVerified = false,
    this.conversationId,
    this.resumedFromMinimized = false,
  });

  static Future<void> startOutgoing(
    BuildContext context, {
    required String peerId,
    required String peerUsername,
    String peerFullName = '',
    String peerAvatar = '',
    bool isPeerVerified = false,
    String? conversationId,
    required bool isVideo,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          isOutgoing: true,
          isVideo: isVideo,
          peerId: peerId,
          peerUsername: peerUsername,
          peerFullName: peerFullName,
          peerAvatar: peerAvatar,
          isPeerVerified: isPeerVerified,
          conversationId: conversationId,
        ),
      ),
    );
  }

  static Future<void> openIncoming(
    NavigatorState navigator, {
    required ZevCallSession session,
    required Map<String, dynamic> peerProfile,
  }) {
    final uname = (peerProfile['username'] ?? 'User').toString();
    final full =
        '${peerProfile['first_name'] ?? ''} ${peerProfile['last_name'] ?? ''}'
            .trim();
    final avatar = (peerProfile['avatar_url'] ?? '').toString();
    final verified = peerProfile['is_verified'] == true;

    return navigator.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          initialSession: session,
          isOutgoing: false,
          isVideo: session.isVideo,
          peerId: session.callerId,
          peerUsername: uname,
          peerFullName: full,
          peerAvatar: avatar,
          isPeerVerified: verified,
          conversationId: session.conversationId,
        ),
      ),
    );
  }

  static Future<void> openById(
    BuildContext context, {
    required String callSessionId,
  }) async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;
    final session = await ZevRtcService.instance.fetchCallById(callSessionId);
    if (session == null || !session.isActive) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This call has already ended.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (ZevRtcService.instance.activeCallId == session.id) return;

    final peerId =
        session.callerId == myId ? session.calleeId : session.callerId;
    final peerProfile = await ZevRtcService.instance.fetchProfileSummary(peerId);
    final navState = appNavigatorKey.currentState;
    if (navState == null || !navState.mounted) return;

    if (session.calleeId == myId) {
      await openIncoming(navState, session: session, peerProfile: peerProfile);
    }
  }

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _RemoteParticipantState {
  final int uid;
  bool videoEnabled;
  bool audioMuted = false;
  bool isSpeaking = false;
  VideoViewController? videoController;
  Map<String, dynamic>? profile;
  String selectedEffectId = 'none';

  _RemoteParticipantState({
    required this.uid,
    this.videoEnabled = true,
    this.videoController,
  });
}

class _CallScreenState extends State<CallScreen>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  ZevCallSession? _session;
  RtcEngine? _engine;
  RtcEngineEventHandler? _engineHandler;
  VideoViewController? _localVideoController;

  // Remote participants map for 1-to-1 & Group Calling
  final Map<int, _RemoteParticipantState> _remoteParticipants = {};
  int? _primaryRemoteUid;

  RealtimeChannel? _callChannel;
  RealtimeChannel? _participantsChannel;
  Timer? _ringTimeoutTimer;
  Timer? _durationTimer;
  Timer? _statusPollTimer;
  Timer? _autoCloseTimer;
  Timer? _controlsHideTimer;

  late final AnimationController _pulseCtrl;
  late final AnimationController _pipSnapCtrl;

  String _phase = 'connecting'; // connecting | ringing | accepted | ended
  String _statusLabel = 'Connecting...';
  String? _errorMsg;
  int _elapsedSeconds = 0;

  bool _isMicMuted = false;
  bool _isSpeakerOn = true;
  bool _isCameraOff = false;
  bool _isVideoActive = false;
  bool _isFrontCamera = true;
  bool _isActionInFlight = false;
  bool _engineJoined = false;
  bool _isClosing = false;
  bool _controlsVisible = true;
  bool _isMinimized = false;
  int? _dataStreamId;

  // Beauty & Lighting Studio State
  bool _showEffectsTray = false;
  String _selectedEffectId = 'none';
  ZevCallEffectCategory _selectedEffectCategory = ZevCallEffectCategory.lighting;
  ZevBeautyTuning _beautyTuning = const ZevBeautyTuning();

  // Draggable PIP State (Snap-to-4-corners)
  Offset _pipOffset = const Offset(20, 80);
  Animation<Offset>? _pipSnapAnim;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _isVideoActive = widget.isVideo || (_session?.isVideo ?? false);
    _isSpeakerOn = _isVideoActive;
    _isCameraOff = !_isVideoActive;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pipSnapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    if (widget.resumedFromMinimized) {
      _session = widget.initialSession ?? ZevRtcService.instance.activeMinimizedSession;
      _phase = 'accepted';
      _statusLabel = 'Connected';
      _engineJoined = true;
      _elapsedSeconds = ZevRtcService.instance.activeDurationSeconds;
      _isMicMuted = ZevRtcService.instance.isActiveMicMuted;
      _isSpeakerOn = ZevRtcService.instance.isActiveSpeakerOn;
      _isCameraOff = ZevRtcService.instance.isActiveCameraOff;
      _isVideoActive = widget.isVideo && !_isCameraOff;
      _engine = ZevRtcService.instance.activeMinimizedEngine;
      _engineHandler = ZevRtcService.instance.activeMinimizedHandler;
      _localVideoController = ZevRtcService.instance.activeLocalVideoController;

      if (ZevRtcService.instance.activeRemoteUid != null) {
        _primaryRemoteUid = ZevRtcService.instance.activeRemoteUid;
        _remoteParticipants[_primaryRemoteUid!] = _RemoteParticipantState(
          uid: _primaryRemoteUid!,
          videoEnabled: true,
          videoController: ZevRtcService.instance.activeRemoteVideoController,
        );
      }

      ZevRtcService.instance.isCallMinimized = false;
      ZevRtcService.instance.minimizedCallNotifier.value = null;

      _startDurationTimer();
      _resetControlsHideTimer();
      if (_session != null) {
        _subscribeCallSession(_session!.id);
        _subscribeParticipants(_session!.id);
      }
      return;
    }

    if (_session != null) {
      ZevRtcService.instance.setActiveCall(_session!.id);
      ZevRtcService.instance.minimizedPeerProfile = {
        'username': widget.peerUsername,
        'first_name': widget.peerFullName,
        'avatar_url': widget.peerAvatar,
        'is_verified': widget.isPeerVerified,
      };
    }

    _resetControlsHideTimer();
    _bootstrapCall();
  }

  @override
  void dispose() {
    _ringTimeoutTimer?.cancel();
    _durationTimer?.cancel();
    _statusPollTimer?.cancel();
    _autoCloseTimer?.cancel();
    _controlsHideTimer?.cancel();
    _pulseCtrl.dispose();
    _pipSnapCtrl.dispose();

    if (_isMinimized) {
      // PRESERVE WEBRTC CALL! DO NOT TEARDOWN!
      super.dispose();
      return;
    }

    final ch = _callChannel;
    _callChannel = null;
    ch?.unsubscribe();

    final pch = _participantsChannel;
    _participantsChannel = null;
    pch?.unsubscribe();

    if (_session != null) {
      ZevRtcService.instance.clearActiveCall(_session!.id);
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(ZevPipService.instance.disableAutoPip());
    }

    unawaited(ZevCallAudioService.instance.stopAll());
    unawaited(_teardownEngine());
    super.dispose();
  }

  Future<void> _teardownEngine() async {
    _localVideoController?.dispose();
    _localVideoController = null;

    for (final p in _remoteParticipants.values) {
      p.videoController?.dispose();
    }
    _remoteParticipants.clear();

    final eng = _engine;
    final handler = _engineHandler;
    _engine = null;
    _engineHandler = null;

    if (eng != null) {
      try {
        if (handler != null) eng.unregisterEventHandler(handler);
      } catch (_) {}
      try {
        await eng.leaveChannel();
      } catch (_) {}
    }
  }

  void _resetControlsHideTimer() {
    _controlsHideTimer?.cancel();
    if (_phase == 'accepted' && _isVideoActive) {
      _controlsHideTimer = Timer(const Duration(seconds: 6), () {
        if (mounted && _controlsVisible && !_showEffectsTray) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  void _toggleControlsVisibility() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _resetControlsHideTimer();
    }
  }

  Future<bool> _ensurePermissions() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return true;
    }

    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        return false;
      }
    }
    if (widget.isVideo || _isVideoActive) {
      var camStatus = await Permission.camera.status;
      if (!camStatus.isGranted) {
        camStatus = await Permission.camera.request();
        if (!camStatus.isGranted) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _bootstrapCall() async {
    try {
      if (widget.isOutgoing) {
        setState(() {
          _phase = 'connecting';
          _statusLabel =
              'Starting ${widget.isVideo ? 'video' : 'voice'} call...';
        });

        final permsOk = await _ensurePermissions();
        if (!permsOk) {
          _finishLocally(
            'Microphone${widget.isVideo ? ' & Camera' : ''} permission required.',
          );
          return;
        }

        final myId = _supabase.auth.currentUser?.id;
        String myDisplayName = 'A ZEV user';
        if (myId != null) {
          final prof = await ZevRtcService.instance.fetchProfileSummary(myId);
          final full =
              '${prof['first_name'] ?? ''} ${prof['last_name'] ?? ''}'.trim();
          final uname = (prof['username'] ?? '').toString().trim();
          if (full.isNotEmpty) {
            myDisplayName = full;
          } else if (uname.isNotEmpty) {
            myDisplayName = '@$uname';
          }
        }

        // Start local video preview immediately for caller (zero lag)
        if (_isVideoActive) {
          await _prestartLocalPreview();
        }

        final created = await ZevRtcService.instance.initiateCall(
          calleeId: widget.peerId,
          callType: widget.isVideo ? 'video' : 'voice',
          callerDisplayName: myDisplayName,
          conversationId: widget.conversationId,
        );

        if (!mounted) {
          unawaited(
            ZevRtcService.instance
                .respondCall(callId: created.id, action: 'cancel')
                .catchError((_) => created),
          );
          return;
        }

        ZevRtcService.instance.setActiveCall(created.id);
        setState(() {
          _session = created;
          _phase = 'ringing';
          _statusLabel = 'Ringing...';
        });
        unawaited(ZevCallAudioService.instance.startOutgoingCallingTone());

        _subscribeCallSession(created.id);
        _subscribeParticipants(created.id);
        _startRingTimeout(created.id);
        unawaited(_startAgoraEngine(created.id));
      } else {
        final session = _session;
        if (session == null) {
          _finishLocally('Invalid call session.');
          return;
        }
        ZevRtcService.instance.setActiveCall(session.id);
        setState(() {
          _phase = session.isAccepted ? 'accepted' : 'ringing';
          _statusLabel =
              session.isVideo ? 'Incoming Video Call' : 'Incoming Voice Call';
        });
        if (!session.isAccepted) {
          unawaited(ZevCallAudioService.instance.startIncomingRingtone());
          if (widget.isVideo || session.isVideo) {
            unawaited(_prestartLocalPreview());
          }
        }
        _subscribeCallSession(session.id);
        _subscribeParticipants(session.id);
        _startStatusPoll(session.id);

        if (session.isAccepted) {
          final permsOk = await _ensurePermissions();
          if (!permsOk) {
            await _hangupOrDecline();
            return;
          }
          _startDurationTimer();
          await _startAgoraEngine(session.id);
        }
      }
    } catch (e) {
      debugPrint('[CallScreen] bootstrap error: $e');
      if (mounted) {
        _finishLocally(
          e.toString().replaceFirst('Exception: ', '').trim(),
        );
      }
    }
  }

  /// Instantly initializes local video preview on outgoing calls before joining channel.
  Future<void> _prestartLocalPreview() async {
    try {
      final engine = await ZevRtcService.instance.getOrInitializeEngine();
      await engine.enableVideo();
      await engine.startPreview();
      try {
        await engine.enableFaceDetection(true);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _localVideoController = VideoViewController(
            rtcEngine: engine,
            canvas: const VideoCanvas(
              uid: 0,
              renderMode: RenderModeType.renderModeHidden,
              mirrorMode: VideoMirrorModeType.videoMirrorModeEnabled,
            ),
          );
        });
      }
    } catch (e) {
      debugPrint('[CallScreen] prestart preview notice: $e');
    }
  }

  void _startRingTimeout(String callId) {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = Timer(const Duration(seconds: 45), () async {
      if (!mounted || _phase != 'ringing') return;
      try {
        await ZevRtcService.instance.respondCall(
          callId: callId,
          action: 'missed',
          reason: 'no_answer',
        );
      } catch (_) {}
      _finishLocally('No Answer');
    });
  }

  void _startStatusPoll(String callId) {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _phase == 'ended' || _phase == 'accepted') {
        _statusPollTimer?.cancel();
        return;
      }
      final latest = await ZevRtcService.instance.fetchCallById(callId);
      if (latest != null && mounted) {
        _applySessionUpdate(latest);
      }
    });
  }

  void _subscribeCallSession(String callId) {
    _callChannel?.unsubscribe();
    try {
      _callChannel = _supabase
          .channel('call_session:$callId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'call_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: callId,
            ),
            callback: (payload) {
              if (!mounted || payload.newRecord.isEmpty) return;
              final updated = ZevCallSession.fromMap(
                Map<String, dynamic>.from(payload.newRecord),
              );
              _applySessionUpdate(updated);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[CallScreen] subscribe notice: $e');
    }
  }

  void _subscribeParticipants(String callId) {
    _participantsChannel?.unsubscribe();
    try {
      _participantsChannel = _supabase
          .channel('call_participants:$callId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'call_participants',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'call_session_id',
              value: callId,
            ),
            callback: (_) {
              if (mounted) _syncParticipants(callId);
            },
          )
          .subscribe();
      _syncParticipants(callId);
    } catch (e) {
      debugPrint('[CallScreen] participants subscribe notice: $e');
    }
  }

  Future<void> _syncParticipants(String callId) async {
    final list = await ZevRtcService.instance.fetchParticipants(callId);
    if (!mounted) return;
    for (final p in list) {
      if (p.isJoined) {
        // Sync profile into existing remote participant state if uid matches
        for (final rp in _remoteParticipants.values) {
          rp.profile ??= p.profile;
        }
      }
    }
    setState(() {});
  }

  void _applySessionUpdate(ZevCallSession updated) {
    if (!mounted || _phase == 'ended') return;
    _session = updated;

    if (updated.isVideo && !_isVideoActive) {
      setState(() => _isVideoActive = true);
      _engine?.enableVideo();
      _engine?.updateChannelMediaOptions(
        const ChannelMediaOptions(autoSubscribeVideo: true),
      );
    }

    if (updated.status == 'accepted' && _phase != 'accepted') {
      _ringTimeoutTimer?.cancel();
      _statusPollTimer?.cancel();
      HapticFeedback.mediumImpact();
      unawaited(ZevCallAudioService.instance.playCallConnectedTone());
      setState(() {
        _phase = 'accepted';
        _statusLabel = 'Connected';
      });
      _startDurationTimer();
      _resetControlsHideTimer();
    } else if (!updated.isActive) {
      final msg = switch (updated.status) {
        'rejected' => widget.isOutgoing ? 'Call Declined' : 'Declined',
        'busy' => 'User is Busy',
        'missed' => 'No Answer',
        _ => 'Call Ended',
      };
      _finishLocally(msg);
    }
  }

  void _startDurationTimer() {
    if (_durationTimer != null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _phase == 'ended') return;
      setState(() {
        _elapsedSeconds += 1;
        ZevRtcService.instance.minimizedDurationSeconds = _elapsedSeconds;
      });
    });
  }

  /// Establishes the Agora RTC channel using pre-warmed engine and cached token.
  Future<void> _startAgoraEngine(String callSessionId) async {
    if (_engineJoined || _phase == 'ended') return;

    final creds = await ZevRtcService.instance.fetchCallToken(
      callSessionId: callSessionId,
    );
    if (!mounted || _phase == 'ended') return;

    final resolvedAppId =
        creds.appId.isNotEmpty ? creds.appId : AppConfig.agoraAppId;
    if (resolvedAppId.isEmpty || creds.token.isEmpty) {
      throw Exception('Agora RTC credentials unavailable.');
    }

    final engine = await ZevRtcService.instance.getOrInitializeEngine(
      appId: resolvedAppId,
    );

    final handler = RtcEngineEventHandler(
      onError: (ErrorCodeType err, String msg) {
        debugPrint('[CallScreen][Agora] onError $err $msg');
      },
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        if (!mounted) return;
        setState(() => _engineJoined = true);
      },
      onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
        if (!mounted || remoteUid == 0) return;
        HapticFeedback.lightImpact();
        setState(() {
          _primaryRemoteUid = remoteUid;
          final part = _remoteParticipants.putIfAbsent(
            remoteUid,
            () => _RemoteParticipantState(uid: remoteUid),
          );
          part.videoEnabled = true;

          if (_phase != 'accepted') {
            _phase = 'accepted';
            _statusLabel = 'Connected';
            _ringTimeoutTimer?.cancel();
            _startDurationTimer();
            _resetControlsHideTimer();
            unawaited(ZevCallAudioService.instance.playCallConnectedTone());
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
              unawaited(
                ZevPipService.instance.enableAutoPip(aspectX: 9, aspectY: 16),
              );
            }
          }

          if (_isVideoActive || widget.isVideo) {
            part.videoController ??= VideoViewController.remote(
              rtcEngine: engine,
              canvas: VideoCanvas(
                uid: remoteUid,
                renderMode: RenderModeType.renderModeFit,
              ),
              connection: connection,
            );
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
          final p = _remoteParticipants.remove(remoteUid);
          p?.videoController?.dispose();
          if (_primaryRemoteUid == remoteUid) {
            _primaryRemoteUid = _remoteParticipants.keys.isNotEmpty
                ? _remoteParticipants.keys.first
                : null;
          }
        });
        if (_remoteParticipants.isEmpty && _phase == 'accepted') {
          _finishLocally('Call Ended');
        }
      },
      onUserMuteVideo: (RtcConnection connection, int remoteUid, bool muted) {
        if (!mounted) return;
        setState(() {
          final part = _remoteParticipants[remoteUid];
          if (part != null) {
            part.videoEnabled = !muted;
          }
        });
      },
      onUserMuteAudio: (RtcConnection connection, int remoteUid, bool muted) {
        if (!mounted) return;
        setState(() {
          final part = _remoteParticipants[remoteUid];
          if (part != null) {
            part.audioMuted = muted;
          }
        });
      },
      onAudioVolumeIndication: (
        RtcConnection connection,
        List<AudioVolumeInfo> speakers,
        int totalVolume,
        int speakerNumber,
      ) {
        if (!mounted) return;
        for (final spk in speakers) {
          final uid = spk.uid ?? 0;
          if (uid > 0 && _remoteParticipants.containsKey(uid)) {
            final isSpeaking = (spk.volume ?? 0) > 15;
            if (_remoteParticipants[uid]!.isSpeaking != isSpeaking) {
              setState(() {
                _remoteParticipants[uid]!.isSpeaking = isSpeaking;
              });
            }
          }
        }
      },
      onRemoteVideoStateChanged: (
        RtcConnection connection,
        int remoteUid,
        RemoteVideoState state,
        RemoteVideoStateReason reason,
        int elapsed,
      ) {
        if (!mounted || remoteUid == 0) return;
        if (state == RemoteVideoState.remoteVideoStateDecoding ||
            state == RemoteVideoState.remoteVideoStateStarting) {
          setState(() {
            _primaryRemoteUid = remoteUid;
            _isVideoActive = true;
            final part = _remoteParticipants.putIfAbsent(
              remoteUid,
              () => _RemoteParticipantState(uid: remoteUid),
            );
            part.videoEnabled = true;
            part.videoController ??= VideoViewController.remote(
              rtcEngine: engine,
              canvas: VideoCanvas(
                uid: remoteUid,
                renderMode: RenderModeType.renderModeFit,
              ),
              connection: connection,
            );
          });
        } else if (state == RemoteVideoState.remoteVideoStateStopped) {
          setState(() {
            _remoteParticipants[remoteUid]?.videoEnabled = false;
          });
        }
      },
      onStreamMessage: (
        RtcConnection connection,
        int remoteUid,
        int streamId,
        Uint8List data,
        int length,
        int sentTs,
      ) {
        if (!mounted || remoteUid == 0) return;
        try {
          final str = utf8.decode(data);
          final map = jsonDecode(str) as Map<String, dynamic>;
          if (map['type'] == 'effect') {
            final effectId = map['id']?.toString() ?? 'none';
            setState(() {
              final part = _remoteParticipants[remoteUid];
              if (part != null) {
                part.selectedEffectId = effectId;
              }
            });
          }
        } catch (_) {}
      },
    );

    engine.registerEventHandler(handler);
    _engine = engine;
    _engineHandler = handler;

    await engine.enableAudio();
    try {
      await engine.enableAudioVolumeIndication(
        interval: 250,
        smooth: 3,
        reportVad: true,
      );
      await engine.setEnableSpeakerphone(_isSpeakerOn);
    } catch (_) {}

    if (_isVideoActive) {
      await engine.enableVideo();
      try {
        await engine.enableFaceDetection(true);
      } catch (_) {}
      try {
        await engine.setVideoEncoderConfiguration(
          const VideoEncoderConfiguration(
            dimensions: VideoDimensions(width: 720, height: 1280),
            frameRate: 30,
            bitrate: 1500,
            orientationMode: OrientationMode.orientationModeAdaptive,
          ),
        );
      } catch (_) {}
      try {
        await engine.startPreview();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _localVideoController = VideoViewController(
            rtcEngine: engine,
            canvas: const VideoCanvas(
              uid: 0,
              renderMode: RenderModeType.renderModeHidden,
              mirrorMode: VideoMirrorModeType.videoMirrorModeEnabled,
            ),
          );
        });
      }
    } else {
      await engine.disableVideo();
    }

    await engine.joinChannel(
      token: creds.token,
      channelId: creds.channelName,
      uid: creds.uid,
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishMicrophoneTrack: !_isMicMuted,
        publishCameraTrack: _isVideoActive && !_isCameraOff,
        autoSubscribeAudio: true,
        autoSubscribeVideo: _isVideoActive,
      ),
    );

    try {
      _dataStreamId = await engine.createDataStream(
        const DataStreamConfig(syncWithAudio: false, ordered: false),
      );
    } catch (_) {}
  }

  Future<void> _acceptIncomingCall() async {
    final session = _session;
    if (session == null || _isActionInFlight) return;
    HapticFeedback.mediumImpact();
    setState(() => _isActionInFlight = true);

    try {
      final permsOk = await _ensurePermissions();
      if (!permsOk) {
        if (mounted) {
          setState(() {
            _isActionInFlight = false;
            _errorMsg =
                'Allow microphone${widget.isVideo ? ' & camera' : ''} to answer.';
          });
        }
        return;
      }

      // Parallel execution: start Agora join while updating database!
      unawaited(_startAgoraEngine(session.id));

      final updated = await ZevRtcService.instance.respondCall(
        callId: session.id,
        action: 'accept',
      );
      if (!mounted) return;
      _applySessionUpdate(updated);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        unawaited(
          ZevPipService.instance.enableAutoPip(aspectX: 9, aspectY: 16),
        );
      }
      setState(() => _isActionInFlight = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInFlight = false);
        _finishLocally(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _hangupOrDecline() async {
    if (_isActionInFlight || _isClosing) return;
    HapticFeedback.mediumImpact();
    setState(() => _isActionInFlight = true);

    final session = _session;
    if (session != null) {
      String action = 'end';
      if (session.isRinging || _phase == 'ringing') {
        action = widget.isOutgoing ? 'cancel' : 'reject';
      }
      try {
        await ZevRtcService.instance.respondCall(
          callId: session.id,
          action: action,
        );
      } catch (_) {}
    }

    _finishLocally(
      _phase == 'accepted'
          ? 'Call Ended'
          : (widget.isOutgoing ? 'Cancelled' : 'Declined'),
    );
  }

  void _finishLocally(String label) {
    if (_isClosing) return;
    _isClosing = true;
    _ringTimeoutTimer?.cancel();
    _durationTimer?.cancel();
    _statusPollTimer?.cancel();
    _controlsHideTimer?.cancel();

    ZevRtcService.instance.minimizedCallNotifier.value = null;

    unawaited(ZevCallAudioService.instance.stopLoop());
    unawaited(ZevCallAudioService.instance.playCallEndedTone());
    unawaited(_teardownEngine());

    if (!mounted) return;
    setState(() {
      _phase = 'ended';
      _statusLabel = label;
      _isActionInFlight = false;
    });

    _autoCloseTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  /// Minimizes the call into a floating in-app mini banner or PiP without dropping WebRTC.
  void _minimizeCall() {
    if (_phase != 'accepted' || _session == null) {
      unawaited(_hangupOrDecline());
      return;
    }

    final eng = _engine;
    final handler = _engineHandler;
    if (eng == null || handler == null) {
      unawaited(_hangupOrDecline());
      return;
    }

    HapticFeedback.lightImpact();
    _isMinimized = true;

    VideoViewController? remoteCtrl;
    int? remoteUid;
    if (_remoteParticipants.isNotEmpty) {
      final p = _remoteParticipants[_primaryRemoteUid] ??
          _remoteParticipants.values.first;
      remoteCtrl = p.videoController;
      remoteUid = p.uid;
    }

    ZevRtcService.instance.minimizeActiveCall(
      session: _session!,
      peerProfile: {
        'username': widget.peerUsername,
        'first_name': widget.peerFullName,
        'avatar_url': widget.peerAvatar,
        'is_verified': widget.isPeerVerified,
      },
      durationSeconds: _elapsedSeconds,
      isMicMuted: _isMicMuted,
      isSpeakerOn: _isSpeakerOn,
      isCameraOff: _isCameraOff,
      engine: eng,
      handler: handler,
      localVideoController: _localVideoController,
      remoteVideoController: remoteCtrl,
      remoteUid: remoteUid,
    );

    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacementNamed('/messages');
      }
    }
  }

  Future<void> _toggleMute() async {
    HapticFeedback.selectionClick();
    final next = !_isMicMuted;
    setState(() => _isMicMuted = next);
    try {
      await _engine?.muteLocalAudioStream(next);
    } catch (_) {}
  }

  Future<void> _toggleSpeaker() async {
    HapticFeedback.selectionClick();
    final next = !_isSpeakerOn;
    setState(() => _isSpeakerOn = next);
    try {
      await _engine?.setEnableSpeakerphone(next);
    } catch (_) {}
  }

  Future<void> _toggleCamera() async {
    final eng = _engine;
    if (eng == null || _phase == 'ended') return;
    HapticFeedback.selectionClick();

    if (!_isVideoActive) {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        final camStatus = await Permission.camera.request();
        if (!camStatus.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Camera permission required'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }

      try {
        await eng.enableVideo();
        await eng.startPreview();
        await eng.updateChannelMediaOptions(
          const ChannelMediaOptions(
            publishCameraTrack: true,
            autoSubscribeVideo: true,
          ),
        );

        if (mounted) {
          setState(() {
            _isVideoActive = true;
            _isCameraOff = false;
            _localVideoController?.dispose();
            _localVideoController = VideoViewController(
              rtcEngine: eng,
              canvas: const VideoCanvas(
                uid: 0,
                renderMode: RenderModeType.renderModeHidden,
                mirrorMode: VideoMirrorModeType.videoMirrorModeEnabled,
              ),
            );
          });
        }
      } catch (e) {
        debugPrint('[CallScreen] enableVideo error: $e');
      }
    } else {
      final nextOff = !_isCameraOff;
      setState(() => _isCameraOff = nextOff);
      try {
        await eng.muteLocalVideoStream(nextOff);
        await eng.enableLocalVideo(!nextOff);
        await eng.updateChannelMediaOptions(
          ChannelMediaOptions(publishCameraTrack: !nextOff),
        );
      } catch (_) {}
    }
  }

  Future<void> _switchCamera() async {
    if (!_isVideoActive || _isCameraOff) return;
    HapticFeedback.selectionClick();
    try {
      await _engine?.switchCamera();
      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
      // Re-configure local canvas mirror mode for natural FOV
      _localVideoController?.dispose();
      _localVideoController = VideoViewController(
        rtcEngine: _engine!,
        canvas: VideoCanvas(
          uid: 0,
          renderMode: RenderModeType.renderModeHidden,
          mirrorMode: _isFrontCamera
              ? VideoMirrorModeType.videoMirrorModeEnabled
              : VideoMirrorModeType.videoMirrorModeDisabled,
        ),
      );
    } catch (_) {}
  }

  void _broadcastEffect(String effectId) {
    final eng = _engine;
    final sid = _dataStreamId;
    if (eng == null || sid == null) return;
    try {
      final payload = jsonEncode({'type': 'effect', 'id': effectId});
      final bytes = Uint8List.fromList(utf8.encode(payload));
      eng.sendStreamMessage(streamId: sid, data: bytes, length: bytes.length);
    } catch (_) {}
  }

  /// Applies video effect independently to outgoing camera track.
  Future<void> _applyEffect(ZevCallEffect effect) async {
    final eng = _engine;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedEffectId = effect.id;
    });

    _broadcastEffect(effect.id);

    if (eng == null) return;

    try {
      // 1. Beauty options
      if (effect.agoraBeauty != null) {
        await eng.setBeautyEffectOptions(
          enabled: true,
          options: effect.agoraBeauty!,
        );
      } else if (!_beautyTuning.isActive) {
        await eng.setBeautyEffectOptions(
          enabled: false,
          options: const BeautyOptions(),
        );
      }

      // 2. Virtual Background
      if (effect.virtualBackground != null) {
        await eng.enableVirtualBackground(
          enabled: true,
          backgroundSource: effect.virtualBackground!,
          segproperty: const SegmentationProperty(
            modelType: SegModelType.segModelAi,
          ),
        );
      } else if (_beautyTuning.blurDegree == 0) {
        await eng.enableVirtualBackground(
          enabled: false,
          backgroundSource: const VirtualBackgroundSource(),
          segproperty: const SegmentationProperty(),
        );
      }

      // 3. Color Enhancement
      if (effect.colorEnhance != null) {
        await eng.setColorEnhanceOptions(
          enabled: true,
          options: effect.colorEnhance!,
        );
      } else {
        await eng.setColorEnhanceOptions(
          enabled: false,
          options: const ColorEnhanceOptions(),
        );
      }

      // 4. Low-Light Enhancement
      if (effect.lowlightEnhance != null) {
        await eng.setLowlightEnhanceOptions(
          enabled: true,
          options: effect.lowlightEnhance!,
        );
      } else if (!_beautyTuning.lowlightBoost) {
        await eng.setLowlightEnhanceOptions(
          enabled: false,
          options: const LowlightEnhanceOptions(),
        );
      }
    } catch (e) {
      debugPrint('[CallScreen] Apply effect error: $e');
    }
  }

  /// Applies granular beauty sliders in real time to the hardware camera pipeline.
  Future<void> _applyGranularBeautyTuning(ZevBeautyTuning tuning) async {
    final eng = _engine;
    setState(() => _beautyTuning = tuning);
    if (eng == null) return;

    try {
      if (tuning.smoothness > 0 ||
          tuning.lightening > 0 ||
          tuning.redness > 0 ||
          tuning.sharpness > 0) {
        await eng.setBeautyEffectOptions(
          enabled: true,
          options: tuning.toBeautyOptions(),
        );
      } else {
        await eng.setBeautyEffectOptions(
          enabled: false,
          options: const BeautyOptions(),
        );
      }

      final bgSource = tuning.toVirtualBackgroundSource();
      if (bgSource != null) {
        await eng.enableVirtualBackground(
          enabled: true,
          backgroundSource: bgSource,
          segproperty: const SegmentationProperty(
            modelType: SegModelType.segModelAi,
          ),
        );
      } else {
        await eng.enableVirtualBackground(
          enabled: false,
          backgroundSource: const VirtualBackgroundSource(),
          segproperty: const SegmentationProperty(),
        );
      }

      if (tuning.lowlightBoost) {
        await eng.setLowlightEnhanceOptions(
          enabled: true,
          options: const LowlightEnhanceOptions(
            level: LowLightEnhanceLevel.lowLightEnhanceLevelHighQuality,
            mode: LowLightEnhanceMode.lowLightEnhanceManual,
          ),
        );
      } else {
        await eng.setLowlightEnhanceOptions(
          enabled: false,
          options: const LowlightEnhanceOptions(),
        );
      }
    } catch (e) {
      debugPrint('[CallScreen] granular tuning notice: $e');
    }
  }

  void _snapPipToNearestCorner(Size screenSize, EdgeInsets padding) {
    const pipW = 116.0;
    const pipH = 174.0;
    final minX = padding.left + 16.0;
    final maxX = screenSize.width - padding.right - pipW - 16.0;
    final minY = padding.top + 60.0;
    final maxY = screenSize.height - padding.bottom - pipH - 120.0;

    final targetX = (_pipOffset.dx - minX).abs() < (maxX - _pipOffset.dx).abs()
        ? minX
        : maxX;
    final targetY = (_pipOffset.dy - minY).abs() < (maxY - _pipOffset.dy).abs()
        ? minY
        : maxY;

    final target = Offset(targetX, targetY);
    _pipSnapAnim = Tween<Offset>(begin: _pipOffset, end: target).animate(
      CurvedAnimation(parent: _pipSnapCtrl, curve: Curves.easeOutBack),
    )..addListener(() {
        setState(() => _pipOffset = _pipSnapAnim!.value);
      });

    _pipSnapCtrl.forward(from: 0.0);
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ZevPipService.instance.isInPipMode,
      builder: (context, inPip, _) {
        if (inPip) {
          return _buildNativePipBody();
        }

        final size = MediaQuery.sizeOf(context);
        final isWide = size.width >= 720 || (kIsWeb && size.width >= 600);

        return PopScope(
          canPop: _phase == 'ended',
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _phase != 'ended') {
              if (_phase == 'accepted') {
                _minimizeCall();
              } else {
                unawaited(_hangupOrDecline());
              }
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF070B14),
            body: isWide ? _buildWidescreenWebLayout() : _buildMobileLayout(),
          ),
        );
      },
    );
  }

  /// Stripped-down native Picture-in-Picture window for Android OS floating PiP mode.
  Widget _buildNativePipBody() {
    final activeParticipants = _remoteParticipants.values
        .where((p) => p.videoController != null && p.videoEnabled)
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Primary Remote Feed or User Profile
          if (activeParticipants.isNotEmpty)
            Positioned.fill(
              child: AgoraVideoView(
                controller: activeParticipants.first.videoController!,
              ),
            )
          else
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: ZevColors.primaryBlue,
                      child: Text(
                        widget.peerUsername.isNotEmpty
                            ? widget.peerUsername[0].toUpperCase()
                            : 'Z',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.peerFullName.isNotEmpty
                          ? widget.peerFullName
                          : '@${widget.peerUsername}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 2. Mini self preview inset
          if (_isVideoActive && !_isCameraOff && _localVideoController != null)
            Positioned(
              right: 8,
              bottom: 8,
              width: 54,
              height: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.black,
                  child: AgoraVideoView(
                    controller: _localVideoController!,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Widescreen Desktop / Web Layout
  Widget _buildWidescreenWebLayout() {
    final showIncomingChoice = !widget.isOutgoing && _phase == 'ringing';
    if (showIncomingChoice) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 860),
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 48,
                spreadRadius: 8,
              ),
            ],
          ),
          child: _buildIncomingCallView(),
        ),
      );
    }

    final displayName = widget.peerFullName.isNotEmpty
        ? widget.peerFullName
        : '@${widget.peerUsername}';

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF070B14),
            Color(0xFF0F172A),
            Color(0xFF0A0F1D),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top HUD Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  // Back / Minimize Button
                  GestureDetector(
                    onTap: _minimizeCall,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isVideo
                              ? Icons.videocam_rounded
                              : Icons.phone_in_talk_rounded,
                          size: 16,
                          color: ZevColors.primaryBlue,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isVideo ? 'ZEV Video Call' : 'ZEV Voice Call',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.lock_rounded,
                          size: 12,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Encrypted',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Duration / Status
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _phase == 'accepted'
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _phase == 'accepted'
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      _phase == 'accepted'
                          ? _formatDuration(_elapsedSeconds)
                          : _statusLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Minimize / Multi-task Button
                  GestureDetector(
                    onTap: _minimizeCall,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Icon(
                        Icons.close_fullscreen_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Desktop Stage
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: _buildVideoGridOrProfile(displayName: displayName),
                    ),
                    if (_isVideoActive &&
                        !_isCameraOff &&
                        _localVideoController != null &&
                        _phase != 'ended')
                      Positioned(
                        right: 20,
                        bottom: 20,
                        child: _buildDesktopSelfPreview(),
                      ),
                  ],
                ),
              ),
            ),

            // AR Effects Tray if open
            if (_showEffectsTray) _buildArEffectsTray(),

            // Desktop Control Dock
            _buildControlDock(isWide: true),
          ],
        ),
      ),
    );
  }

  /// Floating self-preview tile for desktop & web wide screens (Google Meet / Zoom style)
  Widget _buildDesktopSelfPreview() {
    return Container(
      width: 180,
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AgoraVideoView(
              key: const ValueKey('desktop_self_preview'),
              controller: _localVideoController!,
            ),
            Positioned(
              left: 8,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'You',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mobile Portrait Layout with tap-to-hide controls & draggable self PIP
  Widget _buildMobileLayout() {
    final showIncomingChoice = !widget.isOutgoing && _phase == 'ringing';
    if (showIncomingChoice) {
      return _buildIncomingCallView();
    }

    final displayName = widget.peerFullName.isNotEmpty
        ? widget.peerFullName
        : '@${widget.peerUsername}';

    return GestureDetector(
      onTap: _toggleControlsVisibility,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Canvas or Camera-Off Ambient Profile
          _buildVideoGridOrProfile(displayName: displayName),

          // 2. Top HUD Bar (Fade with controls)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        // Minimize Call Button (Multitasking)
                        GestureDetector(
                          onTap: _minimizeCall,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Encrypted Call Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.isVideo
                                    ? Icons.videocam_rounded
                                    : Icons.lock_rounded,
                                size: 14,
                                color: ZevColors.primaryBlue,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.isVideo ? 'ZEV Video' : 'ZEV Voice',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),

                        // Duration Timer
                        if (_phase == 'accepted')
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  ZevColors.successGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: ZevColors.successGreen
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Text(
                              _formatDuration(_elapsedSeconds),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3. Draggable Self-View PIP (4-corner snapping)
          if (_isVideoActive &&
              _localVideoController != null &&
              _phase != 'ended')
            _buildDraggableSelfPip(context),

          // 4. Effects Tray Carousel (if toggled)
          if (_showEffectsTray && _controlsVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 110,
              child: _buildArEffectsTray(),
            ),

          // 5. Bottom Mobile Controls Dock
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: _buildControlDock(isWide: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds Video Stage: 1-to-1 Remote Video, Group Grid, or Camera-Off Ambient Profile.
  Widget _buildVideoGridOrProfile({required String displayName}) {
    final activeParticipants = _remoteParticipants.values
        .where((p) => p.videoController != null && p.videoEnabled)
        .toList();

    // 1. Group Call Grid (2 or more remote video feeds)
    if (activeParticipants.length >= 2) {
      return _buildGroupVideoGrid(activeParticipants);
    }

    // 2. Direct Call with Active Video
    if (activeParticipants.length == 1) {
      final remote = activeParticipants.first;
      final activeEffect = ZevEffectsCatalog.all.firstWhere(
        (e) => e.id == _selectedEffectId,
        orElse: () => ZevEffectsCatalog.none,
      );

      final screenSize = MediaQuery.sizeOf(context);
      final isWide = screenSize.width >= 720 || (kIsWeb && screenSize.width >= 600);

      Widget videoWidget = AgoraVideoView(
        key: ValueKey('remote_${remote.uid}'),
        controller: remote.videoController!,
      );

      if (activeEffect.matrixFilter != null) {
        videoWidget = ColorFiltered(
          colorFilter: activeEffect.matrixFilter!,
          child: videoWidget,
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          // 1. Ambient Blurred Backdrop for widescreen / web
          if (isWide && widget.peerAvatar.isNotEmpty)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 75, sigmaY: 75),
                child: Transform.scale(
                  scale: 1.4,
                  child: ZevCachedImage(
                    imageUrl: widget.peerAvatar,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),

          // 2. Dark Scrim over backdrop
          Positioned.fill(
            child: Container(
              color: isWide
                  ? const Color(0xFF070B14).withValues(alpha: 0.85)
                  : const Color(0xFF030712),
            ),
          ),

          // 3. Main Video Stage: Center 9:16 aspect ratio on desktop/laptop, full display on mobile
          Center(
            child: isWide
                ? Container(
                    constraints: const BoxConstraints(
                      maxWidth: 640,
                      maxHeight: 880,
                    ),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.65),
                          blurRadius: 36,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AspectRatio(
                            aspectRatio: 9 / 16,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                videoWidget,
                                if (activeEffect.snapchatLensType != null)
                                  ZevSnapchatLensOverlay(
                                    lensType: activeEffect.snapchatLensType!,
                                    isSmall: false,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      videoWidget,
                      if (activeEffect.snapchatLensType != null)
                        ZevSnapchatLensOverlay(
                          lensType: activeEffect.snapchatLensType!,
                          isSmall: false,
                        ),
                    ],
                  ),
          ),

          // Gradient Scrim for readable HUD & controls
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.70),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 3. Camera-Off Ambient Profile Display (WhatsApp / Instagram grade)
    return _buildCameraOffProfileView(displayName: displayName);
  }

  /// WhatsApp / Instagram Grade Camera-Off Profile Display
  Widget _buildCameraOffProfileView({required String displayName}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Ambient Blurred Avatar Backdrop
        if (widget.peerAvatar.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Transform.scale(
                scale: 1.35,
                child: ZevCachedImage(
                  imageUrl: widget.peerAvatar,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

        // 2. Multi-stop Dark Scrim
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xDC050914),
                  const Color(0xEA090E1F),
                  const Color(0xF803060E),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),

        // 3. Center Profile Card
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsating Avatar Ring
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) {
                  final glow = _phase == 'accepted'
                      ? 12.0 + (_pulseCtrl.value * 16.0)
                      : 8.0;
                  return Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (_phase == 'accepted'
                                ? const Color(0xFF10B981)
                                : const Color(0xFF3B82F6))
                            .withValues(alpha: 0.55),
                        width: 3.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_phase == 'accepted'
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF3B82F6))
                              .withValues(alpha: 0.35),
                          blurRadius: glow,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: ZevCachedImage.avatar(
                  imageUrl: widget.peerAvatar,
                  size: 120,
                ),
              ),
              const SizedBox(height: 20),

              // Name with verified badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  if (widget.isPeerVerified) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.verified_rounded,
                      size: 20,
                      color: Color(0xFF3B82F6),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Status Chip / Camera Off Indicator
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.isVideo
                          ? Icons.videocam_off_rounded
                          : Icons.phone_in_talk_rounded,
                      size: 15,
                      color: widget.isVideo
                          ? const Color(0xFFF87171)
                          : const Color(0xFF10B981),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isVideo
                          ? (_phase == 'accepted'
                              ? 'Camera is turned off'
                              : _statusLabel)
                          : (_phase == 'accepted'
                              ? 'HD Voice Connected'
                              : _statusLabel),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMsg!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Multi-participant Responsive Group Video Grid with Speaking Indicator
  Widget _buildGroupVideoGrid(List<_RemoteParticipantState> participants) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.85,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: participants.length,
          itemBuilder: (context, idx) {
            final p = participants[idx];
            final pName = (p.profile?['first_name'] != null &&
                    p.profile!['first_name'].toString().isNotEmpty)
                ? '${p.profile!['first_name']} ${p.profile!['last_name'] ?? ''}'
                    .trim()
                : 'User ${p.uid}';

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: p.isSpeaking
                      ? const Color(0xFF10B981)
                      : Colors.white.withValues(alpha: 0.16),
                  width: p.isSpeaking ? 2.5 : 1.2,
                ),
                boxShadow: p.isSpeaking
                    ? [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (p.videoController != null)
                      AgoraVideoView(
                        key: ValueKey('group_tile_${p.uid}'),
                        controller: p.videoController!,
                      )
                    else
                      Container(color: const Color(0xFF0F172A)),
                    // Participant Label Pill
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (p.isSpeaking) ...[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              pName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
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
      ),
    );
  }

  /// Draggable Self-View PIP with Smooth 4-Corner Snapping
  Widget _buildDraggableSelfPip(BuildContext context) {
    const pipW = 116.0;
    const pipH = 174.0;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);

    return Positioned(
      left: _pipOffset.dx,
      top: _pipOffset.dy,
      child: GestureDetector(
        onPanStart: (details) {
          _pipSnapCtrl.stop();
        },
        onPanUpdate: (details) {
          setState(() {
            _pipOffset += details.delta;
          });
        },
        onPanEnd: (details) {
          _snapPipToNearestCorner(size, pad);
        },
        onTap: _switchCamera,
        child: Container(
          width: pipW,
          height: pipH,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!_isCameraOff && _localVideoController != null) ...[
                  AgoraVideoView(
                    key: const ValueKey('local_self_preview'),
                    controller: _localVideoController!,
                  ),
                  Builder(
                    builder: (context) {
                      final myEffect = ZevEffectsCatalog.findById(_selectedEffectId);
                      if (myEffect.snapchatLensType != null) {
                        return ZevSnapchatLensOverlay(
                          lensType: myEffect.snapchatLensType!,
                          isSmall: true,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ]
                else
                  // Camera Off inside PIP
                  Container(
                    color: const Color(0xFF0F172A),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.videocam_off_rounded,
                            size: 24,
                            color: Colors.white60,
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Cam Off',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Top Quick Flip Icon Pill
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: _switchCamera,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cameraswitch_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// AR Face & Camera Effects Tray Carousel with Two-Tier Architecture (Beauty vs Effects)
  Widget _buildArEffectsTray() {
    final currentCatEffects =
        ZevEffectsCatalog.byCategory(_selectedEffectCategory);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. BEAUTY & LIGHTING STUDIO HEADER
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFF60A5FA)),
                        SizedBox(width: 6),
                        Text(
                          'SNAPCHAT LENSES & BEAUTY STUDIO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Granular Sliders Tuning Button
                  GestureDetector(
                    onTap: _openBeautyTuningSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFF3B82F6),
                          width: 1.2,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, size: 13, color: Color(0xFF60A5FA)),
                          SizedBox(width: 4),
                          Text(
                            'Tune',
                            style: TextStyle(
                              color: Color(0xFF60A5FA),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Close Tray Button
                  GestureDetector(
                    onTap: () => setState(() => _showEffectsTray = false),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 2. CATEGORIES BAR (TRENDING, FUNNY & AR, ANIMALS, LIGHTING, SKIN, COLOR, BLUR)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  children: [
                    _buildCategoryPill(
                      'TRENDING',
                      ZevCallEffectCategory.snapchatTrending,
                      Icons.local_fire_department_rounded,
                    ),
                    const SizedBox(width: 6),
                    _buildCategoryPill(
                      'FUNNY & AR',
                      ZevCallEffectCategory.snapchatFunny,
                      Icons.sentiment_very_satisfied_rounded,
                    ),
                    const SizedBox(width: 6),
                    _buildCategoryPill(
                      'ANIMALS',
                      ZevCallEffectCategory.snapchatAnimals,
                      Icons.pets_rounded,
                    ),
                    const SizedBox(width: 6),
                    _buildCategoryPill(
                      'LIGHTING',
                      ZevCallEffectCategory.lighting,
                      Icons.wb_sunny_rounded,
                    ),
                    const SizedBox(width: 6),
                    _buildCategoryPill(
                      'SKIN',
                      ZevCallEffectCategory.beauty,
                      Icons.face_retouching_natural_rounded,
                    ),
                    const SizedBox(width: 6),
                    _buildCategoryPill(
                      'COLOR',
                      ZevCallEffectCategory.color,
                      Icons.palette_rounded,
                    ),
                    const SizedBox(width: 6),
                    _buildCategoryPill(
                      'BLUR',
                      ZevCallEffectCategory.background,
                      Icons.blur_on_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 3. Effects Carousel
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: currentCatEffects.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, idx) {
                    final item = currentCatEffects[idx];
                    final isSelected = item.id == _selectedEffectId;
                    return GestureDetector(
                      onTap: () => _applyEffect(item),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: isSelected
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFF3B82F6),
                                        Color(0xFF8B5CF6),
                                      ],
                                    )
                                  : null,
                              color: isSelected
                                  ? null
                                  : Colors.white.withValues(alpha: 0.12),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.25),
                                width: isSelected ? 2.5 : 1.2,
                              ),
                            ),
                            child: item.emoji != null
                                ? Center(
                                    child: Text(
                                      item.emoji!,
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                  )
                                : Icon(
                                    item.icon,
                                    size: 22,
                                    color: Colors.white,
                                  ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.name,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                              color: isSelected ? Colors.white : Colors.white70,
                            ),
                          ),
                        ],
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
  }



  Widget _buildCategoryPill(
    String label,
    ZevCallEffectCategory cat,
    IconData icon,
  ) {
    final isSelected = _selectedEffectCategory == cat;
    return GestureDetector(
      onTap: () => setState(() => _selectedEffectCategory = cat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: isSelected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: isSelected ? Colors.white : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Granular Beauty Sliders Sheet (Smoothness, Lightening, Redness, Sharpness, Blur)
  void _openBeautyTuningSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.96),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag Handle
                        Container(
                          width: 38,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(
                              Icons.tune_rounded,
                              color: Color(0xFF60A5FA),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Beauty Studio & Camera Tuning',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Spacer(),
                            // Reset All Button
                            GestureDetector(
                              onTap: () {
                                final reset = const ZevBeautyTuning();
                                setSheetState(() => _beautyTuning = reset);
                                _applyGranularBeautyTuning(reset);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Reset',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // 1. Skin Smoothing Slider
                        _buildTuningSlider(
                          label: 'Skin Smoothing',
                          icon: Icons.face_rounded,
                          value: _beautyTuning.smoothness,
                          onChanged: (v) {
                            final next = _beautyTuning.copyWith(smoothness: v);
                            setSheetState(() => _beautyTuning = next);
                            _applyGranularBeautyTuning(next);
                          },
                        ),

                        // 2. Brightness / Lightening Slider
                        _buildTuningSlider(
                          label: 'Face Brightening',
                          icon: Icons.brightness_high_rounded,
                          value: _beautyTuning.lightening,
                          onChanged: (v) {
                            final next = _beautyTuning.copyWith(lightening: v);
                            setSheetState(() => _beautyTuning = next);
                            _applyGranularBeautyTuning(next);
                          },
                        ),

                        // 3. Skin Tone / Redness Slider
                        _buildTuningSlider(
                          label: 'Rosy Tone',
                          icon: Icons.palette_rounded,
                          value: _beautyTuning.redness,
                          onChanged: (v) {
                            final next = _beautyTuning.copyWith(redness: v);
                            setSheetState(() => _beautyTuning = next);
                            _applyGranularBeautyTuning(next);
                          },
                        ),

                        // 4. Sharpness Slider
                        _buildTuningSlider(
                          label: 'Sharpness',
                          icon: Icons.details_rounded,
                          value: _beautyTuning.sharpness,
                          onChanged: (v) {
                            final next = _beautyTuning.copyWith(sharpness: v);
                            setSheetState(() => _beautyTuning = next);
                            _applyGranularBeautyTuning(next);
                          },
                        ),

                        const SizedBox(height: 8),

                        // 5. Background Blur Intensity Chips (Smooth Scrollable)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.blur_on_rounded,
                                  size: 16,
                                  color: Color(0xFF60A5FA),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Background Blur',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  _buildBlurChip('Off', 0, setSheetState),
                                  const SizedBox(width: 8),
                                  _buildBlurChip('Low', 1, setSheetState),
                                  const SizedBox(width: 8),
                                  _buildBlurChip('Medium', 2, setSheetState),
                                  const SizedBox(width: 8),
                                  _buildBlurChip('High', 3, setSheetState),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBlurChip(
    String label,
    int degree,
    void Function(void Function()) setSheetState,
  ) {
    final isSelected = _beautyTuning.blurDegree == degree;
    return GestureDetector(
      onTap: () {
        final next = _beautyTuning.copyWith(blurDegree: degree);
        setSheetState(() => _beautyTuning = next);
        _applyGranularBeautyTuning(next);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF3B82F6)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildTuningSlider({
    required String label,
    required IconData icon,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF60A5FA)),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: const Color(0xFF3B82F6),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                thumbColor: Colors.white,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
              ),
              child: Slider(
                value: value,
                min: 0.0,
                max: 1.0,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${(value * 100).toInt()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom Control Dock (Glassmorphism, 100% Vector Icons)
  Widget _buildControlDock({required bool isWide}) {
    final showIncomingChoice = !widget.isOutgoing && _phase == 'ringing';
    if (showIncomingChoice) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 34),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionCircle(
              icon: Icons.call_end_rounded,
              label: 'Decline',
              bgColor: ZevColors.errorRed,
              size: 68,
              onTap: _isActionInFlight ? null : _hangupOrDecline,
            ),
            _buildActionCircle(
              icon: _isVideoActive
                  ? Icons.videocam_rounded
                  : Icons.call_rounded,
              label: 'Accept',
              bgColor: ZevColors.successGreen,
              size: 68,
              onTap: _isActionInFlight ? null : _acceptIncomingCall,
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          margin: EdgeInsets.fromLTRB(
            isWide ? 24 : 16,
            0,
            isWide ? 24 : 16,
            isWide ? 18 : 24,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute Button
              _buildActionCircle(
                icon: _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: _isMicMuted ? 'Muted' : 'Mute',
                bgColor: _isMicMuted
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.14),
                iconColor:
                    _isMicMuted ? const Color(0xFF0F172A) : Colors.white,
                onTap: _phase == 'ended' ? null : _toggleMute,
              ),

              // Camera Toggle Button
              _buildActionCircle(
                icon: (_isVideoActive && !_isCameraOff)
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: (_isVideoActive && !_isCameraOff) ? 'Camera' : 'Cam Off',
                bgColor: (_isVideoActive && !_isCameraOff)
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.white,
                iconColor: (_isVideoActive && !_isCameraOff)
                    ? Colors.white
                    : const Color(0xFF0F172A),
                onTap: _phase == 'ended' ? null : _toggleCamera,
              ),

              // Filters & Beauty Button
              _buildActionCircle(
                icon: Icons.auto_awesome_rounded,
                label: _selectedEffectId != 'none' || _beautyTuning.isActive
                    ? 'Effect On'
                    : 'Filters',
                bgColor: _showEffectsTray ||
                        _selectedEffectId != 'none' ||
                        _beautyTuning.isActive
                    ? const Color(0xFF3B82F6)
                    : Colors.white.withValues(alpha: 0.14),
                iconColor: Colors.white,
                onTap: _phase == 'ended'
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        setState(() => _showEffectsTray = !_showEffectsTray);
                      },
              ),

              // Add Participant / Group Call Button
              _buildActionCircle(
                icon: Icons.person_add_alt_1_rounded,
                label: 'Invite',
                bgColor: Colors.white.withValues(alpha: 0.14),
                onTap: _phase == 'accepted' ? _openAddParticipantSheet : null,
              ),

              // Tools Sheet Button
              _buildActionCircle(
                icon: Icons.more_horiz_rounded,
                label: 'Tools',
                bgColor: Colors.white.withValues(alpha: 0.14),
                onTap: _phase == 'ended' ? null : _openMobileToolsSheet,
              ),

              // Minimize Window Button (Widescreen)
              if (isWide)
                _buildActionCircle(
                  icon: Icons.picture_in_picture_alt_rounded,
                  label: 'Minimize',
                  bgColor: Colors.white.withValues(alpha: 0.14),
                  onTap: _phase == 'accepted' ? _minimizeCall : null,
                ),

              // End Call Button
              _buildActionCircle(
                icon: Icons.call_end_rounded,
                label: 'End',
                bgColor: ZevColors.errorRed,
                onTap: _phase == 'ended' ? null : _hangupOrDecline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Add Participant Sheet to convert active call to group call
  void _openAddParticipantSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.65,
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.96),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Container(
                      width: 38,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Icon(
                          Icons.group_add_rounded,
                          color: Color(0xFF60A5FA),
                          size: 22,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Add Friends to Call',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _fetchAddableFriends(),
                        builder: (context, snap) {
                          if (snap.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final list = snap.data ?? [];
                          if (list.isEmpty) {
                            return const Center(
                              child: Text(
                                'No friends available to add right now.',
                                style: TextStyle(color: Colors.white60),
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, _) =>
                                const Divider(color: Colors.white12),
                            itemBuilder: (context, idx) {
                              final f = list[idx];
                              final fName =
                                  '${f['first_name'] ?? ''} ${f['last_name'] ?? ''}'
                                      .trim();
                              final fUname =
                                  f['username']?.toString() ?? 'User';
                              final fAvatar =
                                  f['avatar_url']?.toString() ?? '';
                              final fId = f['id']?.toString() ?? '';

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: ZevCachedImage.avatar(
                                  imageUrl: fAvatar,
                                  size: 42,
                                ),
                                title: Text(
                                  fName.isNotEmpty ? fName : '@$fUname',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '@$fUname',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () async {
                                    final scaffold =
                                        ScaffoldMessenger.of(context);
                                    Navigator.pop(ctx);
                                    if (_session != null) {
                                      await ZevRtcService.instance
                                          .inviteParticipant(
                                        callId: _session!.id,
                                        userId: fId,
                                      );
                                      if (!mounted) return;
                                      scaffold.showSnackBar(
                                        SnackBar(
                                          content:
                                              Text('Invited $fName to call'),
                                          behavior:
                                              SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF3B82F6),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Invite',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAddableFriends() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return [];
    try {
      final res = await _supabase
          .from('profiles')
          .select('id, username, first_name, last_name, avatar_url, is_verified')
          .neq('id', myId)
          .limit(20);
      return (res as List).map((m) => Map<String, dynamic>.from(m)).toList();
    } catch (_) {
      return [];
    }
  }

  void _openMobileToolsSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Call Controls & Tools',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Flip Camera
                    if (_isVideoActive && !_isCameraOff)
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.cameraswitch_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Flip Camera',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: const Text(
                          'Switch front / back camera',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _switchCamera();
                        },
                      ),
                    // Speakerphone
                    if (!kIsWeb)
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _isSpeakerOn
                                ? ZevColors.primaryBlue
                                : Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isSpeakerOn
                                ? Icons.volume_up_rounded
                                : Icons.hearing_rounded,
                            color: _isSpeakerOn
                                ? ZevColors.deepNavy
                                : Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          _isSpeakerOn ? 'Speakerphone' : 'Earpiece',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _toggleSpeaker();
                        },
                      ),
                    // Screen Share Coming Soon
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.screen_share_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        'Share Screen',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: const Text(
                        'Coming soon in next release',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _toggleScreenShare();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleScreenShare() async {
    HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.screen_share_rounded,
                color: Color(0xFF60A5FA), size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Screen Sharing is coming soon in the next update!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Flagship Incoming Call Screen (Ambient blurred backdrop, acoustic pulse rings, verified card & glowing controls)
  Widget _buildIncomingCallView() {
    final displayName = widget.peerFullName.isNotEmpty
        ? widget.peerFullName
        : '@${widget.peerUsername}';

    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.peerAvatar.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 55, sigmaY: 55),
              child: Transform.scale(
                scale: 1.35,
                child: ZevCachedImage(
                  imageUrl: widget.peerAvatar,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xDC050914),
                  const Color(0xEA090E1F),
                  const Color(0xF803060E),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield_rounded,
                        size: 15,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        'End-to-End Encrypted',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white54,
                        ),
                      ),
                      Text(
                        widget.isVideo ? '1080p HD Video' : 'HD Voice',
                        style: const TextStyle(
                          color: Color(0xFF60A5FA),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Animated Radial Acoustic Wave Rings & Avatar Card
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) {
                  final t = _pulseCtrl.value;
                  return SizedBox(
                    width: 270,
                    height: 270,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.scale(
                          scale: 1.0 + (t * 0.45),
                          child: Container(
                            width: 210,
                            height: 210,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF2563EB).withValues(
                                  alpha: (1.0 - t) * 0.25,
                                ),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 136,
                          height: 136,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF3B82F6),
                                Color(0xFF06B6D4),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withValues(
                                  alpha: 0.50 + (t * 0.25),
                                ),
                                blurRadius: 28 + (t * 12),
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: ZevCachedImage.avatar(
                              imageUrl: widget.peerAvatar,
                              size: 124,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 18),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                    if (widget.isPeerVerified) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.verified_rounded,
                        size: 22,
                        color: Color(0xFF00B2FF),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 6),

              if (widget.peerUsername.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    '@${widget.peerUsername}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ),

              const SizedBox(height: 14),

              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: (widget.isVideo
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF10B981))
                      .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: (widget.isVideo
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF10B981))
                        .withValues(alpha: 0.40),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isVideo
                          ? 'Incoming Video Call...'
                          : 'Incoming Voice Call...',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE2E8F0),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Quick Reply Option
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isActionInFlight
                        ? null
                        : _showQuickDeclineMessageSheet,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Reply with Message',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Accept & Decline Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 38),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Decline
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.heavyImpact();
                            if (!_isActionInFlight) _hangupOrDecline();
                          },
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFEF4444),
                                  Color(0xFFB91C1C),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFEF4444)
                                      .withValues(alpha: 0.45),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.call_end_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Decline',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),

                    // Accept
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.heavyImpact();
                            if (!_isActionInFlight) _acceptIncomingCall();
                          },
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF10B981),
                                  Color(0xFF047857),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.45),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                widget.isVideo
                                    ? Icons.videocam_rounded
                                    : Icons.call_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Accept',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showQuickDeclineMessageSheet() async {
    final quickMessages = [
      "Can't talk right now. What's up?",
      "I'll call you right back.",
      "I'm in a meeting, please message me.",
      "On my way, see you soon.",
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Decline with Message',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              ...quickMessages.map(
                (msg) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    msg,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.send_rounded,
                    size: 18,
                    color: Color(0xFF3B82F6),
                  ),
                  onTap: () => Navigator.pop(ctx, msg),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null && selected.isNotEmpty && mounted) {
      if (widget.peerId.isNotEmpty) {
        final myId = _supabase.auth.currentUser?.id;
        if (myId != null && myId.isNotEmpty) {
          unawaited(
            _supabase.from('direct_messages').insert({
              'sender_id': myId,
              'receiver_id': widget.peerId,
              if (widget.conversationId != null &&
                  widget.conversationId!.isNotEmpty)
                'conversation_id': widget.conversationId,
              'message_text': selected,
              'message_type': 'text',
              'created_at': DateTime.now().toIso8601String(),
            }),
          );
        }
      }
      await _hangupOrDecline();
    }
  }

  Widget _buildActionCircle({
    required IconData icon,
    required String label,
    required Color bgColor,
    Color iconColor = Colors.white,
    double size = 52,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.50 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: size * 0.46),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
