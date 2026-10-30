import 'package:flutter/material.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/features/details/view/widgets/episodes/episode_thumbnail.dart';
import 'package:ani_dash/features/downloads/model/download_item.dart';
import 'package:ani_dash/features/downloads/model/download_status.dart';

class EpisodeGridItem extends StatelessWidget {
  final EpisodeDataModel episode;
  final int index;
  final bool isWatched;
  final double watchProgress;
  final DownloadItem? download;
  final EpisodeProgress? episodeProgress;
  final String fallbackCover;
  final Function() onTap;
  final Function() onLongPress;
  final VoidCallback? onDownload;
  final VoidCallback? onMoreOptions;
  final bool isSelected;
  final bool isSelectionMode;

  const EpisodeGridItem({
    super.key,
    required this.episode,
    required this.index,
    required this.isWatched,
    required this.watchProgress,
    this.download,
    this.episodeProgress,
    required this.fallbackCover,
    required this.onTap,
    required this.onLongPress,
    this.onDownload,
    this.onMoreOptions,
    this.isSelected = false,
    this.isSelectionMode = false,
  });


  Widget _buildGridDownloadIcon(ThemeData theme) {
    if (download == null) {
      return const Icon(
        Icons.download_rounded,
        size: 14,
        color: Colors.white,
      );
    }
    switch (download!.state) {
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        );
      case DownloadStatus.paused:
        return const Icon(
          Icons.play_arrow_rounded,
          size: 14,
          color: Colors.orangeAccent,
        );
      case DownloadStatus.queued:
        return const Icon(
          Icons.hourglass_top_rounded,
          size: 14,
          color: Colors.white70,
        );
      case DownloadStatus.failed || DownloadStatus.error:
        return const Icon(
          Icons.replay_rounded,
          size: 14,
          color: Colors.redAccent,
        );
      case DownloadStatus.downloaded:
        return const Icon(
          Icons.download_done_rounded,
          size: 14,
          color: Colors.greenAccent,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final episodeNumber = episode.number ?? index + 1;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color:
          episode.isMixed == true
              ? theme.colorScheme.primary.withValues(alpha: 0.16)
              : (episode.isFiller == true
                  ? theme.colorScheme.primary.withValues(alpha: 0.08)
                  : Colors.transparent),
      child: InkWell(
        onLongPress: onLongPress,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EpisodeThumbnail(
                    episodeThumbnail: episodeProgress?.episodeThumbnail,
                    fallbackUrl: episode.thumbnail ?? fallbackCover,
                    episodeNumber: episodeNumber,
                    isWatched: isWatched,
                    aspectRatio:
                        16 /
                        9, // Let parent constraint handle it but default typical video ratio
                  ),
                  if (isSelectionMode)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          isSelected
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 18,
                          color:
                              isSelected
                                  ? theme.colorScheme.primary
                                  : Colors.white,
                        ),
                      ),
                    )
                  else if (download != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          download!.state == DownloadStatus.downloaded
                              ? Icons.download_done
                              : Icons.downloading,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    )
                  else ...[
                    if (onMoreOptions != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          onTap: onMoreOptions,
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.more_vert,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                  if (download != null || onDownload != null)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: InkWell(
                        onTap: download?.state == DownloadStatus.downloaded ? onMoreOptions : onDownload,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: _buildGridDownloadIcon(theme),
                        ),
                      ),
                    ),
                  if (watchProgress > 0 && !isWatched)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: watchProgress,
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Episode $episodeNumber',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isWatched ? theme.hintColor : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    episode.title ?? 'Episode $episodeNumber',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          isWatched
                              ? theme.hintColor
                              : theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.1,
                    ),
                  ),
                  if (episode.isMixed == true)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.25),
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 1.0,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'MIXED',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                        ),
                      ),
                    )
                  else if (episode.isFiller == true)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.10),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'FILLER',
                        style: TextStyle(
                          color: theme.colorScheme.primary.withValues(alpha: 0.85),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
