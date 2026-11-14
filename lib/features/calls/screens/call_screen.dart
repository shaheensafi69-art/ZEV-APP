import 'dart:async';
import 'dart:ui' as ui;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/zev_call_audio_service.dart';
import '../../../core/services/zev_rtc_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../main.dart';

/// Live Face / Camera AR Effect Model for ZEV Calls.
class ZevCallEffect {
  final String id;
  final String name;
  final String iconEmoji;
  final String category; // 'effects', 'lighting', 'backgrounds'
  final BeautyOptions? agoraBeauty;
  final ColorFilter? colorFilter;

  const ZevCallEffect({
    required this.id,
    required this.name,
    required this.iconEmoji,
    required this.category,
    this.agoraBeauty,
    this.colorFilter,
  });
}

/// Production Agora RTC Voice & Video Call Screen for ZEV.
/// Supports 1-to-1 outgoing & incoming calls, real-time Supabase signaling,
/// Android/iOS/Web WebRTC (iris-web) transport, and responsive video PIP + voice UI.
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

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  ZevCallSession? _session;
  RtcEngine? _engine;
  RtcEngineEventHandler? _engineHandler;
  VideoViewController? _localVideoController;
  VideoViewController? _remoteVideoController;
  int? _remoteUid;
  bool _remoteVideoEnabled = true;

  RealtimeChannel? _callChannel;
  Timer? _ringTimeoutTimer;
  Timer? _durationTimer;
  Timer? _statusPollTimer;
  Timer? _autoCloseTimer;

  late final AnimationController _pulseCtrl;

  String _phase = 'connecting'; // connecting | ringing | accepted | ended
  String _statusLabel = 'Connecting...';
  String? _errorMsg;
  int _elapsedSeconds = 0;

  bool _isMicMuted = false;
  bool _isSpeakerOn = true;
  bool _isCameraOff = false;
  bool _isVideoActive = false;
  bool _isScreenSharing = false;
  bool _isActionInFlight = false;
  bool _engineJoined = false;
  bool _isClosing = false;

  // AR Effects & Multi-platform stage state
  bool _showEffectsTray = false;
  String _selectedEffectId = 'none';
  String _selectedEffectCategory = 'effects';
  String _webAspectMode = 'phone'; // 'phone' (9:16 portrait), 'wide' (16:9), 'fit'

  static const List<ZevCallEffect> _kCallEffects = [
    ZevCallEffect(
      id: 'none',
      name: 'None',
      iconEmoji: '🚫',
      category: 'effects',
    ),
    ZevCallEffect(
      id: 'glow',
      name: 'Glow',
      iconEmoji: '✨',
      category: 'effects',
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.70,
        smoothnessLevel: 0.85,
        rednessLevel: 0.30,
        sharpnessLevel: 0.40,
      ),
    ),
    ZevCallEffect(
      id: 'warm',
      name: 'Sunset',
      iconEmoji: '🌅',
      category: 'lighting',
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastHigh,
        lighteningLevel: 0.60,
        smoothnessLevel: 0.50,
        rednessLevel: 0.60,
      ),
      colorFilter: ColorFilter.matrix(<double>[
        1.15, 0, 0, 0, 15,
        0, 1.02, 0, 0, 5,
        0, 0, 0.85, 0, -10,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'studio',
      name: 'Studio',
      iconEmoji: '💡',
      category: 'lighting',
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.90,
        smoothnessLevel: 0.65,
        sharpnessLevel: 0.50,
      ),
    ),
    ZevCallEffect(
      id: 'cyber',
      name: 'Cyber',
      iconEmoji: '⚡',
      category: 'effects',
      colorFilter: ColorFilter.matrix(<double>[
        1.2, 0, 0.2, 0, 10,
        0, 1.1, 0, 0, 0,
        0.2, 0, 1.3, 0, 20,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'noir',
      name: 'Noir',
      iconEmoji: '🎬',
      category: 'effects',
      colorFilter: ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'blush',
      name: 'Blush',
      iconEmoji: '🌸',
      category: 'effects',
      agoraBeauty: BeautyOptions(
        lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
        lighteningLevel: 0.60,
        smoothnessLevel: 0.80,
        rednessLevel: 0.50,
      ),
      colorFilter: ColorFilter.matrix(<double>[
        1.1, 0, 0, 0, 15,
        0, 0.98, 0, 0, 5,
        0, 0, 1.0, 0, 8,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'vintage',
      name: 'Vintage',
      iconEmoji: '🎞️',
      category: 'lighting',
      colorFilter: ColorFilter.matrix(<double>[
        0.393, 0.769, 0.189, 0, 0,
        0.349, 0.686, 0.168, 0, 0,
        0.272, 0.534, 0.131, 0, 0,
        0, 0, 0, 1, 0,
      ]),
    ),
    ZevCallEffect(
      id: 'ocean',
      name: 'Ocean',
      iconEmoji: '🌊',
      category: 'backgrounds',
      colorFilter: ColorFilter.matrix(<double>[
        0.85, 0, 0, 0, -10,
        0, 1.1, 0, 0, 10,
        0, 0.1, 1.2, 0, 25,
        0, 0, 0, 1, 0,
      ]),
    ),
  ];

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

    if (_session != null) {
      ZevRtcService.instance.setActiveCall(_session!.id);
    }

    _bootstrapCall();
  }

  @override
  void dispose() {
    _ringTimeoutTimer?.cancel();
    _durationTimer?.cancel();
    _statusPollTimer?.cancel();
    _autoCloseTimer?.cancel();
    _pulseCtrl.dispose();

    final ch = _callChannel;
    _callChannel = null;
    if (ch != null) {
      unawaited(ch.unsubscribe());
    }

    if (_session != null) {
      ZevRtcService.instance.clearActiveCall(_session!.id);
    }

    unawaited(ZevCallAudioService.instance.stopAll());
    unawaited(_teardownEngine());
    super.dispose();
  }

  Future<void> _teardownEngine() async {
    _localVideoController?.dispose();
    _localVideoController = null;
    _remoteVideoController?.dispose();
    _remoteVideoController = null;

    final eng = _engine;
    final handler = _engineHandler;
    _engine = null;
    _engineHandler = null;
    if (eng != null) {
      if (_isScreenSharing) {
        try {
          await eng.stopScreenCapture();
        } catch (_) {}
      }
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

  Future<bool> _ensurePermissions() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return true;
    }

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      return false;
    }
    if (widget.isVideo || _isVideoActive) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        return false;
      }
    }
    return true;
  }

  Future<void> _bootstrapCall() async {
    try {
      if (widget.isOutgoing) {
        setState(() {
          _phase = 'connecting';
          _statusLabel = 'Starting ${widget.isVideo ? 'video' : 'voice'} call...';
        });

        final permsOk = await _ensurePermissions();
        if (!permsOk) {
          _finishLocally('Microphone${widget.isVideo ? ' & Camera' : ''} permission required.');
          return;
        }

        final myId = _supabase.auth.currentUser?.id;
        String myDisplayName = 'A ZEV user';
        if (myId != null) {
          final prof = await ZevRtcService.instance.fetchProfileSummary(myId);
          final full = '${prof['first_name'] ?? ''} ${prof['last_name'] ?? ''}'.trim();
          final uname = (prof['username'] ?? '').toString().trim();
          if (full.isNotEmpty) {
            myDisplayName = full;
          } else if (uname.isNotEmpty) {
            myDisplayName = '@$uname';
          }
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
          _statusLabel = session.isVideo ? 'Incoming Video Call' : 'Incoming Voice Call';
        });
        if (!session.isAccepted) {
          unawaited(ZevCallAudioService.instance.startIncomingRingtone());
        }
        _subscribeCallSession(session.id);
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
      setState(() => _elapsedSeconds += 1);
    });
  }

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

    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(
        appId: resolvedAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
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
          _remoteUid = remoteUid;
          _remoteVideoEnabled = true;
          if (_phase != 'accepted') {
            _phase = 'accepted';
            _statusLabel = 'Connected';
            _ringTimeoutTimer?.cancel();
            _startDurationTimer();
            unawaited(ZevCallAudioService.instance.playCallConnectedTone());
          }
          if (_isVideoActive || widget.isVideo) {
            _remoteVideoController?.dispose();
            _remoteVideoController = VideoViewController.remote(
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
        if (_remoteUid == remoteUid) {
          setState(() {
            _remoteUid = null;
            _remoteVideoController?.dispose();
            _remoteVideoController = null;
          });
          // Peer left channel -> close cleanly if call ended
          if (_phase == 'accepted') {
            _finishLocally('Call Ended');
          }
        }
      },
      onUserMuteVideo: (RtcConnection connection, int remoteUid, bool muted) {
        if (!mounted) return;
        if (_remoteUid == remoteUid) {
          setState(() => _remoteVideoEnabled = !muted);
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
            _remoteUid = remoteUid;
            _remoteVideoEnabled = true;
            _isVideoActive = true;
            _remoteVideoController?.dispose();
            _remoteVideoController = VideoViewController.remote(
              rtcEngine: engine,
              canvas: VideoCanvas(
                uid: remoteUid,
                renderMode: RenderModeType.renderModeFit,
              ),
              connection: connection,
            );
          });
        } else if (state == RemoteVideoState.remoteVideoStateStopped) {
          setState(() => _remoteVideoEnabled = false);
        }
      },
    );

    engine.registerEventHandler(handler);
    _engine = engine;
    _engineHandler = handler;

    await engine.enableAudio();
    try {
      await engine.setEnableSpeakerphone(_isSpeakerOn);
    } catch (_) {}

    if (_isVideoActive) {
      await engine.enableVideo();
      try {
        await engine.setVideoEncoderConfiguration(
          const VideoEncoderConfiguration(
            dimensions: VideoDimensions(width: 720, height: 1280),
            frameRate: 24,
            bitrate: 1200,
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
              renderMode: RenderModeType.renderModeFit,
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
            _errorMsg = 'Allow microphone${widget.isVideo ? ' & camera' : ''} to answer.';
          });
        }
        return;
      }

      final updated = await ZevRtcService.instance.respondCall(
        callId: session.id,
        action: 'accept',
      );
      if (!mounted) return;
      _applySessionUpdate(updated);
      setState(() => _isActionInFlight = false);
      await _startAgoraEngine(updated.id);
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

    _finishLocally(_phase == 'accepted' ? 'Call Ended' : (widget.isOutgoing ? 'Cancelled' : 'Declined'));
  }

  void _finishLocally(String label) {
    if (_isClosing) return;
    _isClosing = true;
    _ringTimeoutTimer?.cancel();
    _durationTimer?.cancel();
    _statusPollTimer?.cancel();

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
      // Dynamic upgrade from voice call to video call!
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
        try {
          await eng.setVideoEncoderConfiguration(
            const VideoEncoderConfiguration(
              dimensions: VideoDimensions(width: 720, height: 1280),
              frameRate: 24,
              bitrate: 1200,
            ),
          );
        } catch (_) {}

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
                renderMode: RenderModeType.renderModeFit,
              ),
            );
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera turned on'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Color(0xFF0F172A),
            ),
          );
        }

        if (_session != null) {
          unawaited(
            _supabase
                .from('call_sessions')
                .update({'call_type': 'video'})
                .eq('id', _session!.id)
                .catchError((_) => {}),
          );
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
          ChannelMediaOptions(
            publishCameraTrack: !nextOff,
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                nextOff
                    ? 'Camera turned off'
                    : 'Camera turned on',
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF0F172A),
            ),
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _switchCamera() async {
    if (!_isVideoActive || _isCameraOff) return;
    HapticFeedback.selectionClick();
    try {
      await _engine?.switchCamera();
    } catch (_) {}
  }

  Future<void> _applyEffect(ZevCallEffect effect) async {
    final eng = _engine;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedEffectId = effect.id;
    });

    if (eng != null) {
      try {
        if (effect.agoraBeauty != null) {
          await eng.setBeautyEffectOptions(
            enabled: true,
            options: effect.agoraBeauty!,
          );
        } else {
          await eng.setBeautyEffectOptions(
            enabled: false,
            options: const BeautyOptions(),
          );
        }
      } catch (e) {
        debugPrint('[CallScreen] Apply effect error: $e');
      }
    }
  }

  Future<void> _toggleBeautyFilter() async {
    HapticFeedback.lightImpact();
    setState(() => _showEffectsTray = !_showEffectsTray);
  }

  Future<void> _toggleScreenShare() async {
    final eng = _engine;
    if (eng == null || _phase != 'accepted') return;
    HapticFeedback.mediumImpact();

    try {
      if (!_isScreenSharing) {
        // Attempt screen capture
        if (kIsWeb) {
          try {
            await eng.startScreenCapture(
              const ScreenCaptureParameters2(
                captureAudio: false,
                captureVideo: true,
              ),
            );
          } catch (_) {
            await eng.startScreenCapture(
              const ScreenCaptureParameters2(
                captureAudio: true,
                captureVideo: true,
              ),
            );
          }
          await eng.updateChannelMediaOptions(
            const ChannelMediaOptions(
              publishScreenTrack: true,
              publishScreenCaptureVideo: true,
              publishCameraTrack: false,
            ),
          );
        } else {
          try {
            await eng.startScreenCapture(
              const ScreenCaptureParameters2(
                captureAudio: true,
                captureVideo: true,
              ),
            );
          } catch (_) {
            await eng.startScreenCapture(
              const ScreenCaptureParameters2(
                captureAudio: false,
                captureVideo: true,
              ),
            );
          }
          await eng.updateChannelMediaOptions(
            const ChannelMediaOptions(
              publishScreenCaptureVideo: true,
              publishScreenCaptureAudio: true,
              publishCameraTrack: false,
            ),
          );
        }

        if (mounted) {
          setState(() => _isScreenSharing = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Screen sharing started'),
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Color(0xFF0F172A),
            ),
          );
        }
      } else {
        try {
          await eng.stopScreenCapture();
        } catch (_) {}

        if (kIsWeb) {
          await eng.updateChannelMediaOptions(
            ChannelMediaOptions(
              publishScreenTrack: false,
              publishScreenCaptureVideo: false,
              publishCameraTrack: _isVideoActive && !_isCameraOff,
            ),
          );
        } else {
          await eng.updateChannelMediaOptions(
            ChannelMediaOptions(
              publishScreenCaptureVideo: false,
              publishScreenCaptureAudio: false,
              publishCameraTrack: _isVideoActive && !_isCameraOff,
            ),
          );
        }

        if (mounted) {
          setState(() => _isScreenSharing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Screen sharing stopped'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Color(0xFF0F172A),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[CallScreen] Screen share error: $e');
      if (mounted) {
        setState(() => _isScreenSharing = false);
        final isCancelled = e.toString().contains('NotAllowedError') ||
            e.toString().contains('Permission denied') ||
            e.toString().contains('cancelled') ||
            e.toString().contains('canceled');
        if (!isCancelled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Screen share notice: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFFDC2626),
            ),
          );
        }
      }
    }
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 720 || (kIsWeb && size.width >= 600);

    return PopScope(
      canPop: _phase == 'ended',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase != 'ended') {
          unawaited(_hangupOrDecline());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070B14),
        body: isWide ? _buildWidescreenWebLayout() : _buildMobileLayout(),
      ),
    );
  }

  /// Widescreen Desktop / Web Layout (Google Meet / Zoom grade experience)
  Widget _buildWidescreenWebLayout() {
    final displayName = widget.peerFullName.isNotEmpty
        ? widget.peerFullName
        : '@${widget.peerUsername}';
    final showIncomingChoice = !widget.isOutgoing && _phase == 'ringing';
    final hasRemoteVideo =
        _isVideoActive && _remoteVideoController != null && _remoteVideoEnabled;

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
            // Top Desktop HUD Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  // App / Encryption Badge
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
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF64748B),
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

                  // Call status & Duration Timer
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_phase == 'accepted') ...[
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
                            _formatDuration(_elapsedSeconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ] else ...[
                          Text(
                            _statusLabel,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Peer Mini Profile Pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ZevCachedImage.avatar(
                          imageUrl: widget.peerAvatar,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (widget.isPeerVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: ZevColors.primaryBlue,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Main Desktop Stage Area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 1380),
                    child: MediaQuery.sizeOf(context).width >= 960
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Left: Centered Presentation Canvas
                              Expanded(
                                child: _buildWebMainStage(
                                  hasRemoteVideo: hasRemoteVideo,
                                  displayName: displayName,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Right: Google Meet Participant Column
                              SizedBox(
                                width: 280,
                                child: _buildWebSideColumn(
                                  displayName: displayName,
                                  hasRemoteVideo: hasRemoteVideo,
                                ),
                              ),
                            ],
                          )
                        : _buildWebMainStage(
                            hasRemoteVideo: hasRemoteVideo,
                            displayName: displayName,
                          ),
                  ),
                ),
              ),
            ),

            // Live AR Effects Tray if toggled
            if (_showEffectsTray) _buildArEffectsTray(),

            // Bottom Widescreen Floating Control Dock
            if (showIncomingChoice)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildActionCircle(
                      icon: Icons.call_end_rounded,
                      label: 'Decline',
                      bgColor: ZevColors.errorRed,
                      size: 64,
                      onTap: _isActionInFlight ? null : _hangupOrDecline,
                    ),
                    const SizedBox(width: 32),
                    _buildActionCircle(
                      icon: _isVideoActive
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      label: 'Accept',
                      bgColor: ZevColors.successGreen,
                      size: 64,
                      onTap: _isActionInFlight ? null : _acceptIncomingCall,
                    ),
                  ],
                ),
              )
            else
              Container(
                margin: const EdgeInsets.symmetric(vertical: 18),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildActionCircle(
                      icon: _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      label: _isMicMuted ? 'Muted' : 'Mute',
                      bgColor: _isMicMuted
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.14),
                      iconColor: _isMicMuted
                          ? const Color(0xFF0F172A)
                          : Colors.white,
                      onTap: _phase == 'ended' ? null : _toggleMute,
                    ),
                    const SizedBox(width: 14),
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
                    const SizedBox(width: 14),
                    _buildActionCircle(
                      icon: Icons.auto_awesome_rounded,
                      label: _selectedEffectId != 'none' ? 'Effect On' : 'Effects',
                      bgColor: _showEffectsTray || _selectedEffectId != 'none'
                          ? const Color(0xFFEC4899)
                          : Colors.white.withValues(alpha: 0.14),
                      iconColor: Colors.white,
                      onTap: _phase == 'ended' ? null : _toggleBeautyFilter,
                    ),
                    const SizedBox(width: 14),
                    _buildActionCircle(
                      icon: _isScreenSharing
                          ? Icons.stop_screen_share_rounded
                          : Icons.screen_share_rounded,
                      label: _isScreenSharing ? 'Sharing' : 'Share Screen',
                      bgColor: _isScreenSharing
                          ? ZevColors.primaryBlue
                          : Colors.white.withValues(alpha: 0.14),
                      iconColor: _isScreenSharing
                          ? ZevColors.deepNavy
                          : Colors.white,
                      onTap: _phase == 'accepted' ? _toggleScreenShare : null,
                    ),
                    const SizedBox(width: 14),
                    if (_isVideoActive && !_isCameraOff) ...[
                      _buildActionCircle(
                        icon: Icons.cameraswitch_rounded,
                        label: 'Flip',
                        bgColor: Colors.white.withValues(alpha: 0.14),
                        onTap: _switchCamera,
                      ),
                      const SizedBox(width: 14),
                    ],
                    // Prominent End Call Button
                    GestureDetector(
                      onTap: _phase == 'ended' ? null : _hangupOrDecline,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: ZevColors.errorRed,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: ZevColors.errorRed.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.call_end_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'End Call',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Web Main Presentation Stage (Centered 9:16 phone / 16:9 widescreen)
  Widget _buildWebMainStage({
    required bool hasRemoteVideo,
    required String displayName,
  }) {
    final activeEffect = _kCallEffects.firstWhere(
      (e) => e.id == _selectedEffectId,
      orElse: () => _kCallEffects[0],
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF030712),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Remote video in aspect-ratio container (NO STRETCHING)
            if (hasRemoteVideo)
              Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _webAspectMode == 'phone'
                        ? 405
                        : (_webAspectMode == 'wide' ? 1280 : 1280),
                    height: 720,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: activeEffect.colorFilter != null
                          ? ColorFiltered(
                              colorFilter: activeEffect.colorFilter!,
                              child: AgoraVideoView(
                                key: ValueKey(
                                  'remote_wide_${_remoteUid}_${_remoteVideoEnabled}_$_webAspectMode',
                                ),
                                controller: _remoteVideoController!,
                              ),
                            )
                          : AgoraVideoView(
                              key: ValueKey(
                                'remote_wide_${_remoteUid}_${_remoteVideoEnabled}_$_webAspectMode',
                              ),
                              controller: _remoteVideoController!,
                            ),
                    ),
                  ),
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (context, child) {
                        final glow = 12.0 + (_pulseCtrl.value * 18.0);
                        return Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: (_phase == 'accepted'
                                      ? ZevColors.successGreen
                                      : ZevColors.primaryBlue)
                                  .withValues(alpha: 0.55),
                              width: 3.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_phase == 'accepted'
                                        ? ZevColors.successGreen
                                        : ZevColors.primaryBlue)
                                    .withValues(alpha: 0.35),
                                blurRadius: glow,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: child,
                        );
                      },
                      child: ZevCachedImage.avatar(
                        imageUrl: widget.peerAvatar,
                        size: 130,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _phase == 'accepted' && !widget.isVideo
                          ? 'HD Voice Connected • ${_formatDuration(_elapsedSeconds)}'
                          : _statusLabel,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: _phase == 'accepted'
                            ? const Color(0xFF6EE7B7)
                            : Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _errorMsg!,
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

            // Top Bar: Google Meet Style Stream Banner & Aspect Ratio selector
            Positioned(
              left: 16,
              top: 16,
              right: 16,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
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
                          hasRemoteVideo
                              ? '$displayName is presenting screen'
                              : displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Aspect Ratio Mode Switcher (Google Meet grade)
                  if (hasRemoteVideo)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildAspectModeButton('📱 9:16', 'phone'),
                          _buildAspectModeButton('💻 16:9', 'wide'),
                          _buildAspectModeButton('↔ Fit', 'fit'),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Floating Self Camera PIP on Narrow Web Screens
            if (MediaQuery.sizeOf(context).width < 960) ...[
              if (_isScreenSharing && _phase != 'ended')
                Positioned(
                  top: 16,
                  right: 16,
                  child: _buildScreenSharingPipCard(isWide: true),
                )
              else if (_isVideoActive &&
                  _localVideoController != null &&
                  !_isCameraOff &&
                  _phase != 'ended')
                Positioned(
                  top: 16,
                  right: 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 220,
                      height: 124,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: AgoraVideoView(
                        key: const ValueKey('local_self_preview_wide'),
                        controller: _localVideoController!,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAspectModeButton(String label, String mode) {
    final isSelected = _webAspectMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _webAspectMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? ZevColors.primaryBlue
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: isSelected ? ZevColors.deepNavy : Colors.white70,
          ),
        ),
      ),
    );
  }

  /// Google Meet Participant Stack (Right Column on Desktop Web)
  Widget _buildWebSideColumn({
    required String displayName,
    required bool hasRemoteVideo,
  }) {
    return Column(
      children: [
        // Tile 1: Self Video or Avatar Card (NO BLACK BOX)
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1.5,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_isScreenSharing)
                    Center(child: _buildScreenSharingPipCard(isWide: true))
                  else if (_isVideoActive &&
                      !_isCameraOff &&
                      _localVideoController != null)
                    AgoraVideoView(
                      key: const ValueKey('local_self_tile'),
                      controller: _localVideoController!,
                    )
                  else
                    // Camera off placeholder card with avatar (Google Meet style)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: const CircleAvatar(
                              radius: 36,
                              backgroundColor: Color(0xFF1E293B),
                              child: Icon(
                                Icons.person_rounded,
                                color: Colors.white70,
                                size: 36,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'You (Camera Off)',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Pill at bottom left of tile
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isMicMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            size: 13,
                            color: _isMicMuted
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF10B981),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'You',
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
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Tile 2: Peer Profile Summary Card
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ZevCachedImage.avatar(
                    imageUrl: widget.peerAvatar,
                    size: 64,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (widget.isPeerVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 15,
                          color: ZevColors.primaryBlue,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _phase == 'accepted' ? 'HD Connected' : _statusLabel,
                      style: const TextStyle(
                        color: Color(0xFF6EE7B7),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Mobile Portrait Layout (Instagram / FaceTime grade experience)
  Widget _buildMobileLayout() {
    final displayName = widget.peerFullName.isNotEmpty
        ? widget.peerFullName
        : '@${widget.peerUsername}';
    final showIncomingChoice = !widget.isOutgoing && _phase == 'ringing';
    final hasRemoteVideo =
        _isVideoActive && _remoteVideoController != null && _remoteVideoEnabled;
    final activeEffect = _kCallEffects.firstWhere(
      (e) => e.id == _selectedEffectId,
      orElse: () => _kCallEffects[0],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background: Remote Video or Obsidian Gradient
        if (hasRemoteVideo)
          Container(
            color: const Color(0xFF030712),
            child: Center(
              child: activeEffect.colorFilter != null
                  ? ColorFiltered(
                      colorFilter: activeEffect.colorFilter!,
                      child: AgoraVideoView(
                        key: ValueKey('remote_$_remoteUid'),
                        controller: _remoteVideoController!,
                      ),
                    )
                  : AgoraVideoView(
                      key: ValueKey('remote_$_remoteUid'),
                      controller: _remoteVideoController!,
                    ),
            ),
          )
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF070C18),
                  Color(0xFF0D1B2A),
                  Color(0xFF0A1426),
                ],
              ),
            ),
          ),

        // Scrim when remote video is shown
        if (hasRemoteVideo)
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
                    Colors.black.withValues(alpha: 0.68),
                  ],
                ),
              ),
            ),
          ),

        // Foreground content
        SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
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
                    if (_phase == 'accepted')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: ZevColors.successGreen.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: ZevColors.successGreen.withValues(alpha: 0.5),
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

              const Spacer(),

              // Center Avatar & Peer Identity
              if (!hasRemoteVideo)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (context, child) {
                          final glow = _phase == 'ringing' || _phase == 'accepted'
                              ? 10.0 + (_pulseCtrl.value * 14.0)
                              : 6.0;
                          return Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: (_phase == 'accepted'
                                        ? ZevColors.successGreen
                                        : ZevColors.primaryBlue)
                                    .withValues(alpha: 0.55),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_phase == 'accepted'
                                          ? ZevColors.successGreen
                                          : ZevColors.primaryBlue)
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
                          size: 112,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          if (widget.isPeerVerified) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified_rounded,
                              size: 20,
                              color: ZevColors.primaryBlue,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _phase == 'accepted' && !widget.isVideo
                            ? 'Connected • ${_formatDuration(_elapsedSeconds)}'
                            : _statusLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _phase == 'accepted'
                            ? const Color(0xFF6EE7B7)
                            : Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                      if (_errorMsg != null) ...[
                        const SizedBox(height: 10),
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

              const Spacer(),

              // AR Effects Carousel Tray directly above the dock
              if (_showEffectsTray) _buildArEffectsTray(),

              // Bottom Mobile Controls Dock (Overflow-proof 5-button responsive bar)
              if (showIncomingChoice)
                Padding(
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
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionCircle(
                            icon: _isMicMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            label: _isMicMuted ? 'Muted' : 'Mute',
                            bgColor: _isMicMuted
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.14),
                            iconColor: _isMicMuted
                                ? const Color(0xFF0F172A)
                                : Colors.white,
                            onTap: _phase == 'ended' ? null : _toggleMute,
                          ),
                          _buildActionCircle(
                            icon: (_isVideoActive && !_isCameraOff)
                                ? Icons.videocam_rounded
                                : Icons.videocam_off_rounded,
                            label: (_isVideoActive && !_isCameraOff)
                                ? 'Camera'
                                : 'Cam Off',
                            bgColor: (_isVideoActive && !_isCameraOff)
                                ? Colors.white.withValues(alpha: 0.14)
                                : Colors.white,
                            iconColor: (_isVideoActive && !_isCameraOff)
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            onTap: _phase == 'ended' ? null : _toggleCamera,
                          ),
                          _buildActionCircle(
                            icon: Icons.auto_awesome_rounded,
                            label: _selectedEffectId != 'none'
                                ? 'Effect'
                                : 'Filter',
                            bgColor: _showEffectsTray || _selectedEffectId != 'none'
                                ? const Color(0xFFEC4899)
                                : Colors.white.withValues(alpha: 0.14),
                            iconColor: Colors.white,
                            onTap: _phase == 'ended' ? null : _toggleBeautyFilter,
                          ),
                          _buildActionCircle(
                            icon: Icons.more_horiz_rounded,
                            label: 'Tools',
                            bgColor: Colors.white.withValues(alpha: 0.14),
                            onTap: _phase == 'ended' ? null : _openMobileToolsSheet,
                          ),
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
                ),
            ],
          ),
        ),

        // Local Self-View PIP (Hidden cleanly when camera is off - NO BLACK BOX)
        if (_isScreenSharing && _phase != 'ended')
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            right: 16,
            child: _buildScreenSharingPipCard(isWide: false),
          )
        else if (_isVideoActive &&
            _localVideoController != null &&
            !_isCameraOff &&
            _phase != 'ended')
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            right: 16,
            child: GestureDetector(
              onTap: _switchCamera,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 112,
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: AgoraVideoView(
                    key: const ValueKey('local_self_preview'),
                    controller: _localVideoController!,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// AR Face Effects Carousel Tray (Facebook Messenger / Snapchat reference)
  Widget _buildArEffectsTray() {
    final currentCatEffects = _kCallEffects.where(
      (e) => e.id == 'none' || e.category == _selectedEffectCategory,
    ).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.90),
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
              // Category Bar & Dismiss Button
              Row(
                children: [
                  _buildCategoryPill('EFFECTS', 'effects'),
                  const SizedBox(width: 8),
                  _buildCategoryPill('LIGHTING', 'lighting'),
                  const SizedBox(width: 8),
                  _buildCategoryPill('BACKGROUNDS', 'backgrounds'),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _showEffectsTray = false),
                    child: Container(
                      padding: const EdgeInsets.all(4),
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

              // Horizontal Carousel of Circular AR Effects
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: currentCatEffects.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, idx) {
                    final item = currentCatEffects[idx];
                    final isSelected = item.id == _selectedEffectId;
                    return GestureDetector(
                      onTap: () => _applyEffect(item),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: isSelected
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFFEC4899),
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
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFEC4899)
                                            .withValues(alpha: 0.6),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                item.iconEmoji,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.name,
                            style: TextStyle(
                              fontSize: 10.5,
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

  Widget _buildCategoryPill(String label, String catKey) {
    final isSelected = _selectedEffectCategory == catKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedEffectCategory = catKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: isSelected ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _isScreenSharing
                              ? ZevColors.primaryBlue
                              : Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isScreenSharing
                              ? Icons.stop_screen_share_rounded
                              : Icons.screen_share_rounded,
                          color: _isScreenSharing
                              ? ZevColors.deepNavy
                              : Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        _isScreenSharing ? 'Stop Screen Share' : 'Share Screen',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        _isScreenSharing
                            ? 'Currently streaming your screen'
                            : 'Stream your screen to peer',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _toggleScreenShare();
                      },
                    ),
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
                          'Switch between front and back camera',
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
                          _isSpeakerOn ? 'Speakerphone (Loud)' : 'Earpiece',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          _isSpeakerOn
                              ? 'Playing through device speaker'
                              : 'Playing through earpiece receiver',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _toggleSpeaker();
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

  Widget _buildScreenSharingPipCard({required bool isWide}) {
    final width = isWide ? 220.0 : 130.0;
    final height = isWide ? 124.0 : 160.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.65),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF38BDF8).withValues(
                        alpha: 0.15 + (_pulseCtrl.value * 0.18),
                      ),
                    ),
                    child: const Icon(
                      Icons.screen_share_rounded,
                      color: Color(0xFF38BDF8),
                      size: 22,
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              Text(
                isWide ? 'You are sharing screen' : 'Sharing Screen',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Live to peer',
                style: TextStyle(
                  color: Color(0xFF6EE7B7),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _toggleScreenShare,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.7),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.stop_circle_rounded,
                        color: Color(0xFFFCA5A5),
                        size: 12,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Stop',
                        style: TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCircle({
    required IconData icon,
    required String label,
    required Color bgColor,
    Color iconColor = Colors.white,
    double size = 54,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1.0,
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
            const SizedBox(height: 6),
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

