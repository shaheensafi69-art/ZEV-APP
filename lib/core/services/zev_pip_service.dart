import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service interfacing with Android OS-level Picture-in-Picture (PiP).
/// Allows video calls to float above other apps when user navigates away
/// from ZEV, ensuring the video and audio streams never freeze or drop.
class ZevPipService {
  ZevPipService._();
  static final ZevPipService instance = ZevPipService._();

  static const _channel = MethodChannel('com.zevapp.app/pip');
  final ValueNotifier<bool> isInPipMode = ValueNotifier(false);

  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    if (!kIsWeb && Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onPipChanged') {
          final isPip = call.arguments == true;
          isInPipMode.value = isPip;
        }
      });
    }
  }

  Future<bool> isSupported() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isPipSupported');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> enableAutoPip({int aspectX = 9, int aspectY = 16}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('enableAutoPip', {
        'aspectX': aspectX,
        'aspectY': aspectY,
      });
    } catch (_) {}
  }

  Future<void> disableAutoPip() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('disableAutoPip');
    } catch (_) {}
  }

  Future<bool> enterPip({int aspectX = 9, int aspectY = 16}) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('enterPip', {
        'aspectX': aspectX,
        'aspectY': aspectY,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}

