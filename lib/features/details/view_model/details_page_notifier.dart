import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/jikan/jikan_service.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';
import 'package:ani_dash/features/watch/view_model/episode_stream_provider.dart';
import 'package:ani_dash/shared/providers/anime_repo_provider.dart';
import 'package:ani_dash/shared/providers/anilist_service_provider.dart';
import 'package:ani_dash/shared/providers/anime_match_service.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';

part 'details_page_notifier.g.dart';

@immutable
class DetailsPageState {
  final AsyncValue<UniversalMedia> details;
  final bool isLoadingDetails;
  final bool isSearchingMatch;
  final String? bestMatchName;
  final String? animeIdForSource;
  final String selectedRange;
  final List<String> rangeOptions;
  final bool isSortedDescending;
  final String? error;

  const DetailsPageState({
    this.details = const AsyncLoading(),
    this.isLoadingDetails = false,
    this.isSearchingMatch = false,
    this.bestMatchName,
    this.animeIdForSource,
    this.selectedRange = 'All',
    this.rangeOptions = const ['All'],
    this.isSortedDescending = false,
    this.error,
  });

  bool get isLoading => isLoadingDetails || details.isLoading;

  DetailsPageState copyWith({
    AsyncValue<UniversalMedia>? details,
    bool? isLoadingDetails,
    bool? isSearchingMatch,
    String? bestMatchName,
    String? animeIdForSource,
    String? selectedRange,
    List<String>? rangeOptions,
    bool? isSortedDescending,
    String? error,
    bool setBestMatchNull = false,
  }) {
    return DetailsPageState(
      details: details ?? this.details,
      isLoadingDetails: isLoadingDetails ?? this.isLoadingDetails,
      isSearchingMatch: isSearchingMatch ?? this.isSearchingMatch,
      bestMatchName:
          setBestMatchNull ? null : (bestMatchName ?? this.bestMatchName),
      animeIdForSource:
          setBestMatchNull ? null : (animeIdForSource ?? this.animeIdForSource),
      selectedRange: selectedRange ?? this.selectedRange,
      rangeOptions: rangeOptions ?? this.rangeOptions,
      isSortedDescending: isSortedDescending ?? this.isSortedDescending,
      error: error ?? this.error,
    );
  }
}

@riverpod
class DetailsPageNotifier extends _$DetailsPageNotifier {
  @override
  DetailsPageState build(String animeId) {
    return const DetailsPageState();
  }

  Future<void> init(UniversalMedia media) async {
    if (state.details is AsyncLoading) {
      state = state.copyWith(
        details: AsyncData(media),
        isLoadingDetails: true,
        error: null,
      );
      ref.read(episodeListProvider.notifier).reset();
      ref.read(episodeDataProvider.notifier).reset();

      // Episode discovery must not wait for the slower About/details
      // enrichment. Starting both together prevents the Episodes tab from
      // briefly looking empty (and removes the need for a manual refresh).
      final episodesFuture = _fetchEpisodes(media.title);
      await fetchDetails();
      if (!ref.mounted) return;
      await episodesFuture;

      // If the initial title could not be matched, retry once with the
      // enriched title returned by AniList/Jikan.
      if (!ref.mounted) return;
      final episodeState = ref.read(episodeListProvider);
      final enrichedMedia = state.details.value ?? media;
      if (episodeState.episodes.isEmpty && episodeState.error != null) {
        await _fetchEpisodes(enrichedMedia.title, force: true);
      }
    }
  }

  Future<void> fetchDetails() async {
    final currentData = state.details.value;
    final knownMalId = int.tryParse(currentData?.idMal ?? '');
    // Start the independent MAL enrichment alongside AniList so a slow or
    // unavailable primary API does not leave About blank for tens of seconds.
    final jikanFuture =
        knownMalId == null
            ? null
            : JikanService()
                .getFullDetails(knownMalId)
                .timeout(const Duration(seconds: 12), onTimeout: () => null);

    try {
      final anilistId = int.tryParse(currentData?.id ?? animeId);
      UniversalMedia? fresh;
      if (anilistId != null) {
        try {
          fresh = await ref
              .read(anilistServiceProvider)
              .getAnimeDetails(anilistId)
              .timeout(const Duration(seconds: 15));
        } catch (error) {
          // AniList outages must not prevent the MAL/Jikan fallback below.
          AppLogger.w('AniList details unavailable; trying fallback: $error');
        }
      }
      if (fresh == null && currentData != null) {
        var malId = knownMalId;
        final title =
            currentData.title.english ??
            currentData.title.romaji ??
            currentData.title.userPreferred;
        if (title.isNotEmpty) {
          try {
            final anilistSearch = await ref
                .read(anilistServiceProvider)
                .searchAnime(title);
            if (anilistSearch.isNotEmpty) {
              final matchedId = int.tryParse(anilistSearch.first.id);
              if (matchedId != null) {
                fresh = await ref
                    .read(anilistServiceProvider)
                    .getAnimeDetails(matchedId)
                    .timeout(const Duration(seconds: 15));
              }
            }
          } catch (_) {}
        }
        if (fresh == null && malId == null && title.isNotEmpty) {
          final matches = await JikanService().searchUniversal(title);
          malId =
              matches.isEmpty ? null : int.tryParse(matches.first.idMal ?? '');
        }
        if (fresh == null && malId != null) {
          final jikan =
              malId == knownMalId && jikanFuture != null
                  ? await jikanFuture
                  : await JikanService()
                      .getFullDetails(malId)
                      .timeout(
                        const Duration(seconds: 12),
                        onTimeout: () => null,
                      );
          if (jikan != null) {
            fresh = _mergeJikanDetails(currentData, malId, jikan);
          }
        }
      }
      if (fresh == null) {
        final repo = ref.read(animeRepositoryProvider);
        final fallbackId =
            int.tryParse(currentData?.idMal ?? '') ??
            int.tryParse(animeId) ??
            0;
        fresh = await repo
            .getAnimeDetails(fallbackId)
            .timeout(const Duration(seconds: 15));
      }

      // AniList list responses occasionally arrive without the full about
      // payload. Fill those gaps from Jikan instead of treating a partial
      // object as complete and leaving the About tab blank.
      if (fresh != null) {
        final needsEnrichment =
            fresh.description?.trim().isEmpty != false ||
            fresh.staff.isEmpty ||
            fresh.studios.isEmpty;
        final malId = int.tryParse(fresh.idMal ?? currentData?.idMal ?? '');
        if (needsEnrichment && malId != null) {
          final jikan =
              malId == knownMalId && jikanFuture != null
                  ? await jikanFuture
                  : await JikanService()
                      .getFullDetails(malId)
                      .timeout(
                        const Duration(seconds: 12),
                        onTimeout: () => null,
                      );
          if (jikan != null) {
            fresh = _mergeJikanDetails(fresh, malId, jikan);
          }
        }
      }

      if (!ref.mounted) return;

      if (fresh != null) {
        var characters = fresh.characters;
        if (characters.isEmpty &&
            (currentData?.characters.isNotEmpty ?? false)) {
          characters = currentData!.characters;
        }
        if (characters.isEmpty) {
          characters = await _fetchFallbackCharacters(fresh);
        }

        final enriched = fresh.copyWith(
          description:
              fresh.description?.trim().isNotEmpty == true
                  ? fresh.description
                  : currentData?.description,
          episodes: fresh.episodes ?? currentData?.episodes,
          duration: fresh.duration ?? currentData?.duration,
          staff: fresh.staff.isNotEmpty ? fresh.staff : currentData?.staff,
          studios:
              fresh.studios.isNotEmpty ? fresh.studios : currentData?.studios,
          relations:
              fresh.relations.isNotEmpty
                  ? fresh.relations
                  : currentData?.relations,
          characters: characters,
        );
        state = state.copyWith(
          details: AsyncData(enriched),
          isLoadingDetails: false,
        );
      } else if (currentData != null) {
        var enriched = currentData;
        if (enriched.characters.isEmpty) {
          final fallbackChars = await _fetchFallbackCharacters(enriched);
          if (fallbackChars.isNotEmpty) {
            enriched = enriched.copyWith(characters: fallbackChars);
          }
        }
        state = state.copyWith(
          details: AsyncData(enriched),
          isLoadingDetails: false,
        );
      }
    } catch (e, st) {
      AppLogger.e('Failed to fetch anime details for $animeId', e, st);
      if (!ref.mounted) return;
      if (currentData != null) {
        state = state.copyWith(
          details: AsyncData(currentData),
          isLoadingDetails: false,
        );
      } else {
        state = state.copyWith(
          details: AsyncError(e, st),
          isLoadingDetails: false,
        );
      }
    }
  }

  UniversalMedia _mergeJikanDetails(
    UniversalMedia current,
    int malId,
    ({
      Map<String, dynamic> details,
      List<dynamic> staff,
      List<dynamic> characters,
    })
    jikan,
  ) {
    final data = jikan.details;
    final studios =
        (data['studios'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item))
            .map(
              (item) => UniversalStudio(
                name: item['name']?.toString() ?? '',
                isMain: true,
              ),
            )
            .where((studio) => studio.name.isNotEmpty)
            .toList();
    final staff =
        jikan.staff.map((item) => Map<String, dynamic>.from(item)).map((item) {
          final person = Map<String, dynamic>.from(item['person'] ?? {});
          final images = Map<String, dynamic>.from(person['images'] ?? {});
          final jpg = Map<String, dynamic>.from(images['jpg'] ?? {});
          return UniversalStaff(
            id: person['mal_id'] as int?,
            name: UniversalStaffName(full: person['name']?.toString()),
            image: UniversalStaffImage(
              large: jpg['image_url']?.toString(),
              medium: jpg['image_url']?.toString(),
            ),
            role: (item['positions'] as List? ?? const []).join(', '),
          );
        }).toList();
    final characters = _mapJikanCharacters(jikan.characters);
    final genres =
        <String>{
          for (final key in const [
            'genres',
            'explicit_genres',
            'themes',
            'demographics',
          ])
            for (final item in data[key] as List? ?? const [])
              if (item['name']?.toString().isNotEmpty == true)
                item['name'].toString(),
        }.toList();
    final duration = int.tryParse(
      RegExp(r'\d+').firstMatch(data['duration']?.toString() ?? '')?.group(0) ??
          '',
    );
    final trailer = Map<String, dynamic>.from(data['trailer'] ?? {});
    final trailerId = trailer['youtube_id']?.toString();
    return current.copyWith(
      idMal: malId.toString(),
      description: data['synopsis']?.toString(),
      episodes: data['episodes'] as int?,
      duration: duration,
      averageScore:
          data['score'] is num ? (data['score'] as num).toDouble() * 10 : null,
      popularity: data['popularity'] as int?,
      genres: genres.isNotEmpty ? genres : null,
      synonyms:
          (data['title_synonyms'] as List? ?? const [])
              .map((item) => item.toString())
              .toList(),
      source: data['source']?.toString(),
      studios: studios,
      staff: staff,
      characters: characters.isNotEmpty ? characters : current.characters,
      trailer:
          trailerId == null
              ? null
              : UniversalTrailer(
                id: trailerId,
                site: 'youtube',
                thumbnail: trailer['images']?['large_image_url']?.toString(),
              ),
      siteUrl: data['url']?.toString(),
    );
  }

  Future<List<UniversalCharacter>> _fetchFallbackCharacters(
    UniversalMedia media,
  ) async {
    // 1. If media ID is an AniList ID, query AniList details for full character cast
    final anilistId = int.tryParse(media.id);
    if (anilistId != null) {
      try {
        final anilistMedia = await ref
            .read(anilistServiceProvider)
            .getAnimeDetails(anilistId)
            .timeout(const Duration(seconds: 10));
        if (anilistMedia?.characters.isNotEmpty ?? false) {
          return anilistMedia!.characters;
        }
      } catch (_) {}
    }

    // 2. Search AniList by title
    final title =
        media.title.english ?? media.title.romaji ?? media.title.userPreferred;
    if (title.isNotEmpty) {
      try {
        final anilistSearch = await ref
            .read(anilistServiceProvider)
            .searchAnime(title)
            .timeout(const Duration(seconds: 8));
        if (anilistSearch.isNotEmpty) {
          final matchedId = int.tryParse(anilistSearch.first.id);
          if (matchedId != null) {
            final details = await ref
                .read(anilistServiceProvider)
                .getAnimeDetails(matchedId)
                .timeout(const Duration(seconds: 10));
            if (details?.characters.isNotEmpty ?? false) {
              return details!.characters;
            }
          }
        }
      } catch (_) {}
    }

    // 3. Fallback to Jikan using MAL ID
    final malId = int.tryParse(media.idMal ?? '');
    if (malId != null) {
      try {
        final jikan = await JikanService().getFullDetails(malId);
        if (jikan != null && jikan.characters.isNotEmpty) {
          return _mapJikanCharacters(jikan.characters);
        }
      } catch (_) {}
    }

    // 4. Fallback to Jikan search by title
    if (title.isNotEmpty) {
      try {
        final matches = await JikanService().searchUniversal(title);
        if (matches.isNotEmpty) {
          final matchedMalId = int.tryParse(matches.first.idMal ?? '');
          if (matchedMalId != null) {
            final jikan = await JikanService().getFullDetails(matchedMalId);
            if (jikan != null && jikan.characters.isNotEmpty) {
              return _mapJikanCharacters(jikan.characters);
            }
          }
        }
      } catch (_) {}
    }
    return const [];
  }

  List<UniversalCharacter> _mapJikanCharacters(List<dynamic> rawCharacters) {
    return rawCharacters
        .map((item) => Map<String, dynamic>.from(item as Map? ?? {}))
        .map((item) {
          final charMap = Map<String, dynamic>.from(
            item['character'] as Map? ?? {},
          );
          final images = Map<String, dynamic>.from(
            charMap['images'] as Map? ?? {},
          );
          final jpg = Map<String, dynamic>.from(images['jpg'] as Map? ?? {});
          return UniversalCharacter(
            id: (charMap['mal_id'] as num?)?.toInt() ?? 0,
            name: charMap['name']?.toString() ?? '',
            image: jpg['image_url']?.toString(),
            role: item['role']?.toString(),
          );
        })
        .where((c) => c.name.isNotEmpty)
        .toList();
  }

  Future<void> _fetchEpisodes(
    UniversalTitle mediaTitle, {
    bool force = false,
  }) async {
    if (!ref.mounted) return;

    final episodeListState = ref.read(episodeListProvider);

    if (!force &&
        state.animeIdForSource != null &&
        episodeListState.mediaId == animeId &&
        (episodeListState.episodes.isNotEmpty || episodeListState.isLoading)) {
      return;
    }

    AppLogger.d(
      "Fetching episodes for: ${mediaTitle.english ?? mediaTitle.romaji}",
    );

    if (force && state.animeIdForSource == null) {
      state = state.copyWith(setBestMatchNull: true);
    }

    try {
      if (state.animeIdForSource == null) {
        state = state.copyWith(isSearchingMatch: true, error: null);

        // Reset old episodes to avoid bleeding from previously opened anime
        ref.read(episodeListProvider.notifier).reset();

        // Try to restore source first
        final restored =
            force
                ? null
                : await ref
                    .read(animeMatchServiceProvider)
                    .restoreSource(animeId, showSnackbar: false);

        if (!ref.mounted) return;

        if (restored != null) {
          state = state.copyWith(
            animeIdForSource: restored.id,
            bestMatchName: restored.name,
          );
        } else {
          // Fallback to search if restoration failed
          final isAdultMedia =
              state.details.value?.isAdult == true ||
              state.details.value?.isMature == true;
          final match = await ref
              .read(animeMatchServiceProvider)
              .findBestMatch(
                mediaTitle,
                isAdult: isAdultMedia,
                mediaId: animeId,
                malId: state.details.value?.idMal,
              )
              .timeout(
                const Duration(seconds: 14),
                onTimeout: () => null,
              );

          if (!ref.mounted) return;

          if (match == null) {
            _fail(
              'Anime Match',
              'No suitable match found for any title.',
              ContentType.failure,
            );
            return;
          }

          state = state.copyWith(
            animeIdForSource: match.id,
            bestMatchName: match.name,
          );
        }
      }

      state = state.copyWith(isSearchingMatch: false, error: null);

      if (state.bestMatchName == null || state.animeIdForSource == null) {
        return;
      }

      await ref
          .read(episodeListProvider.notifier)
          .fetchEpisodes(
            animeTitle: state.bestMatchName!,
            animeId: state.animeIdForSource,
            mediaId: state.details.value?.id ?? animeId,
            force: force,
            malId: int.tryParse(state.details.value?.idMal ?? ''),
            media: DMedia(
              title: state.bestMatchName,
              url: state.animeIdForSource,
              cover:
                  state.details.value?.coverImage.large ??
                  state.details.value?.coverImage.medium,
            ),
            isMovie: state.details.value?.format?.toUpperCase() == 'MOVIE',
          );

      if (!ref.mounted) return;
      final currentListState = ref.read(episodeListProvider);
      if (currentListState.animeId != null &&
          currentListState.animeId != state.animeIdForSource) {
        state = state.copyWith(animeIdForSource: currentListState.animeId);
      }
      _updateRanges();
    } catch (err, stack) {
      AppLogger.e(err, stack);
      if (ref.mounted) {
        state = state.copyWith(isSearchingMatch: false, error: err.toString());
      }
    } finally {
      if (ref.mounted && state.isSearchingMatch) {
        state = state.copyWith(isSearchingMatch: false);
      }
    }
  }

  void _fail(String title, String message, ContentType type) {
    if (!ref.mounted) return;
    state = state.copyWith(isSearchingMatch: false, error: message);
  }

  Future<void> refresh() async {
    final title = state.details.value?.title;
    if (title != null) {
      state = state.copyWith(
        setBestMatchNull: true,
        selectedRange: 'All',
        isSortedDescending: false,
        error: null,
      );
      await _fetchEpisodes(title, force: true);
    }
  }

  void setManualMatch(String id, String name) {
    state = state.copyWith(animeIdForSource: id, bestMatchName: name);
    final title = state.details.value?.title;
    if (title != null) {
      _fetchEpisodes(title, force: true);
    }
  }

  void updateRange(String range) {
    state = state.copyWith(selectedRange: range);
  }

  void toggleSort() {
    state = state.copyWith(isSortedDescending: !state.isSortedDescending);
  }

  void _updateRanges() {
    final episodes = ref.read(episodeListProvider).episodes;
    final total = episodes.length;
    final ranges = <String>['All'];
    for (int i = 0; i < total; i += 50) {
      final start = i + 1;
      final end = (i + 50).clamp(0, total);
      ranges.add('$start–$end');
    }

    String selectedRange = state.selectedRange;
    if (selectedRange == 'All' && ranges.length > 2) {
      final progress = ref
          .read(watchProgressRepositoryProvider)
          .getProgress(animeId);
      final currentEp = progress?.currentEpisode;
      if (currentEp != null && currentEp > 0) {
        for (final r in ranges) {
          if (r == 'All') continue;
          final parts = r.split('–');
          if (parts.length == 2) {
            final s = int.tryParse(parts[0]) ?? 1;
            final e = int.tryParse(parts[1]) ?? total;
            if (currentEp >= s && currentEp <= e) {
              selectedRange = r;
              break;
            }
          }
        }
      }
    }

    if (!listEquals(state.rangeOptions, ranges) ||
        state.selectedRange != selectedRange) {
      state = state.copyWith(
        rangeOptions: ranges,
        selectedRange: selectedRange,
      );
    }
  }
}
