import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/zev_call_audio_service.dart';
import '../../../core/services/zev_rtc_service.dart';
import '../../../core/theme/zev_theme.dart';
import '../../../core/widgets/zev_cached_image.dart';
import '../../../main.dart';
import '../screens/call_screen.dart';

/// Floating Mini Call Bar that persists across the app when a call is minimized.
/// Allows multitasking (chatting, browsing feed, viewing profile) during an active call.
class ZevFloatingCallBanner extends StatefulWidget {
  const ZevFloatingCallBanner({super.key});

  @override
  State<ZevFloatingCallBanner> createState() => _ZevFloatingCallBannerState();
}

class _ZevFloatingCallBannerState extends State<ZevFloatingCallBanner> {
  Timer? _ticker;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _seconds = ZevRtcService.instance.minimizedDurationSeconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ZevRtcService.instance.minimizedCallNotifier.value != null && mounted) {
        setState(() {
          _seconds = ++ZevRtcService.instance.minimizedDurationSeconds;
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
    final nav = appNavigatorKey.currentState;
    if (nav == null || !nav.mounted) return;

    final prof = ZevRtcService.instance.minimizedPeerProfile ?? const <String, dynamic>{};
    final uname = (prof['username'] ?? 'User').toString();
    final full = '${prof['first_name'] ?? ''} ${prof['last_name'] ?? ''}'.trim();
    final avatar = (prof['avatar_url'] ?? '').toString();
    final verified = prof['is_verified'] == true;

    // Clear minimized state before pushing screen
    ZevRtcService.instance.minimizedCallNotifier.value = null;

    nav.push(
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

  Future<void> _endCall(ZevCallSession session) async {
    ZevRtcService.instance.minimizedCallNotifier.value = null;
    try {
      await ZevRtcService.instance.respondCall(
        callId: session.id,
        action: 'end',
      );
    } catch (_) {}
    unawaited(ZevCallAudioService.instance.playCallEndedTone());
    unawaited(ZevRtcService.instance.releaseWarmEngine());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ZevCallSession?>(
      valueListenable: ZevRtcService.instance.minimizedCallNotifier,
      builder: (context, session, _) {
        if (session == null) return const SizedBox.shrink();

        final prof = ZevRtcService.instance.minimizedPeerProfile ?? const <String, dynamic>{};
        final displayName = (prof['first_name'] != null && prof['first_name'].toString().isNotEmpty)
            ? '${prof['first_name']} ${prof['last_name'] ?? ''}'.trim()
            : '@${prof['username'] ?? 'User'}';
        final avatar = (prof['avatar_url'] ?? '').toString();

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
                                border: Border.all(color: const Color(0xFF0F172A), width: 1.5),
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
                                Icon(
                                  session.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                                  size: 14,
                                  color: const Color(0xFF10B981),
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

                      // End Call Quick Action
                      GestureDetector(
                        onTap: () => _endCall(session),
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
      },
    );
  }
}
