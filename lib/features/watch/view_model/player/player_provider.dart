import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:ani_dash/shared/providers/settings/player_notifier.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/utils/stream_headers.dart';
import 'package:ani_dash/core/network/hls_playback_relay.dart';

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
    this.subtitleDelay = 0.0,
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
    playbackSpeed: 1.0,
    subtitle: [],
    fit: BoxFit.contain,
    fitMode: VideoFitMode.fitScreen,
    subtitleDelay: 0.0,
    isRepeating: false,
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
  }) {
    return PlayerState(
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
}

@Riverpod(keepAlive: true)
class PlayerStateNotifier extends _$PlayerStateNotifier {
  late final Player _player;
  late final VideoController videoController;
  final List<StreamSubscription> _subs = [];
  String? _lastUrl;
  Map<String, String>? _lastHeaders;
  bool _lastIsHls = false;
  HlsPlaybackRelay? _hlsRelay;
  Duration? _pendingSeekTarget;
  Timer? _seekTimeout;
  Timer? _startupTimer;
  String? _activeMediaId;
  int? _activeEpisode;
  Duration _lastStablePosition = Duration.zero;
  bool _automaticRetryInFlight = false;
  Map<String, String> _playbackProperties = const {};
  Map<String, String> _customMpvSettings = const {};
  int _openGeneration = 0;

  Player get player => _player;
  String? get activeMediaId => _activeMediaId;
  int? get activeEpisode => _activeEpisode;
  Duration get lastStablePosition => _lastStablePosition;

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
    if (mediaId == null || episode == null) return false;
    return _activeMediaId == mediaId &&
        _activeEpisode == episode &&
        _lastUrl != null &&
        state.playbackError == null &&
        !_player.state.completed &&
        _player.state.duration > Duration.zero;
  }

  @override
  PlayerState build() {
    final settings = ref.read(playerSettingsProvider);
    final mpvSettings = settings.mpvSettings;
    final vo = mpvSettings['vo'];
    final bufferSize = ref.read(
      playerSettingsProvider.select((s) => s.bufferSize),
    );
    // Leaner, smarter buffer (32 MiB - 96 MiB) prevents Windows pagefile swapping/thrashing
    // when system RAM is heavily utilized by other applications.
    final effectiveBufferBytes = (bufferSize.toInt() * 1024 * 1024).clamp(
      100 * 1024 * 1024,
      256 * 1024 * 1024,
    );
    final backBufferBytes = (effectiveBufferBytes ~/ 5).clamp(
      16 * 1024 * 1024,
      32 * 1024 * 1024,
    );
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: effectiveBufferBytes,
        logLevel: MPVLogLevel.warn,
        vo: vo,
      ),
    );

    _playbackProperties = <String, String>{
      // Hardware acceleration via GPU (DirectX D3D11VA on Windows)
      // relieves CPU and memory bandwidth during high system consumption.
      'hwdec': 'auto-safe',

      // ── High Performance & Anti-Stutter (Low-Latency Profile) ─────────────
      // Automatically drop video frames if presentation falls behind audio clock,
      // preventing slow-motion video lag or stutter when CPU/RAM is maxed out.
      'framedrop': 'vo',
      'hr-seek-framedrop': 'yes',

      // Dedicated demuxer thread isolated from decoding/render thread
      'demuxer-thread': 'yes',

      // Fast, lightweight scaling profile that saves 60-70% GPU shader load
      // so playback stays smooth 60fps even under heavy background system load.
      'profile': 'fast',

      // Multi-threaded decoding (0 = auto select based on CPU core count)
      'vd-lavc-threads': '0',

      // ── Cache / buffer sizing (100 seconds readahead) ─────────────────────
      'cache': 'yes',
      'cache-secs': '600',
      'demuxer-seekable-cache': 'yes',
      'demuxer-max-bytes': effectiveBufferBytes.toString(),
      'demuxer-max-back-bytes': backBufferBytes.toString(),
      'demuxer-readahead-secs': '100',
      'demuxer-hysteresis-secs': '0',

      // ── Instant playback + underrun protection ────────────────────────────
      'cache-pause': 'yes', // Pause gracefully on underrun
      // Starting or resuming with only two seconds buffered caused a visible
      // play/pause loop on segmented HLS hosts. Build a useful reserve first,
      // then keep the 100-second forward cache filling in the background.
      'cache-pause-wait': '8',
      'cache-pause-initial': 'yes',
      // ── Network & Reconnect ───────────────────────────────────────────────
      'network-timeout': '30',
      'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',

      // ── FFmpeg demuxer / HLS probe (tuned for ultra-fast startup) ─────────
      'demuxer-lavf-probesize': '1048576',
      'demuxer-lavf-buffersize': '1048576',
      'demuxer-lavf-analyzeduration': '1.0',

      // ── Seeking & sync ────────────────────────────────────────────────────
      'force-seekable': 'yes',
      'hr-seek': 'default',
      'correct-pts': 'yes',
      'video-sync': 'audio', // Audio-locked sync; prevents A/V drift
    };

    _customMpvSettings =
        Map<String, String>.from(mpvSettings)
          ..remove('vo')
          ..remove('hwdec');

    videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    _attachListeners();

    ref.onDispose(_dispose);

    return PlayerState.initial();
  }

  void _attachListeners() {
    final stream = _player.stream;

    _subs.add(
      stream.position.listen((pos) {
        if (pos > Duration.zero) {
          _startupTimer?.cancel();
          _startupTimer = null;
          _lastStablePosition = pos;
        }
        final target = _pendingSeekTarget;
        final landed =
            target != null &&
            (pos - target).abs() <= const Duration(seconds: 2);
        if (landed) {
          _pendingSeekTarget = null;
          _seekTimeout?.cancel();
        }
        state = state.copyWith(
          position: pos,
          isSeeking: landed ? false : null,
          isOpening: pos > Duration.zero ? false : null,
          clearPlaybackError: pos > Duration.zero,
        );
      }),
    );

    _subs.add(
      stream.duration.listen((dur) {
        // A parsed manifest is not proof that a frame rendered. Keep the
        // startup watchdog alive until playback/position actually advances.
        state = state.copyWith(duration: dur);
      }),
    );

    _subs.add(
      stream.buffer.listen((buf) => state = state.copyWith(buffer: buf)),
    );

    _subs.add(
      stream.buffering.listen((buf) {
        state = state.copyWith(isBuffering: buf);
        if (!buf) {
          // Buffer recovered — cancel watchdog
        }
      }),
    );

    _subs.add(
      stream.playing.listen((play) {
        // MPV can report `playing` as soon as it accepts a manifest, before
        // a frame has rendered. Position advancement is the only reliable
        // startup signal, so the watchdog is cancelled there instead.
        state = state.copyWith(isPlaying: play);
      }),
    );

    _subs.add(
      stream.rate.listen((rate) => state = state.copyWith(playbackSpeed: rate)),
    );

    _subs.add(
      stream.subtitle.listen((subs) => state = state.copyWith(subtitle: subs)),
    );

    _subs.add(
      stream.error.listen((error) {
        // MPV can emit a recoverable stream warning while HLS continues to
        // advance. Retrying immediately in that situation interrupts healthy
        // playback and is the root cause of the visible 2-second/restart loop.
        if (!_automaticRetryInFlight) {
          _automaticRetryInFlight = true;
          unawaited(_handleStreamError(error));
        }
      }),
    );
  }

  Future<void> _handleStreamError(Object error) async {
    final urlAtError = _lastUrl;
    final positionAtError = _player.state.position;
    // A network/demuxer warning can temporarily pause MPV before its regular
    // buffering event arrives. Surface that wait immediately instead of
    // leaving a frozen frame with no feedback.
    state = state.copyWith(isBuffering: true);
    try {
      // HLS may report one failed segment while FFmpeg reconnects. Poll actual
      // position progress instead of treating a transient error or the
      // `playing` flag as proof of failure/recovery.
      var currentPosition = positionAtError;
      for (var attempt = 0; attempt < 10; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (urlAtError == null || urlAtError != _lastUrl) return;
        currentPosition = _player.state.position;
        if (currentPosition > positionAtError + const Duration(seconds: 1)) {
          AppLogger.d('Stream recovered after segment warning: $error');
          state = state.copyWith(isBuffering: false, clearPlaybackError: true);
          return;
        }
      }

      AppLogger.w('Player stream failure after recovery grace period: $error');
      _startupTimer?.cancel();
      _startupTimer = null;
      // Do not reopen the same URL here. The episode provider owns one
      // serialized, language-preserving server failover. Reopening here was
      // racing that provider and sending playback back to the start.
      state = state.copyWith(
        isOpening: false,
        isBuffering: false,
        playbackError: 'Playback failed: $error',
      );
    } finally {
      _automaticRetryInFlight = false;
    }
  }

  void _dispose() {
    _seekTimeout?.cancel();
    _startupTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    if (_hlsRelay != null) {
      unawaited(_hlsRelay!.close());
      _hlsRelay = null;
    }
    _player.dispose();
  }

  Future<void> open(
    String url,
    Duration? startAt, {
    Map<String, String>? headers,
    String? mediaId,
    int? episode,
    bool? isHls,
  }) async {
    final openGeneration = ++_openGeneration;
    final isSameSession =
        mediaId != null &&
        episode != null &&
        mediaId == _activeMediaId &&
        episode == _activeEpisode;
    final requiresPipelineReset =
        !isSameSession ||
        (_lastUrl != null && _lastUrl != url) ||
        _hlsRelay != null;

    // If startAt is explicitly provided, use it. Otherwise, if reopening the same media & episode,
    // preserve the last stable playback position so we don't restart from beginning on stream recovery/reload.
    final effectiveStartAt =
        (startAt != null && startAt > Duration.zero)
            ? startAt
            : (isSameSession && _lastStablePosition > Duration.zero
                ? _lastStablePosition
                : null);

    _activeMediaId = mediaId;
    _activeEpisode = episode;
    if (!isSameSession && effectiveStartAt != null) {
      _lastStablePosition = effectiveStartAt;
    }

    final effectiveHeaders = normalizeStreamHeaders(url, headers);
    _lastUrl = url;
    _lastHeaders = effectiveHeaders;
    _lastIsHls =
        isHls ??
        Uri.tryParse(url)?.path.toLowerCase().endsWith('.m3u8') ??
        false;
    state = state.copyWith(
      isOpening: true,
      clearPlaybackError: true,
      position:
          effectiveStartAt ??
          (isSameSession ? _lastStablePosition : Duration.zero),
      duration: isSameSession ? state.duration : Duration.zero,
    );
    _startupTimer?.cancel();
    if (requiresPipelineReset) {
      // mpv can retain the preceding HLS demuxer/cache when another episode
      // or provider is opened immediately. Stop that session first so the new
      // URL cannot inherit the old demuxer, buffer, or rendered frame.
      try {
        await _player.stop();
      } catch (error) {
        AppLogger.d(
          'Player reset before media switch was not required: $error',
        );
      }
      if (openGeneration != _openGeneration) return;
    }
    // Close the previous relay only after MPV has stopped reading from it.
    final oldRelay = _hlsRelay;
    _hlsRelay = null;
    if (oldRelay != null) await oldRelay.close();
    if (openGeneration != _openGeneration) return;

    // HLS segment requests use the same Dart network stack as downloads.
    // This handles providers whose playlists load in MPV but whose segment
    // requests fail due to missing cookies/referer across redirects.
    var playbackUrl = url;
    var playbackHeaders = effectiveHeaders;
    final uri = Uri.tryParse(url);
    final useLocalHlsRelay =
        Platform.isAndroid &&
        (_lastIsHls || (uri?.path.toLowerCase().endsWith('.m3u8') ?? false));
    if (useLocalHlsRelay) {
      try {
        final relay = await HlsPlaybackRelay.start(url, effectiveHeaders);
        if (openGeneration != _openGeneration) {
          await relay.close();
          return;
        }
        _hlsRelay = relay;
        playbackUrl = relay.localUrl;
        playbackHeaders = const {};
        AppLogger.i('Using authenticated device-local HLS relay');
      } catch (error) {
        AppLogger.w('HLS relay unavailable; opening original URL: $error');
      }
    }

    try {
      // setProperty is asynchronous. The previous fire-and-forget setup raced
      // the first manifest request, so later episodes could open with stale
      // cache/demuxer values from the preceding stream. Apply the complete
      // playback profile in order before every media open.
      await _applyPlaybackProperties();
      final platform = _player.platform as dynamic;
      // ── Apply UA, Referer, and HTTP headers for the new stream ──
      final ua =
          effectiveHeaders.entries
              .firstWhereOrNull(
                (entry) => entry.key.toLowerCase() == 'user-agent',
              )
              ?.value ??
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      final refValue =
          effectiveHeaders.entries
              .firstWhereOrNull((entry) => entry.key.toLowerCase() == 'referer')
              ?.value ??
          '';
      const dedicatedHeaders = {'user-agent', 'referer', 'referrer'};
      final forwardedHeaders = effectiveHeaders.entries
          .where((e) => !dedicatedHeaders.contains(e.key.toLowerCase()))
          .map((e) => '${e.key}: ${e.value}')
          .join(',');

      // Clear stale headers when switching between servers/providers too.
      await platform.setProperty('user-agent', ua);
      await platform.setProperty('referrer', refValue);
      await platform.setProperty('http-header-fields', forwardedHeaders);
    } catch (error) {
      AppLogger.w('Could not apply stream headers before playback: $error');
    }
    if (openGeneration != _openGeneration) return;
    _startupTimer = Timer(const Duration(seconds: 35), () {
      if (openGeneration == _openGeneration &&
          state.isOpening &&
          _player.state.position == Duration.zero) {
        state = state.copyWith(
          isOpening: false,
          playbackError: 'Video startup timed out. Tap Retry to try again.',
        );
      }
    });
    try {
      await _player.open(
        Media(
          playbackUrl,
          httpHeaders: playbackHeaders,
          start: effectiveStartAt,
        ),
        play: true,
      );
    } catch (_) {
      if (openGeneration == _openGeneration) {
        final relay = _hlsRelay;
        _hlsRelay = null;
        if (relay != null) await relay.close();
      }
      rethrow;
    }
  }

  Future<void> _applyPlaybackProperties() async {
    final platform = _player.platform as dynamic;
    for (final entry in _playbackProperties.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (error) {
        AppLogger.d('MPV option ${entry.key} was not accepted: $error');
      }
    }
    for (final entry in _customMpvSettings.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (error) {
        AppLogger.d('Custom MPV option ${entry.key} was not accepted: $error');
      }
    }
  }

  Future<void> retry() async {
    final url = _lastUrl;
    if (url == null) return;
    final currentPos = _player.state.position;
    final pos =
        currentPos > Duration.zero
            ? currentPos
            : (_lastStablePosition > Duration.zero
                ? _lastStablePosition
                : null);
    await open(
      url,
      pos,
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
    final playing = _player.state.playing;
    state = state.copyWith(isPlaying: !playing);
    if (playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();

  Future<void> stop() async {
    _seekTimeout?.cancel();
    _startupTimer?.cancel();
    _pendingSeekTarget = null;
    _lastUrl = null;
    _lastHeaders = null;
    _lastIsHls = false;
    _activeMediaId = null;
    _activeEpisode = null;
    _lastStablePosition = Duration.zero;
    await _player.setPlaylistMode(PlaylistMode.none);
    await _player.stop();
    final relay = _hlsRelay;
    _hlsRelay = null;
    if (relay != null) await relay.close();
    state = PlayerState.initial();
  }

  /// Stops playback only when this player still belongs to [mediaId].
  ///
  /// A watch route can finish its asynchronous cleanup after the user has
  /// already opened another title. Unconditionally stopping the shared player
  /// from that old route would then kill the newly opened video.
  Future<void> stopIfSession(String mediaId) async {
    if (_activeMediaId != mediaId) return;
    await stop();
  }

  Future<void> seek(Duration pos) async {
    _pendingSeekTarget = pos;
    state = state.copyWith(position: pos);
    try {
      await _player.seek(pos);
    } catch (e) {
      AppLogger.w('Player seek error: $e');
    }
  }

  void seekRelative(int seconds) {
    final p =
        (_pendingSeekTarget ?? _player.state.position) +
        Duration(seconds: seconds);
    seek(p);
  }

  void forward(int seconds) {
    final p =
        (_pendingSeekTarget ?? _player.state.position) +
        Duration(seconds: seconds);
    seek(p);
  }

  void rewind(int seconds) {
    final p =
        (_pendingSeekTarget ?? _player.state.position) -
        Duration(seconds: seconds);
    seek(p < Duration.zero ? Duration.zero : p);
  }

  Future<void> setSpeed(double speed) => _player.setRate(speed);

  Future<void> toggleRepeat() async {
    final enabled = !state.isRepeating;
    await _player.setPlaylistMode(
      enabled ? PlaylistMode.single : PlaylistMode.none,
    );
    state = state.copyWith(isRepeating: enabled);
  }

  void setFit(BoxFit fit) => state = state.copyWith(fit: fit);

  void setFitMode(VideoFitMode mode) {
    final fit = switch (mode) {
      VideoFitMode.fitScreen => BoxFit.contain,
      VideoFitMode.fill => BoxFit.cover,
      VideoFitMode.ratio16x9 || VideoFitMode.ratio4x3 => BoxFit.fill,
      VideoFitMode.center => BoxFit.none,
      VideoFitMode.bestFit => BoxFit.scaleDown,
    };
    state = state.copyWith(fit: fit, fitMode: mode);
  }

  VideoFitMode cycleFitMode() {
    final modes = VideoFitMode.values;
    final next = modes[(state.fitMode.index + 1) % modes.length];
    setFitMode(next);
    return next;
  }

  Future<void> setSubtitle(SubtitleTrack track) =>
      _player.setSubtitleTrack(track);

  void volumeUp() =>
      _player.setVolume((_player.state.volume + 10).clamp(0, 100));

  void volumeDown() =>
      _player.setVolume((_player.state.volume - 10).clamp(0, 100));

  void toggleMute() => _player.setVolume(_player.state.volume == 0 ? 100 : 0);

  Future<void> setSubtitleDelay(double seconds) async {
    try {
      final platform = _player.platform as dynamic;
      await platform.setProperty('sub-delay', seconds.toString());
      state = state.copyWith(subtitleDelay: seconds);
      AppLogger.i('Subtitle delay set to: ${seconds}s');
    } catch (e) {
      AppLogger.e('Failed to set subtitle delay: $e');
    }
  }

  Future<void> adjustSubtitleDelay(double deltaSeconds) async {
    final newDelay = ((state.subtitleDelay + deltaSeconds) * 10).round() / 10.0;
    await setSubtitleDelay(newDelay.clamp(-10.0, 10.0));
  }
}
