import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ani_dash/core/models/anime/anime_model.dep.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/helpers/navigation.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/shared/providers/anime_match_service.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';
import 'package:ani_dash/shared/providers/settings/experimental_notifier.dart';
import 'package:ani_dash/shared/ui/anime/anime_search_dialog.dart';
import 'package:ani_dash/shared/ui/anime/anime_search_notifier.dart';

Future<BaseAnimeModel?> providerAnimeMatchSearch({
  Function? beforeSearchCallback,
  Function? afterSearchCallback,
  required BuildContext context,
  required WidgetRef ref,
  required UniversalMedia animeMedia,
  bool withAnimeMatch = true,
  int? startAt,
  int? startAtPosition,
  bool showSnackbar = false,
  bool directAutoMatch = false,
  bool fromHentaiHub = false,
}) async {
  beforeSearchCallback?.call();

  try {
    // Check saved source preference
    final restoredAnime = await ref
        .read(animeMatchServiceProvider)
        .restoreSource(animeMedia.id.toString(), showSnackbar: showSnackbar);

    if (restoredAnime != null && withAnimeMatch) {
      AppLogger.d('Navigating to watch screen...');
      if (context.mounted) {
        navigateToWatch(
          context: context,
          mediaId: animeMedia.id.toString(),
          animeId: restoredAnime.id!,
          animeName: restoredAnime.name ?? 'Unknown',
          animeFormat: animeMedia.format ?? '',
          animeCover: restoredAnime.poster ?? '',
          episodes: const [],
          currentEpisode: startAt ?? 1,
          startAtPosition: startAtPosition,
          malId: int.tryParse(animeMedia.idMal ?? ''),
          fromHentaiHub: fromHentaiHub || animeMedia.isAdult,
        );
      }
      return restoredAnime;
    }

    final selectedKey = ref.read(selectedProviderKeyProvider)?.toLowerCase();
    if ((directAutoMatch || selectedKey == 'justanime') && withAnimeMatch) {
      final match = await ref
          .read(animeMatchServiceProvider)
          .findBestMatch(
            animeMedia.title,
            isAdult: fromHentaiHub || animeMedia.isAdult,
            mediaId: animeMedia.id.toString(),
            malId: animeMedia.idMal,
          );
      if (match == null) {
        throw StateError('No matching title was found on the active source.');
      }
      ref.read(animeSearchProvider.notifier).saveSelection(animeMedia, match);
      if (context.mounted) {
        navigateToWatch(
          context: context,
          mediaId: animeMedia.id.toString(),
          animeId: match.id!,
          animeName: match.name ?? animeMedia.title.userPreferred,
          animeFormat: animeMedia.format ?? '',
          animeCover:
              match.poster ??
              animeMedia.coverImage.large ??
              animeMedia.coverImage.medium ??
              '',
          episodes: const [],
          currentEpisode: startAt ?? 1,
          startAtPosition: startAtPosition,
          malId: int.tryParse(animeMedia.idMal ?? ''),
          fromHentaiHub: fromHentaiHub || animeMedia.isAdult,
        );
      }
      return match;
    }

    // Show search dialog
    final animeProvider = ref.read(selectedAnimeProvider);
    final useExtensions = ref.read(experimentalProvider).useExtensions;
    if (animeProvider == null && !useExtensions) {
      throw Exception('Anime provider is missing.');
    }
    if (!context.mounted) return null;

    return await showDialog<BaseAnimeModel>(
      context: context,
      barrierColor: Colors.black54,
      builder:
          (_) => AnimeSearchDialog(
            animeProvider: animeProvider,
            media: animeMedia,
            autoMatch: withAnimeMatch,
            startAt: startAt,
          ),
    );
  } catch (e, s) {
    AppLogger.e('Search failed', e, s);
    if (context.mounted) {
      // Use your snackbar helper
      showAppSnackBar(
        'Error',
        'Failed to load details.',
        type: ContentType.failure,
      );
    }
    return null;
  } finally {
    afterSearchCallback?.call();
  }
}
