import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';

String? animeSeasonBadge(UniversalMedia anime) {
  final format = anime.format?.toUpperCase() ?? '';
  if (format == 'MOVIE') return 'M';
  if (format == 'MUSIC') return null;

  final titles = [
    anime.title.english,
    anime.title.romaji,
    anime.title.native,
    ...anime.synonyms,
  ].whereType<String>().join(' ');

  final lowerTitles = titles.toLowerCase();
  if (format == 'OVA') return 'OVA';
  if (format == 'SPECIAL' ||
      lowerTitles.contains('special') ||
      lowerTitles.contains('chibi')) {
    return 'SP';
  }

  final seasonMatch = RegExp(
    r'(?:season|series)\s*(\d+)|\b(\d+)(?:st|nd|rd|th)\s+season\b|第\s*(\d+)\s*季',
    caseSensitive: false,
  ).firstMatch(titles);

  final partMatch = RegExp(
    r'(?:part|cour)\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(titles);

  if (seasonMatch != null) {
    final sNum =
        int.tryParse(
          seasonMatch.group(1) ??
              seasonMatch.group(2) ??
              seasonMatch.group(3) ??
              '',
        ) ??
        1;
    final pNum = int.tryParse(partMatch?.group(1) ?? '');
    return pNum != null && pNum > 1 ? 'S$sNum-$pNum' : 'S$sNum';
  }

  if (partMatch != null) {
    final pNum = int.tryParse(partMatch.group(1) ?? '');
    if (pNum != null && pNum > 1) {
      return 'S1-$pNum';
    }
  }

  if (RegExp(
    r'\bii\b|season\s*2|2nd\s*season|wu\s*mian\s*ren',
    caseSensitive: false,
  ).hasMatch(titles)) {
    return 'S2';
  }

  return 'S1';
}

int animeSeasonSortKey(UniversalMedia anime) {
  final badge = animeSeasonBadge(anime);
  if (badge == null) return 9999;
  final match = RegExp(r'^S(\d+)(?:-(\d+))?$').firstMatch(badge);
  final season = int.tryParse(match?.group(1) ?? '') ?? 1;
  final part = int.tryParse(match?.group(2) ?? '') ?? 1;
  return season * 100 + part;
}

String? formatEpisodeText({
  required UniversalMedia? anime,
  int? progress,
  bool compact = false,
  bool uppercase = false,
}) {
  final totalEpisodes = anime?.episodes;
  final hasTotal = totalEpisodes != null && totalEpisodes > 0;
  final currentProgress = progress;
  final isMovie =
      anime?.format?.toUpperCase() == 'MOVIE' ||
      (anime != null &&
          (anime.episodes == 1 || anime.episodes == null) &&
          (anime.title.userPreferred.toLowerCase().contains('the very final') ||
              anime.title.userPreferred.toLowerCase().contains('movie') ||
              anime.title.userPreferred.toLowerCase().contains('film')));

  // The dedicated season badge already renders movies as "M". Repeating
  // "MOVIE" in the metadata row wastes scarce card space on desktop.
  if (isMovie) {
    return null;
  }

  if (currentProgress != null && currentProgress > 0) {
    if (hasTotal) {
      return compact
          ? 'EP $currentProgress/$totalEpisodes'
          : 'EP $currentProgress / $totalEpisodes';
    } else {
      return 'EP $currentProgress';
    }
  } else if (hasTotal) {
    if (compact) {
      return uppercase ? '$totalEpisodes EPS' : '$totalEpisodes EP';
    } else {
      return '$totalEpisodes Episodes';
    }
  } else {
    final nextEp = anime?.nextAiringEpisode?.episode;
    if (nextEp != null && nextEp > 1) {
      final releasedEp = nextEp - 1;
      if (compact) {
        return uppercase ? '$releasedEp+ EPS' : '$releasedEp+ ep';
      } else {
        return '$releasedEp+ Episodes';
      }
    }
  }
  return null;
}

class EpisodesInfo extends StatelessWidget {
  final UniversalMedia? anime;
  final bool compact;
  final int? progress;

  const EpisodesInfo({
    super.key,
    required this.anime,
    this.compact = false,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = formatEpisodeText(
      anime: anime,
      progress: progress,
      compact: compact,
    );

    if (text == null) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Icon(
          Iconsax.play_circle,
          size: 14,
          color: Colors.white.withValues(alpha: 0.9),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.9),
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class Tag extends StatelessWidget {
  final String text;
  final Color? color;
  final Color? textColor;
  final IconData? icon;
  final bool hasShadow;

  const Tag({
    super.key,
    required this.text,
    this.color,
    this.textColor,
    this.icon,
    this.hasShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bgColor = color ?? colorScheme.primaryContainer;
    final txtColor = textColor ?? colorScheme.onPrimaryContainer;
    final iconColor = textColor ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow:
            hasShadow
                ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
                : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: iconColor),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: txtColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class AnimeTitle extends StatelessWidget {
  final UniversalMedia? anime;
  final int maxLines;
  final bool minimal;
  final bool enhanced;
  final TextStyle? style;

  const AnimeTitle({
    super.key,
    required this.anime,
    required this.maxLines,
    this.minimal = false,
    this.enhanced = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title =
        anime?.title.english ??
        anime?.title.romaji ??
        anime?.title.native ??
        'Unknown Title';

    if (minimal) {
      return Text(
        title,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      );
    }

    if (enhanced) {
      return Text(
        title,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style:
            style ??
            theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  offset: const Offset(0, 1),
                  blurRadius: 3,
                ),
              ],
            ),
      );
    }

    // Original style
    return Text(
      title,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style:
          style ??
          theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.5),
                offset: const Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
    );
  }
}

class AnimeImage extends StatelessWidget {
  final UniversalMedia? anime;
  final String tag;
  final double height;

  const AnimeImage({
    super.key,
    required this.anime,
    required this.tag,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      child: Container(
        color: Colors.black,
        height: height,
        width: double.infinity,
        child: CachedNetworkImage(
          imageUrl:
              anime?.highResCoverImage.isNotEmpty == true
                  ? anime!.highResCoverImage
                  : (anime?.coverImage.large ?? anime?.coverImage.medium ?? ''),
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 300),
          placeholder: (_, _) => AnimeCardShimmer(height: height),
          errorWidget: (_, _, _) => AnimeCardShimmer(height: height),
          filterQuality: FilterQuality.high,
          useOldImageOnUrlChange: true,
        ),
      ),
    );
  }
}

class AnimeCardShimmer extends StatelessWidget {
  final double height;
  final double? width;

  const AnimeCardShimmer({super.key, required this.height, this.width});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: height,
      width: width,
      color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.5),
    );
  }
}

class AdultBadge extends StatelessWidget {
  final UniversalMedia? anime;

  const AdultBadge({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    if (anime?.isMature != true) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.5),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const Text(
        '18+',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class SeasonBadge extends StatelessWidget {
  final UniversalMedia anime;

  const SeasonBadge({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    final label = animeSeasonBadge(anime);
    if (label == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.55),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
