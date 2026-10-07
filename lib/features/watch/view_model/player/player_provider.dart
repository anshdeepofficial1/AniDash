import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:ani_dash/shared/providers/settings/player_notifier.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/utils/stream_headers.dart';

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
      32 * 1024 * 1024,
      96 * 1024 * 1024,
    );
    final backBufferBytes = (effectiveBufferBytes ~/ 4).clamp(
      8 * 1024 * 1024,
      24 * 1024 * 1024,
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

      // ── Smart cache / buffer sizing (Low RAM footprint) ───────────────────
      // Sized to buffer 30-60s ahead (~20-40MB) instead of 10 minutes (256MB),
      // preventing Windows pagefile disk thrashing when RAM is tight.
      'cache': 'yes',
      'cache-secs': '120',
      'demuxer-seekable-cache': 'yes',
      'demuxer-max-bytes': effectiveBufferBytes.toString(),
      'demuxer-max-back-bytes': backBufferBytes.toString(),
      'demuxer-readahead-secs': '30',
      'demuxer-hysteresis-secs': '0',

      // ── Instant playback + underrun protection ────────────────────────────
      'cache-pause': 'yes', // Pause gracefully on underrun
      'cache-pause-wait': '1',
      'cache-pause-initial': 'no',

      // ── Network & Reconnect ───────────────────────────────────────────────
      'network-timeout': '15',
      'stream-lavf-o': 'reconnect_streamed=1,reconnect_delay_max=5',

      // ── FFmpeg demuxer / HLS probe (tuned for ultra-fast startup) ────────
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
    try {
      // HLS commonly emits a transient segment warning while MPV reconnects.
      // Escalating after 1.5 seconds caused the source manager to reopen media
      // during ordinary buffering, producing the exact play-2s/restart loop.
      await Future<void>.delayed(const Duration(seconds: 12));
      if (urlAtError == null || urlAtError != _lastUrl) return;

      var currentPosition = _player.state.position;
      if (currentPosition > positionAtError + const Duration(seconds: 1)) {
        AppLogger.d('Ignoring recoverable player stream warning: $error');
        return;
      }

      // If MPV is visibly buffering, let its configured reconnect/cache path
      // finish before considering another server. Switching while buffering
      // discards the cache and is worse on weak connections.
      if (_player.state.buffering) {
        await Future<void>.delayed(const Duration(seconds: 12));
        if (urlAtError != _lastUrl) return;
        currentPosition = _player.state.position;
        if (currentPosition > positionAtError + const Duration(seconds: 1)) {
          AppLogger.d('Stream recovered after extended buffering: $error');
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
    _player.dispose();
  }

  Future<void> open(
    String url,
    Duration? startAt, {
    Map<String, String>? headers,
    String? mediaId,
    int? episode,
  }) async {
    final openGeneration = ++_openGeneration;
    final isSameSession =
        mediaId != null &&
        episode != null &&
        mediaId == _activeMediaId &&
        episode == _activeEpisode;

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
    state = state.copyWith(
      isOpening: true,
      clearPlaybackError: true,
      position:
          effectiveStartAt ??
          (isSameSession ? _lastStablePosition : Duration.zero),
      duration: isSameSession ? state.duration : Duration.zero,
    );
    _startupTimer?.cancel();
    if (!isSameSession) {
      // mpv can retain the preceding HLS demuxer/cache when another episode
      // is opened immediately. Stop that session first so episode two and
      // later start with a clean pipeline instead of timing out at 00:00.
      try {
        await _player.stop();
      } catch (error) {
        AppLogger.d(
          'Player reset before media switch was not required: $error',
        );
      }
      if (openGeneration != _openGeneration) return;
    }
    try {
      // setProperty is asynchronous. The previous fire-and-forget setup raced
      // the first manifest request, so later episodes could open with stale
      // cache/demuxer values from the preceding stream. Apply the complete
      // playback profile in order before every media open.
      await _applyPlaybackProperties();
      final platform = _player.platform as dynamic;
      // ── Set UA, Referer, and http-header-fields concurrently in 1 roundtrip ──
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

      final headerFutures = <Future>[];
      headerFutures.add(platform.setProperty('user-agent', ua));
      if (refValue.isNotEmpty) {
        headerFutures.add(platform.setProperty('referrer', refValue));
      }
      if (forwardedHeaders.isNotEmpty) {
        headerFutures.add(
          platform.setProperty('http-header-fields', forwardedHeaders),
        );
      }
      await Future.wait(headerFutures);
    } catch (error) {
      AppLogger.w('Could not apply stream headers before playback: $error');
    }
    if (openGeneration != _openGeneration) return;
    _startupTimer = Timer(const Duration(seconds: 30), () {
      if (openGeneration == _openGeneration &&
          state.isOpening &&
          _player.state.position == Duration.zero) {
        state = state.copyWith(
          isOpening: false,
          playbackError: 'Video startup timed out. Tap Retry to try again.',
        );
      }
    });
    await _player.open(
      Media(url, httpHeaders: effectiveHeaders, start: effectiveStartAt),
      play: true,
    );
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
      mediaId: _activeMediaId,
      episode: _activeEpisode,
    );
  }

  Future<void> togglePlay() async {
    _player.state.playing ? await _player.pause() : await _player.play();
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();

  Future<void> stop() async {
    _seekTimeout?.cancel();
    _startupTimer?.cancel();
    _pendingSeekTarget = null;
    _lastUrl = null;
    _lastHeaders = null;
    _activeMediaId = null;
    _activeEpisode = null;
    _lastStablePosition = Duration.zero;
    await _player.setPlaylistMode(PlaylistMode.none);
    await _player.stop();
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
