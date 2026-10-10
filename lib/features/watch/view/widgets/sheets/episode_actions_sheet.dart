// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/core/services/share_link_service.dart';
import 'package:ani_dash/features/watch/view/widgets/player/dialogs/jump_to_time_dialog.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/features/watch/view_model/player/player_provider.dart';
import 'package:ani_dash/features/watch/view_model/watch_sync_notifier.dart';
import 'package:ani_dash/shared/ui/sponsor/sponsor_dialog.dart';

class EpisodeActionsSheet extends ConsumerWidget {
  final String mediaId;
  final int episodeNumber;
  final String? episodeTitle;
  final String? episodeDescription;
  final String? animeTitle;
  final String? animeFormat;
  final VoidCallback onDismiss;

  const EpisodeActionsSheet({
    super.key,
    required this.mediaId,
    required this.episodeNumber,
    this.episodeTitle,
    this.episodeDescription,
    this.animeTitle,
    this.animeFormat,
    required this.onDismiss,
  });

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMovie = (animeFormat ?? '').toUpperCase() == 'MOVIE';
    final repo = ref.read(watchProgressRepositoryProvider);
    final progress = repo.getEpisodeProgress(mediaId, episodeNumber);
    final isWatched = progress?.isCompleted == true;
    final player = ref.watch(playerStateProvider);
    final epData = ref.read(episodeListProvider).getEpisode(episodeNumber);

    final titleText = isMovie
        ? (animeTitle ?? 'Movie Options')
        : (episodeTitle ?? 'Episode $episodeNumber Options');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMovie ? 'Movie Details & Actions' : 'Episode $episodeNumber Actions',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        titleText,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onDismiss,
                ),
              ],
            ),
            const Divider(height: 16),

            // 1. Mark as Watched / Unwatched
            ListTile(
              dense: true,
              leading: Icon(
                isWatched
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded,
                color: isWatched ? Colors.green : colorScheme.onSurfaceVariant,
              ),
              title: Text(
                isWatched
                    ? (isMovie ? 'Mark movie as unwatched' : 'Mark episode as unwatched')
                    : (isMovie ? 'Mark movie as watched' : 'Mark episode as watched'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                isWatched
                    ? 'Currently marked as completed'
                    : 'Update your watchlist & progress tracker',
              ),
              onTap: () async {
                onDismiss();
                await repo.updateEpisodeProgress(
                  mediaId,
                  EpisodeProgress(
                    episodeNumber: episodeNumber,
                    episodeTitle: episodeTitle ?? (isMovie ? 'Movie' : 'Episode $episodeNumber'),
                    episodeThumbnail: epData?.thumbnail ?? progress?.episodeThumbnail,
                    progressInSeconds: !isWatched ? 1440 : 0,
                    durationInSeconds: 1440,
                    isCompleted: !isWatched,
                    watchedAt: DateTime.now(),
                  ),
                );
                if (!isWatched) {
                  ref.read(watchSyncProvider.notifier).updateTracking(
                    mediaId: mediaId,
                    episodeNum: episodeNumber,
                  );
                }
              },
            ),

            // 2. Jump to Time
            ListTile(
              dense: true,
              leading: const Icon(Iconsax.timer_1),
              title: const Text(
                'Jump to timestamp',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: Text(
                _formatDuration(player.position),
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {
                onDismiss();
                showDialog(
                  context: context,
                  builder: (ctx) => JumpToTimeDialog(
                    currentPosition: player.position,
                    totalDuration: player.duration,
                    title: 'Jump to Time',
                    actionLabel: 'Jump',
                    onJump: (targetDuration) {
                      ref
                          .read(playerStateProvider.notifier)
                          .seek(targetDuration);
                    },
                  ),
                );
              },
            ),

            // 3. Share Episode
            ListTile(
              dense: true,
              leading: const Icon(Icons.share_rounded),
              title: Text(
                isMovie ? 'Share movie' : 'Share episode',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Share with friends or social media'),
              onTap: () async {
                onDismiss();
                await ShareLinkService.shareEpisode(
                  animeId: mediaId,
                  animeTitle: animeTitle ?? 'Anime',
                  episode: episodeNumber,
                );
              },
            ),

            // 4. About / Synopsis
            if (episodeDescription != null && episodeDescription!.trim().isNotEmpty)
              ListTile(
                dense: true,
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(
                  isMovie ? 'About this movie' : 'Episode synopsis',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  episodeDescription!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  onDismiss();
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(isMovie ? (animeTitle ?? 'Synopsis') : 'Episode $episodeNumber Synopsis'),
                      content: SingleChildScrollView(
                        child: Text(
                          episodeDescription!,
                          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              ),

            // 5. Reload Stream / Clear Cache
            ListTile(
              dense: true,
              leading: const Icon(Icons.refresh_rounded),
              title: const Text(
                'Reload stream',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Clear episode stream cache & re-fetch'),
              onTap: () async {
                onDismiss();
                ref.read(episodeDataProvider.notifier).clearEpisodeCache(
                  mediaId: mediaId,
                  episodeNumber: episodeNumber,
                );
                await ref.read(episodeDataProvider.notifier).loadEpisode(
                  ep: episodeNumber,
                  play: true,
                  mediaId: mediaId,
                );
              },
            ),

            // 6. Sponsor AniDash
            ListTile(
              dense: true,
              leading: const Icon(Icons.favorite_rounded, color: Colors.pinkAccent),
              title: const Text(
                'Support AniDash 💖',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Keep AniDash 100% free & ad-free'),
              onTap: () {
                onDismiss();
                SponsorDialog.show(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
