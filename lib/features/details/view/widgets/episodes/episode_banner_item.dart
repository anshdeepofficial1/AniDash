import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';
import 'package:ani_dash/features/downloads/model/download_item.dart';
import 'package:ani_dash/features/downloads/model/download_status.dart';

class EpisodeBannerItem extends StatelessWidget {
  final EpisodeDataModel episode;
  final int index;
  final bool isWatched;
  final double watchProgress;
  final DownloadItem? download;
  final EpisodeProgress? episodeProgress;
  final String fallbackCover;
  final VoidCallback onTap;
  final VoidCallback onMoreOptions;
  final VoidCallback? onDownload;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool isSelectionMode;

  const EpisodeBannerItem({
    super.key,
    required this.episode,
    required this.index,
    required this.isWatched,
    required this.watchProgress,
    this.download,
    this.episodeProgress,
    required this.fallbackCover,
    required this.onTap,
    required this.onMoreOptions,
    this.onDownload,
    this.onLongPress,
    this.isSelected = false,
    this.isSelectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final episodeNumber = episode.number ?? index + 1;
    final thumbnail = episodeProgress?.episodeThumbnail;
    final fallbackUrl = episode.thumbnail ?? fallbackCover;
    const accentPink = Color(0xFFE91E63);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            height: 74,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    isSelected
                        ? accentPink
                        : isWatched
                        ? theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.15,
                        )
                        : theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.45,
                        ),
                width: isSelected ? 2.0 : 1.0,
              ),
              color: theme.colorScheme.surfaceContainer,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Background thumbnail
                Positioned.fill(
                  child:
                      thumbnail != null
                          ? (thumbnail.startsWith('http')
                              ? CachedNetworkImage(
                                imageUrl: thumbnail,
                                fit: BoxFit.cover,
                                errorWidget:
                                    (_, _, _) => _buildFallbackImage(theme),
                              )
                              : Image.memory(
                                base64Decode(thumbnail),
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (_, _, _) => _buildFallbackImage(theme),
                              ))
                          : (fallbackUrl.isNotEmpty
                              ? CachedNetworkImage(
                                imageUrl: fallbackUrl,
                                fit: BoxFit.cover,
                                httpHeaders: {
                                  "Referer": fallbackUrl.split('#').last,
                                  "User-Agent":
                                      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
                                },
                                errorWidget:
                                    (_, _, _) => _buildFallbackImage(theme),
                              )
                              : _buildFallbackImage(theme)),
                ),

                // Dark Tint / Gradient Overlay (Watched: darker contrast, Unwatched: lighter)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors:
                            isWatched
                                ? [
                                  Colors.black.withValues(alpha: 0.94),
                                  Colors.black.withValues(alpha: 0.88),
                                  Colors.black.withValues(alpha: 0.92),
                                ]
                                : [
                                  Colors.black.withValues(alpha: 0.65),
                                  Colors.black.withValues(alpha: 0.45),
                                  Colors.black.withValues(alpha: 0.55),
                                ],
                      ),
                    ),
                  ),
                ),

                // Content Row
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Selection checkbox if in selection mode
                        if (isSelectionMode)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Icon(
                              isSelected
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: isSelected ? accentPink : Colors.white70,
                              size: 22,
                            ),
                          ),

                        // Play or Watched Circular Button
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                isWatched
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : accentPink,
                            border:
                                isWatched
                                    ? Border.all(
                                      color: Colors.greenAccent.withValues(
                                        alpha: 0.8,
                                      ),
                                      width: 1.5,
                                    )
                                    : null,
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            isWatched
                                ? Icons.check_rounded
                                : Icons.play_arrow_rounded,
                            color:
                                isWatched
                                    ? Colors.greenAccent
                                    : Colors.white,
                            size: isWatched ? 22 : 24,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Episode Number & Title
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'EPISODE $episodeNumber',
                                    style: TextStyle(
                                      color:
                                          isWatched
                                              ? Colors.white60
                                              : accentPink,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  if (isWatched) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.greenAccent.withValues(
                                            alpha: 0.6,
                                          ),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check_circle_rounded,
                                            color: Colors.greenAccent,
                                            size: 11,
                                          ),
                                          SizedBox(width: 3),
                                          Text(
                                            'WATCHED',
                                            style: TextStyle(
                                              color: Colors.greenAccent,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (episode.isMixed == true) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'MIXED',
                                        style: TextStyle(
                                          color: theme.colorScheme.onPrimary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ] else if (episode.isFiller == true) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'FILLER',
                                        style: TextStyle(
                                          color: theme.colorScheme.onPrimary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                episode.title ?? 'Episode $episodeNumber',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      isWatched
                                          ? Colors.white60
                                          : Colors.white,
                                  fontSize: 14,
                                  fontWeight:
                                      isWatched
                                          ? FontWeight.w500
                                          : FontWeight.w600,
                                ),
                              ),
                              if (download != null) ...[
                                const SizedBox(height: 2),
                                _buildDownloadBadge(theme, download!),
                              ],
                            ],
                          ),
                        ),

                        // Trailing actions: Download & More
                        if (!isSelectionMode) ...[
                          if (onDownload != null)
                            IconButton(
                              icon: const Icon(
                                Icons.download_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              padding: EdgeInsets.zero,
                              tooltip: 'Download',
                              onPressed: onDownload,
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: Colors.white70,
                              size: 20,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            padding: EdgeInsets.zero,
                            tooltip: 'More options',
                            onPressed: onMoreOptions,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Bottom watch progress indicator line
                if (watchProgress > 0 && !isWatched)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: watchProgress,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      color: isWatched ? Colors.greenAccent : accentPink,
                      minHeight: 2.5,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackImage(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.movie_filter_rounded,
          size: 32,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildDownloadBadge(ThemeData theme, DownloadItem download) {
    String text;
    Color color;
    IconData icon;

    switch (download.state) {
      case DownloadStatus.downloading:
        final progress = (download.progressPercentage * 100).round().clamp(
          0,
          100,
        );
        text = 'Downloading $progress%';
        color = Colors.blueAccent;
        icon = Icons.downloading;
        break;
      case DownloadStatus.downloaded:
        text = 'Downloaded';
        color = Colors.greenAccent;
        icon = Icons.check_circle_outline;
        break;
      case DownloadStatus.failed || DownloadStatus.error:
        text = 'Failed';
        color = Colors.redAccent;
        icon = Icons.error_outline;
        break;
      case DownloadStatus.paused:
        text = 'Paused';
        color = Colors.orangeAccent;
        icon = Icons.pause_circle_outline;
        break;
      default:
        text = 'Queued';
        color = Colors.white70;
        icon = Icons.hourglass_empty;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
