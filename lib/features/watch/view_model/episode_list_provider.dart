import 'dart:async';
import 'dart:convert';

import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:collection/collection.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ani_dash/core/jikan/jikan_service.dart';
import 'package:ani_dash/core/jikan/models/jikan_media.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/services/anime_filler_service.dart';
import 'package:ani_dash/shared/providers/anime_source_provider.dart';
import 'package:ani_dash/core/registery/sources/anime/anime_provider.dart';
import 'package:ani_dash/core/registery/sources/anime/justanime.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/models/settings/experimental_model.dart';
import 'package:ani_dash/shared/providers/settings/experimental_notifier.dart';
import 'package:ani_dash/shared/providers/settings/source_notifier.dart';
import 'package:ani_dash/helpers/matcher.dart';
import 'package:ani_dash/main.dart';
import 'package:ani_dash/core/repositories/watch_progress_repository.dart';
import 'package:ani_dash/data/hive/models/anime_watch_progress_model.dart';

part 'episode_list_provider.g.dart';

@immutable
class EpisodeListState {
  final String? mediaId;
  final String? animeId;
  final String? animeTitle;
  final String? animeCover;
  final int? malId;
  final List<EpisodeDataModel> episodes;
  final List<({JikanMedia result, double similarity})> jikanMatches;
  final bool isLoading;
  final bool isJikanSyncing;
  final String? error;
  final bool isAdult;

  const EpisodeListState({
    this.mediaId,
    this.animeId,
    this.animeTitle,
    this.animeCover,
    this.malId,
    this.episodes = const [],
    this.jikanMatches = const [],
    this.isLoading = false,
    this.isJikanSyncing = false,
    this.error,
    this.isAdult = false,
  });

  EpisodeListState copyWith({
    String? mediaId,
    String? animeId,
    String? animeTitle,
    String? animeCover,
    int? malId,
    List<EpisodeDataModel>? episodes,
    List<({JikanMedia result, double similarity})>? jikanMatches,
    bool? isLoading,
    bool? isJikanSyncing,
    String? error,
    bool? isAdult,
    bool clearMalId = false,
  }) {
    return EpisodeListState(
      mediaId: mediaId ?? this.mediaId,
      animeId: animeId ?? this.animeId,
      animeTitle: animeTitle ?? this.animeTitle,
      animeCover: animeCover ?? this.animeCover,
      malId: clearMalId ? null : (malId ?? this.malId),
      episodes: episodes ?? this.episodes,
      jikanMatches: jikanMatches ?? this.jikanMatches,
      isLoading: isLoading ?? this.isLoading,
      isJikanSyncing: isJikanSyncing ?? this.isJikanSyncing,
      error: error ?? this.error,
      isAdult: isAdult ?? this.isAdult,
    );
  }

  EpisodeDataModel? getEpisode(int episode) =>
      episodes.firstWhereOrNull((e) => e.number == episode);
}

@Riverpod(keepAlive: true)
class EpisodeListNotifier extends _$EpisodeListNotifier {
  final JikanService _jikan = JikanService();
  int _requestGeneration = 0;

  ExperimentalFeaturesModel get _exp => ref.read(experimentalProvider);
  AnimeProvider? get _animeProvider => ref.read(selectedAnimeProvider);
  SourceNotifier get _sourceNotifier => ref.read(sourceProvider.notifier);

  @override
  EpisodeListState build() => const EpisodeListState();

  String _correctedTitleCacheKey(
    String? mediaId,
    String? animeId,
    String animeTitle,
  ) =>
      // v2 intentionally invalidates the old cache which could persist titles
      // from a mismatched catalogue result (notably One Piece 183-200).
      'corrected_episode_titles_v2_${mediaId ?? animeId ?? animeTitle.toLowerCase().trim()}';

  String _correctedThumbnailCacheKey(
    String? mediaId,
    String? animeId,
    String animeTitle,
  ) =>
      'corrected_episode_thumbnails_v2_${mediaId ?? animeId ?? animeTitle.toLowerCase().trim()}';

  Future<List<EpisodeDataModel>> _applyPersistedCorrectedTitles(
    List<EpisodeDataModel> episodes, {
    required String animeTitle,
    String? animeId,
    String? mediaId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final rawTitles = prefs.getString(
      _correctedTitleCacheKey(mediaId, animeId, animeTitle),
    );
    final rawThumbs = prefs.getString(
      _correctedThumbnailCacheKey(mediaId, animeId, animeTitle),
    );
    if ((rawTitles == null || rawTitles.isEmpty) &&
        (rawThumbs == null || rawThumbs.isEmpty)) {
      return episodes;
    }
    try {
      final decodedTitles =
          rawTitles != null && rawTitles.isNotEmpty
              ? jsonDecode(rawTitles)
              : null;
      final decodedThumbs =
          rawThumbs != null && rawThumbs.isNotEmpty
              ? jsonDecode(rawThumbs)
              : null;
      final titleMap = decodedTitles is Map ? decodedTitles : null;
      final thumbMap = decodedThumbs is Map ? decodedThumbs : null;

      return episodes
          .map((episode) {
            final number = episode.number;
            if (number == null) return episode;
            final numKey = number.toString();
            var next = episode;
            if (titleMap != null) {
              final corrected = titleMap[numKey]?.toString().trim();
              if (corrected != null && corrected.isNotEmpty) {
                next = next.copyWith(title: corrected);
              }
            }
            if (thumbMap != null &&
                (next.thumbnail == null || next.thumbnail!.isEmpty)) {
              final thumb = thumbMap[numKey]?.toString().trim();
              if (thumb != null && thumb.isNotEmpty) {
                next = next.copyWith(thumbnail: thumb);
              }
            }
            return next;
          })
          .toList(growable: false);
    } catch (_) {
      return episodes;
    }
  }

  Future<void> _persistCorrectedTitles(
    List<EpisodeDataModel> episodes, {
    required String animeTitle,
    String? animeId,
    String? mediaId,
  }) async {
    final titles = <String, String>{};
    final thumbs = <String, String>{};
    for (final episode in episodes) {
      final number = episode.number;
      if (number == null) continue;
      final title = episode.title?.trim() ?? '';
      if (title.isNotEmpty &&
          !RegExp(
            r'^(episode|ep\.?)\s*\d+$',
            caseSensitive: false,
          ).hasMatch(title)) {
        titles[number.toString()] = title;
      }
      final thumbnail = episode.thumbnail?.trim() ?? '';
      if (thumbnail.isNotEmpty) {
        thumbs[number.toString()] = thumbnail;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    if (titles.isNotEmpty) {
      await prefs.setString(
        _correctedTitleCacheKey(mediaId, animeId, animeTitle),
        jsonEncode(titles),
      );
    }
    if (thumbs.isNotEmpty) {
      await prefs.setString(
        _correctedThumbnailCacheKey(mediaId, animeId, animeTitle),
        jsonEncode(thumbs),
      );
    }
  }

  // --- Core Fetching Logic ---

  Future<List<EpisodeDataModel>> fetchEpisodes({
    required String animeTitle,
    String? animeId,
    String? mediaId,
    String? animeCover,
    required bool force,
    List<EpisodeDataModel> episodes = const [],
    DMedia? media,
    int? malId,
    bool isAdult = false,
    bool isMovie = false,
  }) async {
    final requestGeneration = ++_requestGeneration;
    final requestedMediaId = mediaId;
    // 1. Check Cache
    if (!force &&
        state.episodes.isNotEmpty &&
        state.animeId == animeId &&
        state.mediaId == requestedMediaId) {
      AppLogger.d('Episode list cache hit for: $animeTitle');
      return state.episodes;
    }

    state = state.copyWith(
      isLoading: true,
      error: null,
      mediaId: mediaId ?? state.mediaId,
      animeId: animeId,
      animeTitle: animeTitle,
      animeCover: animeCover ?? media?.cover,
      malId: malId ?? state.malId,
      clearMalId: malId == null && state.malId == null,
      jikanMatches: const [],
      isAdult: isAdult,
    );
    AppLogger.section('Fetching Episodes: $animeTitle');

    // 2. Use provided episodes if available
    if (episodes.isNotEmpty) {
      AppLogger.success('Using ${episodes.length} pre-provided episodes');
      var normalized = _normalizeEpisodeTitles(
        episodes,
        animeTitle: animeTitle,
        isMovie: isMovie,
      );
      normalized = await _applyPersistedCorrectedTitles(
        normalized,
        animeTitle: animeTitle,
        animeId: animeId,
        mediaId: mediaId,
      );
      if (requestGeneration != _requestGeneration) return const [];
      state = state.copyWith(episodes: normalized, isLoading: false);
      _syncMetadataIfEnabled();
      return normalized;
    }

    // 3. Fetch from remote sources
    var fetched = await _fetchEpisodesInternal(animeId, media: media);
    if (requestGeneration != _requestGeneration) return const [];

    fetched = _normalizeEpisodeTitles(
      fetched,
      animeTitle: animeTitle,
      isMovie: isMovie,
    );
    fetched = await _applyPersistedCorrectedTitles(
      fetched,
      animeTitle: animeTitle,
      animeId: animeId,
      mediaId: mediaId,
    );

    if (fetched.isEmpty) {
      final titleLow = animeTitle.toLowerCase();
      final isLikelyMovie =
          titleLow.contains('movie') ||
          titleLow.contains('film') ||
          (media?.title?.toLowerCase().contains('movie') == true) ||
          (media?.title?.toLowerCase().contains('film') == true);

      if (isLikelyMovie) {
        final synth = [
          EpisodeDataModel(
            id: '1',
            number: 1,
            title: animeTitle,
            thumbnail: animeCover ?? media?.cover,
          ),
        ];
        AppLogger.success('Synthesized single movie episode for $animeTitle');
        state = state.copyWith(episodes: synth, isLoading: false);
        return synth;
      }

      AppLogger.fail('No episodes found for $animeTitle');
      state = state.copyWith(isLoading: false, error: 'No episodes found');
      return [];
    }

    AppLogger.success('Successfully loaded ${fetched.length} episodes');
    state = state.copyWith(episodes: fetched, isLoading: false);
    _syncMetadataIfEnabled();

    return fetched;
  }

  Future<void> refreshEpisodes() async {
    final id = state.animeId;
    final title = state.animeTitle;
    final mediaId = state.mediaId;
    if (id == null || title == null) return;

    final refreshed = await fetchEpisodes(
      animeId: id,
      animeTitle: title,
      mediaId: mediaId,
      force: true,
    );
    await _persistCorrectedTitles(
      refreshed,
      animeTitle: title,
      animeId: id,
      mediaId: mediaId,
    );
  }

  void reset() {
    _requestGeneration++;
    state = const EpisodeListState();
  }

  void setLocalEpisodes({
    required List<EpisodeDataModel> episodes,
    String? mediaId,
    String? animeId,
    String? animeTitle,
    int? malId,
  }) {
    _requestGeneration++;
    state = state.copyWith(
      episodes: episodes,
      mediaId: mediaId,
      animeId: animeId,
      animeTitle: animeTitle,
      malId: malId,
      isLoading: false,
      error: null,
    );
  }

  List<EpisodeDataModel> _normalizeEpisodeTitles(
    List<EpisodeDataModel> episodes, {
    required String animeTitle,
    required bool isMovie,
  }) {
    return episodes.indexed
        .map((entry) {
          final index = entry.$1;
          final episode = entry.$2;
          final number = episode.number ?? index + 1;
          final title = episode.title?.trim() ?? '';
          final genericTitle = RegExp(
            r'^(episode|ep\.?)\s*\d+$',
            caseSensitive: false,
          ).hasMatch(title);
          if (title.isNotEmpty && !(isMovie && genericTitle)) return episode;
          return episode.copyWith(
            title: isMovie ? animeTitle : 'Episode $number',
            number: number,
          );
        })
        .toList(growable: false);
  }

  void attachMalId(int malId) {
    if (state.malId == malId) return;
    state = state.copyWith(malId: malId);
    _syncMetadataIfEnabled();
  }

  // --- Internal Source Routing ---

  Future<List<EpisodeDataModel>> _fetchEpisodesInternal(
    String? animeId, {
    DMedia? media,
  }) async {
    try {
      final registry = ref.read(animeSourceRegistryProvider);
      final currentKey = ref.read(selectedProviderKeyProvider);
      final isNative = currentKey != null && registry.has(currentKey);

      // Fast path for JustAnime: AniList mediaId is the exact anime ID
      if (currentKey == 'justanime') {
        final directId =
            (int.tryParse(animeId ?? '') != null)
                ? animeId
                : (int.tryParse(state.mediaId ?? '') != null
                    ? state.mediaId
                    : null);
        if (directId != null) {
          final directEps = await _fetchLegacyEpisodes(directId);
          if (directEps.isNotEmpty) {
            state = state.copyWith(animeId: directId);
            return directEps;
          }
        }
      }

      var eps =
          (!isNative && _exp.useExtensions)
              ? await _fetchExtensionEpisodes(media)
              : await _fetchLegacyEpisodes(animeId);

      // Multi-Source Fallback: If 0 episodes returned, search active and fallback sources by title
      if (eps.isEmpty &&
          state.animeTitle != null &&
          state.animeTitle!.isNotEmpty) {
        final candidateKeys = [
          if (currentKey != null) currentKey,
          if (registry.has('justanime') && currentKey != 'justanime')
            'justanime',
          ...registry.keys.where((k) => k != currentKey && k != 'justanime'),
        ];

        final cleanTitle =
            state.animeTitle!
                .replaceAll(':', ' ')
                .replaceAll('-', ' ')
                .replaceAll(RegExp(r'[^\w\s]'), ' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();

        for (final altKey in candidateKeys) {
          final altProvider = registry.get(altKey);
          if (altProvider == null) continue;

          try {
            AppLogger.w(
              'Resolving episodes by title on: $altKey for "$cleanTitle"',
            );
            String? matchId;
            if (altKey == 'justanime' &&
                state.mediaId != null &&
                int.tryParse(state.mediaId!) != null) {
              matchId = state.mediaId;
            } else {
              final searchResults = await altProvider
                  .getSearch(
                    cleanTitle.isNotEmpty ? cleanTitle : state.animeTitle!,
                    null,
                    1,
                  )
                  .timeout(const Duration(seconds: 20));
              final altMatch = searchResults.results.firstOrNull;
              matchId = altMatch?.id;
            }
            if (matchId != null && matchId.isNotEmpty) {
              final altResult = await altProvider
                  .getEpisodes(matchId)
                  .timeout(const Duration(seconds: 15));
              final altEps = altResult.episodes ?? [];
              if (altEps.isNotEmpty) {
                AppLogger.success(
                  'Source $altKey found ${altEps.length} episodes!',
                );
                state = state.copyWith(animeId: matchId);
                return altEps;
              }
            }
          } catch (e) {
            AppLogger.d('Fallback $altKey failed: $e');
          }
        }
      }

      return eps;
    } catch (e, st) {
      AppLogger.e('Episode fetch pipeline failed', e, st);
      showAppSnackBar(
        'Episode Fetch',
        'Failed to load episodes',
        type: ContentType.failure,
      );
      reset();
      return [];
    }
  }

  Future<List<EpisodeDataModel>> _fetchExtensionEpisodes(DMedia? media) async {
    media ??= DMedia(title: state.animeTitle, url: state.animeId);
    if (media.url == null) return [];

    AppLogger.d('Fetching episodes via Extensions');
    final details = await _sourceNotifier.getDetails(media);
    final chapters = details?.episodes ?? [];

    final mapped =
        chapters.map((ch) {
          // Safely extract episode number string before parsing
          final numStr =
              ch.episodeNumber.isNotEmpty
                  ? ch.episodeNumber
                  : RegExp(r'\d+').firstMatch(ch.name ?? '')?.group(0) ?? '';

          return EpisodeDataModel(
            title: ch.name,
            url: ch.url,
            isFiller: false,
            number: int.tryParse(numStr),
          );
        }).toList();

    // Sort ascending if valid numbers exist
    if (mapped.isNotEmpty && mapped.first.number != null) {
      mapped.sort((a, b) => (a.number ?? 999999).compareTo(b.number ?? 999999));
    }

    return mapped;
  }

  Future<List<EpisodeDataModel>> _fetchLegacyEpisodes(String? animeId) async {
    final provider = _animeProvider;
    if (provider == null || animeId == null) {
      AppLogger.warning('Legacy provider or AnimeID is null');
      return [];
    }

    var targetId = animeId;
    if (provider.providerName == 'justanime' &&
        int.tryParse(animeId) == null &&
        state.mediaId != null &&
        int.tryParse(state.mediaId!) != null) {
      targetId = state.mediaId!;
    }

    AppLogger.d(
      'Fetching episodes via Legacy Provider: $provider (id: $targetId)',
    );
    try {
      return (await provider.getEpisodes(targetId)).episodes ?? [];
    } catch (e) {
      AppLogger.w('Direct legacy episode fetch failed: $e');
      return [];
    }
  }

  // --- Metadata & Episode Name Syncing ---

  static final Map<String, List<EpisodeDataModel>> _justAnimeTitlesCache = {};
  static final Map<String, Map<int, String>> _tvMazeThumbnailCache = {};
  static final Map<String, Map<int, String>> _tvMazeTitleCache = {};
  static final Map<String, String> _kitsuAnimeIdCache = {};

  void _syncMetadataIfEnabled() {
    if (state.episodes.isEmpty || state.animeTitle == null) {
      return;
    }

    state = state.copyWith(isJikanSyncing: true);
    AppLogger.i(
      'Initializing metadata and episode name sync for: ${state.animeTitle}',
    );

    // unawaited ensures Riverpod doesn't block while fetching non-critical metadata
    unawaited(
      _runMetadataSync().whenComplete(
        () => state = state.copyWith(isJikanSyncing: false),
      ),
    );
  }

  Future<void> _runMetadataSync() async {
    try {
      // 1. Immediately enrich from TVMaze and JustAnime.
      // TVMaze delivers all 16:9 thumbnails and episode titles in 1 fast request (~1s).
      await _syncMissingThumbnailsFromTvMaze().catchError(
        (e) => AppLogger.d('TVMaze sync error: $e'),
      );
      await _syncWithJustAnime().catchError(
        (e) => AppLogger.d('JustAnime sync error: $e'),
      );
      await _persistCurrentEpisodeMetadata().catchError((_) {});

      // 2. Concurrently enrich Jikan & Kitsu for official MAL/Kitsu titles and filler info
      await Future.wait([
        _syncWithJikan().catchError((e) => AppLogger.d('Jikan sync error: $e')),
        _syncWithKitsu().catchError((e) => AppLogger.d('Kitsu sync error: $e')),
        _syncFillerInfo().catchError((e) => AppLogger.d('Filler sync error: $e')),
      ]);

      // 3. Final TVMaze pass in case any thumbnails or titles remain unfilled
      await _syncMissingThumbnailsFromTvMaze().catchError((_) {});
      await _persistCurrentEpisodeMetadata().catchError((_) {});
    } catch (e, st) {
      AppLogger.w('Metadata enrichment exception: $e', e, st);
    }
  }

  Future<void> _persistCurrentEpisodeMetadata() async {
    if (state.episodes.isEmpty) return;
    final repository = ref.read(watchProgressRepositoryProvider);
    AnimeWatchProgressEntry? progress;
    for (final candidate in <String?>[state.mediaId, state.animeId]) {
      if (candidate == null || candidate.isEmpty) continue;
      progress = repository.getProgress(candidate);
      if (progress != null) break;
    }
    if (progress == null && state.animeTitle?.trim().isNotEmpty == true) {
      final normalized = state.animeTitle!.trim().toLowerCase();
      progress = repository.getAllProgress().firstWhereOrNull(
        (entry) => entry.animeTitle.trim().toLowerCase() == normalized,
      );
    }
    if (progress == null || progress.currentEpisode <= 0) return;

    final targetEpisodes = <int>[
      progress.currentEpisode,
      progress.currentEpisode + 1,
    ];
    final updatedEpisodes = Map<int, EpisodeProgress>.from(
      progress.episodesProgress,
    );
    bool changed = false;

    for (final epNum in targetEpisodes) {
      if (epNum <= 0) continue;
      final metadata = state.getEpisode(epNum);
      if (metadata == null) continue;
      final existing = updatedEpisodes[epNum];
      final title = metadata.title?.trim() ?? '';
      final thumbnail = metadata.thumbnail?.trim() ?? '';
      final isGeneric = RegExp(
        r'^(episode|ep\.?)\s*\d+$',
        caseSensitive: false,
      ).hasMatch(title);
      final resolvedTitle =
          title.isNotEmpty && !isGeneric
              ? title
              : (existing?.episodeTitle ?? 'Episode $epNum');
      final resolvedThumbnail =
          thumbnail.isNotEmpty ? thumbnail : existing?.episodeThumbnail;

      if (existing?.episodeTitle == resolvedTitle &&
          existing?.episodeThumbnail == resolvedThumbnail) {
        continue;
      }

      updatedEpisodes[epNum] = EpisodeProgress(
        episodeNumber: epNum,
        episodeTitle: resolvedTitle,
        episodeThumbnail: resolvedThumbnail,
        progressInSeconds: existing?.progressInSeconds,
        durationInSeconds: existing?.durationInSeconds,
        isCompleted: existing?.isCompleted ?? false,
        watchedAt: existing?.watchedAt,
      );
      changed = true;
    }

    if (changed) {
      await repository.saveProgress(
        progress.copyWith(episodesProgress: updatedEpisodes),
      );
    }
  }

  Future<void> _syncMissingThumbnailsFromTvMaze() async {
    final currentEpisodes = state.episodes;
    final currentTitle = state.animeTitle?.trim();
    if (currentEpisodes.isEmpty || currentTitle == null) return;

    final missingCount =
        currentEpisodes
            .where((episode) => episode.thumbnail?.trim().isNotEmpty != true)
            .length;
    final hasGenericTitles = currentEpisodes.any((episode) {
      final t = episode.title?.trim() ?? '';
      return t.isEmpty ||
          RegExp(
            r'^(episode|ep\.?)\s*\d+$',
            caseSensitive: false,
          ).hasMatch(t);
    });

    if (missingCount == 0 && !hasGenericTitles) return;

    final mediaId = state.mediaId;
    final animeId = state.animeId;
    final cacheKey = currentTitle.toLowerCase();

    try {
      var thumbnails = _tvMazeThumbnailCache[cacheKey];
      var titles = _tvMazeTitleCache[cacheKey];
      if (thumbnails == null) {
        final searchUri = Uri.https('api.tvmaze.com', '/search/shows', {
          'q': currentTitle,
        });
        final searchResponse = await UniversalHttpClient.instance
            .get(searchUri)
            .timeout(const Duration(seconds: 15));
        final searchResults = jsonDecode(searchResponse.body) as List<dynamic>;
        final normalizedTitle = _normalizeMetadataTitle(currentTitle);

        Map<String, dynamic>? matchedShow;
        for (final result in searchResults) {
          final show = Map<String, dynamic>.from(
            (result as Map)['show'] as Map,
          );
          final showName = show['name']?.toString() ?? '';
          final showType = show['type']?.toString().toLowerCase() ?? '';
          if (_normalizeMetadataTitle(showName) == normalizedTitle &&
              showType == 'animation') {
            matchedShow = show;
            break;
          }
        }

        // Secondary matching: partial/contained title for animation shows
        if (matchedShow == null) {
          for (final result in searchResults) {
            final show = Map<String, dynamic>.from(
              (result as Map)['show'] as Map,
            );
            final showNorm = _normalizeMetadataTitle(show['name']?.toString() ?? '');
            final showType = show['type']?.toString().toLowerCase() ?? '';
            if (showType == 'animation' &&
                (showNorm.contains(normalizedTitle) ||
                    normalizedTitle.contains(showNorm))) {
              matchedShow = show;
              break;
            }
          }
        }

        // Fallback: first animation show
        matchedShow ??= searchResults
            .map((r) => Map<String, dynamic>.from((r as Map)['show'] as Map))
            .firstWhereOrNull(
              (s) => s['type']?.toString().toLowerCase() == 'animation',
            );

        if (matchedShow == null) return;

        final showId = matchedShow['id'];
        if (showId == null) return;
        final episodeResponse = await UniversalHttpClient.instance
            .get(Uri.parse('https://api.tvmaze.com/shows/$showId/episodes'))
            .timeout(const Duration(seconds: 25));
        final rawEpisodes = jsonDecode(episodeResponse.body) as List<dynamic>;
        thumbnails = <int, String>{};
        titles = <int, String>{};
        var absoluteNumber = 0;
        for (final raw in rawEpisodes) {
          final episode = Map<String, dynamic>.from(raw as Map);
          if (episode['type']?.toString().toLowerCase() != 'regular') continue;
          absoluteNumber++;
          final image = episode['image'];
          if (image is Map) {
            final url =
                image['medium']?.toString() ?? image['original']?.toString();
            if (url != null && url.isNotEmpty) {
              thumbnails[absoluteNumber] = url;
            }
          }
          final name = episode['name']?.toString().trim();
          if (name != null && name.isNotEmpty) {
            titles[absoluteNumber] = name;
          }
        }
        _tvMazeThumbnailCache[cacheKey] = thumbnails;
        if (titles.isNotEmpty) {
          _tvMazeTitleCache[cacheKey] = titles;
        }
      }

      if (thumbnails.isEmpty) return;
      final latestState = state;
      if (latestState.mediaId != mediaId ||
          latestState.animeId != animeId ||
          latestState.animeTitle != currentTitle) {
        return;
      }

      final updated = List<EpisodeDataModel>.of(latestState.episodes);
      var addedThumbnails = 0;
      var addedTitles = 0;
      for (var index = 0; index < updated.length; index++) {
        var episode = updated[index];
        final number = episode.number ?? index + 1;
        bool changed = false;

        // Enrich missing thumbnail
        if (episode.thumbnail?.trim().isNotEmpty != true) {
          final thumbnail = thumbnails[number];
          if (thumbnail != null && thumbnail.isNotEmpty) {
            episode = episode.copyWith(thumbnail: thumbnail);
            changed = true;
            addedThumbnails++;
          }
        }

        // Enrich generic title if TVMaze provides a real name
        final currentEpTitle = episode.title?.trim() ?? '';
        final isGeneric =
            currentEpTitle.isEmpty ||
            RegExp(
              r'^(episode|ep\.?)\s*\d+$',
              caseSensitive: false,
            ).hasMatch(currentEpTitle);
        if (isGeneric && titles != null) {
          final tvTitle = titles[number];
          if (tvTitle != null && tvTitle.isNotEmpty) {
            episode = episode.copyWith(title: tvTitle);
            changed = true;
            addedTitles++;
          }
        }

        if (changed) {
          updated[index] = episode;
        }
      }

      if (addedThumbnails > 0 || addedTitles > 0) {
        state = state.copyWith(episodes: updated);
        AppLogger.success(
          'Enriched $addedThumbnails thumbnails & $addedTitles titles from TVMaze for "$currentTitle"',
        );
        await _persistCorrectedTitles(
          updated,
          animeTitle: currentTitle,
          animeId: animeId,
          mediaId: mediaId,
        );
      }
    } catch (error) {
      AppLogger.d('TVMaze thumbnail enrichment skipped: $error');
    }
  }

  String _normalizeMetadataTitle(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  Future<void> _syncWithKitsu() async {
    final animeTitle = state.animeTitle?.trim();
    if (animeTitle == null || animeTitle.isEmpty || state.episodes.isEmpty) {
      return;
    }
    final mediaId = state.mediaId;
    final animeId = state.animeId;
    final genericNumbers =
        state.episodes
            .where((episode) {
              final title = episode.title?.trim() ?? '';
              return title.isEmpty ||
                  RegExp(
                    r'^(episode|ep\.?)\s*\d+$',
                    caseSensitive: false,
                  ).hasMatch(title);
            })
            .map((episode) => episode.number)
            .whereType<int>()
            .toSet();
    if (genericNumbers.isEmpty) return;

    try {
      final normalized = _normalizeMetadataTitle(animeTitle);
      var kitsuId = _kitsuAnimeIdCache[normalized];
      if (kitsuId == null) {
        final searchUri = Uri.https('kitsu.io', '/api/edge/anime', {
          'filter[text]': animeTitle,
          'page[limit]': '10',
        });
        final response = await UniversalHttpClient.instance
            .get(
              searchUri,
              headers: const {'Accept': 'application/vnd.api+json'},
              cacheConfig: CacheConfig.long,
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) return;
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final results = body['data'] as List<dynamic>? ?? const [];
        for (final raw in results) {
          final item = Map<String, dynamic>.from(raw as Map);
          final attributes = Map<String, dynamic>.from(
            item['attributes'] as Map? ?? const {},
          );
          final candidate =
              attributes['canonicalTitle']?.toString() ??
              attributes['titles']?['en']?.toString() ??
              '';
          if (_normalizeMetadataTitle(candidate) == normalized) {
            kitsuId = item['id']?.toString();
            break;
          }
        }
        if (kitsuId == null || kitsuId.isEmpty) return;
        _kitsuAnimeIdCache[normalized] = kitsuId;
      }

      final offsets =
          genericNumbers
              .map((number) => ((number - 1) ~/ 20) * 20)
              .toSet()
              .toList()
            ..sort();
      for (var start = 0; start < offsets.length; start += 5) {
        final end = (start + 5).clamp(0, offsets.length);
        final batch = offsets.sublist(start, end);
        final responses = await Future.wait(
          batch.map((offset) async {
            final uri = Uri.https(
              'kitsu.io',
              '/api/edge/anime/$kitsuId/episodes',
              {'page[limit]': '20', 'page[offset]': '$offset'},
            );
            try {
              final response = await UniversalHttpClient.instance
                  .get(
                    uri,
                    headers: const {'Accept': 'application/vnd.api+json'},
                    cacheConfig: CacheConfig.long,
                  )
                  .timeout(const Duration(seconds: 15));
              if (response.statusCode != 200) return const <(int, String)>[];
              final body = jsonDecode(response.body) as Map<String, dynamic>;
              final data = body['data'] as List<dynamic>? ?? const [];
              return data
                  .map((raw) {
                    final item = Map<String, dynamic>.from(raw as Map);
                    final attributes = Map<String, dynamic>.from(
                      item['attributes'] as Map? ?? const {},
                    );
                    final number = (attributes['number'] as num?)?.toInt();
                    final title =
                        attributes['canonicalTitle']?.toString().trim() ?? '';
                    return (number ?? 0, title);
                  })
                  .where((item) => item.$1 > 0 && item.$2.isNotEmpty)
                  .toList();
            } catch (_) {
              return const <(int, String)>[];
            }
          }),
        );

        if (state.mediaId != mediaId ||
            state.animeId != animeId ||
            state.animeTitle?.trim() != animeTitle) {
          return;
        }
        final titleByNumber = <int, String>{
          for (final item in responses.expand((items) => items))
            item.$1: item.$2,
        };
        if (titleByNumber.isEmpty) continue;
        final updated = List<EpisodeDataModel>.of(state.episodes);
        var changed = false;
        for (var index = 0; index < updated.length; index++) {
          final episode = updated[index];
          final number = episode.number ?? index + 1;
          if (!genericNumbers.contains(number)) continue;
          final title = titleByNumber[number];
          if (title == null || title.isEmpty) continue;
          updated[index] = episode.copyWith(title: title);
          changed = true;
        }
        if (changed) state = state.copyWith(episodes: updated);
      }

      await _persistCorrectedTitles(
        state.episodes,
        animeTitle: animeTitle,
        animeId: animeId,
        mediaId: mediaId,
      );
    } catch (error) {
      AppLogger.d('Kitsu episode-title enrichment skipped: $error');
    }
  }

  Future<void> _syncFillerInfo() async {
    try {
      final currentTitle = state.animeTitle!;
      final malId = state.malId;

      final fillerInfo = await AnimeFillerService().getFillerInfo(
        title: currentTitle,
        malId: malId,
      );

      if ((fillerInfo.fillers.isNotEmpty || fillerInfo.mixed.isNotEmpty) &&
          state.episodes.isNotEmpty) {
        final updated = List<EpisodeDataModel>.of(state.episodes);
        var fillerCount = 0;
        for (var i = 0; i < updated.length; i++) {
          final epNum = updated[i].number ?? (i + 1);
          final isFiller =
              fillerInfo.fillers.contains(epNum) || updated[i].isFiller == true;
          final isMixed = fillerInfo.mixed.contains(epNum);
          if (isFiller != (updated[i].isFiller ?? false) ||
              isMixed != (updated[i].isMixed ?? false)) {
            updated[i] = updated[i].copyWith(
              isFiller: isFiller,
              isMixed: isMixed,
            );
            if (isFiller || isMixed) fillerCount++;
          }
        }
        if (fillerCount > 0) {
          AppLogger.success(
            'Highlighted $fillerCount filler/mixed episodes for "$currentTitle"',
          );
          state = state.copyWith(episodes: updated);
        }
      }
    } catch (e) {
      AppLogger.d('AnimeFillerService sync error: $e');
    }
  }

  Future<void> _syncWithJustAnime() async {
    if (state.episodes.isEmpty || state.animeTitle == null) return;

    final currentTitle = state.animeTitle!;
    final mediaId = state.mediaId;
    final animeId = state.animeId;

    try {
      final registry = ref.read(animeSourceRegistryProvider);
      final justAnime = registry.get('justanime') ?? JustAnimeProvider();

      List<EpisodeDataModel>? justAnimeEps;

      // 1. Check in-memory cache
      final cacheKey = mediaId ?? currentTitle.toLowerCase().trim();
      if (_justAnimeTitlesCache.containsKey(cacheKey)) {
        justAnimeEps = _justAnimeTitlesCache[cacheKey];
      }

      // 2. Direct AniList ID lookup (JustAnime uses exact AniList IDs for all anime)
      if (justAnimeEps == null && mediaId != null && mediaId.isNotEmpty) {
        try {
          AppLogger.d(
            'Enriching episode names via JustAnime direct AniList ID: $mediaId',
          );
          final res = await justAnime
              .getEpisodes(mediaId)
              .timeout(const Duration(seconds: 15));
          if (res.episodes != null && res.episodes!.isNotEmpty) {
            justAnimeEps = res.episodes;
            _justAnimeTitlesCache[mediaId] = res.episodes!;
            _justAnimeTitlesCache[cacheKey] = res.episodes!;
          }
        } catch (e) {
          AppLogger.d('JustAnime direct AniList ID fetch error: $e');
        }
      }

      // 3. Fallback: Search JustAnime by cleaned title
      if (justAnimeEps == null || justAnimeEps.isEmpty) {
        try {
          final cleanTitle =
              currentTitle
                  .replaceAll(
                    RegExp(
                      r'\s*\((?:Dub|Sub|TV|Audio|Uncensored)[^)]*\)',
                      caseSensitive: false,
                    ),
                    '',
                  )
                  .replaceAll(
                    RegExp(
                      r'\s*\[(?:Dub|Sub|TV|Audio|Uncensored)[^\]]*\]',
                      caseSensitive: false,
                    ),
                    '',
                  )
                  .replaceAll(
                    RegExp(r'\s*-\s*(?:Dub|Sub)$', caseSensitive: false),
                    '',
                  )
                  .replaceAll('-', ' ')
                  .replaceAll(':', ' ')
                  .replaceAll(RegExp(r'[^\w\s]'), ' ')
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();

          final searchTitle = cleanTitle.isNotEmpty ? cleanTitle : currentTitle;
          AppLogger.d('Searching JustAnime for episode names: "$searchTitle"');

          final searchPage = await justAnime
              .getSearch(searchTitle, null, 1)
              .timeout(const Duration(seconds: 10));
          if (searchPage.results.isNotEmpty) {
            final match =
                searchPage.results.firstWhereOrNull(
                  (r) => r.id == mediaId || r.anilistId?.toString() == mediaId,
                ) ??
                searchPage.results.firstOrNull;

            final matchId = match?.id;
            if (matchId != null && matchId.isNotEmpty) {
              final res = await justAnime
                  .getEpisodes(matchId)
                  .timeout(const Duration(seconds: 15));
              if (res.episodes != null && res.episodes!.isNotEmpty) {
                justAnimeEps = res.episodes;
                _justAnimeTitlesCache[cacheKey] = res.episodes!;
                if (mediaId != null) {
                  _justAnimeTitlesCache[mediaId] = res.episodes!;
                }
              }
            }
          }
        } catch (e) {
          AppLogger.d('JustAnime title search for episode names error: $e');
        }
      }

      // 4. Apply JustAnime episode names and metadata
      if (justAnimeEps != null && justAnimeEps.isNotEmpty) {
        final justEpByNum = <int, EpisodeDataModel>{};
        for (final ep in justAnimeEps) {
          if (ep.number != null) {
            justEpByNum[ep.number!] = ep;
          }
        }

        final updated = List<EpisodeDataModel>.of(state.episodes);
        int enrichedTitleCount = 0;
        int enrichedThumbnailCount = 0;

        for (var i = 0; i < updated.length; i++) {
          final epNum = updated[i].number ?? (i + 1);
          final justEp = justEpByNum[epNum];
          if (justEp == null) continue;

          var ep = updated[i];
          bool modified = false;

          // Title: enrich if current is generic or if JustAnime has a real title
          final currentEpTitle = ep.title?.trim() ?? '';
          final isCurrentGeneric =
              currentEpTitle.isEmpty ||
              RegExp(
                r'^(episode|ep\.?)\s*\d+$',
                caseSensitive: false,
              ).hasMatch(currentEpTitle);

          final justTitle = justEp.title?.trim();
          final isJustGeneric =
              justTitle == null ||
              justTitle.isEmpty ||
              RegExp(
                r'^(episode|ep\.?)\s*\d+$',
                caseSensitive: false,
              ).hasMatch(justTitle);

          // Never replace a real source title with a catalogue enrichment.
          // A stale match previously labelled One Piece 183+ as Alabasta
          // while the correct Skypiea stream was playing.
          if (!isJustGeneric && isCurrentGeneric) {
            ep = ep.copyWith(title: justTitle);
            modified = true;
            enrichedTitleCount++;
          }

          // Thumbnail: if current is empty or missing, use JustAnime's HD TMDB thumbnail
          if ((ep.thumbnail == null || ep.thumbnail!.isEmpty) &&
              justEp.thumbnail != null &&
              justEp.thumbnail!.isNotEmpty) {
            ep = ep.copyWith(thumbnail: justEp.thumbnail);
            modified = true;
            enrichedThumbnailCount++;
          }

          // Description: if current is empty, use JustAnime's description
          if ((ep.description == null || ep.description!.isEmpty) &&
              justEp.description != null &&
              justEp.description!.isNotEmpty) {
            ep = ep.copyWith(description: justEp.description);
            modified = true;
          }

          // Filler: if JustAnime marks it as filler
          if (justEp.isFiller == true && ep.isFiller != true) {
            ep = ep.copyWith(isFiller: true);
            modified = true;
          }

          if (modified) {
            updated[i] = ep;
          }
        }

        // Metadata sync runs in the background. Never let a late response from
        // the previously opened anime overwrite the current episode list.
        final isSameAnime =
            state.mediaId == mediaId &&
            state.animeId == animeId &&
            state.animeTitle == currentTitle &&
            state.episodes.length == updated.length;
        final metadataChanged =
            isSameAnime &&
            updated.indexed.any(
              (entry) => !identical(entry.$2, state.episodes[entry.$1]),
            );

        if (isSameAnime && metadataChanged) {
          AppLogger.success(
            'Enriched $enrichedTitleCount titles and '
            '$enrichedThumbnailCount thumbnails from JustAnime for "$currentTitle"',
          );
          state = state.copyWith(episodes: updated);
          await _persistCorrectedTitles(
            updated,
            animeTitle: currentTitle,
            animeId: animeId,
            mediaId: mediaId,
          );
        }
      }
    } catch (e) {
      AppLogger.w('JustAnime episode names sync error: $e');
    }
  }

  Future<void> _syncWithJikan() async {
    try {
      final currentTitle = state.animeTitle!;
      int? malId = state.malId;

      // Title and metadata sync via Jikan (MAL) as fallback
      if (malId == null) {
        var matches = state.jikanMatches;

        // Only search Jikan if we haven't already cached the matches
        if (matches.isEmpty) {
          final cleanedTitle =
              currentTitle
                  .replaceAll(
                    RegExp(
                      r'\s*\((?:Dub|Sub|TV|Audio|Uncensored)[^)]*\)',
                      caseSensitive: false,
                    ),
                    '',
                  )
                  .replaceAll(
                    RegExp(
                      r'\s*\[(?:Dub|Sub|TV|Audio|Uncensored)[^\]]*\]',
                      caseSensitive: false,
                    ),
                    '',
                  )
                  .replaceAll(
                    RegExp(r'\s*-\s*(?:Dub|Sub)$', caseSensitive: false),
                    '',
                  )
                  .trim();
          final searchTitle =
              cleanedTitle.isNotEmpty ? cleanedTitle : currentTitle;

          final searchResults = await _jikan.getSearch(
            title: searchTitle,
            limit: 10,
          );
          matches = getBestMatches<JikanMedia>(
            results: searchResults,
            title: searchTitle,
            nameSelector: (e) => e.title,
            idSelector: (e) => e.malId.toString(),
          );
        }

        if (matches.isNotEmpty && matches.first.similarity >= 0.55) {
          state = state.copyWith(jikanMatches: matches);
          malId = matches.first.result.malId;
        }
      }

      if (malId != null && malId > 0) {
        AppLogger.d('Fetching MAL episode data for ID: $malId');
        final allJikanEpisodes = <JikanEpisode>[];
        int page = 1;
        final totalNeeded = state.episodes.length;

        while (allJikanEpisodes.length < totalNeeded && page <= 15) {
          try {
            final jikanEpisodes = await _jikan
                .getEpisodes(malId, page)
                .timeout(const Duration(seconds: 10));
            if (jikanEpisodes.isEmpty) break;
            allJikanEpisodes.addAll(jikanEpisodes);
            // Publish each page immediately. Long-running shows can need more
            // than ten catalogue requests, so waiting for every page left the
            // visible range showing generic "Episode N" labels for a long time.
            _applyJikanEpisodePage(
              jikanEpisodes,
              animeTitle: currentTitle,
              animeId: state.animeId,
              mediaId: state.mediaId,
            );
            if (jikanEpisodes.length < 100) break; // Last page
            page++;
            await Future.delayed(const Duration(milliseconds: 300));
          } catch (e) {
            AppLogger.d('Jikan page $page fetch interrupted: $e');
            break;
          }
        }

        if (allJikanEpisodes.isNotEmpty) {
          // Create a lookup by malId (episode number in Jikan)
          final titleByEpNum = <int, String>{};
          final fillerByEpNum = <int, bool>{};
          for (final jEp in allJikanEpisodes) {
            fillerByEpNum[jEp.malId] = jEp.filler;
            if (jEp.title.isNotEmpty) {
              titleByEpNum[jEp.malId] = jEp.title;
            }
          }

          // Create a mutable copy of the list to update titles and fillers
          final updated = List<EpisodeDataModel>.of(state.episodes);
          int syncedCount = 0;

          for (var i = 0; i < updated.length; i++) {
            final epNum = updated[i].number ?? (i + 1);
            final syncedTitle = titleByEpNum[epNum];
            final isFiller =
                fillerByEpNum[epNum] == true || updated[i].isFiller == true;
            if (isFiller && updated[i].isFiller != true) {
              updated[i] = updated[i].copyWith(isFiller: true);
            }
            if (syncedTitle != null && syncedTitle.isNotEmpty) {
              final currentEpTitle = updated[i].title ?? '';
              final isGeneric =
                  currentEpTitle.isEmpty ||
                  RegExp(
                    r'^(episode|ep\.?)\s*\d+$',
                    caseSensitive: false,
                  ).hasMatch(currentEpTitle.trim());

              // Only enrich if the existing title is generic (e.g. 'Episode 235').
              // Never replace a real title already provided by the official stream/source with a catalogue translation!
              if (isGeneric) {
                updated[i] = updated[i].copyWith(
                  title: syncedTitle,
                );
                syncedCount++;
              }
            }
          }

          if (syncedCount > 0) {
            AppLogger.success(
              'Successfully synced $syncedCount episode titles from Jikan',
            );
          }
          state = state.copyWith(episodes: updated);
          await _persistCorrectedTitles(
            updated,
            animeTitle: currentTitle,
            animeId: state.animeId,
            mediaId: state.mediaId,
          );
        }
      }
    } catch (e, st) {
      AppLogger.w('Metadata and filler sync failed: $e', e, st);
    }
  }

  void _applyJikanEpisodePage(
    List<JikanEpisode> page, {
    required String animeTitle,
    required String? animeId,
    required String? mediaId,
  }) {
    if (page.isEmpty ||
        state.animeTitle != animeTitle ||
        state.animeId != animeId ||
        state.mediaId != mediaId) {
      return;
    }

    final byNumber = <int, JikanEpisode>{for (final ep in page) ep.malId: ep};
    final updated = List<EpisodeDataModel>.of(state.episodes);
    var changed = false;
    for (var index = 0; index < updated.length; index++) {
      final episode = updated[index];
      final number = episode.number ?? index + 1;
      final catalogue = byNumber[number];
      if (catalogue == null) continue;

      var next = episode;
      if (catalogue.filler && episode.isFiller != true) {
        next = next.copyWith(isFiller: true);
      }
      final currentEpTitle = episode.title?.trim() ?? '';
      final isGeneric = currentEpTitle.isEmpty ||
          RegExp(r'^(episode|ep\.?)\s*\d+$', caseSensitive: false)
              .hasMatch(currentEpTitle);
      if (isGeneric && catalogue.title.trim().isNotEmpty) {
        next = next.copyWith(
          title: catalogue.title.trim(),
        );
      }
      if (!identical(next, episode)) {
        updated[index] = next;
        changed = true;
      }
    }
    if (changed) state = state.copyWith(episodes: updated);
  }
}
