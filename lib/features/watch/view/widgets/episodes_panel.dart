import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/downloads/model/download_item.dart';
import 'package:ani_dash/features/downloads/view_model/downloads_notifier.dart';
import 'package:ani_dash/features/downloads/model/download_status.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/features/episode_groups/model/named_episode_group.dart';
import 'package:ani_dash/features/episode_groups/repository/episode_grouping_repository.dart';

class EpisodesPanel extends ConsumerStatefulWidget {
  final AnimationController panelAnimation;
  final String mediaId;

  const EpisodesPanel({
    super.key,
    required this.panelAnimation,
    required this.mediaId,
  });

  @override
  ConsumerState<EpisodesPanel> createState() => _EpisodesPanelState();
}

class _EpisodesPanelState extends ConsumerState<EpisodesPanel> {
  static const _rangeSizeKey = 'player_episode_range_size';
  int _rangeSize = 50;
  int _currentStart = 1;
  bool _initializedForEp = false;
  int? _lastSelectedEp;
  int? _lastScrolledEp;
  bool _useNamedGroups = false;
  List<NamedEpisodeGroup> _namedGroups = const [];
  NamedEpisodeGroup? _selectedNamedGroup;
  String? _groupsLoadedFor;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadRangeSize();
    _useNamedGroups = sharedPrefs.getString('episode_grouping_mode') == 'named';
    widget.panelAnimation.addStatusListener(_onPanelStatusChanged);
  }

  void _onPanelStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _lastScrolledEp = null;
      if (mounted) setState(() {});
    }
  }

  void _scrollToEpisode(int epNum, List<EpisodeDataModel> visible) {
    final selectedIndex =
        visible.indexWhere((e) => e.number != null && e.number == epNum);
    if (selectedIndex < 0) return;

    void performJump() {
      if (!mounted || !_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final target = selectedIndex * 72.0;
      if (maxScroll > 0) {
        _scrollController.jumpTo(target.clamp(0.0, maxScroll));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => performJump());
    Future.delayed(const Duration(milliseconds: 100), performJump);
    Future.delayed(const Duration(milliseconds: 250), performJump);
  }

  Future<void> _loadNamedGroups(String? animeTitle) async {
    final token = '${widget.mediaId}:${animeTitle ?? ''}';
    if (!_useNamedGroups || _groupsLoadedFor == token) return;
    _groupsLoadedFor = token;
    final groups = await const VerifiedEpisodeGroupingRepository()
        .getNamedGroups(animeId: widget.mediaId, title: animeTitle);
    if (!mounted) return;
    final selectedEp = ref.read(episodeDataProvider).selectedEpisode ?? 1;
    setState(() {
      _namedGroups = groups;
      _selectedNamedGroup = groups.firstWhereOrNull(
        (group) => group.contains(selectedEp),
      );
      _selectedNamedGroup ??= groups.firstOrNull;
      if (groups.isEmpty) _useNamedGroups = false;
      _lastScrolledEp = null;
    });
  }

  Future<void> _loadRangeSize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_rangeSizeKey);
    if (!mounted || !const [25, 50, 100].contains(saved)) return;
    setState(() {
      _rangeSize = saved!;
      _initializedForEp = false;
    });
  }

  @override
  void dispose() {
    widget.panelAnimation.removeStatusListener(_onPanelStatusChanged);
    _scrollController.dispose();
    super.dispose();
  }

  List<(int, int)> _generateRanges(int total) {
    if (total == 0) return const [];
    final ranges = <(int, int)>[];
    for (int start = 1; start <= total; start += _rangeSize) {
      final end = (start + _rangeSize - 1).clamp(1, total);
      ranges.add((start, end));
    }
    return ranges;
  }

  void _showRangeSizeDialog(
    BuildContext context,
    EpisodeListNotifier notifier,
  ) {
    int temp = _rangeSize;

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder:
              (context, setDialogState) => AlertDialog(
                title: const Text("Episode Range Size"),
                content: Wrap(
                  spacing: 8,
                  children:
                      [25, 50, 100].map((size) {
                        return ChoiceChip(
                          label: Text("$size"),
                          selected: temp == size,
                          onSelected: (_) {
                            setDialogState(() {
                              temp = size;
                            });
                          },
                        );
                      }).toList(),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel"),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      setState(() {
                        _rangeSize = temp;
                        _currentStart = 1;
                        _initializedForEp = false;
                      });
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt(_rangeSizeKey, temp);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
                    child: const Text("Apply"),
                  ),
                ],
              ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final episodes = ref.watch(episodeListProvider.select((s) => s.episodes));
    final selectedEp = ref.watch(
      episodeDataProvider.select((s) => s.selectedEpisode),
    );

    final episodeNotifier = ref.read(episodeDataProvider.notifier);
    final episodeListNotifier = ref.read(episodeListProvider.notifier);

    final total = episodes.length;
    final ranges = _generateRanges(total);
    final animeTitle = ref.watch(
      episodeListProvider.select((s) => s.animeTitle),
    );
    final currentGroupingMode = sharedPrefs.getString('episode_grouping_mode');
    final wantNamedGroups = currentGroupingMode == 'named';
    if (_useNamedGroups != wantNamedGroups) {
      _useNamedGroups = wantNamedGroups;
      _groupsLoadedFor = null;
    }
    if (_useNamedGroups && _groupsLoadedFor == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadNamedGroups(animeTitle),
      );
    }

    if (selectedEp != null && selectedEp > 0) {
      if (!_initializedForEp || _lastSelectedEp != selectedEp) {
        _lastSelectedEp = selectedEp;
        _initializedForEp = true;
        _currentStart = ((selectedEp - 1) ~/ _rangeSize) * _rangeSize + 1;
      }
    }

    if (ranges.isNotEmpty && !ranges.any((r) => r.$1 == _currentStart)) {
      if (selectedEp != null && selectedEp > 0) {
        final matching = ranges.firstWhereOrNull(
          (r) => selectedEp >= r.$1 && selectedEp <= r.$2,
        );
        _currentStart = matching?.$1 ?? ranges.first.$1;
      } else {
        _currentStart = ranges.first.$1;
      }
    }

    final startIdx = (_currentStart - 1).clamp(0, total);
    final endIdx = (_currentStart + _rangeSize - 1).clamp(0, total);

    final visibleEpisodes =
        _useNamedGroups && _selectedNamedGroup != null
            ? episodes
                .where((episode) {
                  final number = episode.number;
                  return number != null &&
                      _selectedNamedGroup!.contains(number);
                })
                .toList(growable: false)
            : episodes.sublist(startIdx, endIdx);
    if (selectedEp != null &&
        selectedEp > 0 &&
        _lastScrolledEp != selectedEp &&
        visibleEpisodes.isNotEmpty) {
      _lastScrolledEp = selectedEp;
      _scrollToEpisode(selectedEp, visibleEpisodes);
    }
    final progressAsync = ref.watch(watchProgressStreamProvider);
    final allProgress = progressAsync.value ?? [];
    final singleProgress =
        ref.watch(animeWatchProgressProvider(widget.mediaId)).value;

    final animeProgress =
        singleProgress ??
        allProgress
            .where(
              (e) =>
                  e.animeId == widget.mediaId ||
                  (animeTitle != null &&
                      e.animeTitle.trim().toLowerCase() ==
                          animeTitle.trim().toLowerCase()),
            )
            .firstOrNull ??
        ref.read(watchProgressRepositoryProvider).getProgress(widget.mediaId);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 200) {
            widget.panelAnimation.reverse();
          }
        },
        child: Container(
          color: theme.colorScheme.surface,
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(
                children: [
                  Text("Episodes", style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (_useNamedGroups && _namedGroups.isNotEmpty)
                    DropdownButton<String>(
                      value: _selectedNamedGroup?.id,
                      underline: const SizedBox.shrink(),
                      items:
                          _namedGroups
                              .map(
                                (group) => DropdownMenuItem(
                                  value: group.id,
                                  child: Text(
                                    group.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (id) {
                        final group = _namedGroups.firstWhereOrNull(
                          (item) => item.id == id,
                        );
                        if (group == null) return;
                        setState(() {
                          _selectedNamedGroup = group;
                          _lastScrolledEp = null;
                        });
                      },
                    )
                  else if (ranges.isNotEmpty)
                    DropdownButton<int>(
                      value: _currentStart,
                      underline: const SizedBox.shrink(),
                      items:
                          ranges
                              .map(
                                (r) => DropdownMenuItem(
                                  value: r.$1,
                                  child: Text("${r.$1}-${r.$2}"),
                                ),
                              )
                              .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _currentStart = v;
                          _lastScrolledEp = null;
                          _scrollController.jumpTo(0);
                        });
                      },
                    ),
                  if (!_useNamedGroups)
                    IconButton(
                      icon: const Icon(Iconsax.setting_2, size: 20),
                      onPressed:
                          () => _showRangeSizeDialog(
                            context,
                            episodeListNotifier,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: visibleEpisodes.length,
                  itemBuilder: (_, i) {
                    final episode = visibleEpisodes[i];
                    final actualIndex = episodes.indexOf(episode);

                    final epNum = episode.number ?? (actualIndex + 1);
                    final epProgress = animeProgress?.episodesProgress[epNum];
                    final isCompleted = epProgress?.isCompleted ?? false;
                    final duration = epProgress?.durationInSeconds ?? 0;
                    final progressSec = epProgress?.progressInSeconds ?? 0;
                    final watchProgress =
                        (duration > 0)
                            ? (progressSec / duration).clamp(0.0, 1.0)
                            : (isCompleted ? 1.0 : 0.0);

                    final downloadState = ref.watch(downloadsProvider);
                    final download = downloadState.downloads.firstWhereOrNull(
                      (d) =>
                          d.animeTitle == animeTitle &&
                          d.episodeNumber == epNum,
                    );

                    final savedEpProgress =
                        animeProgress?.episodesProgress[epNum];
                    final epRawTitle = episode.title?.trim();
                    final isGeneric =
                        epRawTitle == null ||
                        RegExp(
                          r'^(episode|ep\.?)\s*\d+$',
                          caseSensitive: false,
                        ).hasMatch(epRawTitle);
                    final resolvedTitle =
                        (!isGeneric && epRawTitle.isNotEmpty)
                            ? epRawTitle
                            : (savedEpProgress?.episodeTitle != null &&
                                    savedEpProgress!
                                        .episodeTitle
                                        .trim()
                                        .isNotEmpty &&
                                    !RegExp(
                                      r'^(episode|ep\.?)\s*\d+$',
                                      caseSensitive: false,
                                    ).hasMatch(
                                      savedEpProgress.episodeTitle.trim(),
                                    ))
                            ? savedEpProgress.episodeTitle.trim()
                            : (epRawTitle?.isNotEmpty == true
                                ? epRawTitle!
                                : "Episode ${episode.number}");
                    final resolvedThumbnail =
                        (episode.thumbnail?.trim().isNotEmpty == true)
                            ? episode.thumbnail
                            : savedEpProgress?.episodeThumbnail;

                    return EpisodeTile(
                      isFiller: episode.isFiller ?? false,
                      isMixed: episode.isMixed ?? false,
                      isCompleted: isCompleted,
                      watchProgress: watchProgress,
                      episodeNumber: episode.number?.toString() ?? "?",
                      episodeTitle: resolvedTitle,
                      thumbnail: resolvedThumbnail,
                      durationSeconds:
                          duration > 0 ? duration : download?.durationSeconds,
                      isSelected: episode.number == selectedEp,
                      download: download,
                      onTap: () {
                        episodeNotifier.changeEpisode(
                          episode.number,
                          force: true,
                        );
                        widget.panelAnimation.reverse();
                      },
                      onLongPress: () {
                        final epNum = episode.number ?? 1;
                        showModalBottomSheet(
                          context: context,
                          useRootNavigator: true,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          builder: (sheetContext) {
                            return SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 12.0,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(
                                      child: Container(
                                        width: 36,
                                        height: 4,
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withValues(
                                            alpha: 0.4,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      episode.title ?? 'Episode $epNum',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const Divider(height: 20),
                                    ListTile(
                                      leading: Icon(
                                        isCompleted
                                            ? Icons.remove_red_eye_outlined
                                            : Icons
                                                .check_circle_outline_rounded,
                                        color:
                                            isCompleted
                                                ? Colors.orange
                                                : Colors.green,
                                      ),
                                      title: Text(
                                        isCompleted
                                            ? 'Mark as Unwatched'
                                            : 'Mark as Watched',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.pop(sheetContext);
                                        final newWatched = !isCompleted;
                                        final repo = ref.read(
                                          watchProgressRepositoryProvider,
                                        );
                                        repo.updateEpisodeProgress(
                                          widget.mediaId,
                                          EpisodeProgress(
                                            episodeNumber: epNum,
                                            episodeTitle:
                                                episode.title ??
                                                'Episode $epNum',
                                            episodeThumbnail: episode.thumbnail,
                                            progressInSeconds:
                                                newWatched ? 1440 : 0,
                                            durationInSeconds: 1440,
                                            isCompleted: newWatched,
                                            watchedAt: DateTime.now(),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EpisodeTile extends StatelessWidget {
  final bool isFiller;
  final bool isMixed;
  final bool isCompleted;
  final double watchProgress;
  final String episodeNumber;
  final String episodeTitle;
  final String? thumbnail;
  final int? durationSeconds;
  final bool isSelected;
  final DownloadItem? download;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const EpisodeTile({
    super.key,
    required this.isFiller,
    this.isMixed = false,
    required this.isCompleted,
    this.watchProgress = 0.0,
    required this.episodeNumber,
    required this.episodeTitle,
    this.thumbnail,
    this.durationSeconds,
    required this.isSelected,
    this.download,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bgColor =
        isSelected
            ? theme.colorScheme.primary
            : isMixed
            ? theme.colorScheme.primary.withValues(alpha: 0.28)
            : isFiller
            ? theme.colorScheme.primaryContainer
            : isCompleted
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest;

    String durationLabel(int seconds) {
      final minutes = seconds ~/ 60;
      final remainder = seconds % 60;
      return remainder == 0
          ? '$minutes min'
          : '$minutes:${remainder.toString().padLeft(2, '0')}';
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? theme.colorScheme.primaryContainer
                  : isMixed
                  ? theme.colorScheme.primary.withValues(alpha: 0.24)
                  : isFiller
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
          border:
              isMixed
                  ? Border.all(color: theme.colorScheme.primary, width: 1.6)
                  : isFiller
                  ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.6),
                    width: 1.2,
                  )
                  : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 96,
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child:
                              thumbnail?.trim().isNotEmpty == true
                                  ? CachedNetworkImage(
                                    imageUrl: thumbnail!,
                                    fit: BoxFit.cover,
                                    placeholder:
                                        (_, __) => ColoredBox(color: bgColor),
                                    errorWidget:
                                        (_, __, ___) => ColoredBox(
                                          color: bgColor,
                                          child: const Icon(
                                            Icons.movie_outlined,
                                          ),
                                        ),
                                  )
                                  : ColoredBox(
                                    color: bgColor,
                                    child: const Icon(Icons.movie_outlined),
                                  ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .76),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'E$episodeNumber',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (isCompleted && !isSelected)
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 9,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        episodeTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color:
                              isSelected
                                  ? theme.colorScheme.onSurface
                                  : isCompleted
                                  ? theme.colorScheme.outline
                                  : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (durationSeconds != null && durationSeconds! > 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          durationLabel(durationSeconds!),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isMixed)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.28),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Mixed',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  )
                else if (isFiller)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                        width: 0.8,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Filler',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                if (isCompleted)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Watched',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                if (isSelected)
                  Icon(
                    Iconsax.play5,
                    size: 18,
                    color: theme.colorScheme.primary,
                  )
                else if (download != null)
                  _buildDownloadIndicator(theme, download!)
                else if (isCompleted)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
            if (watchProgress > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: watchProgress,
                  minHeight: 2.5,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color:
                      isCompleted
                          ? theme.colorScheme.primary
                          : theme.colorScheme.secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadIndicator(ThemeData theme, DownloadItem item) {
    if (item.state == DownloadStatus.downloading) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          value: item.progressPercentage,
          color: theme.colorScheme.primary,
        ),
      );
    } else if (item.state == DownloadStatus.downloaded) {
      return Icon(
        Icons.download_done_rounded,
        size: 18,
        color: theme.colorScheme.primary,
      );
    } else if (item.state == DownloadStatus.paused) {
      return Icon(
        Icons.pause_circle_outline,
        size: 18,
        color: theme.colorScheme.tertiary,
      );
    }
    return const SizedBox.shrink();
  }
}
