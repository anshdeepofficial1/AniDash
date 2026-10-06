import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';

final pipProvider = NotifierProvider<PiPNotifier, bool>(
  PiPNotifier.new,
);

class PiPNotifier extends Notifier<bool> {
  static const MethodChannel _channel = MethodChannel('shonenx/pip');

  @override
  bool build() {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(_handleMethodCall);
      _checkInitialPiPState();
    }
    return false;
  }

  Future<void> _checkInitialPiPState() async {
    try {
      final bool? isPiP = await _channel.invokeMethod<bool>('isPiP');
      if (isPiP != null) {
        state = isPiP;
      }
    } catch (_) {}
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onPiPChanged') {
      final bool inPiP = call.arguments as bool? ?? false;
      AppLogger.i('PiP state changed: $inPiP');
      state = inPiP;
      if (inPiP) {
        // When entering PiP, ensure video continues playing smoothly
        final isPlaying = ref.read(playerStateProvider).isPlaying;
        if (!isPlaying) {
          await ref.read(playerStateProvider.notifier).play();
        }
      }
    } else if (call.method == 'onPiPAction') {
      final String action = call.arguments?.toString() ?? '';
      AppLogger.i('PiP action received: $action');
      if (action == 'play_pause') {
        final playerNotifier = ref.read(playerStateProvider.notifier);
        final isPlaying = ref.read(playerStateProvider).isPlaying;
        if (isPlaying) {
          await playerNotifier.pause();
        } else {
          await playerNotifier.play();
        }
        await updatePlaybackState(!isPlaying);
      } else if (action == 'prev') {
        ref.read(episodeDataProvider.notifier).changeEpisode(null, by: -1);
      } else if (action == 'next') {
        ref.read(episodeDataProvider.notifier).changeEpisode(null, by: 1);
      }
    }
  }

  Future<bool> enterPiP({bool? isPlaying}) async {
    if (!Platform.isAndroid) return false;
    try {
      state = true;
      final playing = isPlaying ?? ref.read(playerStateProvider).isPlaying;
      final res = await _channel.invokeMethod<bool>('enterPiP', {'isPlaying': playing});
      if (res != true) {
        state = false;
      }
      return res ?? false;
    } catch (e) {
      state = false;
      AppLogger.e('Failed to enter PiP: $e');
      return false;
    }
  }

  Future<void> updatePlaybackState(bool isPlaying) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('updatePlaybackState', {'isPlaying': isPlaying});
    } catch (_) {}
  }

  Future<bool> exitPiP() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('exitPiP');
      return res ?? false;
    } catch (e) {
      AppLogger.e('Failed to exit PiP: $e');
      return false;
    }
  }

  Future<bool> closePiP() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('closePiP');
      return res ?? false;
    } catch (e) {
      AppLogger.e('Failed to close PiP: $e');
      return false;
    }
  }

  void setPiPMode(bool value) {
    state = value;
  }
}
