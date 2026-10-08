import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:ani_dash/core/models/aniskip/aniskip_result.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/models/anime/source_model.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/core/services/audio_focus_service.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/features/downloads/model/download_item.dart';
import 'package:ani_dash/features/downloads/model/download_status.dart';
import 'package:ani_dash/features/downloads/view_model/downloads_notifier.dart';
import 'package:ani_dash/features/watch/view/widgets/episodes_panel.dart';
import 'package:ani_dash/features/watch/view/widgets/player/shonenx_video_player.dart';
import 'package:ani_dash/features/watch/view_model/aniskip_notifier.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/next_episode_prompt_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/pip_controller.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:ani_dash/router/desktop/windows_caption_buttons.dart';
import 'package:ani_dash/helpers/ui.dart';
import 'package:ani_dash/shared/providers/settings/player_notifier.dart';

class LocalPlayerScreen extends ConsumerStatefulWidget {
  final DownloadItem item;
  final Duration? initialPosition;

  const LocalPlayerScreen({
    super.key,
    required this.item,
    this.initialPosition,
  });

  @override
  ConsumerState<LocalPlayerScreen> createState() => _LocalPlayerScreenState();
}

class _LocalPlayerScreenState extends ConsumerState<LocalPlayerScreen>
    with SingleTickerProviderStateMixin {
  late DownloadItem _currentItem;
  late Duration _startAt;
  int _lastSavedSecond = -1;
  late final AnimationController _panelController;
  late final CurvedAnimation _panelAnimation;
  bool _hasAutoSkippedIntro = false;
  bool _hasAutoSkippedOutro = false;
  bool _nextPromptTriggered = false;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    final entry = _matchingEntry();
    final saved = entry?.episodesProgress[_currentItem.episodeNumber];
    _startAt =
        widget.initialPosition ??
        Duration(seconds: saved?.progressInSeconds ?? 0);

    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _panelAnimation = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOutCubic,
    );

    UIHelper.enableImmersiveMode();
    UIHelper.forceLandscape();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initEpisodeState();
      }
    });
  }

  void _togglePanel() {
    if (_panelController.isCompleted) {
      _panelController.reverse();
    } else {
      _panelController.forward();
    }
  }

  Future<void> _initEpisodeState() async {
    _hasAutoSkippedIntro = false;
    _hasAutoSkippedOutro = false;
    _nextPromptTriggered = false;
    ref.read(nextEpisodePromptProvider.notifier).dismissForEpisodeTransition();

    // 1. Set current episode
    ref
        .read(episodeDataProvider.notifier)
        .changeEpisode(_currentItem.episodeNumber);

    // 2. Populate episodes for panel
    final title = _currentItem.animeTitle.trim().toLowerCase();
    final downloadedItems =
        ref
            .read(downloadsProvider)
            .downloads
            .where(
              (item) =>
                  item.state == DownloadStatus.downloaded &&
                  item.animeTitle.trim().toLowerCase() == title,
            )
            .sortedBy<num>((item) => item.episodeNumber)
            .toList();

    final epModels =
        downloadedItems
            .map(
              (item) => EpisodeDataModel(
                number: item.episodeNumber,
                title: item.episodeTitle,
                thumbnail: item.thumbnail,
                id: '${item.animeId ?? item.animeTitle}_${item.episodeNumber}',
              ),
            )
            .toList();

    ref
        .read(episodeListProvider.notifier)
        .setLocalEpisodes(
          episodes: epModels,
          mediaId: _currentItem.animeId,
          animeId: _currentItem.animeId,
          animeTitle: _currentItem.animeTitle,
        );

    // 3. Load intro & outro from sidecar metadata or fetch
    try {
      final metaFile = File(
        '${p.withoutExtension(_currentItem.filePath)}.meta.json',
      );
      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        Intro? intro;
        Intro? outro;
        if (map['intro'] is Map) {
          intro = Intro.fromJson(Map<String, dynamic>.from(map['intro'] as Map));
        }
        if (map['outro'] is Map) {
          outro = Intro.fromJson(Map<String, dynamic>.from(map['outro'] as Map));
        }
        if (intro != null || outro != null) {
          ref
              .read(aniSkipProvider.notifier)
              .setFallbackFromSource(intro: intro, outro: outro);
        }
      }
    } catch (_) {}

    // Fetch skip times from API if available to ensure complete coverage
    unawaited(
      ref
          .read(aniSkipProvider.notifier)
          .fetchSkipTimes(
            mediaId: _currentItem.animeId ?? '',
            animeTitle: _currentItem.animeTitle,
            episodeNumber: _currentItem.episodeNumber,
            episodeLength: _currentItem.durationSeconds ?? 0,
          ),
    );
  }

  void _checkSkipAndNextPrompt(Duration pos, Duration dur) {
    if (dur <= Duration.zero) return;
    final posSec = pos.inSeconds;
    final durSec = dur.inSeconds;
    final remainingSec = durSec - posSec;
    final settings = ref.read(playerSettingsProvider);

    // 1. Auto Skip Intro / Outro
    if (settings.enableAutoSkip) {
      final skips = ref.read(aniSkipProvider);
      for (final skip in skips) {
        if (skip.interval != null) {
          final start = skip.interval!.startTime.toInt();
          final end = skip.interval!.endTime.toInt();
          if (posSec >= start && posSec < end) {
            if (skip.skipType == SkipType.op && !_hasAutoSkippedIntro) {
              _hasAutoSkippedIntro = true;
              ref
                  .read(playerStateProvider.notifier)
                  .seek(Duration(seconds: end));
            } else if (skip.skipType == SkipType.ed && !_hasAutoSkippedOutro) {
              _hasAutoSkippedOutro = true;
              ref
                  .read(playerStateProvider.notifier)
                  .seek(Duration(seconds: end));
            }
          }
        }
      }
    }

    // 2. Next Episode Prompt
    if (settings.showNextEpisodePrompt &&
        !_nextPromptTriggered &&
        !settings.stopAfterCurrentEpisode) {
      final skips = ref.read(aniSkipProvider);
      final hasDetectedOutro = skips.any(
        (s) =>
            s.interval != null &&
            (s.skipType == SkipType.ed ||
                (s.skipType == SkipType.mixed && s.interval!.startTime > 300)),
      );
      final isInDetectedOutro = skips.any(
        (s) =>
            s.interval != null &&
            (s.skipType == SkipType.ed ||
                (s.skipType == SkipType.mixed && s.interval!.startTime > 300)) &&
            posSec >= s.interval!.startTime.toInt() &&
            posSec <= s.interval!.endTime.toInt(),
      );

      final shouldTrigger =
          hasDetectedOutro
              ? isInDetectedOutro
              : (remainingSec <= 90 && remainingSec > 0 && durSec > 90);

      if (shouldTrigger) {
        final nextEpNum = _currentItem.episodeNumber + 1;
        final hasNext = ref
            .read(downloadsProvider)
            .downloads
            .any(
              (d) =>
                  d.animeTitle.trim().toLowerCase() ==
                      _currentItem.animeTitle.trim().toLowerCase() &&
                  d.state == DownloadStatus.downloaded &&
                  d.episodeNumber == nextEpNum,
            );
        if (hasNext) {
          _nextPromptTriggered = true;
          ref.read(nextEpisodePromptProvider.notifier).show();
        }
      }
    }
  }

  Future<void> _playEpisode(DownloadItem nextItem) async {
    final playerState = ref.read(playerStateProvider);
    await _saveProgress(
      playerState.position,
      playerState.duration,
      force: true,
    );
    setState(() {
      _currentItem = nextItem;
      _lastSavedSecond = -1;
      _startAt = Duration.zero;
    });
    await _initEpisodeState();
    await ref
        .read(playerStateProvider.notifier)
        .open(nextItem.filePath, Duration.zero);
  }

  AnimeWatchProgressEntry? _matchingEntry() {
    final stableId = _currentItem.animeId;
    if (stableId != null && stableId.isNotEmpty) {
      final byId =
          ref
              .read(watchProgressRepositoryProvider)
              .getAllProgress()
              .where((entry) => entry.animeId == stableId)
              .firstOrNull;
      if (byId != null) return byId;
    }
    final title = _currentItem.animeTitle.trim().toLowerCase();
    final matches =
        ref
            .read(watchProgressRepositoryProvider)
            .getAllProgress()
            .where((entry) => entry.animeTitle.trim().toLowerCase() == title)
            .toList();
    if (matches.isEmpty) return null;
    return matches.firstWhere(
      (entry) => !entry.animeId.startsWith('offline:'),
      orElse: () => matches.first,
    );
  }

  Future<void> _saveProgress(
    Duration position,
    Duration duration, {
    bool force = false,
  }) async {
    if (duration.inSeconds <= 0 || position.inSeconds <= 0) return;
    if (!force &&
        _lastSavedSecond >= 0 &&
        (position.inSeconds - _lastSavedSecond).abs() < 5) {
      return;
    }
    _lastSavedSecond = position.inSeconds;

    final repository = ref.read(watchProgressRepositoryProvider);
    final existing = _matchingEntry();
    final downloadedEpisodeCount = ref
        .read(downloadsProvider)
        .downloads
        .where(
          (item) =>
              item.animeTitle.trim().toLowerCase() ==
              _currentItem.animeTitle.trim().toLowerCase(),
        )
        .fold<int>(
          _currentItem.episodeNumber,
          (maximum, item) =>
              item.episodeNumber > maximum ? item.episodeNumber : maximum,
        );
    final mediaId =
        existing?.animeId ??
        _currentItem.animeId ??
        'offline:${_currentItem.animeTitle.trim().toLowerCase()}';
    final knownTotal =
        _currentItem.totalEpisodes ??
        existing?.totalEpisodes ??
        downloadedEpisodeCount;
    final episode = EpisodeProgress(
      episodeNumber: _currentItem.episodeNumber,
      episodeTitle: _currentItem.episodeTitle,
      episodeThumbnail: _currentItem.thumbnail,
      progressInSeconds: position.inSeconds,
      durationInSeconds: duration.inSeconds,
      isCompleted: position.inSeconds / duration.inSeconds >= 0.90,
      watchedAt: DateTime.now(),
    );
    final episodes = Map<int, EpisodeProgress>.from(
      existing?.episodesProgress ?? const {},
    )..[_currentItem.episodeNumber] = episode;
    await repository.saveProgress(
      (existing ??
              AnimeWatchProgressEntry(
                animeId: mediaId,
                animeTitle: _currentItem.animeTitle,
                animeCover: _currentItem.thumbnail,
                totalEpisodes: knownTotal,
                isAdult: _currentItem.isAdult,
              ))
          .copyWith(
            episodesProgress: episodes,
            currentEpisode: _currentItem.episodeNumber,
            totalEpisodes: knownTotal,
            lastUpdated: DateTime.now(),
            lastPlayedAt: DateTime.now(),
          ),
    );
  }

  @override
  void dispose() {
    _panelController.dispose();
    final state = ref.read(playerStateProvider);
    unawaited(
      _saveProgress(
        state.position,
        state.duration,
        force: true,
      ).whenComplete(() => ref.read(playerStateProvider.notifier).stop()),
    );
    AudioFocusService().reset();
    UIHelper.forcePortrait();
    UIHelper.exitImmersiveMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playerStateProvider, (previous, next) {
      unawaited(_saveProgress(next.position, next.duration));
      _checkSkipAndNextPrompt(next.position, next.duration);
    });

    ref.listen(episodeDataProvider.select((s) => s.selectedEpisode), (
      prev,
      next,
    ) {
      if (next == null || next == _currentItem.episodeNumber) return;
      final nextItem = ref
          .read(downloadsProvider)
          .downloads
          .firstWhereOrNull(
            (d) =>
                d.animeTitle.trim().toLowerCase() ==
                    _currentItem.animeTitle.trim().toLowerCase() &&
                d.state == DownloadStatus.downloaded &&
                d.episodeNumber == next,
          );
      if (nextItem != null) {
        _playEpisode(nextItem);
      }
    });

    final mediaId =
        _currentItem.animeId ??
        'offline:${_currentItem.animeTitle.trim().toLowerCase()}';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_panelController.isCompleted || _panelController.value > 0) {
          _panelController.reverse();
          return;
        }
        final playerState = ref.read(playerStateProvider);
        await _saveProgress(
          playerState.position,
          playerState.duration,
          force: true,
        );
        await ref.read(playerStateProvider.notifier).stop();
        AudioFocusService().reset();
        if (context.mounted) Navigator.pop(context);
        await UIHelper.forcePortrait();
        await UIHelper.exitImmersiveMode();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: OrientationBuilder(
          builder: (_, orientation) {
            final isPiP = ref.watch(pipProvider);
            if (isPiP && _panelController.value > 0) {
              _panelController.reset();
            }

            final player = AniDashVideoPlayer(
              onEpisodesPressed: _togglePanel,
              onPanelCloseRequest: () => _panelController.reverse(),
              localFilePath: _currentItem.filePath,
              localTitle:
                  '${_currentItem.animeTitle} - ${_currentItem.episodeTitle}',
              localStartAt: _startAt,
            );

            final isDesktop = !Platform.isAndroid && !Platform.isIOS;
            if (isDesktop && !isPiP) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141416),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Go Back (Esc)',
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          color: Colors.white70,
                          onPressed: () async {
                            final playerState = ref.read(playerStateProvider);
                            await _saveProgress(
                              playerState.position,
                              playerState.duration,
                              force: true,
                            );
                            await ref.read(playerStateProvider.notifier).stop();
                            if (context.mounted) Navigator.pop(context);
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        const SizedBox(width: 8),
                        Container(height: 16, width: 1, color: Colors.white24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_currentItem.animeTitle} - ${_currentItem.episodeTitle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const WindowsCaptionButtons(height: 42, isDark: true),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: player),
                        SizeTransition(
                          sizeFactor: _panelAnimation,
                          axis: Axis.horizontal,
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width * 0.35,
                            child: EpisodesPanel(
                              panelAnimation: _panelController,
                              mediaId: mediaId,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            if (orientation == Orientation.landscape && !isPiP) {
              return Row(
                children: [
                  Expanded(child: player),
                  SizeTransition(
                    sizeFactor: _panelAnimation,
                    axis: Axis.horizontal,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.35,
                      child: EpisodesPanel(
                        panelAnimation: _panelController,
                        mediaId: mediaId,
                      ),
                    ),
                  ),
                ],
              );
            }

            return SizedBox.expand(child: player);
          },
        ),
      ),
    );
  }
}
