import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/utils/html_parser.dart';
import 'package:ani_dash/features/browse/model/search_filter.dart';
import 'package:ani_dash/features/details/view/widgets/horizontal_media_list.dart';
import 'package:ani_dash/features/details/view_model/details_page_notifier.dart';
import 'package:ani_dash/helpers/navigation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/core/services/franchise_service.dart';
import 'package:ani_dash/features/details/view/widgets/watch_guide_bottom_sheet.dart';
import 'package:ani_dash/features/ai/view/widgets/ask_nia_button.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';

class DetailsContent extends ConsumerWidget {
  final UniversalMedia anime;
  final bool isLoading;
  final Function(UniversalMedia)? onMediaTap;
  final String mediaId;

  const DetailsContent({
    super.key,
    required this.anime,
    required this.mediaId,
    this.isLoading = false,
    this.onMediaTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentEpisode =
        ref
            .watch(animeWatchProgressProvider(mediaId))
            .asData
            ?.value
            ?.currentEpisode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (anime.nextAiringEpisode != null) ...[
            NextEpisodeWidget(anime: anime),
            const SizedBox(height: 12),
          ],
          AvailableLanguagesCard(mediaId: mediaId, anime: anime),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: AskNiaButton(
              animeId: mediaId,
              animeTitle:
                  anime.title.english ??
                  anime.title.romaji ??
                  anime.title.native,
              currentEpisode: currentEpisode,
            ),
          ),
          const SizedBox(height: 16),
          AnimeSynopsis(
            description: anime.description ?? '',
            isLoading: isLoading && (anime.description?.isEmpty ?? true),
          ),
          const SizedBox(height: 16),
          if (anime.rankings.isNotEmpty) ...[
            const SizedBox(height: 24),
            AnimeRankings(rankings: anime.rankings),
          ],
          const SizedBox(height: 24),
          AdditionalInfoWidget(anime: anime),
          _WatchOrderSection(anime: anime, onMediaTap: onMediaTap),
          if (anime.staff.isNotEmpty) ...[
            const SizedBox(height: 24),
            HorizontalMediaSection<UniversalStaff>(
              title: 'Staff',
              items: anime.staff,
              isLoading: isLoading,
              itemBuilder: (context, staff) {
                return StaffCard(
                  staff: staff,
                  onTap: () {
                    // Handle staff tap if needed
                  },
                );
              },
            ),
          ],
          const SizedBox(height: 24),
          HorizontalMediaSection<UniversalMediaRelation>(
            title: 'Related',
            items: anime.relations,
            isLoading: isLoading,
            itemBuilder: (context, relation) {
              return MediaCard(
                media: relation.media,
                badgeText: _formatRelationType(relation.relationType),
                onTap: () => onMediaTap?.call(relation.media),
              );
            },
          ),
          const SizedBox(height: 24),
          HorizontalMediaSection<UniversalMedia>(
            title: 'More Like This',
            items: anime.recommendations,
            isLoading: isLoading,
            itemBuilder: (context, media) {
              return MediaCard(
                media: media,
                onTap: () => onMediaTap?.call(media),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatRelationType(String type) {
    if (type.isEmpty) return type;
    final formatted = type.replaceAll('_', ' ');
    return formatted[0].toUpperCase() + formatted.substring(1).toLowerCase();
  }
}

class _WatchOrderSection extends ConsumerStatefulWidget {
  final UniversalMedia anime;
  final Function(UniversalMedia)? onMediaTap;

  const _WatchOrderSection({required this.anime, this.onMediaTap});

  @override
  ConsumerState<_WatchOrderSection> createState() => _WatchOrderSectionState();
}

class _WatchOrderSectionState extends ConsumerState<_WatchOrderSection> {
  bool _isExtrasExpanded = false;

  @override
  Widget build(BuildContext context) {
    final franchiseAsync = ref.watch(franchiseWatchOrderProvider(widget.anime));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return franchiseAsync.when(
      data: (franchise) {
        final mainItems = franchise.mainStory;
        final extraItems = franchise.optionalExtras;
        if (mainItems.length <= 1 && extraItems.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Watch Order',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${mainItems.length} Story Parts',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                AskNiaButton(
                  compact: true,
                  animeId: widget.anime.id,
                  animeTitle:
                      widget.anime.title.english ??
                      widget.anime.title.romaji ??
                      widget.anime.title.native,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: mainItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = mainItems[index];
                final isCurrent = item.isCurrent;

                final epCount =
                    item.episodes != null && item.episodes! > 0
                        ? '${item.episodes} eps'
                        : null;
                final yearText = item.year != null ? '${item.year}' : null;

                final metadataParts = [
                  item.orderLabel,
                  if (epCount != null) epCount,
                  if (yearText != null) yearText,
                ];

                return InkWell(
                  onTap: () {
                    WatchGuideBottomSheet.show(
                      context,
                      item: item,
                      onOpenDetails: () => widget.onMediaTap?.call(item.media),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isCurrent
                              ? colorScheme.primaryContainer.withValues(
                                alpha: 0.35,
                              )
                              : colorScheme.surfaceContainerHighest.withValues(
                                alpha: 0.4,
                              ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            isCurrent
                                ? colorScheme.primary
                                : colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                        width: isCurrent ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Number circle
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                isCurrent
                                    ? colorScheme.primary
                                    : colorScheme.surfaceContainerHigh,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color:
                                  isCurrent
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Titles and metadata
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight:
                                      isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                  color:
                                      isCurrent
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (item.placementNote != null &&
                                  item.placementNote!.isNotEmpty) ...[
                                Container(
                                  margin: const EdgeInsets.only(bottom: 3),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer
                                        .withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.placementNote!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                              Text(
                                metadataParts.join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'CURRENT',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 9,
                              ),
                            ),
                          )
                        else
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (extraItems.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    'Optional / Extras',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${extraItems.length} Extras',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final displayedExtras =
                      _isExtrasExpanded
                          ? extraItems
                          : extraItems.take(3).toList();

                  return Column(
                    children: [
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: displayedExtras.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = displayedExtras[index];
                          final isCurrent = item.isCurrent;
                          final note =
                              item.placementNote ?? item.format ?? 'Extra';

                          return InkWell(
                            onTap: () {
                              WatchGuideBottomSheet.show(
                                context,
                                item: item,
                                onOpenDetails:
                                    () => widget.onMediaTap?.call(item.media),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isCurrent
                                        ? colorScheme.primaryContainer
                                            .withValues(alpha: 0.25)
                                        : colorScheme.surfaceContainerHigh
                                            .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      isCurrent
                                          ? colorScheme.primary
                                          : colorScheme.outlineVariant
                                              .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.isMovie
                                        ? Icons.movie_outlined
                                        : (item.isOvaOrSpecial
                                            ? Icons.video_library_outlined
                                            : Icons.play_circle_outline),
                                    size: 20,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.displayTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                fontWeight:
                                                    isCurrent
                                                        ? FontWeight.bold
                                                        : FontWeight.w500,
                                                color:
                                                    isCurrent
                                                        ? colorScheme.primary
                                                        : colorScheme.onSurface,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          note,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colorScheme.onSurface
                                                    .withValues(alpha: 0.6),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isCurrent)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'CURRENT',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colorScheme.onPrimary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 9,
                                            ),
                                      ),
                                    )
                                  else
                                    Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      if (extraItems.length > 3) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _isExtrasExpanded = !_isExtrasExpanded;
                              });
                            },
                            icon: Icon(
                              _isExtrasExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 20,
                            ),
                            label: Text(
                              _isExtrasExpanded
                                  ? 'Show Less'
                                  : 'Show More (${extraItems.length - 3} more)',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class AvailableLanguagesCard extends ConsumerStatefulWidget {
  final String mediaId;
  final UniversalMedia anime;

  const AvailableLanguagesCard({
    super.key,
    required this.mediaId,
    required this.anime,
  });

  @override
  ConsumerState<AvailableLanguagesCard> createState() =>
      _AvailableLanguagesCardState();
}

class _AvailableLanguagesCardState
    extends ConsumerState<AvailableLanguagesCard> {
  String? _lookupKey;
  Future<({bool sub, bool dub})>? _availability;

  @override
  Widget build(BuildContext context) {
    final episodes = ref.watch(episodeListProvider);
    final detailsState = ref.watch(detailsPageProvider(widget.mediaId));
    final isMatching =
        detailsState.animeIdForSource != null &&
        episodes.animeId == detailsState.animeIdForSource;
    final firstEpisode =
        (!isMatching || episodes.episodes.isEmpty)
            ? null
            : episodes.episodes.first;
    final key = '${widget.mediaId}:${episodes.animeId}:${firstEpisode?.id}';
    if (firstEpisode != null && episodes.animeId != null && key != _lookupKey) {
      _lookupKey = key;
      _availability = _checkAvailability(firstEpisode);
    }

    return FutureBuilder<({bool sub, bool dub})>(
      future: _availability,
      builder: (context, snapshot) {
        final result = snapshot.data;
        final loading =
            episodes.isLoading ||
            firstEpisode == null ||
            snapshot.connectionState == ConnectionState.waiting;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Icon(Iconsax.headphone, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Audio & Subs',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              _AudioBadge(
                label: 'SUB',
                available: result?.sub,
                loading: loading,
              ),
              const SizedBox(width: 8),
              _AudioBadge(
                label: 'DUB',
                available: result?.dub,
                loading: loading,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<({bool sub, bool dub})> _checkAvailability(dynamic episode) async {
    final regular = await ref
        .read(episodeDataProvider.notifier)
        .checkLanguageAvailability(episode);
    return (sub: regular.sub, dub: regular.dub);
  }
}

class _AudioBadge extends StatelessWidget {
  final String label;
  final bool? available;
  final bool loading;

  const _AudioBadge({
    required this.label,
    required this.available,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (loading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  colors.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    final isAvail = available == true;
    final badgeColor = isAvail ? Colors.green : colors.outlineVariant;
    final bgColor =
        isAvail
            ? Colors.green.withValues(alpha: 0.12)
            : colors.surfaceContainerHighest.withValues(alpha: 0.4);
    final textColor =
        isAvail
            ? (theme.brightness == Brightness.dark
                ? Colors.greenAccent
                : Colors.green.shade800)
            : colors.onSurfaceVariant.withValues(alpha: 0.5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              isAvail ? badgeColor.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAvail ? Icons.check_circle_rounded : Icons.cancel_outlined,
            size: 13,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Info widget displaying anime statistics in a sleek horizontal row
class AnimeInfoCard extends ConsumerWidget {
  final UniversalMedia anime;
  final VoidCallback onShare;

  const AnimeInfoCard({super.key, required this.anime, required this.onShare});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadedCount = ref.watch(
      episodeListProvider.select((s) => s.episodes.length),
    );
    final nextEp = anime.nextAiringEpisode?.episode;
    final bool hasValidTotal = anime.episodes != null && anime.episodes! > 0;
    final int? airingReleased =
        (nextEp != null && nextEp > 1) ? nextEp - 1 : null;
    final isReleasing = anime.status?.toLowerCase() == 'releasing';

    final int? resolvedEpCount =
        isReleasing
            ? (airingReleased ??
                (loadedCount > 0 ? loadedCount : null) ??
                (hasValidTotal ? anime.episodes : null))
            : ((hasValidTotal ? anime.episodes : null) ??
                airingReleased ??
                (loadedCount > 0 ? loadedCount : null));

    final String epValue =
        resolvedEpCount != null
            ? (isReleasing || !hasValidTotal
                ? '$resolvedEpCount+'
                : '$resolvedEpCount')
            : (isReleasing ? 'Ongoing' : 'TBA');

    final String epLabel =
        (hasValidTotal && !isReleasing) ? 'Episodes' : 'Ongoing';

    final mainStudio = anime.studios.firstWhere(
      (s) => s.isMain,
      orElse:
          () =>
              anime.studios.isNotEmpty
                  ? anime.studios.first
                  : UniversalStudio(name: 'Unknown', isMain: true),
    );

    final stats = [
      if (anime.averageScore != null)
        _StatData(
          icon: Iconsax.star1,
          value: (anime.averageScore! / 10).toStringAsFixed(1),
          label: 'Rating',
          color: Colors.amber,
        ),
      if (anime.seasonYear != null)
        _StatData(
          icon: Iconsax.calendar_1,
          value: '${anime.seasonYear}',
          label: anime.season ?? 'Year',
          color: Colors.blueAccent,
        ),
      if (resolvedEpCount != null || isReleasing || hasValidTotal)
        _StatData(
          icon: Iconsax.layer,
          value: epValue,
          label: epLabel,
          color: Colors.purpleAccent,
        ),
      if (anime.format != null)
        _StatData(
          icon: Iconsax.monitor,
          value: anime.format!,
          label: 'Format',
          color: Colors.tealAccent,
        ),
      if (anime.duration != null)
        _StatData(
          icon: Iconsax.timer_1,
          value: '${anime.duration}m',
          label: 'Duration',
          color: Colors.orangeAccent,
        ),
      _StatData(
        icon: Iconsax.building_3,
        value:
            mainStudio.name.length > 20
                ? '${mainStudio.name.substring(0, 18)}...'
                : mainStudio.name,
        label: 'Studio',
        color: Colors.pinkAccent,
      ),
    ];

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stats.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final stat = stats[index];
          return _StatItem(stat: stat);
        },
      ),
    );
  }
}

class _StatData {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  _StatData({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });
}

class _StatItem extends StatelessWidget {
  final _StatData stat;

  const _StatItem({required this.stat});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(stat.icon, size: 16, color: stat.color),
              const SizedBox(width: 8),
              Text(
                stat.value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            stat.label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget to display next episode countdown
class NextEpisodeWidget extends StatelessWidget {
  final UniversalMedia anime;

  const NextEpisodeWidget({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    final nextEp = anime.nextAiringEpisode;
    if (nextEp == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final timeUntil = Duration(seconds: nextEp.timeUntilAiring ?? 0);
    final days = timeUntil.inDays;
    final hours = timeUntil.inHours % 24;
    final minutes = timeUntil.inMinutes % 60;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Iconsax.clock, color: colorScheme.onPrimary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EPISODE ${nextEp.episode}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                RichText(
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    children: [
                      const TextSpan(text: 'Airing in '),
                      TextSpan(
                        text: '${days}d ${hours}h ${minutes}m',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AnimeSynopsis extends StatefulWidget {
  final String description;
  final double collapsedHeight;
  final bool isLoading;

  const AnimeSynopsis({
    super.key,
    required this.description,
    this.collapsedHeight = 150,
    this.isLoading = false,
  });

  @override
  State<AnimeSynopsis> createState() => _AnimeSynopsisState();
}

class _AnimeSynopsisState extends State<AnimeSynopsis>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Synopsis',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        if (widget.isLoading)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 14,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 14,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: MediaQuery.of(context).size.width * 0.6,
                height: 14,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          )
        else ...[
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  _isExpanded
                      ? const BoxConstraints() // no height limit
                      : BoxConstraints(maxHeight: widget.collapsedHeight),
              child: Text(
                parseHtmlToString(widget.description),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
                softWrap: true,
                overflow: TextOverflow.fade,
              ),
            ),
          ),
          if (widget.description.length > 200)
            TextButton(
              onPressed: () => setState(() => _isExpanded = !_isExpanded),
              child: Text(_isExpanded ? 'Show Less' : 'Read More'),
            ),
        ],
      ],
    );
  }
}

/// Rankings widget for displaying anime rankings horizontally
class AnimeRankings extends StatelessWidget {
  final List<UniversalMediaRanking> rankings;

  const AnimeRankings({super.key, required this.rankings});

  @override
  Widget build(BuildContext context) {
    if (rankings.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: Text(
            'Achievements', // Renamed from Rankings for flair
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rankings.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder:
                (context, index) => RankingPill(ranking: rankings[index]),
          ),
        ),
      ],
    );
  }
}

class RankingPill extends StatelessWidget {
  final UniversalMediaRanking ranking;

  const RankingPill({super.key, required this.ranking});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isTop100 = (ranking.rank ?? 999) <= 100;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:
            isTop100
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isTop100
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isTop100 ? Iconsax.cup : Iconsax.ranking_1,
            size: 16,
            color:
                isTop100
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '#${ranking.rank} ${ranking.context} ${ranking.year ?? ''}'.trim(),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color:
                  isTop100
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class AdditionalInfoWidget extends StatelessWidget {
  final UniversalMedia anime;

  const AdditionalInfoWidget({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (anime.tags.isNotEmpty) ...[
          _SectionHeader(title: 'Tags', icon: Iconsax.tag),
          const SizedBox(height: 12),
          AnimeTagsWidget(tags: anime.tags),
          const SizedBox(height: 32),
        ],
        _SectionHeader(title: 'Details', icon: Iconsax.info_circle),
        const SizedBox(height: 16),
        AnimeInformationGrid(anime: anime),
        const SizedBox(height: 32),
        if (anime.trailer != null || anime.siteUrl != null) ...[
          _SectionHeader(title: 'Links', icon: Iconsax.link),
          const SizedBox(height: 16),
          ExternalLinksWidget(anime: anime),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class AnimeTagsWidget extends StatefulWidget {
  final List<String> tags;

  const AnimeTagsWidget({super.key, required this.tags});

  @override
  State<AnimeTagsWidget> createState() => _AnimeTagsWidgetState();
}

class _AnimeTagsWidgetState extends State<AnimeTagsWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = widget.tags;
    const initialLimit = 10;
    final showToggle = tags.length > initialLimit;
    final displayTags =
        (_isExpanded || !showToggle) ? tags : tags.take(initialLimit).toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...displayTags.map((tag) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                navigateToBrowse(context, filter: SearchFilter(tags: [tag]));
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
                child: Text(
                  tag,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
        if (showToggle)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: _isExpanded ? 0.3 : 0.6,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isExpanded
                          ? 'Show less'
                          : '+${tags.length - initialLimit} more',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AnimeInformationGrid extends ConsumerWidget {
  final UniversalMedia anime;

  const AnimeInformationGrid({super.key, required this.anime});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadedCount = ref.watch(
      episodeListProvider.select((s) => s.episodes.length),
    );
    final nextEp = anime.nextAiringEpisode?.episode;
    final bool hasValidTotal = anime.episodes != null && anime.episodes! > 0;
    final int? airingReleased =
        (nextEp != null && nextEp > 1) ? nextEp - 1 : null;
    final isReleasing = anime.status?.toLowerCase() == 'releasing';

    final int? resolvedEpCount =
        isReleasing
            ? (airingReleased ??
                (loadedCount > 0 ? loadedCount : null) ??
                (hasValidTotal ? anime.episodes : null))
            : ((hasValidTotal ? anime.episodes : null) ??
                airingReleased ??
                (loadedCount > 0 ? loadedCount : null));

    final items = [
      if (anime.title.english != null)
        _InfoItemData('English Title', anime.title.english!),
      if (anime.title.native != null)
        _InfoItemData('Native Title', anime.title.native!),
      if (anime.synonyms.isNotEmpty)
        _InfoItemData('Synonyms', anime.synonyms.take(2).join(', ')),
      if (hasValidTotal && !isReleasing)
        _InfoItemData('Episodes', '${anime.episodes}')
      else if (resolvedEpCount != null && resolvedEpCount > 0)
        _InfoItemData('Episodes', '$resolvedEpCount+ (Ongoing)')
      else if (isReleasing)
        _InfoItemData('Episodes', 'Ongoing')
      else
        _InfoItemData('Episodes', 'TBA'),
      if (anime.source != null)
        _InfoItemData('Source', _formatSource(anime.source!)),
      if (anime.startDate != null)
        _InfoItemData(
          'Aired',
          _formatDateRange(
            anime.startDate,
            anime.endDate,
            isOngoing: anime.status?.toLowerCase() == 'releasing',
          ),
        ),
      if (anime.studios.isNotEmpty)
        _InfoItemData('Studios', anime.studios.map((s) => s.name).join(', ')),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children:
          items.map((item) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final screenWidth = MediaQuery.of(context).size.width;
                final itemWidth = (screenWidth - 32 - 16) / 2;

                return SizedBox(
                  width: itemWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }).toList(),
    );
  }

  String _formatSource(String source) {
    return source
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ');
  }

  String _formatDateRange(
    dynamic start,
    dynamic end, {
    bool isOngoing = false,
  }) {
    String format(dynamic d) {
      if (d == null) return '?';
      if (d.year == null) return '?';
      // Handle partial dates
      if (d.month == null) return '${d.year}';
      final dt = DateTime(d.year, d.month!, d.day ?? 1);
      return DateFormat.yMMM().format(dt);
    }

    final s = format(start);
    if (end == null || end.year == null) {
      return isOngoing ? '$s - Ongoing' : s;
    }
    final e = format(end);
    if (e == '?') {
      return isOngoing ? '$s - Ongoing' : s;
    }
    return '$s - $e';
  }
}

class _InfoItemData {
  final String label;
  final String value;
  _InfoItemData(this.label, this.value);
}

class ExternalLinksWidget extends StatelessWidget {
  final UniversalMedia anime;

  const ExternalLinksWidget({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (anime.trailer != null && (anime.trailer!.site == 'youtube'))
          Expanded(
            child: _LinkButton(
              icon: Iconsax.video_play,
              label: 'Watch Trailer',
              color: const Color(0xFFFF0000), // YouTube Red
              onTap:
                  () => _launchUrl(
                    'https://www.youtube.com/watch?v=${anime.trailer!.id}',
                  ),
            ),
          ),
        if (anime.trailer != null && anime.siteUrl != null)
          const SizedBox(width: 12),
        if (anime.siteUrl != null)
          Expanded(
            child: _LinkButton(
              icon: Iconsax.global,
              label: 'AniList',
              color: const Color(0xFF02A9FF), // AniList Blue
              onTap: () => _launchUrl(anime.siteUrl!),
            ),
          ),
      ],
    );
  }

  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

class _LinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _LinkButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
