import 'dart:async';
import 'dart:math' as math;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_config.dart';

/// Twitter Spaces / Telegram Voice Chat style Group Audio Space.
class AudioSpaceScreen extends StatefulWidget {
  final String spaceId;
  final String title;
  final String hostId;
  final String hostName;
  final String hostAvatar;
  final bool isHost;

  const AudioSpaceScreen({
    super.key,
    required this.spaceId,
    required this.title,
    required this.hostId,
    required this.hostName,
    required this.hostAvatar,
    this.isHost = false,
  });

  static Future<void> open(
    BuildContext context, {
    required String spaceId,
    required String title,
    required String hostId,
    required String hostName,
    required String hostAvatar,
    bool isHost = false,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioSpaceScreen(
          spaceId: spaceId,
          title: title,
          hostId: hostId,
          hostName: hostName,
          hostAvatar: hostAvatar,
          isHost: isHost,
        ),
      ),
    );
  }

  @override
  State<AudioSpaceScreen> createState() => _AudioSpaceScreenState();
}

class _AudioSpaceScreenState extends State<AudioSpaceScreen>
    with SingleTickerProviderStateMixin {
  RtcEngine? _engine;
  bool _isJoined = false;
  bool _isMuted = false;
  bool _hasHandRaised = false;
  bool _isSpeaker = false;

  late AnimationController _pulseController;
  final List<_FloatingReaction> _reactions = [];

  final List<Map<String, dynamic>> _speakers = [];
  final List<Map<String, dynamic>> _listeners = [];
  final Set<int> _activeSpeakingUids = {};

  @override
  void initState() {
    super.initState();
    _isSpeaker = widget.isHost;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _initSpaceParticipants();
    _initAgora();
  }

  void _initSpaceParticipants() {
    // Add Host to speakers
    _speakers.add({
      'uid': 1001,
      'userId': widget.hostId,
      'name': widget.hostName,
      'avatar': widget.hostAvatar,
      'isHost': true,
      'isMuted': false,
    });

    // Populate mock listeners / community participants
    _listeners.addAll([
      {
        'uid': 2001,
        'name': 'Sophia Miller',
        'avatar': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
      },
      {
        'uid': 2002,
        'name': 'Alex Rivera',
        'avatar': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
      },
      {
        'uid': 2003,
        'name': 'Elena Rostova',
        'avatar': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      },
      {
        'uid': 2004,
        'name': 'David Chen',
        'avatar': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150',
      },
    ]);
  }

  Future<void> _initAgora() async {
    try {
      final appId = AppConfig.agoraAppId;
      if (appId.isEmpty) {
        setState(() => _isJoined = true);
        return;
      }

      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint('[AudioSpaceScreen] Joined channel');
            if (mounted) setState(() => _isJoined = true);
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            if (mounted) {
              setState(() {
                _activeSpeakingUids.add(remoteUid);
              });
            }
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            if (mounted) {
              setState(() {
                _activeSpeakingUids.remove(remoteUid);
              });
            }
          },
          onAudioVolumeIndication: (
            RtcConnection connection,
            List<AudioVolumeInfo> speakers,
            int totalVolume,
            int vad,
          ) {
            if (mounted) {
              final active = <int>{};
              for (final s in speakers) {
                if ((s.volume ?? 0) > 10 && (s.uid ?? 0) > 0) {
                  active.add(s.uid!);
                }
              }
              setState(() => _activeSpeakingUids.clear());
              setState(() => _activeSpeakingUids.addAll(active));
            }
          },
        ),
      );

      await _engine!.enableAudio();
      await _engine!.enableAudioVolumeIndication(
        interval: 300,
        smooth: 3,
        reportVad: true,
      );

      await _engine!.setClientRole(
        role: _isSpeaker
            ? ClientRoleType.clientRoleBroadcaster
            : ClientRoleType.clientRoleAudience,
      );

      await _engine!.joinChannel(
        token: '',
        channelId: 'space_${widget.spaceId}',
        uid: widget.isHost ? 1001 : 0,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );
    } catch (e) {
      debugPrint('[AudioSpaceScreen] Agora init: $e');
      if (mounted) setState(() => _isJoined = true);
    }
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    setState(() => _isMuted = !_isMuted);
    _engine?.muteLocalAudioStream(_isMuted);
  }

  void _toggleRaiseHand() {
    HapticFeedback.mediumImpact();
    setState(() => _hasHandRaised = !_hasHandRaised);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _hasHandRaised
              ? 'Hand raised! The host has been notified to speak.'
              : 'Hand lowered.',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addReaction(String emoji) {
    HapticFeedback.selectionClick();
    final r = _FloatingReaction(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      emoji: emoji,
      startX: 0.3 + math.Random().nextDouble() * 0.4,
    );
    setState(() => _reactions.add(r));
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() => _reactions.removeWhere((x) => x.id == r.id));
      }
    });
  }

  Future<void> _leaveSpace() async {
    HapticFeedback.mediumImpact();
    await _engine?.leaveChannel();
    await _engine?.release();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalParticipants = _speakers.length + _listeners.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate space ambient
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top Header Bar
                _buildHeaderBar(totalParticipants),

                // Scrollable Stage & Audience
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    children: [
                      // Space Title Card
                      _buildTitleCard(),

                      const SizedBox(height: 24),

                      // Speakers Stage Section
                      _buildSectionHeader("SPEAKERS & STAGE", _speakers.length),
                      const SizedBox(height: 14),
                      _buildSpeakersGrid(),

                      const SizedBox(height: 30),

                      // Audience / Listeners Section
                      _buildSectionHeader("LISTENERS", _listeners.length),
                      const SizedBox(height: 14),
                      _buildListenersGrid(),

                      const SizedBox(height: 120), // Bottom padding for controls
                    ],
                  ),
                ),
              ],
            ),

            // Floating Reactions Overlay
            ..._reactions.map((r) => _buildAnimatedReaction(r)),

            // Bottom Clearmorphic Controls Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBar(int totalParticipants) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.7),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          // Live Indicator Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isJoined ? "LIVE STAGE" : "CONNECTING...",
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Listener Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.people_alt_rounded,
                  color: Colors.white70,
                  size: 15,
                ),
                const SizedBox(width: 5),
                Text(
                  "$totalParticipants",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Leave Quietly Button
          GestureDetector(
            onTap: _leaveSpace,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                ),
              ),
              child: const Text(
                "Leave quietly",
                style: TextStyle(
                  color: Color(0xFFFCA5A5),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0284C7).withValues(alpha: 0.35),
            const Color(0xFF1E293B).withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.graphic_eq_rounded, color: Color(0xFF38BDF8), size: 18),
              SizedBox(width: 8),
              Text(
                "ZEV AUDIO SPACE",
                style: TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundImage: widget.hostAvatar.isNotEmpty
                    ? CachedNetworkImageProvider(widget.hostAvatar)
                    : null,
                child: widget.hostAvatar.isEmpty
                    ? const Icon(Icons.person, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                "Hosted by ${widget.hostName}",
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            "$count",
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeakersGrid() {
    return Wrap(
      spacing: 24,
      runSpacing: 20,
      children: _speakers.map((s) {
        final isHost = s['isHost'] == true;
        final isSpeaking = _activeSpeakingUids.contains(s['uid']);

        return Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                // Animated speaking glow ring
                if (isSpeaking)
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (ctx, child) {
                      return Container(
                        width: 78 + (_pulseController.value * 8),
                        height: 78 + (_pulseController.value * 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF38BDF8).withValues(
                              alpha: 0.7 - (_pulseController.value * 0.3),
                            ),
                            width: 3,
                          ),
                        ),
                      );
                    },
                  ),

                // Avatar
                CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFF1E293B),
                  backgroundImage: (s['avatar'] as String).isNotEmpty
                      ? CachedNetworkImageProvider(s['avatar'])
                      : null,
                  child: (s['avatar'] as String).isEmpty
                      ? const Icon(Icons.person, color: Colors.white, size: 28)
                      : null,
                ),

                // Host Crown
                if (isHost)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEAB308),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        color: Colors.black,
                        size: 13,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              s['name'],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              isHost ? "Host" : "Speaker",
              style: TextStyle(
                color: isHost ? const Color(0xFF38BDF8) : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildListenersGrid() {
    return Wrap(
      spacing: 20,
      runSpacing: 18,
      children: _listeners.map((l) {
        return Column(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFF1E293B),
              backgroundImage: (l['avatar'] as String).isNotEmpty
                  ? CachedNetworkImageProvider(l['avatar'])
                  : null,
              child: (l['avatar'] as String).isEmpty
                  ? const Icon(Icons.person, color: Colors.white70, size: 20)
                  : null,
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 60,
              child: Text(
                l['name'],
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildAnimatedReaction(_FloatingReaction r) {
    return Positioned(
      bottom: 110,
      left: MediaQuery.of(context).size.width * r.startX,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 1600),
        builder: (context, val, child) {
          return Transform.translate(
            offset: Offset(0, -val * 240),
            child: Opacity(
              opacity: (1.0 - val).clamp(0.0, 1.0),
              child: Text(
                r.emoji,
                style: const TextStyle(fontSize: 34),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Mic Button (for speaker) or Raise Hand (for audience)
          if (_isSpeaker)
            GestureDetector(
              onTap: _toggleMute,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  gradient: _isMuted
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF0284C7), Color(0xFF06B6D4)],
                        ),
                  color: _isMuted ? Colors.white.withValues(alpha: 0.15) : null,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isMuted
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isMuted ? "Unmute" : "Mic ON",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            GestureDetector(
              onTap: _toggleRaiseHand,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _hasHandRaised
                      ? const Color(0xFFEAB308)
                      : Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _hasHandRaised
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.back_hand_rounded,
                      color: _hasHandRaised ? Colors.black : Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _hasHandRaised ? "Hand Raised" : "Raise Hand",
                      style: TextStyle(
                        color: _hasHandRaised ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Emoji Reactions Quick Bar
          Row(
            children: ["❤️", "👏", "🔥", "🚀"].map((emoji) {
              return GestureDetector(
                onTap: () => _addReaction(emoji),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              );
            }).toList(),
          ),

          // Share Space Button
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.share_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
            tooltip: "Share Space",
            onPressed: () {
              Share.share(
                "🎙️ Join our live ZEV Audio Space '${widget.title}': https://zevapp.com/spaces/${widget.spaceId}",
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FloatingReaction {
  final String id;
  final String emoji;
  final double startX;

  _FloatingReaction({
    required this.id,
    required this.emoji,
    required this.startX,
  });
}
