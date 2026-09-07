import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native Picture-in-Picture manager communicating directly with MainActivity over MethodChannel.
class PipService {
  PipService._();
  static final PipService instance = PipService._();

  static const MethodChannel _channel = MethodChannel('com.example.adnetwork/pip');

  /// Reactive notifier for PiP mode state.
  final ValueNotifier<bool> isPipMode = ValueNotifier(false);

  /// Initialize MethodChannel listener. Call once in main() or on app startup.
  void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipModeChanged') {
        final bool inPip = call.arguments as bool? ?? false;
        debugPrint('[PipService] 🔲 onPipModeChanged: $inPip');
        isPipMode.value = inPip;
      }
    });
  }

  /// Check whether Picture-in-Picture is supported by the OS/device.
  Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('isPipSupported');
      return res ?? false;
    } catch (e) {
      debugPrint('[PipService] ⚠️ isSupported check failed: $e');
      return false;
    }
  }

  /// Enter native Android Picture-in-Picture mode with 9:16 aspect ratio.
  Future<bool> enterPip() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('enterPip');
      if (res == true) {
        isPipMode.value = true;
      }
      return res ?? false;
    } catch (e) {
      debugPrint('[PipService] ❌ enterPip error: $e');
      return false;
    }
  }

  /// Exit PiP mode and restore the activity to fullscreen.
  Future<void> exitPip() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('exitPip');
      isPipMode.value = false;
    } catch (e) {
      debugPrint('[PipService] ❌ exitPip error: $e');
    }
  }
}
