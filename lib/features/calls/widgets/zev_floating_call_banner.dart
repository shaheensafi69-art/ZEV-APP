import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/zev_rtc_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';

/// Floating Mini Call Bar & Draggable Picture-in-Picture (PiP) Window.
/// Persists across the app when a call is minimized so users can browse chats,
/// explore feeds, or use other app features without dropping WebRTC audio/video.
class ZevFloatingCallBanner extends StatefulWidget {
  const ZevFloatingCallBanner({super.key});

  @override
  State<ZevFloatingCallBanner> createState() => _ZevFloatingCallBannerState();
}

class _ZevFloatingCallBannerState extends State<ZevFloatingCallBanner> {
  Timer? _ticker;
  int _seconds = 0;
  Offset? _pipOffset;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _seconds = ZevRtcService.instance.activeDurationSeconds;
    _isMuted = ZevRtcService.instance.isActiveMicMuted;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ZevRtcService.instance.minimizedCallNotifier.value != null && mounted) {
        setState(() {
          _seconds = ++ZevRtcService.instance.activeDurationSeconds;
          ZevRtcService.instance.minimizedDurationSeconds = _seconds;
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _restoreCall(ZevCallSession session) {
    HapticFeedback.lightImpact();
    ZevRtcService.instance.restoreActiveCall(context);
  }

  Future<void> _endCall() async {
    HapticFeedback.mediumImpact();
    await ZevRtcService.instance.endActiveCall();
  }

  Future<void> _toggleMute() async {
    HapticFeedback.selectionClick();
    final eng = ZevRtcService.instance.activeMinimizedEngine;
    final nextMute = !_isMuted;
    setState(() {
      _isMuted = nextMute;
      ZevRtcService.instance.isActiveMicMuted = nextMute;
      ZevRtcService.instance.isMinimizedMicMuted = nextMute;
    });
    if (eng != null) {
      try {
        await eng.muteLocalAudioStream(nextMute);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ZevCallSession?>(
      valueListenable: ZevRtcService.instance.minimizedCallNotifier,
      builder: (context, session, _) {
        if (session == null) return const SizedBox.shrink();

        final prof = ZevRtcService.instance.activePeerProfile ??
            ZevRtcService.instance.minimizedPeerProfile ??
            const <String, dynamic>{};
        final displayName = (prof['first_name'] != null &&
                prof['first_name'].toString().isNotEmpty)
            ? '${prof['first_name']} ${prof['last_name'] ?? ''}'.trim()
            : '@${prof['username'] ?? 'User'}';
        final avatar = (prof['avatar_url'] ?? '').toString();

        final hasRemoteVideo = session.isVideo &&
            ZevRtcService.instance.activeRemoteVideoController != null;

        // Render draggable Video PiP if video call with active remote stream
        if (hasRemoteVideo) {
          return _buildDraggableVideoPip(session, displayName);
        }

        // Otherwise render sleek top audio banner
        return Align(
          alignment: Alignment.topCenter,
          child: _buildAudioTopBanner(session, displayName, avatar),
        );
      },
    );
  }

  /// Draggable Floating Picture-in-Picture window for Video Calls
  Widget _buildDraggableVideoPip(ZevCallSession session, String displayName) {
    final screenSize = MediaQuery.sizeOf(context);
    final isDesktop = screenSize.width >= 720 || (kIsWeb && screenSize.width >= 600);

    final pipWidth = isDesktop ? 220.0 : 130.0;
    final pipHeight = isDesktop ? 150.0 : 190.0;

    // Default to bottom right if not yet dragged
    _pipOffset ??= Offset(
      screenSize.width - pipWidth - 16,
      screenSize.height - pipHeight - (isDesktop ? 32 : 90),
    );

    // Keep within screen boundaries
    final currentOffset = Offset(
      _pipOffset!.dx.clamp(8.0, screenSize.width - pipWidth - 8.0),
      _pipOffset!.dy.clamp(32.0, screenSize.height - pipHeight - 32.0),
    );

    final remoteCtrl = ZevRtcService.instance.activeRemoteVideoController;
    final localCtrl = ZevRtcService.instance.activeLocalVideoController;
    final isCameraOff = ZevRtcService.instance.isActiveCameraOff;

    return Stack(
      children: [
        Positioned(
          left: currentOffset.dx,
          top: currentOffset.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _pipOffset = Offset(
                  currentOffset.dx + details.delta.dx,
                  currentOffset.dy + details.delta.dy,
                );
              });
            },
            onTap: () => _restoreCall(session),
            child: Material(
              color: Colors.transparent,
              elevation: 16,
              shadowColor: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: pipWidth,
                height: pipHeight,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF10B981),
                    width: 2.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 1. Remote Video Stream
                      if (remoteCtrl != null)
                        AgoraVideoView(
                          key: ValueKey(
                            'pip_remote_${ZevRtcService.instance.activeRemoteUid ?? 0}',
                          ),
                          controller: remoteCtrl,
                        )
                      else
                        Container(
                          color: const Color(0xFF0A0F1D),
                          child: const Center(
                            child: Icon(
                              Icons.videocam_off_rounded,
                              color: Colors.white38,
                              size: 28,
                            ),
                          ),
                        ),

                      // 2. Top Scrim & HUD (Duration & Expand)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.75),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Duration Pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _formatDuration(_seconds),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              // Expand Icon
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.open_in_full_rounded,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 3. Mini Inset for Local Self Preview
                      if (localCtrl != null && !isCameraOff)
                        Positioned(
                          right: 8,
                          bottom: 38,
                          child: Container(
                            width: 34,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.8),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: AgoraVideoView(
                                key: const ValueKey('pip_local_self'),
                                controller: localCtrl,
                              ),
                            ),
                          ),
                        ),

                      // 4. Bottom Controls Overlay
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.80),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Mic Toggle
                              GestureDetector(
                                onTap: _toggleMute,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: _isMuted
                                        ? const Color(0xFFEF4444)
                                        : Colors.white.withValues(alpha: 0.25),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _isMuted
                                        ? Icons.mic_off_rounded
                                        : Icons.mic_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              // Hangup Action
                              GestureDetector(
                                onTap: _endCall,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.call_end_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
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
          ),
        ),
      ],
    );
  }

  /// Sleek Floating Top Banner for Voice Calls
  Widget _buildAudioTopBanner(
    ZevCallSession session,
    String displayName,
    String avatar,
  ) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => _restoreCall(session),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Avatar with animated pulse green ring
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF10B981),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: ZevCachedImage.avatar(
                            imageUrl: avatar,
                            size: 34,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF10B981),
                            border: Border.all(
                              color: const Color(0xFF0F172A),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Peer Name and Duration
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.call_rounded,
                              size: 14,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to return • ${_formatDuration(_seconds)}',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Quick Mute Action
                  GestureDetector(
                    onTap: _toggleMute,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: _isMuted
                            ? const Color(0xFFEF4444).withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isMuted
                              ? const Color(0xFFEF4444)
                              : Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(
                        _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        size: 16,
                        color: _isMuted
                            ? const Color(0xFFFCA5A5)
                            : Colors.white,
                      ),
                    ),
                  ),

                  // End Call Quick Action
                  GestureDetector(
                    onTap: _endCall,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: ZevColors.errorRed.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ZevColors.errorRed.withValues(alpha: 0.6),
                        ),
                      ),
                      child: const Icon(
                        Icons.call_end_rounded,
                        size: 16,
                        color: Color(0xFFFCA5A5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
