import 'package:flutter/material.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/features/downloads/model/download_item.dart';
import 'package:ani_dash/features/downloads/model/download_status.dart';

class EpisodeCompactItem extends StatelessWidget {
  final EpisodeDataModel episode;
  final int index;
  final bool isWatched;
  final double watchProgress;
  final DownloadItem? download;
  final EpisodeProgress? episodeProgress;
  final Function() onTap;
  final Function() onMoreOptions;
  final VoidCallback? onDownload;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isHindi;

  const EpisodeCompactItem({
    super.key,
    required this.episode,
    required this.index,
    required this.isWatched,
    required this.watchProgress,
    this.download,
    this.episodeProgress,
    required this.onTap,
    required this.onMoreOptions,
    this.onDownload,
    this.onLongPress,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isHindi = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        ListTile(
          tileColor:
              episode.isMixed == true
                  ? theme.colorScheme.primary.withValues(alpha: 0.16)
                  : (episode.isFiller == true
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : null),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10.0),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: Icon(
                    isSelected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color:
                        isSelected
                            ? theme.colorScheme.primary
                            : theme.hintColor,
                  ),
                ),
              SizedBox(
                width: 44,
                child: Center(
                  child: Text(
                    '${episode.number ?? index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color:
                          isWatched
                              ? theme.hintColor
                              : theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          title: Text(
            episode.title ?? 'Episode ${episode.number ?? index + 1}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: isWatched ? theme.hintColor : null),
          ),
          subtitle: _buildSubtitle(context, theme),
          trailing:
              isSelectionMode
                  ? null
                  : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onDownload != null)
                        IconButton(
                          icon: const Icon(Icons.download_rounded, size: 20),
                          tooltip: 'Download',
                          onPressed: onDownload,
                        ),
                      IconButton(
                        icon: const Icon(Icons.more_vert, size: 20),
                        tooltip: 'More options',
                        onPressed: onMoreOptions,
                      ),
                    ],
                  ),
          onTap: onTap,
          onLongPress: onLongPress,
        ),
        if (watchProgress > 0 && !isWatched)
          LinearProgressIndicator(
            value: watchProgress,
            backgroundColor: Colors.transparent,
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
            minHeight: 1,
          ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildDownloadStatus(ThemeData theme, DownloadItem download) {
    if (download.state == DownloadStatus.downloading) {
      return SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          value: download.progressPercentage,
        ),
      );
    } else if (download.state == DownloadStatus.downloaded) {
      return Icon(
        Icons.download_done_rounded,
        size: 14,
        color: theme.colorScheme.primary,
      );
    } else {
      return Icon(
        Icons.downloading,
        size: 14,
        color: theme.colorScheme.tertiary,
      );
    }
  }

  Widget? _buildSubtitle(BuildContext context, ThemeData theme) {
    final titleLower = (episode.title ?? '').toLowerCase();
    final isHindiEp = isHindi ||
        titleLower.contains('hindi') ||
        titleLower.contains('hin dub') ||
        titleLower.contains('[hin]') ||
        titleLower.contains('(hin)');
    final isDubEp = !isHindiEp && (episode.dub == true || titleLower.contains('dub'));
    final isSubEp = episode.sub == true || titleLower.contains('sub');

    final hasBadges = isHindiEp || isDubEp || isSubEp || episode.isMixed == true || episode.isFiller == true;
    if (!hasBadges && download == null) return null;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (isHindiEp)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.18),
              border: Border.all(color: Colors.orange, width: 0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'HINDI DUB',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 9,
                letterSpacing: 0.4,
              ),
            ),
          )
        else if (isDubEp)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              border: Border.all(color: Colors.blue, width: 0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'DUB',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 9,
                letterSpacing: 0.4,
              ),
            ),
          ),
        if (isSubEp && !isHindiEp)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.15),
              border: Border.all(color: Colors.teal, width: 0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'SUB',
              style: TextStyle(
                color: Colors.teal,
                fontWeight: FontWeight.bold,
                fontSize: 9,
                letterSpacing: 0.4,
              ),
            ),
          ),
        if (episode.isMixed == true)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.25),
              border: Border.all(color: theme.colorScheme.primary, width: 1.0),
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
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5), width: 0.8),
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
        if (download != null)
          _buildDownloadStatus(theme, download!),
      ],
    );
  }
}
