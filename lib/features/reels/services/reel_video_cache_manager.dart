import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Next-Generation Video RAM Cache & Preloader for ZEV Reels.
/// - Keeps initialized VideoPlayerControllers in RAM memory
/// - Instant replay when scrolling back to previously viewed reels (no reload needed!)
/// - Background preloading of adjacent reels (N+1, N+2) for zero-wait instant play
/// - High-performance LRU cache to safely manage memory
class ReelVideoCacheManager {
  static final ReelVideoCacheManager _instance = ReelVideoCacheManager._internal();
  factory ReelVideoCacheManager() => _instance;
  ReelVideoCacheManager._internal();

  // Maximum active controllers kept in phone RAM
  static const int _maxControllersInRam = 8;

  final Map<String, VideoPlayerController> _controllerCache = {};
  final Map<String, Completer<VideoPlayerController>> _inProgressInit = {};
  final List<String> _lruKeys = [];

  /// Check whether a video is already initialized and stored in phone RAM
  bool isCachedInRam(String videoUrl) {
    final controller = _controllerCache[videoUrl];
    return controller != null && controller.value.isInitialized;
  }

  /// Retrieves an already initialized controller from RAM, or initializes and caches it.
  Future<VideoPlayerController> getOrCreateController(
    String videoUrl, {
    bool isMuted = false,
  }) async {
    if (videoUrl.isEmpty) {
      throw ArgumentError("videoUrl cannot be empty");
    }

    // 1. Hit in RAM Cache!
    if (_controllerCache.containsKey(videoUrl)) {
      final controller = _controllerCache[videoUrl]!;
      _touch(videoUrl);
      try {
        controller.setVolume(isMuted ? 0.0 : 1.0);
      } catch (_) {}
      return controller;
    }

    // 2. Currently being initialized in background
    if (_inProgressInit.containsKey(videoUrl)) {
      final controller = await _inProgressInit[videoUrl]!.future;
      try {
        controller.setVolume(isMuted ? 0.0 : 1.0);
      } catch (_) {}
      return controller;
    }

    // 3. Initialize fresh controller and store in RAM
    final completer = Completer<VideoPlayerController>();
    _inProgressInit[videoUrl] = completer;

    try {
      VideoPlayerController controller;
      if (videoUrl.startsWith('http')) {
        controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      } else {
        controller = VideoPlayerController.file(File(videoUrl));
      }

      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(isMuted ? 0.0 : 1.0);

      _controllerCache[videoUrl] = controller;
      _touch(videoUrl);
      _pruneCacheIfNeeded();

      completer.complete(controller);
      return controller;
    } catch (e) {
      debugPrint("ReelVideoCacheManager init warning for $videoUrl: $e");
      completer.completeError(e);
      rethrow;
    } finally {
      _inProgressInit.remove(videoUrl);
    }
  }

  /// Preloads a list of video URLs into RAM in background so user never waits.
  void preloadVideos(List<String> videoUrls, {bool isMuted = true}) {
    for (final url in videoUrls) {
      if (url.isEmpty || _controllerCache.containsKey(url) || _inProgressInit.containsKey(url)) {
        continue;
      }
      // Fire-and-forget background preload
      unawaited(getOrCreateController(url, isMuted: isMuted).catchError((err) {
        debugPrint("Background preload skipped: $err");
        return _controllerCache[url] ?? VideoPlayerController.networkUrl(Uri.parse(url));
      }));
    }
  }

  /// Pauses all controllers in RAM except the active one
  void pauseAllExcept(String? activeUrl) {
    _controllerCache.forEach((url, controller) {
      if (url != activeUrl) {
        try {
          if (controller.value.isPlaying) {
            controller.pause();
          }
        } catch (_) {}
      }
    });
  }

  /// Safely manages RAM capacity by disposing oldest controllers when exceeding threshold
  void _pruneCacheIfNeeded() {
    while (_controllerCache.length > _maxControllersInRam && _lruKeys.isNotEmpty) {
      final oldestUrl = _lruKeys.removeAt(0);
      final controller = _controllerCache.remove(oldestUrl);
      if (controller != null) {
        try {
          controller.pause();
          controller.dispose();
        } catch (_) {}
      }
    }
  }

  void _touch(String key) {
    _lruKeys.remove(key);
    _lruKeys.add(key);
  }

  /// Clears cache when navigating away or on low memory
  void clearAll() {
    for (final controller in _controllerCache.values) {
      try {
        controller.pause();
        controller.dispose();
      } catch (_) {}
    }
    _controllerCache.clear();
    _inProgressInit.clear();
    _lruKeys.clear();
  }
}

