import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Service responsible for VoIP call audio sound effects:
/// - Outgoing ringback calling tone (standard 440+480Hz telecommunications tone)
/// - Incoming melodic marimba/bell ringtone
/// - Ascending call connected chime
/// - Descending call ended disconnect tone
class ZevCallAudioService {
  ZevCallAudioService._();
  static final ZevCallAudioService instance = ZevCallAudioService._();

  AudioPlayer? _loopPlayer;
  AudioPlayer? _oneShotPlayer;

  bool _isPlayingLoop = false;
  bool get isPlayingLoop => _isPlayingLoop;

  /// Starts repeating outgoing calling tone (ringback tone) while waiting for callee.
  Future<void> startOutgoingCallingTone() async {
    await stopLoop();
    try {
      _loopPlayer ??= AudioPlayer();
      await _loopPlayer!.setReleaseMode(ReleaseMode.loop);
      await _loopPlayer!.setVolume(0.85);
      await _loopPlayer!.play(AssetSource('audio/outgoing_calling.wav'));
      _isPlayingLoop = true;
    } catch (e) {
      debugPrint('[ZevCallAudioService] Error starting outgoing calling tone: $e');
    }
  }

  /// Starts repeating incoming call ringtone when receiving an incoming call.
  Future<void> startIncomingRingtone() async {
    await stopLoop();
    try {
      _loopPlayer ??= AudioPlayer();
      await _loopPlayer!.setReleaseMode(ReleaseMode.loop);
      await _loopPlayer!.setVolume(1.0);
      await _loopPlayer!.play(AssetSource('audio/incoming_ringtone.wav'));
      _isPlayingLoop = true;
    } catch (e) {
      debugPrint('[ZevCallAudioService] Error starting incoming ringtone: $e');
    }
  }

  /// Plays short ascending connection sound when call is accepted/answered.
  Future<void> playCallConnectedTone() async {
    await stopLoop();
    try {
      _oneShotPlayer ??= AudioPlayer();
      await _oneShotPlayer!.stop();
      await _oneShotPlayer!.setReleaseMode(ReleaseMode.stop);
      await _oneShotPlayer!.setVolume(0.9);
      await _oneShotPlayer!.play(AssetSource('audio/call_connected.wav'));
    } catch (e) {
      debugPrint('[ZevCallAudioService] Error playing call connected tone: $e');
    }
  }

  /// Plays soft descending sound effect when call is ended/declined/canceled.
  Future<void> playCallEndedTone() async {
    await stopLoop();
    try {
      _oneShotPlayer ??= AudioPlayer();
      await _oneShotPlayer!.stop();
      await _oneShotPlayer!.setReleaseMode(ReleaseMode.stop);
      await _oneShotPlayer!.setVolume(0.85);
      await _oneShotPlayer!.play(AssetSource('audio/call_ended.wav'));
    } catch (e) {
      debugPrint('[ZevCallAudioService] Error playing call ended tone: $e');
    }
  }

  /// Stops loop tone (calling or ringing) immediately.
  Future<void> stopLoop() async {
    if (_loopPlayer != null) {
      try {
        await _loopPlayer!.stop();
      } catch (_) {}
      _isPlayingLoop = false;
    }
  }

  /// Stops all call sounds immediately.
  Future<void> stopAll() async {
    await stopLoop();
    if (_oneShotPlayer != null) {
      try {
        await _oneShotPlayer!.stop();
      } catch (_) {}
    }
  }

  /// Disposes audio players and releases system audio resources.
  void dispose() {
    try {
      _loopPlayer?.dispose();
      _oneShotPlayer?.dispose();
    } catch (_) {}
    _loopPlayer = null;
    _oneShotPlayer = null;
    _isPlayingLoop = false;
  }
}
