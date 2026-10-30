import 'package:flutter/material.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/features/downloads/model/download_item.dart';
import 'package:ani_dash/features/downloads/model/download_status.dart';

class EpisodeBlockItem extends StatelessWidget {
  final EpisodeDataModel episode;
  final int index;
  final bool isWatched;
  final double watchProgress;
  final DownloadItem? download;
  final Function() onTap;
  final Function() onLongPress;
  final VoidCallback? onDownload;
  final bool isSelected;
  final bool isSelectionMode;

  const EpisodeBlockItem({
    super.key,
    required this.episode,
    required this.index,
    required this.isWatched,
    required this.watchProgress,
    this.download,
    required this.onTap,
    required this.onLongPress,
    this.onDownload,
    this.isSelected = false,
    this.isSelectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final episodeNumber = episode.number ?? index + 1;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color:
              isSelected
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : isWatched
                  ? theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  )
                  : episode.isMixed == true
                  ? theme.colorScheme.primary.withValues(alpha: 0.28)
                  : episode.isFiller == true
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border:
              isSelected
                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                  : episode.isMixed == true
                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                  : episode.isFiller == true
                  ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.6), width: 1.5)
                  : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                '$episodeNumber',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color:
                      isWatched ? theme.hintColor : theme.colorScheme.onSurface,
                ),
              ),
            ),

            if (isSelectionMode)
              Positioned(
                top: 4,
                left: 4,
                child: Icon(
                  isSelected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 16,
                  color:
                      isSelected ? theme.colorScheme.primary : theme.hintColor,
                ),
              ),

            // Download Icon
            if (download != null)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  download!.state == DownloadStatus.downloaded
                      ? Icons.download_done
                      : download!.state == DownloadStatus.paused
                      ? Icons.pause_circle_outline
                      : download!.state == DownloadStatus.queued
                      ? Icons.hourglass_top_rounded
                      : download!.state == DownloadStatus.failed
                      ? Icons.replay_rounded
                      : Icons.downloading,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
              ),

            // Progress Bar
            if (watchProgress > 0 && !isWatched)
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: LinearProgressIndicator(
                  value: watchProgress,
                  minHeight: 3,
                  backgroundColor: theme.colorScheme.surfaceDim,
                  color:
                      isWatched
                          ? theme.colorScheme.secondary
                          : theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

            // Watched Checkmark (Subtle)
            if (isWatched)
              Positioned(
                bottom: 4,
                right: 4,
                child: Icon(Icons.check, size: 14, color: theme.hintColor),
              ),
          ],
        ),
      ),
    );
  }
}
