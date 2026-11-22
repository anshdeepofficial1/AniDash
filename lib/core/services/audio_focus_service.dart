import 'dart:async';
import 'package:flutter/services.dart';
import 'package:ani_dash/core/utils/app_logger.dart';

class AudioFocusService {
  static final AudioFocusService _instance = AudioFocusService._internal();
  factory AudioFocusService() => _instance;
  AudioFocusService._internal();

  static const MethodChannel _channel = MethodChannel('shonenx/audio_focus');

  bool isPausedByInterruption = false;
  bool isSessionActive = false;

  Future<bool> Function()? _onPauseRequested;
  Future<bool> Function()? _onResumeRequested;
  bool _isInitialized = false;

  void initialize({
    required Future<bool> Function() onPauseRequested,
    required Future<bool> Function() onResumeRequested,
  }) {
    _onPauseRequested = onPauseRequested;
    _onResumeRequested = onResumeRequested;
    isSessionActive = true;
    isPausedByInterruption = false;

    if (!_isInitialized) {
      _isInitialized = true;
      _channel.setMethodCallHandler(_handleMethodCall);
      AppLogger.i('[AudioFocusService] Initialized audio focus handler');
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (!isSessionActive) {
      AppLogger.d(
        '[AudioFocusService] Ignored focus event (${call.method}): session inactive',
      );
      return;
    }

    switch (call.method) {
      case 'onAudioFocusLossTransient':
        AppLogger.w(
          '[AudioFocusService] Transient focus loss (incoming call / alarm). Pausing video...',
        );
        if (_onPauseRequested != null) {
          final shouldResume = await _onPauseRequested!();
          // Duplicate focus-loss/call-state events must not erase an already
          // pending resume after the first event has paused the player.
          isPausedByInterruption = isPausedByInterruption || shouldResume;
        }
        break;

      case 'onAudioFocusGain':
        AppLogger.success('[AudioFocusService] Audio focus regained.');
        if (isSessionActive && isPausedByInterruption) {
          AppLogger.i(
            '[AudioFocusService] Call ended. Checking whether playback may resume...',
          );
          if (_onResumeRequested != null) {
            final didResume = await _onResumeRequested!();
            // Keep the interruption pending while AniDash is backgrounded.
            // The watch controller consumes it only after the app resumes.
            if (didResume) isPausedByInterruption = false;
          }
        }
        break;

      case 'onAudioFocusLoss':
        AppLogger.w(
          '[AudioFocusService] Permanent focus loss. Pausing video...',
        );
        if (_onPauseRequested != null) {
          await _onPauseRequested!();
        }
        isPausedByInterruption = false;
        break;

      default:
        break;
    }
  }

  Future<bool> requestAudioFocus() async {
    if (!isSessionActive) return false;
    try {
      final res = await _channel.invokeMethod<bool>('requestAudioFocus');
      return res ?? false;
    } catch (e) {
      AppLogger.d('[AudioFocusService] requestAudioFocus error: $e');
      return false;
    }
  }

  Future<void> abandonAudioFocus() async {
    try {
      isPausedByInterruption = false;
      await _channel.invokeMethod('abandonAudioFocus');
    } catch (e) {
      AppLogger.d('[AudioFocusService] abandonAudioFocus error: $e');
    }
  }

  void reset() {
    isSessionActive = false;
    isPausedByInterruption = false;
    _onPauseRequested = null;
    _onResumeRequested = null;
    abandonAudioFocus();
  }
}
