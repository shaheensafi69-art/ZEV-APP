import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/zev_theme.dart';

/// WhatsApp-Grade Video Trimmer Bottom Sheet.
/// Enforces a maximum allowed duration (e.g. 90 seconds / 1:30) for Stories & Highlights.
/// Allows the user to select any segment using a filmstrip slider and trims the file cleanly.
class VideoTrimmerSheet extends StatefulWidget {
  final File videoFile;
  final Duration maxDuration;

  const VideoTrimmerSheet({
    super.key,
    required this.videoFile,
    this.maxDuration = const Duration(seconds: 90),
  });

  static Future<File?> show(
    BuildContext context, {
    required File videoFile,
    Duration maxDuration = const Duration(seconds: 90),
  }) {
    return showModalBottomSheet<File>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VideoTrimmerSheet(
        videoFile: videoFile,
        maxDuration: maxDuration,
      ),
    );
  }

  @override
  State<VideoTrimmerSheet> createState() => _VideoTrimmerSheetState();
}

class _VideoTrimmerSheetState extends State<VideoTrimmerSheet> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  double _totalDurationSec = 0;
  double _startSec = 0;
  double _endSec = 90;
  bool _isProcessing = false;

  Timer? _playbackLoopTimer;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    _controller = VideoPlayerController.file(widget.videoFile);
    try {
      await _controller.initialize();
      _totalDurationSec = _controller.value.duration.inMilliseconds / 1000.0;
      final maxAllowed = widget.maxDuration.inSeconds.toDouble();

      setState(() {
        _isInitialized = true;
        _startSec = 0.0;
        _endSec = _totalDurationSec > maxAllowed ? maxAllowed : _totalDurationSec;
      });

      await _controller.setLooping(false);
      await _controller.seekTo(Duration(milliseconds: (_startSec * 1000).toInt()));
      await _controller.play();

      _startLoopMonitoring();
    } catch (e) {
      debugPrint("VideoTrimmer init error: $e");
    }
  }

  void _startLoopMonitoring() {
    _playbackLoopTimer?.cancel();
    _playbackLoopTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_controller.value.isPlaying) return;
      final currentPos = _controller.value.position.inMilliseconds / 1000.0;
      if (currentPos >= _endSec) {
        _controller.seekTo(Duration(milliseconds: (_startSec * 1000).toInt()));
      }
    });
  }

  @override
  void dispose() {
    _playbackLoopTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _formatTime(double seconds) {
    final s = seconds.toInt();
    final m = s ~/ 60;
    final remS = s % 60;
    return "${m.toString().padLeft(2, '0')}:${remS.toString().padLeft(2, '0')}";
  }

  Future<void> _trimAndConfirm() async {
    HapticFeedback.mediumImpact();
    setState(() => _isProcessing = true);

    final selectedDurationSec = _endSec - _startSec;

    // If whole video is within limit and no trimming needed
    if (_startSec <= 0.5 && (_totalDurationSec - _endSec) <= 0.5) {
      if (mounted) Navigator.pop(context, widget.videoFile);
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final ext = widget.videoFile.path.split('.').last;
      final outputPath =
          "${tempDir.path}/trimmed_${DateTime.now().millisecondsSinceEpoch}.$ext";

      final startFormatted = _startSec.toStringAsFixed(2);
      final durationFormatted = selectedDurationSec.toStringAsFixed(2);

      // Fast, lossless stream copy trimming
      final command =
          "-y -ss $startFormatted -i \"${widget.videoFile.path}\" -t $durationFormatted -c copy \"$outputPath\"";

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final trimmedFile = File(outputPath);
        if (await trimmedFile.exists()) {
          if (mounted) Navigator.pop(context, trimmedFile);
          return;
        }
      }

      // Fallback with re-encode if stream copy fails
      final fallbackCommand =
          "-y -ss $startFormatted -i \"${widget.videoFile.path}\" -t $durationFormatted -preset ultrafast \"$outputPath\"";
      final fallbackSession = await FFmpegKit.execute(fallbackCommand);
      final fallbackReturnCode = await fallbackSession.getReturnCode();

      if (ReturnCode.isSuccess(fallbackReturnCode)) {
        final trimmedFile = File(outputPath);
        if (await trimmedFile.exists()) {
          if (mounted) Navigator.pop(context, trimmedFile);
          return;
        }
      }

      // If all fails, return original
      if (mounted) Navigator.pop(context, widget.videoFile);
    } catch (e) {
      debugPrint("Trimming error: $e");
      if (mounted) Navigator.pop(context, widget.videoFile);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxAllowedSec = widget.maxDuration.inSeconds.toDouble();
    final selectedDuration = (_endSec - _startSec).clamp(0.0, _totalDurationSec);

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: ZevColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: ZevColors.deepNavy.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Drag Handle
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: ZevColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 12),

            // Top Header: Title, Duration Badge, and Done Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: ZevColors.deepNavy),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Column(
                    children: [
                      const Text(
                        "Trim Video (Max 1:30)",
                        style: TextStyle(
                          color: ZevColors.deepNavy,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: ZevColors.primaryBlue.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "${_formatTime(selectedDuration)} / 01:30",
                          style: const TextStyle(
                            color: ZevColors.secondaryBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _isProcessing ? null : _trimAndConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZevColors.primaryBlue,
                      foregroundColor: ZevColors.deepNavy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      elevation: 0,
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ZevColors.deepNavy,
                            ),
                          )
                        : const Text(
                            "Done",
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Video Player Preview
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: ZevColors.softSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: ZevColors.border, width: 1.2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(19),
                  child: _isInitialized
                      ? Center(
                          child: AspectRatio(
                            aspectRatio: _controller.value.aspectRatio,
                            child: VideoPlayer(_controller),
                          ),
                        )
                      : const Center(
                          child: CircularProgressIndicator(
                            color: ZevColors.primaryBlue,
                            strokeWidth: 2,
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Light Clearmorphic Video Slider Trimmer
            if (_isInitialized && _totalDurationSec > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatTime(_startSec),
                          style: const TextStyle(
                            color: ZevColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: ZevColors.softSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ZevColors.border, width: 1),
                          ),
                          child: Text(
                            "Selected: ${_formatTime(selectedDuration)}",
                            style: const TextStyle(
                              color: ZevColors.deepNavy,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          _formatTime(_endSec),
                          style: const TextStyle(
                            color: ZevColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: ZevColors.softSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: ZevColors.border, width: 1.5),
                      ),
                      child: RangeSlider(
                        values: RangeValues(_startSec, _endSec),
                        min: 0.0,
                        max: _totalDurationSec,
                        activeColor: ZevColors.primaryBlue,
                        inactiveColor: ZevColors.border,
                        onChanged: (RangeValues values) {
                          double newStart = values.start;
                          double newEnd = values.end;

                          // Enforce max 90s limit
                          if (newEnd - newStart > maxAllowedSec) {
                            if (newStart != _startSec) {
                              newStart = newEnd - maxAllowedSec;
                            } else {
                              newEnd = newStart + maxAllowedSec;
                            }
                          }

                          setState(() {
                            _startSec = newStart.clamp(0.0, _totalDurationSec);
                            _endSec = newEnd.clamp(0.0, _totalDurationSec);
                          });

                          _controller.seekTo(
                            Duration(milliseconds: (_startSec * 1000).toInt()),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 6),
                    Text(
                      "Total Video Length: ${_formatTime(_totalDurationSec)} • Drag handles to select 90s",
                      style: const TextStyle(color: ZevColors.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

