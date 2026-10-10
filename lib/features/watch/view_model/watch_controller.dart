import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:screenshot/screenshot.dart';

import 'package:ani_dash/core/models/aniskip/aniskip_result.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/core/services/audio_focus_service.dart';
import 'package:ani_dash/core/services/notification_service.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/features/watch/view_model/aniskip_notifier.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:ani_dash/features/watch/view_model/watch_progress_notifier.dart';
import 'package:ani_dash/features/watch/view_model/watch_sync_notifier.dart';
import 'package:ani_dash/shared/providers/settings/player_notifier.dart';
import 'package:ani_dash/shared/providers/settings/sync_settings_notifier.dart';
import 'package:ani_dash/shared/providers/continue_watching_dismissed_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/pip_controller.dart';
import 'package:ani_dash/features/watch/view_model/next_episode_prompt_provider.dart';

part 'watch_controller.g.dart';

@riverpod
class WatchController extends _$WatchController with WidgetsBindingObserver {
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<String>? _playbackActionSubscription;
  int? _lastAniSkipEpisode;
  bool _isDisposed = false;
  bool _isPlayerReady = false;

  String? _mediaId, _animeName, _animeFormat, _animeCover;
  int? _malId;
  int _pos = 0, _dur = 0, _totalEps = 0;
  int? _epNum;
  String? _epTitle, _epThumb;

  int _lastSavedPos = -1;
  bool _trackingTriggered = false;
  bool _hasAutoAdvanced = false;
  bool _hasAutoSkippedIntro = false;
  bool _hasAutoSkippedOutro = false;
  bool _fromHentaiHub = false;
  bool _prefetchTriggered = false;
  bool _nextPromptTriggered = false;
  bool _episodeTransitionInProgress = false;
  bool _wasPlayingBeforeLock = false;
  bool _isAppInBackground = false;
  int _savedPosBeforeLock = 0;
  Timer? _pendingAutoSkipTimer;

  @override
  void build() {
    WidgetsBinding.instance.addObserver(this);

    _playbackActionSubscription = NotificationService().onPlaybackAction.listen(
      (action) {
        if (_isDisposed) return;
        if (action == 'play_pause') {
          ref
              .read(playerStateProvider.notifier)
              .videoController
              .player
              .playOrPause();
        } else if (action == 'prev') {
          ref.read(episodeDataProvider.notifier).changeEpisode(null, by: -1);
        } else if (action == 'next') {
          ref.read(episodeDataProvider.notifier).changeEpisode(null, by: 1);
        }
      },
    );

    ref.onDispose(() {
      unawaited(cleanup());
      WidgetsBinding.instance.removeObserver(this);
    });
  }

  Future<void> cleanup() async {
    if (_isDisposed) return;
    // Persist the last known position before the player is unloaded. Awaiting
    // this path prevents a quick back/close from losing the final seconds.
    await _triggerSave(force: true);
    _isDisposed = true;
    _wasPlayingBeforeLock = false;
    _isAppInBackground = false;
    _completedSubscription?.cancel();
    _playbackActionSubscription?.cancel();
    _pendingAutoSkipTimer?.cancel();
    NotificationService().hidePlaybackNotification();
    AudioFocusService().reset();
    try {
      ref.read(playerStateProvider.notifier).setActiveSession(null, null);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (ref.read(pipProvider)) {
        // App is playing in Picture-in-Picture! Do not pause.
        _isAppInBackground = false;
        return;
      }
      _isAppInBackground = true;
      _savedPosBeforeLock = _pos;
      final isPlaying = ref.read(playerStateProvider).isPlaying;
      if (isPlaying && !_isDisposed) {
        _wasPlayingBeforeLock = true;
        // Pause safely before hardware rendering surface detaches to keep MPV memory cache intact
        ref.read(playerStateProvider.notifier).pause();
      }
      if (_savedPosBeforeLock > 0) {
        _triggerSave(targetPos: _savedPosBeforeLock);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isDisposed || !AudioFocusService().isSessionActive) {
        _wasPlayingBeforeLock = false;
        _isAppInBackground = false;
        return;
      }

      // If Next Episode prompt was mistakenly triggered while backgrounded, dismiss it
      ref.read(nextEpisodePromptProvider.notifier).dismiss();

      // Check if position was corrupted to EOF or 0 by hardware surface detachment in background
      final currentPos = ref.read(playerStateProvider).position.inSeconds;
      if (_savedPosBeforeLock > 0 &&
          (_savedPosBeforeLock < _dur - 15) &&
          (currentPos >= _dur - 2 || currentPos == 0)) {
        AppLogger.i(
          'Restoring position after app resume: $_savedPosBeforeLock s (was corrupted to $currentPos s)',
        );
        ref
            .read(playerStateProvider.notifier)
            .seek(Duration(seconds: _savedPosBeforeLock));
        _pos = _savedPosBeforeLock;
      }

      _isAppInBackground = false;

      if (AudioFocusService().isPausedByInterruption) {
        // App returned to foreground after call interruption while video was actively being watched
        AudioFocusService().requestAudioFocus().then((granted) {
          if (granted &&
              !_isDisposed &&
              AudioFocusService().isSessionActive &&
              AudioFocusService().isPausedByInterruption) {
            AudioFocusService().isPausedByInterruption = false;
            ref.read(playerStateProvider.notifier).play();
          }
        });
      } else if (_wasPlayingBeforeLock) {
        _wasPlayingBeforeLock = false;
        // Cleanly resume from existing buffer without re-fetching stream from network
        ref.read(playerStateProvider.notifier).play();
      }
    }
  }

  void setScreenshotController(ScreenshotController controller) {
    ref
        .read(watchProgressProvider.notifier)
        .setScreenshotController(controller);
  }

  Future<void> initialize({
    required String animeName,
    required String? animeId,
    required List<EpisodeDataModel> episodes,
    required int initialEpisode,
    required String mediaId,
    required String? animeFormat,
    required String animeCover,
    int? malId,
    int? startAtPosition,
    bool fromHentaiHub = false,
    bool forceRefetch = false,
  }) async {
    _isDisposed = false;
    _wasPlayingBeforeLock = false;

    // If the player has an active session for a different anime, stop and clear it
    final playerNotifier = ref.read(playerStateProvider.notifier);
    if (playerNotifier.activeMediaId != null &&
        playerNotifier.activeMediaId != mediaId) {
      AppLogger.i(
        'Clearing stale player session: ${playerNotifier.activeMediaId} -> $mediaId',
      );
      await playerNotifier.stop();
    }

    final savedProgress = ref.read(watchProgressRepositoryProvider).getProgress(mediaId);
    final resolvedFormat = (animeFormat?.trim().isNotEmpty == true)
        ? animeFormat
        : savedProgress?.animeFormat;

    final nameLower = animeName.toLowerCase();
    final isMovie = (resolvedFormat?.toUpperCase() == 'MOVIE') ||
        nameLower.contains('the very final') ||
        nameLower.contains('movie') ||
        nameLower.contains('film') ||
        (episodes.length <= 1 && (resolvedFormat?.toUpperCase() == 'MOVIE'));

    _mediaId = mediaId;
    _animeName = animeName;
    _animeFormat = resolvedFormat ?? (isMovie ? 'MOVIE' : null);
    _animeCover = animeCover;
    _totalEps = episodes.length;
    _fromHentaiHub = fromHentaiHub;
    _malId = malId;

    await ref
        .read(episodeListProvider.notifier)
        .fetchEpisodes(
          animeTitle: animeName,
          animeId: animeId,
          mediaId: mediaId,
          malId: malId,
          animeCover: animeCover,
          episodes: episodes,
          force: false,
          isAdult: fromHentaiHub,
          isMovie: isMovie,
        );

    // Resolve the initial episode metadata before the first progress save.
    // Previously only later episode changes populated these fields, so the
    // first Continue Watching card permanently inherited the anime cover.
    final resolvedEpisodes = ref.read(episodeListProvider).episodes;
    try {
      final initialInfo = resolvedEpisodes.firstWhere(
        (episode) => episode.number == initialEpisode,
      );
      _epTitle = isMovie ? animeName : initialInfo.title;
      _epThumb = initialInfo.thumbnail;
    } catch (_) {
      try {
        final initialInfo = episodes.firstWhere(
          (episode) => episode.number == initialEpisode,
        );
        _epTitle = isMovie ? animeName : initialInfo.title;
        _epThumb = initialInfo.thumbnail;
      } catch (_) {
        _epTitle = isMovie ? animeName : 'Episode $initialEpisode';
        _epThumb = animeCover;
      }
    }

    AudioFocusService().initialize(
      onPauseRequested: () async {
        if (_isDisposed) return;
        final wasPlaying = ref.read(playerStateProvider).isPlaying;
        AudioFocusService().isPausedByInterruption = wasPlaying;
        if (wasPlaying) {
          await ref.read(playerStateProvider.notifier).pause();
        }
      },
      onResumeRequested: () async {
        if (_isDisposed) return;
        await ref.read(playerStateProvider.notifier).play();
      },
    );

    await _initEpisode(
      mediaId,
      initialEpisode,
      startAtPosition: startAtPosition,
      forceRefetch: forceRefetch,
    );
    _attachPlaybackListeners(mediaId, animeName, episodes);
  }

  Future<void> _initEpisode(
    String? mediaId,
    int initialEpisode, {
    int? startAtPosition,
    bool forceRefetch = false,
  }) async {
    if (mediaId == null) return;

    _isPlayerReady = false;
    _epNum = initialEpisode;

    // Immediately restore if previously dismissed and update repository so Continue Watching jumps to #1
    ref
        .read(continueWatchingDismissedProvider.notifier)
        .restoreIfWatched(mediaId);
    ref
        .read(watchProgressRepositoryProvider)
        .updateCurrentEpisode(
          mediaId,
          initialEpisode,
          animeTitle: _animeName,
          animeCover: _animeCover,
          animeFormat: _animeFormat,
        );

    final playerNotifier = ref.read(playerStateProvider.notifier);
    final isAlreadyLoaded =
        !forceRefetch &&
        playerNotifier.isCurrentEpisodeLoaded(
          mediaId: mediaId,
          episode: initialEpisode,
        );

    if (isAlreadyLoaded) {
      AppLogger.i(
        '⚡ Instant-resuming active session for $mediaId Ep $initialEpisode (buffer & demuxer preserved)',
      );
      _isPlayerReady = true;
      _pos = playerNotifier.player.state.position.inSeconds;
      _dur = playerNotifier.player.state.duration.inSeconds;

      // If a custom jump position was requested, seek to it immediately
      if (startAtPosition != null && startAtPosition > 0) {
        playerNotifier.seek(Duration(seconds: startAtPosition));
      }

      // Restore saved playback speed if customized
      final savedSpeed = ref.read(playerSettingsProvider).defaultPlaybackSpeed;
      if (savedSpeed != 1.0) {
        playerNotifier.setSpeed(savedSpeed);
      }

      final playerSettings = ref.read(playerSettingsProvider);
      if (playerSettings.enableAniSkip) {
        ref
            .read(aniSkipProvider.notifier)
            .fetchSkipTimes(
              mediaId: mediaId,
              animeTitle: _animeName ?? '',
              episodeNumber: initialEpisode,
              episodeLength: _dur,
              malId: _malId,
            );
      }

      await playerNotifier.play();
      return;
    }

    playerNotifier.setActiveSession(mediaId, initialEpisode);

    Duration startAt = Duration.zero;
    if (startAtPosition != null && startAtPosition > 0) {
      startAt = Duration(seconds: startAtPosition);
      AppLogger.i(
        '⚡ Jumping directly to timestamp ${startAt.inSeconds}s for episode $initialEpisode',
      );
    } else {
      final saved = ref
          .read(watchProgressRepositoryProvider)
          .getEpisodeProgress(mediaId, initialEpisode);
      final savedSeconds = saved?.progressInSeconds ?? 0;
      final savedDuration = saved?.durationInSeconds ?? 0;
      if (savedSeconds > 0 &&
          !(savedDuration > 0 && savedSeconds >= savedDuration - 20)) {
        startAt = Duration(seconds: savedSeconds);
        AppLogger.i(
          'Resuming episode $initialEpisode at ${startAt.inSeconds}s',
        );
      }
    }

    // Restore saved playback speed if customized
    final savedSpeed = ref.read(playerSettingsProvider).defaultPlaybackSpeed;
    if (savedSpeed != 1.0) {
      ref.read(playerStateProvider.notifier).setSpeed(savedSpeed);
    }

    final playerSettings = ref.read(playerSettingsProvider);
    if (playerSettings.enableAniSkip) {
      // Non-blocking: fetch skip times in background asynchronously without blocking stream loading
      ref
          .read(aniSkipProvider.notifier)
          .fetchSkipTimes(
            mediaId: mediaId,
            animeTitle: _animeName ?? '',
            episodeNumber: initialEpisode,
            episodeLength: 0,
            malId: _malId,
          );
    }

    await ref
        .read(episodeDataProvider.notifier)
        .loadEpisode(ep: initialEpisode, startAt: startAt, mediaId: mediaId);
  }

  void _attachPlaybackListeners(
    String mediaId,
    String animeName,
    List<EpisodeDataModel> episodes,
  ) {
    void triggerAutoAdvance() {
      if (_isDisposed ||
          _hasAutoAdvanced ||
          !_isPlayerReady ||
          _episodeTransitionInProgress) {
        return;
      }

      // Halt playback if "Stop after this episode" is enabled.
      if (ref.read(playerSettingsProvider).stopAfterCurrentEpisode) {
        AppLogger.i('Stop After This Episode active: Halting auto-advance.');
        ref
            .read(playerSettingsProvider.notifier)
            .updateSettings((s) => s.copyWith(stopAfterCurrentEpisode: false));
        ref.read(playerStateProvider.notifier).pause();
        return;
      }

      final epList = ref.read(episodeListProvider).episodes;
      final effectiveTotal = _totalEps > 0 ? _totalEps : epList.length;
      if (effectiveTotal <= 1) return;
      _hasAutoAdvanced = true;
      var target = (_epNum ?? 0) + 1;
      if (target > effectiveTotal) return;
      if (ref.read(playerSettingsProvider).skipFillerEpisodes) {
        while (target <= effectiveTotal) {
          EpisodeDataModel? episode;
          for (final item in epList) {
            if (item.number == target) {
              episode = item;
              break;
            }
          }
          if (episode?.isFiller != true) break;
          target++;
        }
      }
      if (target > effectiveTotal) return;
      AppLogger.i('Auto-advancing to episode $target');
      ref.read(episodeDataProvider.notifier).changeEpisode(target);
    }

    ref.listen(pipProvider, (prev, inPiP) {
      if (inPiP) {
        _isAppInBackground = false;
        _wasPlayingBeforeLock = false;
      }
    });

    _completedSubscription?.cancel();
    _completedSubscription = ref
        .read(playerStateProvider.notifier)
        .videoController
        .player
        .stream
        .completed
        .distinct()
        .listen((completed) {
          if (!completed) {
            _hasAutoAdvanced = false;
            return;
          }
          if (_isAppInBackground) {
            // Screen off / app in background caused surface loss or pause; ignore false EOF
            return;
          }
          if (_isPlayerReady &&
              _dur > 60 &&
              _pos >= _dur - 2 &&
              !_hasAutoAdvanced &&
              !_isDisposed) {
            triggerAutoAdvance();
          }
        });

    ref.listen(playerStateProvider, (prev, next) {
      if (_isDisposed || _isAppInBackground) return;

      _pos = next.position.inSeconds;
      _dur = next.duration.inSeconds;

      // `selectedEpisode` changes before the new stream is opened. Ignore the
      // previous episode's final position until the replacement open begins;
      // otherwise its 95% state immediately re-shows the prompt as Ep N+2.
      if (_episodeTransitionInProgress &&
          next.isOpening &&
          ref.read(playerStateProvider.notifier).activeEpisode == _epNum) {
        _episodeTransitionInProgress = false;
      }

      if (next.playbackError != null &&
          next.playbackError != prev?.playbackError &&
          !_isAppInBackground) {
        unawaited(
          ref.read(episodeDataProvider.notifier).recoverFromPlaybackFailure(),
        );
      }

      // Fetch skip ranges as soon as the manifest duration is known. This lets
      // auto-skip seek before the opening frames have to begin rendering.
      if (_dur > 30) _checkAniSkip(mediaId, animeName, next.duration);

      if (next.isPlaying && !(prev?.isPlaying ?? false)) {
        AudioFocusService().requestAudioFocus();
        // MPV may finish creating its Android audio output after the first
        // playing event. Reassert our focus listener once that settles so an
        // incoming call is delivered to AniDash instead of only muting audio.
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          if (!_isDisposed && ref.read(playerStateProvider).isPlaying) {
            AudioFocusService().requestAudioFocus();
          }
        });
      }

      if (!_isPlayerReady) {
        if (_dur == 0 || next.position.inSeconds == 0) return;
        _isPlayerReady = true;
      }

      _checkAutoSkip(next.position);
      if (_dur > 120 && _pos >= _dur - 1) triggerAutoAdvance();

      // Flow optimizations: 85% pre-fetch & 95% next episode prompt
      if (!_episodeTransitionInProgress && _dur > 60) {
        final progressRatio = _pos / _dur;

        // 85% Trigger: Pre-fetch next episode stream in background
        if (!_prefetchTriggered && progressRatio >= 0.85) {
          _prefetchTriggered = true;
          ref.read(episodeDataProvider.notifier).prefetchNextEpisode();
        }

        final hasDetectedOutro = ref.read(aniSkipProvider).any((skip) {
          final interval = skip.interval;
          if (interval == null) return false;
          return skip.skipType == SkipType.ed ||
              (skip.skipType == SkipType.mixed && interval.startTime > 300);
        });

        final isInDetectedOutro = ref.read(aniSkipProvider).any((skip) {
          final interval = skip.interval;
          if (interval == null) return false;
          final isOutro =
              skip.skipType == SkipType.ed ||
              (skip.skipType == SkipType.mixed && interval.startTime > 300);
          return isOutro &&
              _pos >= interval.startTime.floor() &&
              _pos < interval.endTime.ceil();
        });

        // User requirement: Prompt appears immediately when outro begins.
        // If there is NO outro detected, only appear exactly 90 seconds before the episode ends.
        final remainingSeconds = _dur - _pos;
        final shouldTriggerNextPrompt = hasDetectedOutro
            ? isInDetectedOutro
            : (remainingSeconds <= 90 && remainingSeconds > 0 && _dur > 90);

        final hasNextEpisode =
            (_epNum ?? 0) > 0 && (_totalEps <= 0 || (_epNum ?? 0) < _totalEps);
        if (!_nextPromptTriggered &&
            hasNextEpisode &&
            shouldTriggerNextPrompt) {
          _nextPromptTriggered = true;
          final settings = ref.read(playerSettingsProvider);
          if (settings.showNextEpisodePrompt) {
            ref.read(nextEpisodePromptProvider.notifier).show();
          }
        }
      }

      final syncPercentage = ref.read(syncSettingsProvider).syncPercentage;
      if (!_trackingTriggered &&
          _dur > 0 &&
          (_pos / _dur * 100) >= syncPercentage) {
        _trackingTriggered = true;
        if ((_epNum ?? 0) > 0) {
          ref
              .read(watchSyncProvider.notifier)
              .handleTrackingUpdate(mediaId: mediaId, episodeNum: _epNum!);
        }
      }

      _handlePeriodicSave();
    });

    ref.listen(aniSkipProvider, (previous, next) {
      if (_isDisposed ||
          !ref.read(playerSettingsProvider).enableAutoSkip ||
          next.isEmpty) {
        return;
      }
      final position = ref.read(playerStateProvider).position;
      _checkAutoSkip(position);
    });

    ref.listen(episodeDataProvider.select((p) => p.selectedEpisode), (
      prev,
      next,
    ) {
      if (prev != null && prev != next && _epNum == prev) {
        saveProgressManual(takeScreenshot: true);
      }

      if (next != null) {
        _episodeTransitionInProgress = true;
        ref.read(aniSkipProvider.notifier).clear();
        _hasAutoSkippedIntro = false;
        _hasAutoSkippedOutro = false;
        _pendingAutoSkipTimer?.cancel();
        _lastAniSkipEpisode = null;
        _epNum = next;
        _pos = 0;
        _dur = 0;
        _trackingTriggered = false;
        _prefetchTriggered = false;
        _nextPromptTriggered = false;
        _isPlayerReady = false;
        ref
            .read(nextEpisodePromptProvider.notifier)
            .dismissForEpisodeTransition();
        ref.read(watchProgressProvider.notifier).resetLastSavedPosition();

        try {
          final currentEpisodes = ref.read(episodeListProvider).episodes;
          final epInfo = currentEpisodes.firstWhere(
            (e) => e.number == next,
            orElse: () => episodes.firstWhere((e) => e.number == next),
          );
          _epTitle = epInfo.title;
          _epThumb = epInfo.thumbnail;
        } catch (_) {}
      }
    });
  }

  Future<void> _handlePeriodicSave() async {
    if (_lastSavedPos == -1) _lastSavedPos = _pos;

    if ((_pos - _lastSavedPos).abs() >= 5) {
      _lastSavedPos = _pos;
      _triggerSave(takeScreenshot: false);
      if (_mediaId != null && _epNum != null && _pos > 0) {
        ref.read(watchSyncProvider.notifier).syncWatchPosition(
              mediaId: _mediaId!,
              episodeNum: _epNum!,
              progressInSeconds: _pos,
              durationInSeconds: _dur,
            );
      }
    }
  }

  Future<void> _triggerSave({
    bool takeScreenshot = false,
    int? targetPos,
    bool force = false,
  }) async {
    if (_mediaId == null || _epNum == null) return;

    final savePos = targetPos ?? _pos;

    final newThumb = await ref
        .read(watchProgressProvider.notifier)
        .saveProgress(
          mediaId: _mediaId!,
          animeName: _animeName!,
          animeFormat: _animeFormat,
          animeCover: _animeCover!,
          totalEps: _totalEps,
          epNum: _epNum!,
          epTitle: _epTitle,
          epThumb: _epThumb,
          pos: savePos,
          dur: _dur,
          takeScreenshot: takeScreenshot,
          isAdult: _fromHentaiHub,
          force: force,
        );

    if (newThumb != null) _epThumb = newThumb;
  }

  Future<void> saveProgressManual({
    bool takeScreenshot = false,
    bool force = false,
  }) async {
    if (_isDisposed) return;
    await _triggerSave(takeScreenshot: takeScreenshot, force: force);
    if (_mediaId != null && _epNum != null && _pos > 0) {
      ref.read(watchSyncProvider.notifier).syncWatchPosition(
            mediaId: _mediaId!,
            episodeNum: _epNum!,
            progressInSeconds: _pos,
            durationInSeconds: _dur,
            force: true,
          );
    }
  }

  void _checkAniSkip(String mediaId, String animeName, Duration duration) {
    if (!ref.read(playerSettingsProvider).enableAniSkip) {
      ref.read(aniSkipProvider.notifier).clear();
      return;
    }

    final epNum = _epNum;
    if (epNum == null) return;

    // This runs from the position listener. Re-fetching on every frame until
    // an ED interval arrives floods AniSkip/JustAnime requests and competes
    // directly with HLS segment downloads, which can produce recurring
    // two-second buffering on slower connections.
    if (epNum == _lastAniSkipEpisode) return;

    _lastAniSkipEpisode = epNum;
    ref
        .read(aniSkipProvider.notifier)
        .fetchSkipTimes(
          mediaId: mediaId,
          animeTitle: animeName,
          episodeNumber: epNum,
          episodeLength: duration.inSeconds,
          malId: _malId,
        );
  }

  void _checkAutoSkip(Duration position) {
    if (!ref.read(playerSettingsProvider).enableAutoSkip) return;

    // Never seek an old/empty MPV session while the replacement media is
    // still opening. Seeking before the manifest is ready can leave some HLS
    // episodes indefinitely on "Starting video". The position listener calls
    // this again as soon as the first frame advances.
    final playerState = ref.read(playerStateProvider);
    if (playerState.isOpening ||
        playerState.duration <= Duration.zero ||
        position <= Duration.zero) {
      return;
    }

    final skips = ref.read(aniSkipProvider);
    for (final skip in skips) {
      if (skip.interval == null) continue;
      final isIntro =
          skip.skipType == SkipType.op ||
          (skip.skipType == SkipType.mixed && skip.interval!.startTime <= 300);
      final isOutro =
          skip.skipType == SkipType.ed ||
          (skip.skipType == SkipType.mixed && skip.interval!.startTime > 300);

      if (isIntro && _hasAutoSkippedIntro) continue;
      if (isOutro && _hasAutoSkippedOutro) continue;

      final start = Duration(seconds: skip.interval!.startTime.toInt());
      final end = Duration(seconds: skip.interval!.endTime.toInt() + 1);

      final validType =
          skip.skipType == SkipType.op ||
          skip.skipType == SkipType.ed ||
          skip.skipType == SkipType.mixed;
      final length = end - start;
      final isSourceVerified = skip.skipId?.startsWith('source-') ?? false;
      final durationMatches =
          skip.episodeLength > 0 && (skip.episodeLength - _dur).abs() <= 90;
      final hasVerifiedEpisodeMatch =
          isSourceVerified ||
          skip.skipId?.isNotEmpty == true ||
          durationMatches;
      final plausiblePlacement =
          (isIntro && start <= const Duration(minutes: 5)) ||
          (isOutro &&
              start.inSeconds >= (_dur * .50) &&
              start >= const Duration(minutes: 5));
      final validTiming =
          start >= Duration.zero &&
          end > start &&
          end <= Duration(seconds: _dur + 3) &&
          length <= const Duration(minutes: 5) &&
          length.inSeconds <= (_dur * 0.25);

      if (validType &&
          validTiming &&
          hasVerifiedEpisodeMatch &&
          plausiblePlacement &&
          position >= start &&
          position < end) {
        if (isIntro) _hasAutoSkippedIntro = true;
        if (isOutro) _hasAutoSkippedOutro = true;
        final scheduledEpisode = _epNum;
        _pendingAutoSkipTimer?.cancel();
        // Keep the manual Skip Intro/Outro action visible for its documented
        // three-second countdown even when auto-skip is enabled. Seeking in
        // the same frame previously made the button impossible to see.
        _pendingAutoSkipTimer = Timer(const Duration(seconds: 3), () {
          if (_isDisposed || _epNum != scheduledEpisode) return;
          final current = ref.read(playerStateProvider).position;
          if (current >= start && current < end) {
            ref.read(playerStateProvider.notifier).seek(end);
          }
        });
        return;
      }
    }
  }
}
