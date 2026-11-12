import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:easy_compressor/easy_compressor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../theme/zev_theme.dart';
import 'zev_skeleton.dart';

/// Light Clearmorphic Video Thumbnail & Preview Widget for ZEV.
/// Used across Explore Grid, Profile Reels/Posts, Feed video slides, Highlights, and Chat video bubbles.
///
/// Features:
/// 1. Multi-tier visual loading (Remote/Local Cover -> Disk Cache -> Bounded RAM LRU -> Concurrency-limited Frame Extractor -> Fallback Player).
/// 2. Persistent disk cache (`getTemporaryDirectory()/zev_video_thumbs`) + bounded RAM LRU (64 frames).
/// 3. Concurrency limiter (`_maxConcurrentExtractions = 3`) prevents native decoder starvation on dense grids.
/// 4. Smooth cover-to-video crossfade (`AnimatedOpacity`) on `autoPlay: true` without black flicker, plus optional interactive mute toggle.
class ZevVideoThumbnail extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final int? viewsCount;
  final int? durationSeconds;
  final bool autoPlay;
  final bool initialMuted;
  final bool showMuteToggle;
  final bool showPlayBadge;
  final bool showCenterPlayButton;
  final bool showViews;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;

  const ZevVideoThumbnail({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.viewsCount,
    this.durationSeconds,
    this.autoPlay = false,
    this.initialMuted = true,
    this.showMuteToggle = false,
    this.showPlayBadge = true,
    this.showCenterPlayButton = false,
    this.showViews = true,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
  });

  static const Set<String> _videoExtensions = {
    '.mp4',
    '.mov',
    '.m4v',
    '.webm',
    '.mkv',
    '.avi',
    '.3gp',
  };

  /// Returns `true` when [url] points to a known video extension (ignoring query/fragment parameters).
  static bool isVideoUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final parsed = Uri.tryParse(trimmed);
    final path = (parsed?.path.isNotEmpty == true ? parsed!.path : trimmed)
        .toLowerCase();
    for (final ext in _videoExtensions) {
      if (path.endsWith(ext)) return true;
    }
    return false;
  }

  /// Returns `true` when [thumbUrl] is a usable non-video image URL or local image path.
  static bool isValidImageThumbUrl(String? thumbUrl) {
    final trimmed = (thumbUrl ?? '').trim();
    if (trimmed.isEmpty) return false;
    return !isVideoUrl(trimmed);
  }

  static const int _maxCacheEntries = 64;
  static const int _maxConcurrentExtractions = 3;
  static final Map<String, Uint8List> _globalBytesCache = {};
  static final List<String> _cacheLruOrder = [];
  static final Map<String, Future<Uint8List?>> _inFlightExtractions = {};
  static final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();
  static int _activeExtractions = 0;
  static Directory? _diskCacheDir;
  static bool _diskCacheUnavailable = false;

  static String _cacheKey(String videoUrl, int positionMs, int maxHeight) {
    return '$videoUrl@$positionMs@$maxHeight';
  }

  static Uint8List? _getCachedBytes(String key) {
    final bytes = _globalBytesCache[key];
    if (bytes != null) {
      _cacheLruOrder.remove(key);
      _cacheLruOrder.add(key);
    }
    return bytes;
  }

  static void _putCachedBytes(String key, Uint8List bytes) {
    _globalBytesCache[key] = bytes;
    _cacheLruOrder.remove(key);
    _cacheLruOrder.add(key);
    while (_cacheLruOrder.length > _maxCacheEntries) {
      final oldest = _cacheLruOrder.removeAt(0);
      _globalBytesCache.remove(oldest);
    }
  }

  static Future<Directory?> _ensureDiskCacheDir() async {
    if (_diskCacheUnavailable) return null;
    if (_diskCacheDir != null) return _diskCacheDir;
    try {
      final temp = await getTemporaryDirectory();
      final dir = Directory('${temp.path}/zev_video_thumbs');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _diskCacheDir = dir;
      return dir;
    } catch (_) {
      _diskCacheUnavailable = true;
      return null;
    }
  }

  static String _diskFileName(String key) {
    final digest = sha256.convert(utf8.encode(key)).toString();
    return '$digest.jpg';
  }

  static Future<void> _acquireSlot() async {
    if (_activeExtractions < _maxConcurrentExtractions) {
      _activeExtractions++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.addLast(completer);
    await completer.future;
  }

  static void _releaseSlot() {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeFirst();
      next.complete();
    } else if (_activeExtractions > 0) {
      _activeExtractions--;
    }
  }

  /// Extracts (and caches in RAM + temp disk) a JPEG thumbnail frame for [videoUrl].
  /// Safe for dense grids and live scrubber frame previews.
  static Future<Uint8List?> extractThumbnailBytes(
    String videoUrl, {
    Duration position = const Duration(milliseconds: 300),
    int maxHeight = 480,
    int quality = 75,
  }) {
    final targetUrl = videoUrl.trim();
    if (targetUrl.isEmpty) return Future.value(null);

    final posMs = position.inMilliseconds < 0 ? 0 : position.inMilliseconds;
    final key = _cacheKey(targetUrl, posMs, maxHeight);

    final memHit = _getCachedBytes(key);
    if (memHit != null && memHit.isNotEmpty) {
      return Future.value(memHit);
    }

    return _inFlightExtractions.putIfAbsent(key, () async {
      try {
        final dir = await _ensureDiskCacheDir();
        if (dir != null) {
          final file = File('${dir.path}/${_diskFileName(key)}');
          if (await file.exists()) {
            final diskBytes = await file.readAsBytes();
            if (diskBytes.isNotEmpty) {
              _putCachedBytes(key, diskBytes);
              return diskBytes;
            }
          }
        }

        await _acquireSlot();
        try {
          Uint8List? bytes = await EasyCompressor()
              .getThumbnail(
                targetUrl,
                position: Duration(milliseconds: posMs),
                maxHeight: maxHeight,
                quality: quality,
              )
              .timeout(const Duration(seconds: 12), onTimeout: () => null);

          if ((bytes == null || bytes.isEmpty) && posMs > 0) {
            bytes = await EasyCompressor()
                .getThumbnail(
                  targetUrl,
                  position: Duration.zero,
                  maxHeight: maxHeight,
                  quality: quality,
                )
                .timeout(const Duration(seconds: 10), onTimeout: () => null);
          }

          if (bytes != null && bytes.isNotEmpty) {
            _putCachedBytes(key, bytes);
            if (dir != null) {
              try {
                final file = File('${dir.path}/${_diskFileName(key)}');
                await file.writeAsBytes(bytes, flush: false);
              } catch (_) {}
            }
            return bytes;
          }
        } finally {
          _releaseSlot();
        }
      } catch (e) {
        debugPrint('[ZevVideoThumbnail] Frame extract notice: $e');
      }
      return null;
    }).whenComplete(() => _inFlightExtractions.remove(key));
  }

  /// Clears extracted frame bytes from RAM (e.g. under low-memory pressure).
  static void clearMemoryCache() {
    _globalBytesCache.clear();
    _cacheLruOrder.clear();
  }

  @override
  State<ZevVideoThumbnail> createState() => _ZevVideoThumbnailState();
}

class _ZevVideoThumbnailState extends State<ZevVideoThumbnail> {
  Uint8List? _extractedBytes;
  VideoPlayerController? _controller;
  VoidCallback? _playerListener;
  bool _isPlayerInitialized = false;
  bool _hasFirstFrame = false;
  bool _isExtracting = false;
  bool _remoteThumbFailed = false;
  late bool _isMuted;
  bool _disposed = false;

  bool get _hasUsableThumb =>
      !_remoteThumbFailed &&
      ZevVideoThumbnail.isValidImageThumbUrl(widget.thumbnailUrl);

  @override
  void initState() {
    super.initState();
    _isMuted = widget.initialMuted;
    _loadVisualMedia();
  }

  @override
  void didUpdateWidget(ZevVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlChanged = oldWidget.videoUrl != widget.videoUrl;
    final thumbChanged = oldWidget.thumbnailUrl != widget.thumbnailUrl;
    final autoPlayChanged = oldWidget.autoPlay != widget.autoPlay;

    if (urlChanged) {
      _disposeController();
      _extractedBytes = null;
      _isExtracting = false;
      _remoteThumbFailed = false;
    }

    if (thumbChanged) {
      _remoteThumbFailed = false;
    }

    if (urlChanged || thumbChanged || autoPlayChanged) {
      _loadVisualMedia();
    }
  }

  void _loadVisualMedia() {
    final key = ZevVideoThumbnail._cacheKey(widget.videoUrl.trim(), 300, 480);
    final cached = ZevVideoThumbnail._getCachedBytes(key);
    if (cached != null) {
      _extractedBytes = cached;
    } else if (!_hasUsableThumb && widget.videoUrl.trim().isNotEmpty) {
      _extractHardwareThumbnail();
    }

    if (widget.autoPlay && widget.videoUrl.trim().isNotEmpty) {
      _initPreviewController();
    } else if (_controller != null && _hasUsableThumb) {
      _disposeController();
    }
  }

  void _onRemoteThumbError() {
    if (_disposed || _remoteThumbFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed || _remoteThumbFailed) return;
      setState(() => _remoteThumbFailed = true);
      if (_extractedBytes == null && widget.videoUrl.trim().isNotEmpty) {
        _extractHardwareThumbnail();
      }
    });
  }

  Future<void> _extractHardwareThumbnail() async {
    final targetUrl = widget.videoUrl.trim();
    if (_isExtracting || targetUrl.isEmpty) return;
    _isExtracting = true;

    try {
      final bytes = await ZevVideoThumbnail.extractThumbnailBytes(
        targetUrl,
        position: const Duration(milliseconds: 300),
        maxHeight: 480,
        quality: 75,
      );

      if (bytes != null && bytes.isNotEmpty) {
        if (mounted && !_disposed && widget.videoUrl.trim() == targetUrl) {
          setState(() {
            _extractedBytes = bytes;
            _isExtracting = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('[ZevVideoThumbnail] Native frame extractor notice: $e');
    }

    if (mounted &&
        !_disposed &&
        widget.videoUrl.trim() == targetUrl &&
        _extractedBytes == null &&
        !_hasUsableThumb &&
        !widget.autoPlay) {
      _initFallbackController();
    }
    _isExtracting = false;
  }

  Future<void> _initFallbackController() async {
    final targetUrl = widget.videoUrl.trim();
    if (_controller != null || targetUrl.isEmpty || _disposed) return;

    VideoPlayerController? controller;
    try {
      controller = targetUrl.startsWith('http')
          ? VideoPlayerController.networkUrl(
              Uri.parse(targetUrl),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            )
          : VideoPlayerController.file(
              File(targetUrl),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            );
      _controller = controller;
      await controller.initialize();
      if (_disposed || !mounted || widget.videoUrl.trim() != targetUrl) {
        await controller.dispose();
        if (identical(_controller, controller)) _controller = null;
        return;
      }
      await controller.setVolume(0.0);
      await controller.pause();
      if (mounted && !_disposed) {
        setState(() {
          _isPlayerInitialized = true;
          _hasFirstFrame = true;
        });
      }
    } catch (e) {
      debugPrint('[ZevVideoThumbnail] Fallback player notice: $e');
      try {
        await controller?.dispose();
      } catch (_) {}
      if (identical(_controller, controller)) {
        _controller = null;
      }
    }
  }

  void _attachFrameListener(VideoPlayerController ctrl) {
    _detachFrameListener(ctrl);
    _playerListener = () {
      if (_disposed || !mounted || !identical(_controller, ctrl)) return;
      final v = ctrl.value;
      if (!_hasFirstFrame &&
          v.isInitialized &&
          (v.position > Duration.zero || v.isPlaying)) {
        setState(() => _hasFirstFrame = true);
      }
    };
    ctrl.addListener(_playerListener!);
  }

  void _detachFrameListener(VideoPlayerController ctrl) {
    if (_playerListener != null) {
      try {
        ctrl.removeListener(_playerListener!);
      } catch (_) {}
      _playerListener = null;
    }
  }

  Future<void> _initPreviewController() async {
    final targetUrl = widget.videoUrl.trim();
    if (targetUrl.isEmpty || _disposed) return;

    if (_controller != null && _controller!.value.isInitialized) {
      await _controller!.setVolume(_isMuted ? 0.0 : 1.0);
      await _controller!.setLooping(true);
      await _controller!.play();
      if (mounted && !_disposed) {
        setState(() {
          _isPlayerInitialized = true;
          _hasFirstFrame = true;
        });
      }
      return;
    }

    VideoPlayerController? controller;
    try {
      controller = targetUrl.startsWith('http')
          ? VideoPlayerController.networkUrl(
              Uri.parse(targetUrl),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            )
          : VideoPlayerController.file(
              File(targetUrl),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            );
      _controller = controller;
      _attachFrameListener(controller);
      await controller.initialize();
      if (_disposed ||
          !mounted ||
          !widget.autoPlay ||
          widget.videoUrl.trim() != targetUrl) {
        _detachFrameListener(controller);
        await controller.dispose();
        if (identical(_controller, controller)) _controller = null;
        return;
      }
      await controller.setVolume(_isMuted ? 0.0 : 1.0);
      await controller.setLooping(true);
      await controller.play();
      if (mounted && !_disposed) {
        setState(() {
          _isPlayerInitialized = true;
          _hasFirstFrame = controller!.value.isPlaying ||
              controller.value.position > Duration.zero;
        });
      }
    } catch (e) {
      debugPrint('[ZevVideoThumbnail] Preview controller notice: $e');
      if (controller != null) {
        _detachFrameListener(controller);
        try {
          await controller.dispose();
        } catch (_) {}
      }
      if (identical(_controller, controller)) {
        _controller = null;
      }
    }
  }

  Future<void> _toggleMute() async {
    HapticFeedback.selectionClick();
    final nextMuted = !_isMuted;
    setState(() => _isMuted = nextMuted);
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller!.setVolume(nextMuted ? 0.0 : 1.0);
      } catch (_) {}
    }
  }

  void _disposeController() {
    final existing = _controller;
    _controller = null;
    _isPlayerInitialized = false;
    _hasFirstFrame = false;
    if (existing != null) {
      _detachFrameListener(existing);
      try {
        existing.pause();
        existing.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeController();
    super.dispose();
  }

  String _formatViews(int count) {
    if (count >= 1000000) {
      return "${(count / 1000000).toStringAsFixed(1)}M";
    } else if (count >= 1000) {
      return "${(count / 1000).toStringAsFixed(1)}K";
    }
    return count.toString();
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(1, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$mins:$secs";
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.zero;
    final showLiveVideo = widget.autoPlay &&
        _isPlayerInitialized &&
        _hasFirstFrame &&
        _controller != null &&
        _controller!.value.isInitialized;

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildStaticCoverLayer(),

            if (_isPlayerInitialized &&
                _controller != null &&
                _controller!.value.isInitialized)
              AnimatedOpacity(
                opacity: (showLiveVideo || !_hasVisualCover) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: SizedBox.expand(
                  child: FittedBox(
                    fit: widget.fit,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: _controller!.value.size.width > 0
                          ? _controller!.value.size.width
                          : 100,
                      height: _controller!.value.size.height > 0
                          ? _controller!.value.size.height
                          : 100,
                      child: VideoPlayer(_controller!),
                    ),
                  ),
                ),
              ),

            // Subtle Bottom Gradient for view-count contrast
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.06),
                        Colors.black.withValues(alpha: 0.42),
                      ],
                      stops: const [0.6, 0.82, 1.0],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),

            // Center Play Button overlay (e.g. for Feed Video slides)
            if (widget.showCenterPlayButton && !showLiveVideo)
              Center(
                child: IgnorePointer(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ZevColors.deepNavy.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: ZevColors.deepNavy,
                      size: 32,
                    ),
                  ),
                ),
              ),

            // Top-Right Reels Video Indicator Badge
            if (widget.showPlayBadge)
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5.5,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ZevColors.border,
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ZevColors.deepNavy.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.movie_rounded,
                        color: ZevColors.deepNavy,
                        size: 13,
                      ),
                      if (widget.durationSeconds != null &&
                          widget.durationSeconds! > 0) ...[
                        const SizedBox(width: 3),
                        Text(
                          _formatDuration(widget.durationSeconds!),
                          style: const TextStyle(
                            color: ZevColors.deepNavy,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // Interactive Mute/Unmute Toggle (Quick Peek / Auto-Play Previews)
            if (widget.showMuteToggle && widget.autoPlay)
              Positioned(
                bottom: 10,
                right: 10,
                child: GestureDetector(
                  onTap: _toggleMute,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.32),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      _isMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              ),

            // Bottom-Left View Count Badge
            if (widget.showViews &&
                widget.viewsCount != null &&
                widget.viewsCount! > 0)
              Positioned(
                bottom: 6,
                left: 7,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _formatViews(widget.viewsCount!),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 4),
                        ],
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

  bool get _hasVisualCover => _extractedBytes != null || _hasUsableThumb;

  Widget _buildStaticCoverLayer() {
    if (_extractedBytes != null) {
      return Image.memory(
        _extractedBytes!,
        fit: widget.fit,
        gaplessPlayback: true,
      );
    }

    if (_hasUsableThumb) {
      final thumb = widget.thumbnailUrl!.trim();
      if (thumb.startsWith('http://') || thumb.startsWith('https://')) {
        return CachedNetworkImage(
          imageUrl: thumb,
          fit: widget.fit,
          memCacheWidth: 480,
          memCacheHeight: 640,
          placeholder: (context, url) => _buildAnimatedShimmer(),
          errorWidget: (context, url, error) {
            _onRemoteThumbError();
            return _buildAnimatedShimmer();
          },
        );
      }
      return Image.file(
        File(thumb),
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) {
          _onRemoteThumbError();
          return _buildAnimatedShimmer();
        },
      );
    }

    if (_remoteThumbFailed && !_isExtracting && _extractedBytes == null) {
      return widget.placeholder ?? _buildFallbackFrame();
    }

    return widget.placeholder ?? _buildAnimatedShimmer();
  }

  Widget _buildAnimatedShimmer() {
    return ZevSkeleton(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          color: ZevColors.primaryBlue.withValues(alpha: 0.65),
          size: 28,
        ),
      ),
    );
  }

  Widget _buildFallbackFrame() {
    return Container(
      decoration: BoxDecoration(
        color: ZevColors.softSurface,
        border: Border.all(color: ZevColors.border, width: 0.8),
      ),
      child: Center(
        child: Icon(
          Icons.movie_filter_rounded,
          color: ZevColors.secondaryBlue.withValues(alpha: 0.55),
          size: 28,
        ),
      ),
    );
  }
}
