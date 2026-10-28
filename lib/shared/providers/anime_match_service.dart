import 'package:ani_dash/core/utils/language_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ani_dash/core/models/anime/anime_model.dep.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/repositories/source_preference_repository.dart';
import 'package:ani_dash/data/isar/isar_source_preference.dart';
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
    final rawTitles = [title.english, title.romaji, title.userPreferred, title.native];
    final titles = <String>[];
    final seen = <String>{};

    void addTitle(String? t) {
      if (t == null) return;
      final trimmed = t.trim();
      if (trimmed.isEmpty) return;
      final lower = trimmed.toLowerCase();
      if (seen.add(lower)) {
        titles.add(trimmed);
      }
    }

    for (final raw in rawTitles) {
      if (raw == null || raw.trim().isEmpty) continue;
      addTitle(raw);

      // 1. Colon-separated prefix (e.g. "Demon Slayer: Kimetsu no Yaiba" -> "Demon Slayer")
      if (raw.contains(':')) {
        final prefix = raw.split(':').first.trim();
        if (prefix.length >= 3) addTitle(prefix);
      }

      // 2. Dash-separated prefix (e.g. "Naruto Shippuden - The Movie" -> "Naruto Shippuden")
      if (raw.contains(' - ') || raw.contains(' – ')) {
        final prefix = raw.split(RegExp(r'\s*[-–]\s*')).first.trim();
        if (prefix.length >= 3) addTitle(prefix);
      }

      // 3. Remove parentheses / brackets: e.g. "Attack on Titan (TV)" -> "Attack on Titan"
      final withoutParens = raw
          .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
          .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
          .trim();
      if (withoutParens.isNotEmpty && withoutParens.length >= 3) {
        addTitle(withoutParens);
      }
    }

    if (titles.isEmpty) {
      AppLogger.w("No valid title available for searching episodes.");
      return null;
    }

    BaseAnimeModel? bestCandidate;
    double bestSimilarity = 0.0;

    final nativeKey = _ref.read(selectedProviderKeyProvider)?.toLowerCase();
    final useExt = _ref.read(experimentalProvider).useExtensions;
    final isExplicitJustAnime = !useExt && (nativeKey == 'justanime');
    if (isExplicitJustAnime &&
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
            (r) => r.id == malId,
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
            _saveMatchPreference(mediaId, topMatch.result);
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

    if (bestCandidate != null && bestSimilarity >= 0.40) {
      AppLogger.d(
        'Using closest match: ${bestCandidate.name} (similarity: ${bestSimilarity.toStringAsFixed(2)})',
      );
      _saveMatchPreference(mediaId, bestCandidate);
      return bestCandidate;
    }

    final activeSource = _ref.read(sourceProvider).activeAnimeSource;
    final isHindiExt = useExt &&
        activeSource != null &&
        LanguageUtils.isHindiSourceNameOrLang(
          name: activeSource.name,
          lang: activeSource.lang,
        );

    // If active source is Hindi and no match was found on it (e.g. One Piece has no Hindi dub),
    // seamlessly try fallback to official server (JustAnime) so playback does not fail or freeze!
    if (bestCandidate == null && isHindiExt) {
      AppLogger.w('No match found on Hindi source for "$mediaId". Trying Official JustAnime fallback...');
      try {
        final registry = _ref.read(animeSourceRegistryProvider);
        final justProvider = registry.get('justanime');
        if (justProvider != null) {
          if (mediaId != null && int.tryParse(mediaId) != null && justProvider is JustAnimeProvider) {
            final exists = await justProvider.probeAnimeExists(mediaId);
            if (exists) {
              return BaseAnimeModel(
                id: mediaId,
                anilistId: int.tryParse(mediaId),
                name: title.english ?? title.romaji ?? title.userPreferred,
              );
            }
          }
          for (final t in titles) {
            final res = await justProvider.getSearch(t, null, 1).timeout(const Duration(seconds: 10));
            final justResults = res.results
                .where((item) => item.id != null && item.name != null)
                .map((item) => BaseAnimeModel(id: item.id!, name: item.name!, poster: item.poster))
                .toList();
            if (justResults.isNotEmpty) {
              final matches = getBestMatches<BaseAnimeModel>(
                results: justResults,
                title: t,
                nameSelector: (r) => r.name,
                idSelector: (r) => r.id,
              );
              if (matches.isNotEmpty && matches.first.similarity >= 0.40) {
                return matches.first.result;
              }
            }
          }
        }
      } catch (e) {
        AppLogger.w('JustAnime fallback probe failed: $e');
      }
    }

    return null;
  }

  void _saveMatchPreference(String? mediaId, BaseAnimeModel anime) {
    if (mediaId == null || mediaId.isEmpty) return;
    try {
      final repo = _ref.read(sourcePreferenceRepositoryProvider);
      final useExtensions = _ref.read(experimentalProvider).useExtensions;
      final nativeKey = _ref.read(selectedProviderKeyProvider);
      final isNative =
          nativeKey != null &&
          _ref.read(animeSourceRegistryProvider).has(nativeKey);

      if (useExtensions && !isNative) {
        final activeSource = _ref.read(sourceProvider).activeAnimeSource;
        if (activeSource != null) {
          final selection = IsarSourcePreference(
            animeId: mediaId,
            sourceId: activeSource.id?.toString(),
            sourceType: 'mangayomi',
            matchedAnimeId: anime.id,
            matchedAnimeTitle: anime.name,
          );
          repo.saveSourcePreference(mediaId, anime.poster ?? '', selection);
        }
      } else {
        final currentKey = _ref.read(selectedProviderKeyProvider) ?? 'justanime';
        final selection = IsarSourcePreference(
          animeId: mediaId,
          sourceId: currentKey,
          sourceType: 'legacy',
          matchedAnimeId: anime.id,
          matchedAnimeTitle: anime.name,
        );
        repo.saveSourcePreference(mediaId, anime.poster ?? '', selection);
      }
    } catch (e) {
      AppLogger.w('Failed to auto-persist match preference: $e');
    }
  }

  /// Searches for anime using the configured source (Mangayomi or Legacy).
  Future<List<BaseAnimeModel>> search(
    String query, {
    bool isAdult = false,
  }) async {
    final useExtensions = _ref.read(experimentalProvider).useExtensions;
    final activeSource = _ref.read(sourceProvider).activeAnimeSource;
    final nativeKey = _ref.read(selectedProviderKeyProvider)?.toLowerCase();

    if (useExtensions && activeSource != null) {
      try {
        final res = await _ref.read(sourceProvider.notifier).search(query);

        return res.list
            .where((r) => r.title != null && r.url != null)
            .map((r) => BaseAnimeModel(id: r.url, name: r.title, poster: r.cover))
            .toList();
      } catch (e) {
        AppLogger.w('Extension search for "$query" failed: $e');
      }
    }

    final registry = _ref.read(animeSourceRegistryProvider);
    final currentKey = nativeKey ?? 'justanime';
    final candidate = registry.get(currentKey);
    if (candidate != null) {
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
        if (results.isNotEmpty) return results;
      } catch (error) {
        AppLogger.d('Search failed on $currentKey: $error');
      }
    }
    return [];
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
          // A saved native match must never override an active extension.
          if (selectedKey == null &&
              _ref.read(experimentalProvider).useExtensions &&
              _ref.read(sourceProvider).activeAnimeSource != null) {
            return null;
          }
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
          final selectedKey = _ref.read(selectedProviderKeyProvider);
          final useExtensions = _ref.read(experimentalProvider).useExtensions;
          final activeSource = _ref.read(sourceProvider).activeAnimeSource;

          // If user currently selected a native provider, DO NOT restore an extension!
          if (selectedKey != null || !useExtensions) {
            AppLogger.d(
              'Ignoring saved extension match; user selected native $selectedKey',
            );
            return null;
          }

          // If user selected a different extension than saved selection, DO NOT restore the old extension!
          if (activeSource != null && activeSource.id?.toString() != selection.sourceId) {
            AppLogger.d(
              'Ignoring saved extension ${selection.sourceId}; user selected ${activeSource.name}',
            );
            return null;
          }

          // Don't restore if title was "None" or empty or invalid
          if (selection.matchedAnimeTitle == null ||
              selection.matchedAnimeTitle!.trim().isEmpty ||
              selection.matchedAnimeTitle!.toLowerCase() == 'none' ||
              selection.matchedAnimeId == null ||
              selection.matchedAnimeId!.trim().isEmpty) {
            return null;
          }

          AppLogger.d(
            'Auto-Restore: Restoring extension source ${selection.sourceId}',
          );
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
