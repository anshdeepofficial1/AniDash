import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ani_dash/core/jikan/jikan_service.dart';
import 'package:ani_dash/core/models/aniskip/aniskip_result.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/services/aniskip_service.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/models/anime/source_model.dart';
import 'package:ani_dash/features/watch/view_model/episode_list_provider.dart';

part 'aniskip_notifier.g.dart';

@riverpod
class AniSkipNotifier extends _$AniSkipNotifier {
  final JikanService _jikan = JikanService();
  static final Map<String, int> _malIdCache = {};
  int _requestGeneration = 0;

  @override
  List<AniSkipResultItem> build() {
    return const [];
  }

  static const Map<String, int> _knownTopAnimeMalIds = {
    'one piece': 21,
    'naruto': 20,
    'naruto shippuden': 1735,
    'naruto: shippuuden': 1735,
    'bleach': 269,
    'bleach: thousand-year blood war': 41467,
    'death note': 1535,
    'attack on titan': 16498,
    'shingeki no kyojin': 16498,
    'jujutsu kaisen': 40748,
    'demon slayer': 38000,
    'kimetsu no yaiba': 38000,
    'hunter x hunter': 11061,
    'hunter x hunter (2011)': 11061,
    'my hero academia': 31964,
    'boku no hero academia': 31964,
    'dragon ball z': 813,
    'dragon ball': 223,
    'dragon ball super': 30694,
    'fullmetal alchemist: brotherhood': 5114,
    'fullmetal alchemist brotherhood': 5114,
    'chainsaw man': 44511,
    'solo leveling': 52299,
    'black clover': 34572,
    'sword art online': 11757,
    'tokyo ghoul': 22319,
    'one punch man': 30276,
    'spy x family': 50273,
    'vinland saga': 37521,
  };

  Future<void> fetchSkipTimes({
    required String mediaId,
    required String animeTitle,
    required int episodeNumber,
    required int episodeLength,
    int? malId,
  }) async {
    final requestGeneration = ++_requestGeneration;
    try {
      final cacheKey = animeTitle.trim().toLowerCase();

      // 1. Direct MAL ID parameter if provided or from known top anime mapping
      if (malId == null || malId <= 0) {
        if (_malIdCache.containsKey(mediaId)) {
          malId = _malIdCache[mediaId];
        } else if (_malIdCache.containsKey(cacheKey)) {
          malId = _malIdCache[cacheKey];
        } else if (_knownTopAnimeMalIds.containsKey(cacheKey)) {
          malId = _knownTopAnimeMalIds[cacheKey];
        } else {
          final sortedEntries = _knownTopAnimeMalIds.entries.toList()
            ..sort((a, b) => b.key.length.compareTo(a.key.length));
          for (final entry in sortedEntries) {
            final pattern = RegExp('(^|[^a-z0-9])${RegExp.escape(entry.key)}([^a-z0-9]|\$)', caseSensitive: false);
            if (cacheKey == entry.key || pattern.hasMatch(cacheKey)) {
              malId = entry.value;
              break;
            }
          }
          malId ??= ref.read(episodeListProvider).malId;
        }
      }

      final anilistId =
          int.tryParse(mediaId) ??
          int.tryParse(ref.read(episodeListProvider).animeId ?? '') ??
          int.tryParse(ref.read(episodeListProvider).mediaId ?? '');

      // 3. Query AniList directly by numeric ID (fast GraphQL, ~200ms)
      if (malId == null && anilistId != null) {
        try {
          final res = await UniversalHttpClient.instance.post(
            Uri.parse('https://graphql.anilist.co'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'query':
                  'query (\$id: Int) { Media(id: \$id, type: ANIME) { idMal } }',
              'variables': {'id': anilistId},
            }),
            cacheConfig: CacheConfig.veryLong,
          );

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final rawMal = data?['data']?['Media']?['idMal'];
            if (rawMal != null) {
              malId = rawMal is int ? rawMal : int.tryParse(rawMal.toString());
            }
          }
        } catch (e) {
          AppLogger.w('AniList fast ID query failed: $e');
        }
      }

      // 4. Query AniList by Title Search if ID was not numeric or had no MAL ID
      if (malId == null && animeTitle.isNotEmpty) {
        try {
          final cleanTitle =
              animeTitle
                  .replaceAll(
                    RegExp(
                      r'\s*\((?:sub|dub|uncensored|tv)\)',
                      caseSensitive: false,
                    ),
                    '',
                  )
                  .replaceAll(RegExp(r'\[.*?\]'), '')
                  .trim();
          final res = await UniversalHttpClient.instance.post(
            Uri.parse('https://graphql.anilist.co'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'query':
                  'query (\$search: String) { Media(search: \$search, type: ANIME, sort: [POPULARITY_DESC]) { idMal } }',
              'variables': {
                'search': cleanTitle.isNotEmpty ? cleanTitle : animeTitle,
              },
            }),
            cacheConfig: CacheConfig.veryLong,
          );

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final rawMal = data?['data']?['Media']?['idMal'];
            if (rawMal != null) {
              malId = rawMal is int ? rawMal : int.tryParse(rawMal.toString());
            }
          }
        } catch (e) {
          AppLogger.w('AniList search MAL query failed: $e');
        }
      }

      // 5. Fallback via Jikan search
      if (malId == null && animeTitle.isNotEmpty) {
        try {
          final results = await _jikan.getSearch(title: animeTitle, limit: 3);
          if (results.isNotEmpty) {
            final cleanQuery = animeTitle.trim().toLowerCase();
            final exactMatch = results.firstWhereOrNull((r) {
              final t = r.title.trim().toLowerCase();
              return t == cleanQuery || t.startsWith(cleanQuery) || cleanQuery.startsWith(t);
            });
            if (exactMatch != null) {
              malId = exactMatch.malId;
            }
          }
        } catch (e) {
          AppLogger.w('Jikan search failed: $e');
        }
      }

      // 6. Fetch skip times if MAL ID resolved
      if (malId != null) {
        _malIdCache[mediaId] = malId;
        _malIdCache[cacheKey] = malId;

        final effectiveLength = episodeLength > 0 ? episodeLength : 1440;
        final results = await aniSkipService.getSkipTimes(
          malId,
          episodeNumber,
          effectiveLength,
        );
        if (requestGeneration != _requestGeneration) return;
        _aniSkipSkips = results;
        // Merge AniSkip results: Original AniSkip crowd timestamps ALWAYS take primary priority!
        state = _mergeSkips(
          aniSkipSkips: _aniSkipSkips,
          sourceSkips: _sourceSkips,
        );
        AppLogger.d(
          'AniSkip: ${state.length} skip intervals active for ep $episodeNumber (AniSkip: ${_aniSkipSkips.length}, Source Fallback: ${_sourceSkips.length})',
        );
      } else {
        AppLogger.w('Could not resolve MAL ID for $animeTitle ($mediaId)');
      }
    } catch (e) {
      AppLogger.w('Failed to fetch skip times for ep $episodeNumber: $e');
    }
  }

  List<AniSkipResultItem> _aniSkipSkips = [];
  List<AniSkipResultItem> _sourceSkips = [];

  List<AniSkipResultItem> _mergeSkips({
    required List<AniSkipResultItem> aniSkipSkips,
    required List<AniSkipResultItem> sourceSkips,
  }) {
    // AniSkip entries are indexed by MAL title + exact episode and are the
    // canonical markers. Provider markers are only a fallback: some stream
    // APIs reuse series-average timestamps, which shifts unusual placements.
    final list = List<AniSkipResultItem>.from(aniSkipSkips);

    final hasOp = list.any(
      (s) =>
          s.skipType == SkipType.op ||
          (s.skipType == SkipType.mixed && (s.interval?.startTime ?? 0) <= 300),
    );
    final hasEd = list.any(
      (s) =>
          s.skipType == SkipType.ed ||
          (s.skipType == SkipType.mixed && (s.interval?.startTime ?? 0) > 300),
    );

    final hasRecap = list.any((s) => s.skipType == SkipType.recap);
    for (final source in sourceSkips) {
      final isSourceOp = source.skipType == SkipType.op;
      final isSourceEd = source.skipType == SkipType.ed;
      final isSourceRecap = source.skipType == SkipType.recap;
      if ((isSourceOp && !hasOp) ||
          (isSourceEd && !hasEd) ||
          (isSourceRecap && !hasRecap) ||
          (!isSourceOp && !isSourceEd && !isSourceRecap)) {
        list.add(source);
      }
    }
    return list;
  }

  void setFallbackFromSource({Intro? intro, Intro? outro}) {
    final newSourceItems = <AniSkipResultItem>[];

    if (intro != null &&
        intro.start != null &&
        intro.end != null &&
        intro.end! > intro.start!) {
      final start = intro.start!.toDouble();
      final end = intro.end!.toDouble();
      final duration = end - start;

      // These markers came from the exact stream response for this episode.
      // Do not replace them with an averaged placement: some episodes move or
      // omit their opening intentionally. Only reject structurally impossible
      // intervals.
      if (start >= 0 && duration >= 3 && duration <= 360) {
        newSourceItems.add(
          AniSkipResultItem(
            interval: AniSkipInterval(startTime: start, endTime: end),
            skipType: SkipType.op,
            action: 'skip',
            episodeLength: 0,
            skipId: 'source-intro',
          ),
        );
      } else {
        AppLogger.w('AniSkip: Rejected invalid source intro ($start -> $end).');
      }
    }

    if (outro != null &&
        outro.start != null &&
        outro.end != null &&
        outro.end! > outro.start!) {
      final start = outro.start!.toDouble();
      final end = outro.end!.toDouble();
      final duration = end - start;

      // Trust the episode-specific stream marker even when an unusual episode
      // places its ending earlier than the series average.
      if (start >= 0 && duration >= 3 && duration <= 360) {
        newSourceItems.add(
          AniSkipResultItem(
            interval: AniSkipInterval(startTime: start, endTime: end),
            skipType: SkipType.ed,
            action: 'skip',
            episodeLength: 0,
            skipId: 'source-outro',
          ),
        );
      } else {
        AppLogger.w('AniSkip: Rejected invalid source outro ($start -> $end).');
      }
    }

    _sourceSkips = newSourceItems;
    // Overwrite state while strictly keeping any original AniSkip intervals as primary priority!
    state = _mergeSkips(aniSkipSkips: _aniSkipSkips, sourceSkips: _sourceSkips);
    AppLogger.d(
      'AniSkip: Applied ${newSourceItems.length} validated fallback intro/outro from source (Active total: ${state.length})',
    );
  }

  /// Removes timestamps supplied by the previous stream/server while keeping
  /// provider-independent AniSkip data. This prevents a failed stream from
  /// leaking its intro/outro markers into the next playback attempt.
  void clearSourceFallback() {
    _sourceSkips = [];
    state = _mergeSkips(aniSkipSkips: _aniSkipSkips, sourceSkips: const []);
  }

  void clear() {
    _requestGeneration++;
    _aniSkipSkips = [];
    _sourceSkips = [];
    state = [];
  }
}
