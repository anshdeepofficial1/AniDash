import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/helpers/anime_match_search.dart';
import 'package:ani_dash/shared/providers/continue_watching_dismissed_provider.dart';
import 'package:ani_dash/features/downloads/view/local_player_screen.dart';
import 'package:ani_dash/features/downloads/view_model/downloads_notifier.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/watch_sync_notifier.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/core/repositories/source_preference_repository.dart';
import 'package:ani_dash/features/watch/view/widgets/player/dialogs/jump_to_time_dialog.dart';

final Map<String, String> _continueEpisodeThumbnailCache = {};

class ContinueSection extends ConsumerWidget {
  final List<AnimeWatchProgressEntry> allProgress;
  final bool isAdult;

  const ContinueSection({
    super.key,
    required this.allProgress,
    this.isAdult = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissedIds = ref.watch(continueWatchingDismissedProvider);
    final activeEpisodeList = ref.watch(episodeListProvider);
    final scopedEntries =
        isAdult
            ? allProgress.where((e) => e.isAdult).toList()
            : List<AnimeWatchProgressEntry>.from(allProgress);
    final validEntries =
        scopedEntries.where((entry) {
            if (!entry.hasAnyWatchProgress) return false;
            if (dismissedIds.contains(entry.animeId)) return false;
            if (entry.isCompletedOrFinished) return false;
            return true;
          }).toList()
          ..sort(AnimeWatchProgressEntry.compareByRecency);

    if (validEntries.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final itemWidth = (screenWidth * 0.6).clamp(180.0, 280.0);
    final imageHeight = itemWidth * (9 / 16);
    final listHeight = imageHeight + 78.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                "Continue Watching",
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'View all continue watching',
              onPressed: () => context.push('/settings/watch-history'),
              icon: const Icon(Iconsax.arrow_right_3, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: listHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: validEntries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final entry = validEntries[index];
              final currentEp = entry.episodesProgress[entry.currentEpisode];

              // Keep resuming the current episode unless it has truly reached the end (within last 45s or >= 92% watched)
              final dur = currentEp?.durationInSeconds ?? 0;
              final prog = currentEp?.progressInSeconds ?? 0;
              final isCurrentCompleted =
                  (currentEp?.isCompleted == true &&
                      (dur == 0 || prog >= dur - 45 || (prog / dur) >= 0.92)) ||
                  (dur > 0 && (prog / dur) >= 0.92);

              final baseEp =
                  entry.currentEpisode > 0 ? entry.currentEpisode : 1;
              final nextEpisodeNum =
                  isCurrentCompleted &&
                          (entry.totalEpisodes == 0 ||
                              baseEp < entry.totalEpisodes)
                      ? baseEp + 1
                      : baseEp;

              final displayEp =
                  entry.episodesProgress[nextEpisodeNum] ?? currentEp;
              String? listEpisodeTitle;

              double progressValue = 0.0;
              if (!isCurrentCompleted && currentEp != null) {
                final p = currentEp.progressInSeconds?.toDouble() ?? 0.0;
                final d = currentEp.durationInSeconds?.toDouble() ?? 0.0;
                if (d > 0) progressValue = (p / d).clamp(0.0, 1.0);
              }

              String? listThumbnail;
              final listMatchesEntry =
                  activeEpisodeList.mediaId == entry.animeId ||
                  activeEpisodeList.animeId == entry.animeId ||
                  activeEpisodeList.animeTitle == entry.animeTitle;
              if (listMatchesEntry) {
                for (final episode in activeEpisodeList.episodes) {
                  if (episode.number == nextEpisodeNum) {
                    final epTitle = episode.title?.trim();
                    final isGeneric =
                        epTitle == null ||
                        RegExp(
                          r'^(episode|ep\.?)\s*\d+$',
                          caseSensitive: false,
                        ).hasMatch(epTitle);
                    if (!isGeneric && epTitle.isNotEmpty) {
                      listEpisodeTitle = epTitle;
                    }
                    if (episode.thumbnail?.trim().isNotEmpty == true) {
                      listThumbnail = episode.thumbnail!.trim();
                      final cacheKey = '${entry.animeId}:$nextEpisodeNum';
                      _continueEpisodeThumbnailCache[cacheKey] = listThumbnail;
                    }
                    if (listThumbnail != null ||
                        (listEpisodeTitle != null && !isGeneric)) {
                      _persistEpisodeMetadata(
                        ref,
                        entry,
                        nextEpisodeNum,
                        listEpisodeTitle,
                        listThumbnail,
                      );
                    }
                    break;
                  }
                }
              }
              final savedEpisodeTitle = displayEp?.episodeTitle.trim() ?? '';
              final resolvedEpisodeTitle =
                  (listEpisodeTitle?.trim().isNotEmpty ?? false)
                      ? listEpisodeTitle!.trim()
                      : savedEpisodeTitle;
              final episodeLabel =
                  resolvedEpisodeTitle.isEmpty ||
                          resolvedEpisodeTitle.toLowerCase() ==
                              'episode $nextEpisodeNum'
                      ? 'E$nextEpisodeNum'
                      : 'E$nextEpisodeNum - $resolvedEpisodeTitle';
              final watchedSeconds = displayEp?.progressInSeconds ?? 0;
              final totalSeconds = displayEp?.durationInSeconds ?? 0;
              final remainingSeconds =
                  totalSeconds > watchedSeconds
                      ? totalSeconds - watchedSeconds
                      : 0;
              final timeLabel =
                  totalSeconds > 0
                      ? '${_formatWatchTime(watchedSeconds)} watched · ${_formatWatchTime(remainingSeconds)} left'
                      : null;
              final cachedThumbnail =
                  _continueEpisodeThumbnailCache['${entry.animeId}:$nextEpisodeNum'];
              final savedThumbnail =
                  displayEp?.episodeThumbnail ?? currentEp?.episodeThumbnail;
              final thumb =
                  listThumbnail ??
                  cachedThumbnail ??
                  (savedThumbnail != entry.animeCover ? savedThumbnail : null);
              Widget imageWidget;

              if (thumb != null && thumb.startsWith('http')) {
                imageWidget = CachedNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => _buildFallback(colorScheme),
                );
              } else if (thumb != null) {
                try {
                  imageWidget = Image.memory(
                    base64Decode(thumb),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _buildFallback(colorScheme),
                  );
                } catch (_) {
                  imageWidget = _buildFallback(colorScheme);
                }
              } else if (entry.animeCover.isNotEmpty) {
                imageWidget = Image.network(
                  entry.animeCover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _buildFallback(colorScheme),
                );
              } else {
                imageWidget = _buildFallback(colorScheme);
              }

              bool isLoading = false;
              return StatefulBuilder(
                builder: (context, setState) {
                  return RepaintBoundary(
                    child: SizedBox(
                      width: itemWidth,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onLongPress: () {
                          _showContinueWatchingMenu(
                            context,
                            ref,
                            entry,
                            nextEpisodeNum,
                            entry.episodesProgress[nextEpisodeNum],
                            colorScheme,
                          );
                        },
                        onTap: () async {
                          if (isLoading) return;
                          setState(() => isLoading = true);
                          final localDownload = await ref
                              .read(downloadsProvider.notifier)
                              .findDownloadedEpisode(
                                animeTitle: entry.animeTitle,
                                episodeNumber: nextEpisodeNum,
                              );
                          if (localDownload != null && context.mounted) {
                            await Navigator.of(
                              context,
                              rootNavigator: true,
                            ).push(
                              MaterialPageRoute(
                                builder:
                                    (_) =>
                                        LocalPlayerScreen(item: localDownload),
                              ),
                            );
                            if (context.mounted) {
                              setState(() => isLoading = false);
                            }
                            return;
                          }
                          if (!context.mounted) return;
                          await providerAnimeMatchSearch(
                            context: context,
                            ref: ref,
                            animeMedia: UniversalMedia(
                              id: entry.animeId,
                              idMal: entry.animeId,
                              title: UniversalTitle(
                                romaji: entry.animeTitle,
                                english: entry.animeTitle,
                                native: entry.animeTitle,
                              ),
                              coverImage: UniversalCoverImage(
                                large: entry.animeCover,
                                medium: entry.animeCover,
                              ),
                              isAdult: isAdult || entry.isAdult,
                            ),
                            startAt: nextEpisodeNum,
                            startAtPosition:
                                (nextEpisodeNum == entry.currentEpisode &&
                                        (currentEp?.progressInSeconds ?? 0) > 0)
                                    ? currentEp?.progressInSeconds
                                    : null,
                            withAnimeMatch: true,
                            directAutoMatch: true,
                            fromHentaiHub: isAdult || entry.isAdult,
                          );
                          if (context.mounted) {
                            setState(() => isLoading = false);
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Stack(
                                  children: [
                                    Positioned.fill(child: imageWidget),
                                    Positioned.fill(
                                      child: Center(
                                        child:
                                            isLoading
                                                ? const CircularProgressIndicator()
                                                : Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: colorScheme
                                                        .primaryContainer
                                                        .withValues(alpha: 0.5),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    Iconsax.play5,
                                                    color:
                                                        colorScheme
                                                            .onPrimaryContainer,
                                                    size: 20,
                                                  ),
                                                ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'EP $nextEpisodeNum',
                                          style: TextStyle(
                                            color:
                                                colorScheme.onPrimaryContainer,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: LinearProgressIndicator(
                                        value: progressValue,
                                        minHeight: 3,
                                        backgroundColor: Colors.transparent,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              colorScheme.primary,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              entry.animeTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              episodeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                            if (timeLabel != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                timeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _formatWatchTime(int seconds) {
    final safe = seconds.clamp(0, 24 * 60 * 60);
    final minutes = safe ~/ 60;
    final remainder = safe % 60;
    if (minutes == 0) return '${remainder}s';
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  void _persistEpisodeMetadata(
    WidgetRef ref,
    AnimeWatchProgressEntry entry,
    int episodeNumber,
    String? episodeTitle,
    String? thumbnail,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repository = ref.read(watchProgressRepositoryProvider);
      final current = repository.getProgress(entry.animeId) ?? entry;
      final currentEpisode = current.episodesProgress[episodeNumber];

      final currentTitle = currentEpisode?.episodeTitle.trim() ?? '';
      final currentIsGeneric =
          currentTitle.isEmpty ||
          RegExp(
            r'^(episode|ep\.?)\s*\d+$',
            caseSensitive: false,
          ).hasMatch(currentTitle);

      final newTitle =
          (episodeTitle != null && episodeTitle.trim().isNotEmpty)
              ? episodeTitle.trim()
              : null;
      final titleNeedsUpdate =
          newTitle != null && (currentIsGeneric || currentTitle != newTitle);

      final currentThumbnail = currentEpisode?.episodeThumbnail?.trim() ?? '';
      final newThumbnail =
          (thumbnail != null && thumbnail.trim().isNotEmpty)
              ? thumbnail.trim()
              : null;
      final thumbnailNeedsUpdate =
          newThumbnail != null &&
          (currentThumbnail.isEmpty || currentThumbnail != newThumbnail);

      if (!titleNeedsUpdate && !thumbnailNeedsUpdate) return;

      final updatedEpisodes = Map<int, EpisodeProgress>.from(
        current.episodesProgress,
      );
      updatedEpisodes[episodeNumber] = EpisodeProgress(
        episodeNumber: episodeNumber,
        episodeTitle:
            (titleNeedsUpdate ? newTitle : null) ??
            (currentTitle.isNotEmpty ? currentTitle : 'Episode $episodeNumber'),
        episodeThumbnail:
            (thumbnailNeedsUpdate ? newThumbnail : null) ??
            (currentThumbnail.isNotEmpty ? currentThumbnail : null),
        progressInSeconds: currentEpisode?.progressInSeconds,
        durationInSeconds: currentEpisode?.durationInSeconds,
        isCompleted: currentEpisode?.isCompleted ?? false,
        watchedAt: currentEpisode?.watchedAt,
      );

      await repository.saveProgress(
        current.copyWith(episodesProgress: updatedEpisodes),
      );
    });
  }

  void _showContinueWatchingMenu(
    BuildContext context,
    WidgetRef ref,
    AnimeWatchProgressEntry entry,
    int targetEpNum,
    EpisodeProgress? targetEp,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final screenHeight = MediaQuery.sizeOf(sheetContext).height;

        final epList = ref.read(episodeListProvider);
        String resolvedTitle = 'Episode $targetEpNum';
        if (targetEp != null &&
            targetEp.episodeNumber == targetEpNum &&
            targetEp.episodeTitle.trim().isNotEmpty) {
          resolvedTitle = targetEp.episodeTitle;
        } else if (epList.animeId == entry.animeId) {
          final match =
              epList.episodes.where((e) => e.number == targetEpNum).firstOrNull;
          if (match != null &&
              match.title != null &&
              match.title!.trim().isNotEmpty) {
            resolvedTitle = match.title!;
          }
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    entry.animeTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    resolvedTitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Divider(height: 24),
                  // 1. View Anime Details
                  ListTile(
                    leading: Icon(
                      Iconsax.info_circle,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('View Anime Details'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      context.push('/details', extra: entry.toUniversalMedia());
                    },
                  ),
                  if (entry.totalEpisodes == 0 ||
                      targetEpNum < entry.totalEpisodes)
                    ListTile(
                      leading: Icon(
                        Iconsax.next,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text('Play Episode ${targetEpNum + 1}'),
                      subtitle: const Text('Open the next episode'),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await providerAnimeMatchSearch(
                          context: context,
                          ref: ref,
                          animeMedia: UniversalMedia(
                            id: entry.animeId,
                            title: UniversalTitle(
                              romaji: entry.animeTitle,
                              english: entry.animeTitle,
                              native: entry.animeTitle,
                            ),
                            coverImage: UniversalCoverImage(
                              large: entry.animeCover,
                              medium: entry.animeCover,
                            ),
                            isAdult: isAdult || entry.isAdult,
                          ),
                          startAt: targetEpNum + 1,
                          withAnimeMatch: true,
                          directAutoMatch: true,
                          fromHentaiHub: isAdult || entry.isAdult,
                        );
                      },
                    ),
                  // 2. Mark as Watched
                  ListTile(
                    leading: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Colors.green,
                    ),
                    title: Text('Mark Episode $targetEpNum as Watched'),
                    subtitle: const Text(
                      'Marks this episode complete and updates progress',
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final isSameEp =
                          targetEp != null &&
                          targetEp.episodeNumber == targetEpNum;
                      final duration =
                          (isSameEp &&
                                  targetEp.durationInSeconds != null &&
                                  targetEp.durationInSeconds! > 0)
                              ? targetEp.durationInSeconds!
                              : 1440;
                      final repo = ref.read(watchProgressRepositoryProvider);
                      await repo.updateEpisodeProgress(
                        entry.animeId,
                        EpisodeProgress(
                          episodeNumber: targetEpNum,
                          episodeTitle: resolvedTitle,
                          episodeThumbnail:
                              (isSameEp && targetEp.episodeThumbnail != null)
                                  ? targetEp.episodeThumbnail!
                                  : entry.animeCover,
                          progressInSeconds: duration,
                          durationInSeconds: duration,
                          isCompleted: true,
                          watchedAt: DateTime.now(),
                        ),
                      );
                      ref
                          .read(watchSyncProvider.notifier)
                          .handleTrackingUpdate(
                            mediaId: entry.animeId,
                            episodeNum: targetEpNum,
                          );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            entry.totalEpisodes == 0 ||
                                    targetEpNum < entry.totalEpisodes
                                ? 'Episode $targetEpNum watched — Episode ${targetEpNum + 1} is up next'
                                : 'Marked Episode $targetEpNum as watched',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  // 3. Jump to Time
                  ListTile(
                    leading: Icon(
                      Iconsax.timer_1,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Jump to Time'),
                    subtitle: Text(
                      'Start Episode $targetEpNum from a specific timestamp',
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      final isSameEp =
                          targetEp != null &&
                          targetEp.episodeNumber == targetEpNum;
                      final totalDur =
                          (isSameEp &&
                                  targetEp.durationInSeconds != null &&
                                  targetEp.durationInSeconds! > 0)
                              ? Duration(seconds: targetEp.durationInSeconds!)
                              : Duration.zero;
                      final currentPos =
                          (isSameEp &&
                                  targetEp.progressInSeconds != null &&
                                  targetEp.progressInSeconds! > 0)
                              ? Duration(seconds: targetEp.progressInSeconds!)
                              : Duration.zero;

                      showDialog(
                        context: context,
                        builder:
                            (dialogCtx) => JumpToTimeDialog(
                              currentPosition: currentPos,
                              totalDuration: totalDur,
                              title: 'Jump to Time (Ep $targetEpNum)',
                              actionLabel: 'Play',
                              onJump: (targetDuration) async {
                                final localDownload = await ref
                                    .read(downloadsProvider.notifier)
                                    .findDownloadedEpisode(
                                      animeTitle: entry.animeTitle,
                                      episodeNumber: targetEpNum,
                                    );
                                if (localDownload != null && context.mounted) {
                                  await Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).push(
                                    MaterialPageRoute(
                                      builder:
                                          (_) => LocalPlayerScreen(
                                            item: localDownload,
                                            initialPosition: targetDuration,
                                          ),
                                    ),
                                  );
                                  return;
                                }
                                if (!context.mounted) return;
                                await providerAnimeMatchSearch(
                                  context: context,
                                  ref: ref,
                                  animeMedia: UniversalMedia(
                                    id: entry.animeId,
                                    title: UniversalTitle(
                                      romaji: entry.animeTitle,
                                      english: entry.animeTitle,
                                      native: entry.animeTitle,
                                    ),
                                    coverImage: UniversalCoverImage(
                                      large: entry.animeCover,
                                      medium: entry.animeCover,
                                    ),
                                    isAdult: isAdult || entry.isAdult,
                                  ),
                                  startAt: targetEpNum,
                                  startAtPosition: targetDuration.inSeconds,
                                  withAnimeMatch: true,
                                  directAutoMatch: true,
                                  fromHentaiHub: isAdult || entry.isAdult,
                                );
                              },
                            ),
                      );
                    },
                  ),
                  // 4. Download this episode
                  ListTile(
                    leading: Icon(
                      Iconsax.document_download,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Download this episode'),
                    subtitle: Text('Episode $targetEpNum'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final currentEpList = ref.read(episodeListProvider);
                      if (currentEpList.animeId != entry.animeId ||
                          currentEpList.episodes.isEmpty) {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder:
                              (ctx) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                        );
                        await ref
                            .read(episodeListProvider.notifier)
                            .fetchEpisodes(
                              animeTitle: entry.animeTitle,
                              animeId: entry.animeId,
                              mediaId: entry.animeId,
                              animeCover: entry.animeCover,
                              episodes: [],
                              force: true,
                              isAdult: isAdult || entry.isAdult,
                            );
                        if (context.mounted) {
                          Navigator.of(context, rootNavigator: true).pop();
                        }
                      }
                      if (!context.mounted) return;
                      await ref
                          .read(episodeDataProvider.notifier)
                          .downloadEpisode(context, targetEpNum);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.refresh_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Refresh source match'),
                    subtitle: const Text(
                      'Clear the saved stream match and resolve it again',
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await ref
                          .read(sourcePreferenceRepositoryProvider)
                          .clearSourcePreference(entry.animeId);
                      ref
                          .read(episodeDataProvider.notifier)
                          .clearEpisodeCache(
                            mediaId: entry.animeId,
                            episodeNumber: targetEpNum,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Source match will refresh on next play.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  // Remove from Continue Watching
                  ListTile(
                    leading: Icon(
                      Iconsax.close_circle,
                      color: theme.colorScheme.error,
                    ),
                    title: const Text('Remove from Continue Watching'),
                    subtitle: const Text('Clears your watch progress'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      showContinueWatchingUndoSnackBar(
                        context: context,
                        ref: ref,
                        animeId: entry.animeId,
                        animeTitle: entry.animeTitle,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFallback(ColorScheme colorScheme) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Iconsax.video_play,
          size: 28,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
