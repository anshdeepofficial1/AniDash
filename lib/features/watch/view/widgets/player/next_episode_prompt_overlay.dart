import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/next_episode_prompt_provider.dart';
import 'package:ani_dash/shared/providers/settings/player_notifier.dart';
import 'package:ani_dash/core/services/franchise_service.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';
import 'package:ani_dash/helpers/anime_match_search.dart';

final _storyMovieCueProvider = FutureProvider.autoDispose.family<
  FranchiseWatchOrderItem?,
  ({String mediaId, int episode})
>((ref, request) async {
  final server = ref.read(episodeDataProvider).selectedServer;
  if (server?.isDub != true) return null;

  final movie = await FranchiseService().movieAfterEpisode(
    request.mediaId,
    request.episode,
  );
  if (movie == null) return null;

  final watched = ref
      .read(watchProgressRepositoryProvider)
      .getProgress(movie.id);
  if (watched != null &&
      (watched.status.toLowerCase() == 'completed' ||
          watched.episodesProgress.values.any(
            (episode) => episode.isCompleted,
          ))) {
    return null;
  }

  final source = ref.read(selectedAnimeProvider);
  if (source == null) return null;
  try {
    final search = await source.getSearch(movie.displayTitle, null, 1);
    final exact = search.results.firstWhereOrNull(
      (candidate) =>
          candidate.anilistId?.toString() == movie.id ||
          (candidate.name ?? '').trim().toLowerCase() ==
              movie.displayTitle.trim().toLowerCase(),
    );
    if (exact == null || (exact.episodes?.dub ?? 0) < 1) return null;
    return movie;
  } catch (_) {
    // Never interrupt playback unless dub availability was positively verified.
    return null;
  }
});

class NextEpisodePromptOverlay extends ConsumerWidget {
  const NextEpisodePromptOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVisible = ref.watch(nextEpisodePromptProvider);
    if (!isVisible) return const SizedBox.shrink();

    final stopAfter = ref.watch(
      playerSettingsProvider.select((s) => s.stopAfterCurrentEpisode),
    );
    if (stopAfter) return const SizedBox.shrink();

    final currentEp = ref.watch(
      episodeDataProvider.select((s) => s.selectedEpisode),
    );
    if (currentEp == null) return const SizedBox.shrink();

    final nextEpNum = currentEp + 1;
    final epList = ref.watch(episodeListProvider);
    final nextEp = epList.episodes.firstWhereOrNull(
      (e) => e.number == nextEpNum,
    );

    final movieCue =
        epList.mediaId == null
            ? null
            : ref
                .watch(
                  _storyMovieCueProvider((
                    mediaId: epList.mediaId!,
                    episode: currentEp,
                  )),
                )
                .value;

    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      bottom: 80,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: AnimatedOpacity(
          opacity: isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.4),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child:
                movieCue != null
                    ? _StoryMoviePrompt(
                      movie: movieCue,
                      nextEpisode: nextEpNum,
                      onSkip: () {
                        ref
                            .read(nextEpisodePromptProvider.notifier)
                            .dismissForEpisodeTransition();
                        ref
                            .read(episodeDataProvider.notifier)
                            .changeEpisode(null, by: 1);
                      },
                      onWatch: () async {
                        ref.read(nextEpisodePromptProvider.notifier).dismiss();
                        await providerAnimeMatchSearch(
                          context: context,
                          ref: ref,
                          animeMedia: movieCue.media,
                        );
                      },
                    )
                    : Row(
                      children: [
                        // Thumbnail
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 70,
                            height: 50,
                            color: colorScheme.surfaceContainerHighest,
                            child:
                                (nextEp?.thumbnail != null &&
                                        nextEp!.thumbnail!.isNotEmpty)
                                    ? CachedNetworkImage(
                                      imageUrl: nextEp.thumbnail!,
                                      fit: BoxFit.cover,
                                      errorWidget:
                                          (_, _, _) => Icon(
                                            Icons.play_circle_outline,
                                            color: colorScheme.primary,
                                          ),
                                    )
                                    : Icon(
                                      Icons.play_circle_outline,
                                      color: colorScheme.primary,
                                    ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Info & Action
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Up Next: Ep $nextEpNum',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (nextEp?.title != null &&
                                  nextEp!.title!.isNotEmpty)
                                Text(
                                  nextEp.title!,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 28,
                                child: FilledButton.icon(
                                  onPressed: () {
                                    ref
                                        .read(
                                          nextEpisodePromptProvider.notifier,
                                        )
                                        .dismissForEpisodeTransition();
                                    ref
                                        .read(episodeDataProvider.notifier)
                                        .changeEpisode(null, by: 1);
                                  },
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Play Now',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Dismiss Button
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white70,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: () {
                            ref
                                .read(nextEpisodePromptProvider.notifier)
                                .dismiss();
                          },
                        ),
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}

class _StoryMoviePrompt extends StatelessWidget {
  const _StoryMoviePrompt({
    required this.movie,
    required this.nextEpisode,
    required this.onSkip,
    required this.onWatch,
  });

  final FranchiseWatchOrderItem movie;
  final int nextEpisode;
  final VoidCallback onSkip;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: CachedNetworkImage(
                imageUrl: movie.coverImage,
                width: 52,
                height: 72,
                fit: BoxFit.cover,
                errorWidget:
                    (_, __, ___) => const SizedBox(
                      width: 52,
                      height: 72,
                      child: Icon(Icons.movie_outlined, color: Colors.white70),
                    ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Story movie available in English Dub',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    movie.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Recommended before Episode $nextEpisode',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onSkip,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                ),
                child: const Text('Skip & Play Episode'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: onWatch,
                icon: const Icon(Icons.movie_filter_rounded, size: 17),
                label: const Text('Watch Movie'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
