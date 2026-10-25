import 'dart:async';

import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/utils/stream_headers.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'player_provider.g.dart';

enum VideoFitMode { fitScreen, fill, ratio16x9, ratio4x3, center, bestFit }

extension VideoFitModeLabel on VideoFitMode {
  String get label => switch (this) {
    VideoFitMode.fitScreen => 'Fit Screen',
    VideoFitMode.fill => 'Fill',
    VideoFitMode.ratio16x9 => '16:9',
    VideoFitMode.ratio4x3 => '4:3',
    VideoFitMode.center => 'Center',
    VideoFitMode.bestFit => 'Best Fit',
  };
}

@immutable
class PlayerState {
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final bool isPlaying;
  final bool isBuffering;
  final bool isSeeking;
  final bool isOpening;
  final String? playbackError;
  final double playbackSpeed;
  final List<String> subtitle;
  final BoxFit fit;
  final VideoFitMode fitMode;
  final double subtitleDelay;
  final bool isRepeating;

  const PlayerState({
    required this.position,
    required this.duration,
    required this.buffer,
    required this.isPlaying,
    required this.isBuffering,
    required this.isSeeking,
    required this.isOpening,
    this.playbackError,
    required this.playbackSpeed,
    required this.subtitle,
    required this.fit,
    required this.fitMode,
    this.subtitleDelay = 0,
    this.isRepeating = false,
  });

  factory PlayerState.initial() => const PlayerState(
    position: Duration.zero,
    duration: Duration.zero,
    buffer: Duration.zero,
    isPlaying: false,
    isBuffering: false,
    isSeeking: false,
    isOpening: false,
    playbackSpeed: 1,
    subtitle: [],
    fit: BoxFit.contain,
    fitMode: VideoFitMode.fitScreen,
  );

  PlayerState copyWith({
    Duration? position,
    Duration? duration,
    Duration? buffer,
    bool? isPlaying,
    bool? isBuffering,
    bool? isSeeking,
    bool? isOpening,
    String? playbackError,
    bool clearPlaybackError = false,
    double? playbackSpeed,
    List<String>? subtitle,
    BoxFit? fit,
    VideoFitMode? fitMode,
    double? subtitleDelay,
    bool? isRepeating,
  }) => PlayerState(
    position: position ?? this.position,
    duration: duration ?? this.duration,
    buffer: buffer ?? this.buffer,
    isPlaying: isPlaying ?? this.isPlaying,
    isBuffering: isBuffering ?? this.isBuffering,
    isSeeking: isSeeking ?? this.isSeeking,
    isOpening: isOpening ?? this.isOpening,
    playbackError:
        clearPlaybackError ? null : (playbackError ?? this.playbackError),
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    subtitle: subtitle ?? this.subtitle,
    fit: fit ?? this.fit,
    fitMode: fitMode ?? this.fitMode,
    subtitleDelay: subtitleDelay ?? this.subtitleDelay,
    isRepeating: isRepeating ?? this.isRepeating,
  );
}

@Riverpod(keepAlive: true)
class PlayerStateNotifier extends _$PlayerStateNotifier {
  late final BetterPlayerController betterPlayerController;
  final StreamController<bool> _completedController =
      StreamController<bool>.broadcast();
  String? _lastUrl;
  Map<String, String>? _lastHeaders;
  bool _lastIsHls = false;
  Duration? _pendingSeekTarget;
  Timer? _seekTimeout;
  Timer? _startupTimer;
  String? _activeMediaId;
  int? _activeEpisode;
  Duration _lastStablePosition = Duration.zero;
  int _openGeneration = 0;
  bool _completionEmitted = false;
  bool _videoListenerAttached = false;
  bool _isEpisodeTransition = false;

  String? get activeMediaId => _activeMediaId;
  int? get activeEpisode => _activeEpisode;
  Duration get lastStablePosition => _lastStablePosition;
  Duration get currentPosition => state.position;
  Duration get currentDuration => state.duration;
  Stream<bool> get completedStream => _completedController.stream;

  @override
  PlayerState build() {
    betterPlayerController = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: false,
        looping: false,
        allowedScreenSleep: false,
        handleLifecycle: false,
        autoDispose: false,
        expandToFill: true,
        fit: BoxFit.contain,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false,
          showControlsOnInitialize: false,
        ),
        subtitlesConfiguration: const BetterPlayerSubtitlesConfiguration(
          fontSize: 0,
          fontColor: Color(0x00000000),
          outlineEnabled: false,
        ),
        eventListener: _onPlayerEvent,
      ),
    );
    ref.onDispose(_dispose);
    return PlayerState.initial();
  }

  void setActiveSession(String? mediaId, int? episode) {
    if (_activeMediaId != mediaId || _activeEpisode != episode) {
      _lastStablePosition = Duration.zero;
    }
    _activeMediaId = mediaId;
    _activeEpisode = episode;
  }

  bool isCurrentEpisodeLoaded({
    required String? mediaId,
    required int? episode,
  }) {
    return mediaId != null &&
        episode != null &&
        _activeMediaId == mediaId &&
        _activeEpisode == episode &&
        _lastUrl != null &&
        state.playbackError == null &&
        !_completionEmitted &&
        state.duration > Duration.zero;
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.play:
        _startupTimer?.cancel();
        _startupTimer = null;
        state = state.copyWith(
          isPlaying: true,
          isOpening: false,
          isBuffering: false,
          clearPlaybackError: true,
        );
      case BetterPlayerEventType.progress:
        _startupTimer?.cancel();
        _startupTimer = null;
        state = state.copyWith(
          isOpening: false,
          clearPlaybackError: true,
        );
      case BetterPlayerEventType.bufferingStart:
        state = state.copyWith(isBuffering: true);
      case BetterPlayerEventType.bufferingEnd:
        state = state.copyWith(
          isBuffering: false,
          isOpening: state.isPlaying ? false : null,
        );
      case BetterPlayerEventType.finished:
        if (!_completionEmitted) {
          _completionEmitted = true;
          _completedController.add(true);
        }
      case BetterPlayerEventType.exception:
        _startupTimer?.cancel();
        state = state.copyWith(
          isOpening: false,
          isBuffering: false,
          playbackError:
              'This server could not play the episode. Try another server.',
        );
      default:
        break;
    }
  }

  void _attachVideoListener() {
    final video = betterPlayerController.videoPlayerController;
    if (video == null || _videoListenerAttached) return;
    video.addListener(_syncVideoState);
    _videoListenerAttached = true;
    _syncVideoState();
  }

  void _syncVideoState() {
    final value = betterPlayerController.videoPlayerController?.value;
    if (value == null) return;
    var pos = value.position;
    final rawDuration = value.duration ?? Duration.zero;

    if (_isEpisodeTransition) {
      if (pos > const Duration(seconds: 3) &&
          (_lastStablePosition == Duration.zero ||
              pos > _lastStablePosition + const Duration(seconds: 5))) {
        // Stale position leaking from previous episode! Suppress it.
        pos = _lastStablePosition;
      } else {
        _isEpisodeTransition = false;
      }
    }

    if ((pos > Duration.zero || value.isPlaying) && !_isEpisodeTransition) {
      _startupTimer?.cancel();
      _startupTimer = null;
      _lastStablePosition = pos;
    }
    if (value.isPlaying) {
      try {
        WakelockPlus.enable();
      } catch (_) {}
    }
    final target = _pendingSeekTarget;
    final landed =
        target != null && (pos - target).abs() <= const Duration(seconds: 2);
    final isActuallyBuffering = value.isBuffering || (target != null && !landed);
    if (landed && !value.isBuffering) {
      _pendingSeekTarget = null;
      _seekTimeout?.cancel();
    }
    final duration =
        rawDuration <= const Duration(hours: 6) ? rawDuration : state.duration;
    var buffer = Duration.zero;
    for (final range in value.buffered) {
      if (range.end > buffer) buffer = range.end;
    }
    final subtitlePosition =
        pos + Duration(milliseconds: (state.subtitleDelay * 1000).round());
    final subtitle = betterPlayerController.subtitlesLines
        .where(
          (line) =>
              line.start != null &&
              line.end != null &&
              subtitlePosition >= line.start! &&
              subtitlePosition <= line.end!,
        )
        .expand((line) => line.texts ?? const <String>[])
        .toList(growable: false);
    final isActivelyPlaying = value.isPlaying;
    state = state.copyWith(
      position: pos,
      duration: duration,
      buffer: buffer,
      isPlaying: isActivelyPlaying,
      isBuffering: isActuallyBuffering,
      isSeeking: (target != null) ? true : false,
      isOpening: (pos > Duration.zero || isActivelyPlaying) ? false : null,
      subtitle: subtitle,
      clearPlaybackError: pos > Duration.zero || isActivelyPlaying,
    );
  }

  Future<void> open(
    String url,
    Duration? startAt, {
    Map<String, String>? headers,
    String? mediaId,
    int? episode,
    bool? isHls,
  }) async {
    final generation = ++_openGeneration;
    final isSameSession =
        !_isEpisodeTransition &&
        mediaId != null &&
        episode != null &&
        mediaId == _activeMediaId &&
        episode == _activeEpisode;
    if (isSameSession) {
      _isEpisodeTransition = false;
    }
    final Duration effectiveStartAt;
    if (startAt != null) {
      effectiveStartAt = startAt > Duration.zero ? startAt : Duration.zero;
    } else if (isSameSession && _lastStablePosition > Duration.zero) {
      effectiveStartAt = _lastStablePosition;
    } else {
      effectiveStartAt = Duration.zero;
    }
    _activeMediaId = mediaId;
    _activeEpisode = episode;
    _lastStablePosition = effectiveStartAt;
    final effectiveHeaders = normalizeStreamHeaders(url, headers);
    _lastUrl = url;
    _lastHeaders = effectiveHeaders;
    _lastIsHls =
        isHls ??
        (Uri.tryParse(url)?.path.toLowerCase().endsWith('.m3u8') ?? false);
    _completionEmitted = false;
    state = state.copyWith(
      isOpening: true,
      isBuffering: true,
      clearPlaybackError: true,
      position: effectiveStartAt,
      duration: isSameSession ? state.duration : Duration.zero,
      buffer: Duration.zero,
    );
    _startupTimer?.cancel();
    _startupTimer = Timer(const Duration(seconds: 20), () {
      if (generation == _openGeneration &&
          state.isOpening &&
          state.position == Duration.zero) {
        state = state.copyWith(
          isOpening: false,
          isBuffering: false,
          playbackError:
              'This server did not start in time. Try another server.',
        );
      }
    });
    final oldVideo = betterPlayerController.videoPlayerController;
    if (_videoListenerAttached) {
      oldVideo?.removeListener(_syncVideoState);
      _videoListenerAttached = false;
    }
    final source =
        url.startsWith('http')
            ? BetterPlayerDataSource.network(
              url,
              headers: effectiveHeaders,
              videoFormat: _lastIsHls ? BetterPlayerVideoFormat.hls : null,
              bufferingConfiguration: const BetterPlayerBufferingConfiguration(
                // Fast startup & high reservoir: start playing at 1000ms,
                // resume after rebuffer at 1500ms, and keep up to 300s (5 mins) buffer reservoir.
                minBufferMs: 60000,
                maxBufferMs: 300000,
                bufferForPlaybackMs: 1000,
                bufferForPlaybackAfterRebufferMs: 1500,
              ),
            )
            : BetterPlayerDataSource.file(url);
    try {
      await betterPlayerController.setupDataSource(source);
      if (generation != _openGeneration) return;
      _attachVideoListener();
      if (effectiveStartAt > Duration.zero) {
        await betterPlayerController.seekTo(effectiveStartAt);
      }
      await betterPlayerController.play();
    } catch (error) {
      AppLogger.e('ExoPlayer setup failed: $error');
      if (generation == _openGeneration) {
        state = state.copyWith(
          isOpening: false,
          isBuffering: false,
          playbackError:
              'This server could not play the episode. Try another server.',
        );
      }
    }
  }

  Future<void> retry() async {
    final url = _lastUrl;
    if (url == null) return;
    await open(
      url,
      state.position > Duration.zero ? state.position : _lastStablePosition,
      headers: _lastHeaders,
      isHls: _lastIsHls,
      mediaId: _activeMediaId,
      episode: _activeEpisode,
    );
  }

  void clearPlaybackError() {
    if (state.playbackError != null) {
      state = state.copyWith(clearPlaybackError: true);
    }
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    return betterPlayerController.play();
  }

  Future<void> pause() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    return betterPlayerController.pause();
  }

  Future<void> stop() async {
    _openGeneration++;
    _seekTimeout?.cancel();
    _startupTimer?.cancel();
    _pendingSeekTarget = null;
    _lastUrl = null;
    _lastHeaders = null;
    _lastIsHls = false;
    _activeMediaId = null;
    _activeEpisode = null;
    _lastStablePosition = Duration.zero;
    _isEpisodeTransition = false;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    await betterPlayerController.pause();
    await betterPlayerController.seekTo(Duration.zero);
    state = PlayerState.initial();
  }

  Future<void> stopIfSession(String mediaId) async {
    if (_activeMediaId == mediaId) await stop();
  }

  void resetForNewEpisode({int? episode}) {
    if (_activeEpisode == episode && state.isPlaying && state.position > Duration.zero) {
      // Episode already actively playing; keep playback smooth
      return;
    }
    _isEpisodeTransition = true;
    _activeEpisode = episode;
    _lastStablePosition = Duration.zero;
    _pendingSeekTarget = null;
    _completionEmitted = false;
    _seekTimeout?.cancel();
    _startupTimer?.cancel();
    if (_videoListenerAttached) {
      betterPlayerController.videoPlayerController?.removeListener(
        _syncVideoState,
      );
      _videoListenerAttached = false;
    }
    state = state.copyWith(
      position: Duration.zero,
      duration: Duration.zero,
      buffer: Duration.zero,
      isPlaying: false,
      isOpening: true,
      isBuffering: true,
      clearPlaybackError: true,
    );
  }

  Future<void> seek(Duration pos) async {
    final clamped = pos < Duration.zero ? Duration.zero : pos;
    _pendingSeekTarget = clamped;
    _seekTimeout?.cancel();
    _seekTimeout = Timer(const Duration(seconds: 4), () {
      if (_pendingSeekTarget == clamped) {
        _pendingSeekTarget = null;
        state = state.copyWith(isSeeking: false, isBuffering: false);
      }
    });
    state = state.copyWith(
      position: clamped,
      isSeeking: true,
      isBuffering: true,
    );
    try {
      await betterPlayerController.seekTo(clamped);
    } catch (error) {
      AppLogger.w('Player seek error: $error');
      _seekTimeout?.cancel();
      _pendingSeekTarget = null;
      state = state.copyWith(isSeeking: false, isBuffering: false);
    }
  }

  void seekRelative(int seconds) =>
      seek((_pendingSeekTarget ?? state.position) + Duration(seconds: seconds));
  void forward(int seconds) => seekRelative(seconds);
  void rewind(int seconds) => seekRelative(-seconds);

  Future<void> setSpeed(double speed) async {
    await betterPlayerController.setSpeed(speed);
    state = state.copyWith(playbackSpeed: speed);
  }

  Future<void> toggleRepeat() async {
    final enabled = !state.isRepeating;
    await betterPlayerController.setLooping(enabled);
    state = state.copyWith(isRepeating: enabled);
  }

  void setFit(BoxFit fit) {
    betterPlayerController.setOverriddenFit(fit);
    state = state.copyWith(fit: fit);
  }

  void setFitMode(VideoFitMode mode) {
    final fit = switch (mode) {
      VideoFitMode.fitScreen => BoxFit.contain,
      VideoFitMode.fill => BoxFit.cover,
      VideoFitMode.ratio16x9 || VideoFitMode.ratio4x3 => BoxFit.fill,
      VideoFitMode.center => BoxFit.none,
      VideoFitMode.bestFit => BoxFit.scaleDown,
    };
    betterPlayerController.setOverriddenFit(fit);
    state = state.copyWith(fit: fit, fitMode: mode);
  }

  VideoFitMode cycleFitMode() {
    final modes = VideoFitMode.values;
    final next = modes[(state.fitMode.index + 1) % modes.length];
    setFitMode(next);
    return next;
  }

  Future<void> setSubtitle(String? url, {Map<String, String>? headers}) async {
    if (url == null || url.isEmpty) {
      betterPlayerController.subtitlesLines = [];
      state = state.copyWith(subtitle: const []);
      return;
    }
    final isNetwork = url.startsWith('http://') || url.startsWith('https://');
    final effectiveHeaders = isNetwork ? (headers ?? _lastHeaders) : null;
    final cleanUrl = url.startsWith('file://')
        ? (Uri.tryParse(url)?.toFilePath() ?? url.replaceFirst('file://', ''))
        : url;
    await betterPlayerController.setupSubtitleSource(
      BetterPlayerSubtitlesSource(
        type: isNetwork
            ? BetterPlayerSubtitlesSourceType.network
            : BetterPlayerSubtitlesSourceType.file,
        urls: [cleanUrl],
        selectedByDefault: true,
        headers: effectiveHeaders,
      ),
    );
  }

  Future<void> setVolume(double volumePercent) =>
      betterPlayerController.setVolume(volumePercent.clamp(0, 100) / 100);
  void volumeUp() => setVolume(100);
  void volumeDown() => setVolume(0);
  void toggleMute() => setVolume(0);

  Future<void> setSubtitleDelay(double seconds) async {
    state = state.copyWith(subtitleDelay: seconds);
    _syncVideoState();
  }

  Future<void> adjustSubtitleDelay(double deltaSeconds) => setSubtitleDelay(
    (((state.subtitleDelay + deltaSeconds) * 10).round() / 10)
        .clamp(-10, 10)
        .toDouble(),
  );

  void _dispose() {
    _seekTimeout?.cancel();
    _startupTimer?.cancel();
    try {
      unawaited(WakelockPlus.disable());
    } catch (_) {}
    if (_videoListenerAttached) {
      betterPlayerController.videoPlayerController?.removeListener(
        _syncVideoState,
      );
    }
    _completedController.close();
    betterPlayerController.dispose(forceDispose: true);
  }
}
