import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/zev_rtc_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../main.dart';

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
  bool _isActionInFlight = false;
  bool _engineJoined = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _isSpeakerOn = widget.isVideo;
    _isCameraOff = !widget.isVideo;

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
    if (widget.isVideo) {
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

    if (updated.status == 'accepted' && _phase != 'accepted') {
      _ringTimeoutTimer?.cancel();
      _statusPollTimer?.cancel();
      HapticFeedback.mediumImpact();
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
          }
          if (widget.isVideo) {
            _remoteVideoController?.dispose();
            _remoteVideoController = VideoViewController.remote(
              rtcEngine: engine,
              canvas: VideoCanvas(
                uid: remoteUid,
                renderMode: RenderModeType.renderModeHidden,
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
    );

    engine.registerEventHandler(handler);
    _engine = engine;
    _engineHandler = handler;

    await engine.enableAudio();
    try {
      await engine.setEnableSpeakerphone(_isSpeakerOn);
    } catch (_) {}

    if (widget.isVideo) {
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
              renderMode: RenderModeType.renderModeHidden,
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
        publishCameraTrack: widget.isVideo && !_isCameraOff,
        autoSubscribeAudio: true,
        autoSubscribeVideo: widget.isVideo,
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
    if (!widget.isVideo) return;
    HapticFeedback.selectionClick();
    final nextOff = !_isCameraOff;
    setState(() => _isCameraOff = nextOff);
    try {
      await _engine?.muteLocalVideoStream(nextOff);
      await _engine?.enableLocalVideo(!nextOff);
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (!widget.isVideo) return;
    HapticFeedback.selectionClick();
    try {
      await _engine?.switchCamera();
    } catch (_) {}
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.peerFullName.isNotEmpty
        ? widget.peerFullName
        : '@${widget.peerUsername}';
    final showIncomingChoice = !widget.isOutgoing && _phase == 'ringing';
    final hasRemoteVideo =
        widget.isVideo && _remoteVideoController != null && _remoteVideoEnabled;

    return PopScope(
      canPop: _phase == 'ended',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase != 'ended') {
          unawaited(_hangupOrDecline());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070B14),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Background: Remote Video or Sleek Obsidian Call Surface
            if (hasRemoteVideo)
              AgoraVideoView(
                key: ValueKey('remote_$_remoteUid'),
                controller: _remoteVideoController!,
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

            // Subtle dark scrim when remote video is shown so top/bottom HUD stays legible
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

            // Main Call Foreground
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

                  // Center Avatar & Peer Identity (shown for Voice calls or while Video is connecting/off)
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

                  // Bottom Controls Dock
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
                            icon: widget.isVideo
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
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.82),
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
                          if (widget.isVideo) ...[
                            _buildActionCircle(
                              icon: _isCameraOff
                                  ? Icons.videocam_off_rounded
                                  : Icons.videocam_rounded,
                              label: _isCameraOff ? 'Cam Off' : 'Camera',
                              bgColor: _isCameraOff
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.14),
                              iconColor: _isCameraOff
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                              onTap: _phase == 'ended' ? null : _toggleCamera,
                            ),
                            _buildActionCircle(
                              icon: Icons.cameraswitch_rounded,
                              label: 'Flip',
                              bgColor: Colors.white.withValues(alpha: 0.14),
                              onTap: (_phase == 'ended' || _isCameraOff)
                                  ? null
                                  : _switchCamera,
                            ),
                          ],
                          if (!kIsWeb)
                            _buildActionCircle(
                              icon: _isSpeakerOn
                                  ? Icons.volume_up_rounded
                                  : Icons.hearing_rounded,
                              label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                              bgColor: _isSpeakerOn
                                  ? ZevColors.primaryBlue
                                  : Colors.white.withValues(alpha: 0.14),
                              iconColor: _isSpeakerOn
                                  ? ZevColors.deepNavy
                                  : Colors.white,
                              onTap: _phase == 'ended' ? null : _toggleSpeaker,
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
                ],
              ),
            ),

            // Local Self-View PIP for Video Calls
            if (widget.isVideo &&
                _localVideoController != null &&
                !_isCameraOff &&
                _phase != 'ended')
              Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                right: 16,
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
          ],
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

