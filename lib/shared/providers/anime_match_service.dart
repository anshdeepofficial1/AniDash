import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ani_dash/core/models/anime/anime_model.dep.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/repositories/source_preference_repository.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/helpers/matcher.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';
import 'package:ani_dash/shared/providers/settings/experimental_notifier.dart';
import 'package:ani_dash/shared/providers/settings/content_settings_notifier.dart';
import 'package:collection/collection.dart';
import 'package:ani_dash/core/registery/sources/anime/justanime.dart';
import 'package:ani_dash/shared/providers/settings/source_notifier.dart';

part 'anime_match_service.g.dart';

@Riverpod(keepAlive: true)
AnimeMatchService animeMatchService(Ref ref) {
  return AnimeMatchService(ref);
}

class AnimeMatchService {
  final Ref _ref;

  AnimeMatchService(this._ref);

  /// Finds the best match for the given [title] using the active source.
  ///
  /// Iterates through English, Romaji, and Native titles.
  /// Returns the best match as a [BaseAnimeModel] or null if no match is found.
  Future<BaseAnimeModel?> findBestMatch(
    UniversalTitle title, {
    bool isAdult = false,
    String? mediaId,
    String? malId,
  }) async {
    final titles =
        [title.english, title.romaji, title.native]
            .where((t) => t != null && t.trim().isNotEmpty)
            .cast<String>()
            .toList();

    if (titles.isEmpty) {
      AppLogger.w("No valid title available for searching episodes.");
      return null;
    }

    BaseAnimeModel? bestCandidate;
    double bestSimilarity = 0.0;

    final nativeKey = _ref.read(selectedProviderKeyProvider)?.toLowerCase();
    // Fast Path for JustAnime: JustAnime anime ID is exactly the AniList media ID!
    if ((nativeKey == null || nativeKey == 'justanime' || nativeKey.isEmpty) &&
        mediaId != null &&
        int.tryParse(mediaId) != null) {
      try {
        final registry = _ref.read(animeSourceRegistryProvider);
        final justProvider = registry.get('justanime');
        if (justProvider is JustAnimeProvider) {
          final exists = await justProvider.probeAnimeExists(mediaId);
          if (exists) {
            AppLogger.success(
              'JustAnime direct AniList ID match verified for ID: $mediaId',
            );
            _ref.read(selectedProviderKeyProvider.notifier).select('justanime');
            return BaseAnimeModel(
              id: mediaId,
              anilistId: int.tryParse(mediaId),
              name: title.english ?? title.romaji ?? title.userPreferred,
            );
          }
        }
      } catch (e) {
        AppLogger.w('JustAnime direct AniList ID probe failed: $e');
      }
    }

    for (final title in titles) {
      try {
        final results = await search(title, isAdult: isAdult);

        if (results.isEmpty) continue;

        // 1. Direct AniList / MAL ID Match (e.g. JustAnime where ID == AniList ID)
        if (mediaId != null && mediaId.isNotEmpty) {
          final idMatch = results.firstWhereOrNull(
            (r) => r.id == mediaId || r.anilistId?.toString() == mediaId,
          );
          if (idMatch != null) {
            AppLogger.d(
              'Direct AniList ID match found: ${idMatch.name} (id: $mediaId)',
            );
            return idMatch;
          }
        }
        if (malId != null && malId.isNotEmpty) {
          final malMatch = results.firstWhereOrNull(
            (r) => r.id == malId || (r.id != null && r.id!.contains(malId)),
          );
          if (malMatch != null) {
            AppLogger.d(
              'Direct MAL ID match found: ${malMatch.name} (malId: $malId)',
            );
            return malMatch;
          }
        }

        final matches = getBestMatches<BaseAnimeModel>(
          results: results,
          title: title,
          nameSelector: (r) => r.name,
          idSelector: (r) => r.id,
        );

        if (matches.isNotEmpty) {
          final topMatch = matches.first;
          if (topMatch.similarity >= 0.75) {
            AppLogger.d(
              'High-confidence match found: ${topMatch.result.name} (via "$title")',
            );
            return topMatch.result;
          }
          if (topMatch.similarity > bestSimilarity) {
            bestSimilarity = topMatch.similarity;
            bestCandidate = topMatch.result;
          }
        }
      } catch (e) {
        AppLogger.e('Error searching for title: $title', e);
        // Continue to next title
      }
    }

    if (bestCandidate != null && bestSimilarity >= 0.55) {
      AppLogger.d(
        'Using closest match: ${bestCandidate.name} (similarity: ${bestSimilarity.toStringAsFixed(2)})',
      );
      return bestCandidate;
    }

    return null;
  }

  /// Searches for anime using the configured source (Mangayomi or Legacy).
  Future<List<BaseAnimeModel>> search(
    String query, {
    bool isAdult = false,
  }) async {
    final useExtensions = _ref.read(experimentalProvider).useExtensions;
    final nativeKey = _ref.read(selectedProviderKeyProvider);
    final isNative =
        nativeKey != null &&
        _ref.read(animeSourceRegistryProvider).has(nativeKey);

    final activeSource = _ref.read(sourceProvider).activeAnimeSource;

    if (useExtensions && !isNative && activeSource != null) {
      final res = await _ref.read(sourceProvider.notifier).search(query);

      return res.list
          .where((r) => r.title != null && r.url != null)
          .map((r) => BaseAnimeModel(id: r.url, name: r.title, poster: r.cover))
          .toList();
    } else {
      final registry = _ref.read(animeSourceRegistryProvider);
      final currentKey = _ref.read(selectedProviderKeyProvider);
      final keys = <String>[
        if (currentKey != null) currentKey,
        for (final fallback in const ['justanime', 'hianime', 'anikoto'])
          if (fallback != currentKey) fallback,
      ];
      for (final key in keys) {
        final candidate = registry.get(key);
        if (candidate == null) continue;
        try {
          final res = await candidate
              .getSearch(query, null, 1)
              .timeout(const Duration(seconds: 20));
          final results =
              res.results
                  .where((item) => item.id != null && item.name != null)
                  .map(
                    (item) => BaseAnimeModel(
                      id: item.id,
                      anilistId: item.anilistId,
                      name: item.name,
                      jname: item.jname,
                      type: item.type,
                      poster: item.poster,
                      releaseDate: item.releaseDate,
                      number: item.number,
                    ),
                  )
                  .toList();
          if (results.isNotEmpty) {
            if (key != currentKey) {
              // Keep all subsequent episode and stream calls on the provider
              // which produced this id.
              _ref.read(selectedProviderKeyProvider.notifier).select(key);
              AppLogger.w('Source search fell back from $currentKey to $key');
            }
            return results;
          }
        } catch (error) {
          AppLogger.d('Search failed on $key: $error');
        }
      }
      return [];
    }
  }

  /// Attempts to restore a previously selected source for the given [animeId].
  ///
  /// Checks if smart source is enabled and if a saved selection exists.
  /// resteres the source (legacy or extension) and returns the matched anime.
  /// Returns null if restoration fails or is disabled.
  Future<BaseAnimeModel?> restoreSource(
    String animeId, {
    bool showSnackbar = false,
  }) async {
    try {
      final repo = _ref.read(sourcePreferenceRepositoryProvider);
      final settings = _ref.read(contentSettingsProvider);

      // Smart Source Persistence Check
      AppLogger.d('Auto-Restore: Check enabled=${settings.smartSourceEnabled}');
      if (!settings.smartSourceEnabled) return null;

      final selection = repo.getSourcePreference(animeId);
      AppLogger.d('Auto-Restore: Selection found=${selection != null}');

      if (selection != null) {
        if (selection.sourceType == 'legacy') {
          final targetSourceKey = selection.sourceId ?? 'justanime';
          final registry = _ref.read(animeSourceRegistryProvider);
          final selectedKey = _ref.read(selectedProviderKeyProvider);
          if (selectedKey != null && targetSourceKey != selectedKey) {
            AppLogger.d(
              'Ignoring saved $targetSourceKey match; user selected $selectedKey',
            );
            return null;
          }
          final provider =
              registry.get(targetSourceKey) ?? registry.get('justanime');
          final matchedId = selection.matchedAnimeId;
          if (provider != null && matchedId != null && matchedId.isNotEmpty) {
            try {
              if (provider is JustAnimeProvider) {
                final exists = await provider
                    .probeAnimeExists(matchedId)
                    .timeout(const Duration(seconds: 6), onTimeout: () => true);
                if (exists) {
                  AppLogger.d(
                    'Auto-Restore: Fast verified JustAnime for ID $matchedId',
                  );
                  return BaseAnimeModel(
                    id: matchedId,
                    name: selection.matchedAnimeTitle,
                    anilistId: int.tryParse(matchedId),
                  );
                }
              }
              final episodes = await provider
                  .getEpisodes(matchedId)
                  .timeout(const Duration(seconds: 20));
              if (episodes.episodes?.isNotEmpty == true) {
                AppLogger.d(
                  'Auto-Restore: Success with ${provider.providerName}',
                );
                return BaseAnimeModel(
                  id: matchedId,
                  name: selection.matchedAnimeTitle,
                );
              }
              AppLogger.w('Auto-Restore: Saved match has no episodes');
            } catch (error) {
              AppLogger.w('Auto-Restore: Saved match is stale: $error');
            }
          } else {
            AppLogger.w('Auto-Restore: Legacy provider not found');
          }
        } else if (['mangayomi', 'aniyomi'].contains(selection.sourceType)) {
          AppLogger.d(
            'Auto-Restore: Restoring extension source ${selection.sourceId}',
          );
          // Switch to extensions
          _ref.read(experimentalProvider.notifier).toggleExtensions(true);
          _ref.read(selectedProviderKeyProvider.notifier).clear();

          final sourceNotifier = _ref.read(sourceProvider.notifier);
          final source = _ref
              .read(sourceProvider)
              .installedAnimeExtensions
              .firstWhereOrNull((s) => s.id.toString() == selection.sourceId);

          if (source != null) {
            sourceNotifier.setActiveSource(source);
            AppLogger.d('Auto-Restore: Success');
            return BaseAnimeModel(
              id: selection.matchedAnimeId,
              name: selection.matchedAnimeTitle,
            );
          } else {
            AppLogger.w('Auto-Restore: Extension source not found');
          }
        }
      }
    } catch (e, st) {
      AppLogger.e('Failed to auto-restore source selection', e, st);
    }
    return null;
  }
}
