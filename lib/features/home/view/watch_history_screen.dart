import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/features/home/view_model/watch_history_notifier.dart';
import 'package:ani_dash/helpers/anime_match_search.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/features/watch/view/widgets/player/dialogs/jump_to_time_dialog.dart';
import 'package:ani_dash/features/watch/view_model/watch_sync_notifier.dart';
import 'package:go_router/go_router.dart';

class WatchHistoryScreen extends ConsumerWidget {
  const WatchHistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(watchHistoryProvider);
    final notifier = ref.read(watchHistoryProvider.notifier);
    final filtered = state.filteredHistory;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_2),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Continue Watching',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          _SearchBar(
            hint: "Search continue watching...",
            onChanged: notifier.setSearchQuery,
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      state.searchQuery.isEmpty
                          ? "No anime in continue watching"
                          : "No matches found",
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _HistoryTile(
                      entry: filtered[index],
                      onDelete: () =>
                          notifier.deleteProgress(filtered[index].animeId),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class AnimeHistoryDetailScreen extends ConsumerWidget {
  final String animeId;
  const AnimeHistoryDetailScreen({super.key, required this.animeId});

  void _play(
    BuildContext context,
    WidgetRef ref,
    AnimeWatchProgressEntry entry,
    int ep,
  ) {
    providerAnimeMatchSearch(
      context: context,
      ref: ref,
      animeMedia: UniversalMedia(
        id: entry.animeId,
        title: UniversalTitle(
          english: entry.animeTitle,
          romaji: entry.animeTitle,
        ),
        coverImage: UniversalCoverImage(large: entry.animeCover),
      ),
      startAt: ep,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(animeHistoryDetailProvider(animeId));
    final notifier = ref.read(animeHistoryDetailProvider(animeId).notifier);

    final entry = state.entry;
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Iconsax.arrow_left_2),
            onPressed: () => context.pop(),
          ),
          title: const Text('Watch History'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final filtered = state.filteredEpisodes;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_2),
          onPressed: () => context.pop(),
        ),
        title: Text(
          entry.animeTitle,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          _DetailHeader(
            entry: entry,
            currentEp: filtered.isNotEmpty ? filtered.first.episodeNumber : 1,
            onResume: () => _play(
              context,
              ref,
              entry,
              filtered.isNotEmpty ? filtered.first.episodeNumber : 1,
            ),
            onNext: () => _play(
              context,
              ref,
              entry,
              (filtered.isNotEmpty ? filtered.first.episodeNumber : 0) + 1,
            ),
          ),
          _SearchBar(
            hint: "Search episode number or title...",
            onChanged: notifier.setSearchQuery,
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8),
              itemCount: filtered.length,
              itemBuilder: (context, index) => _EpisodeRow(
                episode: filtered[index],
                onPlay: () =>
                    _play(context, ref, entry, filtered[index].episodeNumber),
                onDelete: () => notifier.deleteEpisodeProgress(
                  filtered[index].episodeNumber,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          onChanged: onChanged,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: theme.colorScheme.outline,
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Iconsax.search_normal,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  final AnimeWatchProgressEntry entry;
  final int currentEp;
  final VoidCallback onResume;
  final VoidCallback onNext;

  const _DetailHeader({
    required this.entry,
    required this.currentEp,
    required this.onResume,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: entry.animeCover,
              width: 90,
              height: 130,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "CURRENTLY AT",
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Episode $currentEp",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                // Optimized Action Blade
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Material(
                          color: theme.colorScheme.primary,
                          child: InkWell(
                            onTap: onResume,
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              child: Text(
                                "RESUME",
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 1),
                      Expanded(
                        flex: 1,
                        child: Material(
                          color: theme.colorScheme.primary,
                          child: InkWell(
                            onTap: onNext,
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              child: Text(
                                "NEXT",
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
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

class _HistoryTile extends ConsumerWidget {
  final AnimeWatchProgressEntry entry;
  final VoidCallback onDelete;
  const _HistoryTile({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentEp = entry.episodesProgress[entry.currentEpisode];
    final dur = currentEp?.durationInSeconds ?? 0;
    final prog = currentEp?.progressInSeconds ?? 0;
    final isCurrentCompleted = (currentEp?.isCompleted == true &&
            (dur == 0 || prog >= dur - 45 || (prog / dur) >= 0.92)) ||
        (dur > 0 && (prog / dur) >= 0.92);
    final baseEp = entry.currentEpisode > 0 ? entry.currentEpisode : 1;
    final nextEpNum = isCurrentCompleted &&
            (entry.totalEpisodes == 0 || baseEp < entry.totalEpisodes)
        ? baseEp + 1
        : baseEp;
    final epText = entry.totalEpisodes > 0
        ? "Episode $nextEpNum of ${entry.totalEpisodes}"
        : "Episode $nextEpNum";

    return Dismissible(
      key: ValueKey(entry.animeId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        color: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.delete_forever_rounded,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text("Remove from Continue Watching"),
              content: const Text(
                "Are you sure you want to remove this anime from Continue Watching?",
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Remove"),
                ),
              ],
            );
          },
        );
      },
      onDismissed: (direction) => onDelete(),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AnimeHistoryDetailScreen(animeId: entry.animeId),
          ),
        ),
        onLongPress: () {
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (sheetContext) {
              final ep = entry.episodesProgress[nextEpNum];
              final totalDur = (ep?.durationInSeconds != null && ep!.durationInSeconds! > 0)
                  ? Duration(seconds: ep.durationInSeconds!)
                  : Duration.zero;
              final currentPos = (ep?.progressInSeconds != null && ep!.progressInSeconds! > 0)
                  ? Duration(seconds: ep.progressInSeconds!)
                  : Duration.zero;
              return SafeArea(
                child: Padding(
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
                        'Episode $nextEpNum',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Divider(height: 24),
                      ListTile(
                        leading: const Icon(Iconsax.timer_1, color: Colors.cyanAccent),
                        title: const Text('Jump to Time'),
                        subtitle: Text('Start Episode $nextEpNum from a specific timestamp'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          showDialog(
                            context: context,
                            builder: (dialogCtx) => JumpToTimeDialog(
                              currentPosition: currentPos,
                              totalDuration: totalDur,
                              title: 'Jump to Time (Ep $nextEpNum)',
                              actionLabel: 'Play',
                              onJump: (targetDuration) async {
                                await providerAnimeMatchSearch(
                                  context: context,
                                  ref: ref,
                                  animeMedia: UniversalMedia(
                                    id: entry.animeId,
                                    title: UniversalTitle(
                                      english: entry.animeTitle,
                                      romaji: entry.animeTitle,
                                      native: entry.animeTitle,
                                    ),
                                    coverImage: UniversalCoverImage(large: entry.animeCover),
                                    isAdult: entry.isAdult,
                                  ),
                                  startAt: nextEpNum,
                                  startAtPosition: targetDuration.inSeconds,
                                  withAnimeMatch: true,
                                  directAutoMatch: true,
                                  fromHentaiHub: entry.isAdult,
                                );
                              },
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                        title: Text('Mark Episode $nextEpNum as Watched'),
                        subtitle: const Text('Marks this episode complete and updates progress'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          final dur = totalDur.inSeconds > 0 ? totalDur.inSeconds : 1440;
                          ref.read(watchProgressRepositoryProvider).updateEpisodeProgress(
                            entry.animeId,
                            EpisodeProgress(
                              episodeNumber: nextEpNum,
                              episodeTitle: ep?.episodeTitle.isNotEmpty == true
                                  ? ep!.episodeTitle
                                  : 'Episode $nextEpNum',
                              episodeThumbnail: ep?.episodeThumbnail ?? entry.animeCover,
                              progressInSeconds: dur,
                              durationInSeconds: dur,
                              isCompleted: true,
                              watchedAt: DateTime.now(),
                            ),
                          );
                          ref.read(watchSyncProvider.notifier).handleTrackingUpdate(
                            mediaId: entry.animeId,
                            episodeNum: nextEpNum,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Marked Episode $nextEpNum as watched'),
                              duration: const Duration(seconds: 2),
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
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: entry.animeCover,
            width: 44,
            height: 60,
            fit: BoxFit.cover,
          ),
        ),
        title: Text(
          entry.animeTitle,
          maxLines: 1,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        subtitle: Text(
          "$epText • ${DateFormat.MMMd().format(entry.effectiveLastPlayedTime)}",
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Iconsax.play5, size: 22),
              color: theme.colorScheme.primary,
              tooltip: 'Play Episode $nextEpNum',
              onPressed: () {
                providerAnimeMatchSearch(
                  context: context,
                  ref: ref,
                  animeMedia: UniversalMedia(
                    id: entry.animeId,
                    title: UniversalTitle(
                      english: entry.animeTitle,
                      romaji: entry.animeTitle,
                      native: entry.animeTitle,
                    ),
                    coverImage: UniversalCoverImage(large: entry.animeCover),
                    isAdult: entry.isAdult,
                  ),
                  startAt: nextEpNum,
                  withAnimeMatch: true,
                  directAutoMatch: true,
                  fromHentaiHub: entry.isAdult,
                );
              },
            ),
            const Icon(Iconsax.arrow_right_3, size: 14),
          ],
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final EpisodeProgress episode;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  const _EpisodeRow({
    required this.episode,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (episode.durationInSeconds ?? 0) > 0
        ? (episode.progressInSeconds ?? 0) / episode.durationInSeconds!
        : 0.0;
    return Dismissible(
      key: ValueKey(episode.episodeNumber),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        color: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.delete_forever_rounded,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text("Delete Progress"),
              content: const Text(
                "Are you sure you want to delete progress for this episode?",
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Delete"),
                ),
              ],
            );
          },
        );
      },
      onDismissed: (direction) => onDelete(),
      child: ListTile(
        onTap: onPlay,
        leading: SizedBox(
          width: 110,
          height: 62,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _Thumb(url: episode.episodeThumbnail),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 2,
                  valueColor: AlwaysStoppedAnimation(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const Center(
                child: Icon(Iconsax.play5, color: Colors.white70, size: 20),
              ),
            ],
          ),
        ),
        title: Text(
          "Episode ${episode.episodeNumber}",
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        subtitle: Text(
          episode.episodeTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? url;
  const _Thumb({this.url});
  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return Container(color: Colors.black12);
    return url!.startsWith('http')
        ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover)
        : Image.memory(base64Decode(url!.split(',').last), fit: BoxFit.cover);
  }
}
