import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/helpers/anime_match_search.dart';
import 'package:ani_dash/shared/providers/continue_watching_dismissed_provider.dart';
import 'package:ani_dash/shared/providers/anime_match_service.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';
import 'package:ani_dash/core/registery/sources/anime/justanime.dart';
import 'package:ani_dash/features/downloads/view/local_player_screen.dart';
import 'package:ani_dash/features/downloads/view_model/downloads_notifier.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/watch_sync_notifier.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/core/repositories/source_preference_repository.dart';
import 'package:ani_dash/features/watch/view/widgets/player/dialogs/jump_to_time_dialog.dart';

final Map<String, String> _continueEpisodeThumbnailCache = {};

int _credibleEpisodeDurationSeconds(int savedDuration, String? animeFormat) {
  if (savedDuration <= 0) return 0;
  final format = animeFormat?.toUpperCase();
  // Old native-player failures could persist a raw transport timestamp as the
  // episode duration. A regular TV episode cannot have 50+ minutes remaining;
  // use the standard 24-minute runtime until ExoPlayer writes the real value.
  if ((format == null || format == 'TV' || format == 'TV_SHORT') &&
      savedDuration > const Duration(minutes: 45).inSeconds) {
    return const Duration(minutes: 24).inSeconds;
  }
  return savedDuration;
}

final _continueEpisodeMetadataProvider = FutureProvider.family<
  EpisodeDataModel?,
  ({String animeId, String title, int episode, bool isAdult})
>((ref, request) async {
  // 1. Check if the active episode list already has it
  final activeList = ref.read(episodeListProvider);
  if (activeList.mediaId == request.animeId ||
      activeList.animeId == request.animeId ||
      activeList.animeTitle == request.title) {
    final activeEp = activeList.episodes
        .firstWhereOrNull((e) => e.number == request.episode);
    final hasRealTitle = activeEp?.title != null &&
        activeEp!.title!.trim().isNotEmpty &&
        !RegExp(r'^(episode|ep\.?)\s*\d+$', caseSensitive: false)
            .hasMatch(activeEp.title!.trim());
    final hasThumb = activeEp?.thumbnail?.trim().isNotEmpty == true;
    if (hasThumb || hasRealTitle) {
      return activeEp;
    }
  }

  // 2. Fast Ani.zip mappings lookup (High quality episode screenshots & titles)
  final anilistId = int.tryParse(request.animeId);
  if (anilistId != null) {
    try {
      final response = await UniversalHttpClient.instance
          .get(
            Uri.parse('https://api.ani.zip/mappings?anilist_id=$anilistId'),
            cacheConfig: CacheConfig.medium,
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final rawEpisodes = decoded['episodes'] as Map<String, dynamic>? ?? {};
        final item = rawEpisodes[request.episode.toString()];
        if (item is Map) {
          final titles = item['title'] as Map?;
          final title = titles?['en']?.toString() ??
              titles?['x-jat']?.toString() ??
              titles?['ja']?.toString();
          final image = item['image']?.toString();
          if ((image != null && image.isNotEmpty) ||
              (title != null && title.isNotEmpty)) {
            return EpisodeDataModel(
              number: request.episode,
              title: title,
              thumbnail: image,
            );
          }
        }
      }
    } catch (_) {}
  }

  // 3. Fast TVMaze lookup (HD 16:9 thumbnails and canonical titles)
  try {
    final cleanTitle = request.title
        .replaceAll(
          RegExp(
            r'\s*\((?:Dub|Sub|TV|Audio|Uncensored)[^)]*\)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\s*\[(?:Dub|Sub|TV|Audio|Uncensored)[^\]]*\]',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s*-\s*(?:Dub|Sub)$', caseSensitive: false), '')
        .trim();
    final searchUri = Uri.https('api.tvmaze.com', '/search/shows', {
      'q': cleanTitle,
    });
    final searchRes = await UniversalHttpClient.instance
        .get(searchUri, cacheConfig: CacheConfig.veryLong)
        .timeout(const Duration(seconds: 6));
    if (searchRes.statusCode == 200) {
      final searchResults = jsonDecode(searchRes.body) as List<dynamic>;
      int? showId;
      for (final res in searchResults) {
        final show = (res as Map)['show'] as Map;
        final type = show['type']?.toString().toLowerCase();
        if (type == 'animation') {
          showId = show['id'] as int?;
          break;
        }
      }
      showId ??= searchResults.isNotEmpty
          ? ((searchResults.first as Map)['show'] as Map)['id'] as int?
          : null;
      if (showId != null) {
        final epRes = await UniversalHttpClient.instance
            .get(
              Uri.parse('https://api.tvmaze.com/shows/$showId/episodes'),
              cacheConfig: CacheConfig.veryLong,
            )
            .timeout(const Duration(seconds: 8));
        if (epRes.statusCode == 200) {
          final rawEps = jsonDecode(epRes.body) as List<dynamic>;
          var absNum = 0;
          for (final raw in rawEps) {
            final epMap = raw as Map;
            if (epMap['type']?.toString().toLowerCase() != 'regular') continue;
            absNum++;
            if (absNum == request.episode) {
              final imgMap = epMap['image'];
              final img = imgMap is Map
                  ? (imgMap['original'] ?? imgMap['medium'])?.toString()
                  : null;
              final name = epMap['name']?.toString().trim();
              if ((img != null && img.isNotEmpty) ||
                  (name != null && name.isNotEmpty)) {
                return EpisodeDataModel(
                  number: request.episode,
                  title: name,
                  thumbnail: img,
                );
              }
            }
          }
        }
      }
    }
  } catch (_) {}

  // 4. JustAnime TMDB Direct lookup
  try {
    final registry = ref.read(animeSourceRegistryProvider);
    final justAnime = registry.get('justanime') ?? JustAnimeProvider();
    final res = await justAnime
        .getEpisodes(request.animeId)
        .timeout(const Duration(seconds: 8));
    final matching = res.episodes?.firstWhereOrNull(
      (e) => e.number == request.episode,
    );
    if (matching != null &&
        (matching.thumbnail != null || matching.title != null)) {
      return matching;
    }
  } catch (_) {}

  // 5. Selected Provider Fallback
  try {
    final match = await ref
        .read(animeMatchServiceProvider)
        .findBestMatch(
          UniversalTitle(
            english: request.title,
            romaji: request.title,
            native: request.title,
          ),
          mediaId: request.animeId,
          isAdult: request.isAdult,
        );
    final provider = ref.read(selectedAnimeProvider);
    if (match?.id != null && provider != null) {
      final episodes = await provider
          .getEpisodes(match!.id!, anilistId: request.animeId)
          .timeout(const Duration(seconds: 10));
      return episodes.episodes
          ?.where((e) => e.number == request.episode)
          .firstOrNull;
    }
  } catch (_) {}

  return null;
});

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
            if (entry.isOnHoldOrPaused || entry.isDropped) return false;
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
              // A tracker can advance [currentEpisode] before the local
              // playback write for the preceding episode settles. Prefer the
              // most recently watched, genuinely unfinished episode so an
              // 18/23 minute episode keeps appearing as resumable instead of
              // incorrectly jumping the card to the next episode.
              final unfinished =
                  entry.episodesProgress.values.where((item) {
                      final progress = item.progressInSeconds ?? 0;
                      return progress > 0 &&
                          !isEpisodeProgressEffectivelyComplete(item);
                    }).toList()
                    ..sort((a, b) {
                      final aTime = a.watchedAt ?? DateTime(0);
                      final bTime = b.watchedAt ?? DateTime(0);
                      return bTime.compareTo(aTime);
                    });
              final currentEp =
                  unfinished.firstOrNull ??
                  entry.episodesProgress[entry.currentEpisode];

              // Advance only after the actual end. A partially watched
              // episode must remain selected after refresh or tracker sync.
              final isCurrentCompleted =
                  currentEp != null &&
                  isEpisodeProgressEffectivelyComplete(currentEp);

              final baseEp =
                  currentEp?.episodeNumber ??
                  (entry.currentEpisode > 0 ? entry.currentEpisode : 1);
              final nextEpisodeNum =
                  isCurrentCompleted &&
                          (entry.totalEpisodes == 0 ||
                              baseEp < entry.totalEpisodes)
                      ? baseEp + 1
                      : baseEp;

              final displayEp =
                  entry.episodesProgress[nextEpisodeNum] ?? currentEp;
              String? listEpisodeTitle;
              final remoteEpisode =
                  ref
                      .watch(
                        _continueEpisodeMetadataProvider((
                          animeId: entry.animeId,
                          title: entry.animeTitle,
                          episode: nextEpisodeNum,
                          isAdult: entry.isAdult,
                        )),
                      )
                      .value;

              double progressValue = 0.0;
              if (!isCurrentCompleted && currentEp != null) {
                final p = currentEp.progressInSeconds?.toDouble() ?? 0.0;
                final d =
                    _credibleEpisodeDurationSeconds(
                      currentEp.durationInSeconds ?? 0,
                      entry.animeFormat,
                    ).toDouble();
                if (d > 0) progressValue = (p / d).clamp(0.0, 1.0);
              }

              String? listThumbnail;
              final remoteTitle = remoteEpisode?.title?.trim();
              if (remoteTitle != null &&
                  remoteTitle.isNotEmpty &&
                  !RegExp(
                    r'^(episode|ep\.?)\s*\d+$',
                    caseSensitive: false,
                  ).hasMatch(remoteTitle)) {
                listEpisodeTitle = remoteTitle;
              }
              if (remoteEpisode?.thumbnail?.trim().isNotEmpty == true) {
                listThumbnail = remoteEpisode!.thumbnail!.trim();
                final cacheKey = '${entry.animeId}:$nextEpisodeNum';
                _continueEpisodeThumbnailCache[cacheKey] = listThumbnail;
              }
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
              if (remoteEpisode != null &&
                  (listEpisodeTitle != null || listThumbnail != null)) {
                _persistEpisodeMetadata(
                  ref,
                  entry,
                  nextEpisodeNum,
                  listEpisodeTitle,
                  listThumbnail,
                );
              }
              final resolvedEpisodeTitle =
                  (listEpisodeTitle?.trim().isNotEmpty ?? false)
                      ? listEpisodeTitle!.trim()
                      : savedEpisodeTitle;
              final isMovie =
                  entry.animeFormat?.toUpperCase() == 'MOVIE' ||
                  entry.animeTitle.toLowerCase().contains('the very final') ||
                  entry.animeTitle.toLowerCase().contains('movie') ||
                  entry.animeTitle.toLowerCase().contains('film') ||
                  (entry.totalEpisodes == 1 &&
                      entry.animeFormat?.toUpperCase() == 'MOVIE');
              final episodeLabel =
                  isMovie
                      ? (resolvedEpisodeTitle.isNotEmpty &&
                              !resolvedEpisodeTitle.toLowerCase().startsWith(
                                'episode',
                              )
                          ? resolvedEpisodeTitle
                          : 'Movie')
                      : (resolvedEpisodeTitle.isEmpty ||
                              resolvedEpisodeTitle.toLowerCase() ==
                                  'episode $nextEpisodeNum'
                          ? 'E$nextEpisodeNum'
                          : 'E$nextEpisodeNum - $resolvedEpisodeTitle');
              final watchedSeconds = displayEp?.progressInSeconds ?? 0;
              final totalSeconds = _credibleEpisodeDurationSeconds(
                displayEp?.durationInSeconds ?? 0,
                entry.animeFormat,
              );
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
                  filterQuality: FilterQuality.high,
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
                              format:
                                  entry.animeFormat ??
                                  (isMovie ? 'MOVIE' : null),
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
                                !isCurrentCompleted &&
                                        (displayEp?.progressInSeconds ?? 0) > 0
                                    ? displayEp?.progressInSeconds
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
                                          isMovie
                                              ? 'MOVIE'
                                              : 'EP $nextEpisodeNum',
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

        final isMovie =
            entry.animeFormat?.toUpperCase() == 'MOVIE' ||
            entry.animeTitle.toLowerCase().contains('the very final') ||
            entry.animeTitle.toLowerCase().contains('movie') ||
            entry.animeTitle.toLowerCase().contains('film') ||
            (entry.totalEpisodes == 1 &&
                entry.animeFormat?.toUpperCase() == 'MOVIE');

        if (isMovie &&
            (resolvedTitle.isEmpty ||
                resolvedTitle.toLowerCase().startsWith('episode'))) {
          resolvedTitle = 'Movie';
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
                  if (!isMovie &&
                      (entry.totalEpisodes == 0 ||
                          targetEpNum < entry.totalEpisodes))
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
                            format: entry.animeFormat,
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
                            isMovie
                                ? 'Marked Movie as watched'
                                : (entry.totalEpisodes == 0 ||
                                        targetEpNum < entry.totalEpisodes
                                    ? 'Episode $targetEpNum watched — Episode ${targetEpNum + 1} is up next'
                                    : 'Marked Episode $targetEpNum as watched'),
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
                      isMovie
                          ? 'Start movie from a specific timestamp'
                          : 'Start Episode $targetEpNum from a specific timestamp',
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
                              title:
                                  isMovie
                                      ? 'Jump to Time'
                                      : 'Jump to Time (Ep $targetEpNum)',
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
                                    format:
                                        entry.animeFormat ??
                                        (isMovie ? 'MOVIE' : null),
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
                    title: Text(
                      isMovie ? 'Download movie' : 'Download this episode',
                    ),
                    subtitle: Text(
                      isMovie ? entry.animeTitle : 'Episode $targetEpNum',
                    ),
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
                              isMovie: isMovie,
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
