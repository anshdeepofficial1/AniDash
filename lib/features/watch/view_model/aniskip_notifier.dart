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

      int? anilistId =
          int.tryParse(mediaId) ??
          int.tryParse(ref.read(episodeListProvider).animeId ?? '') ??
          int.tryParse(ref.read(episodeListProvider).mediaId ?? '');

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

      // 2. Query Ani.zip mappings by AniList ID (instant, accurate MAL ID resolution)
      if (malId == null && anilistId != null) {
        try {
          final res = await UniversalHttpClient.instance
              .get(
                Uri.parse('https://api.ani.zip/mappings?anilist_id=$anilistId'),
                cacheConfig: CacheConfig.veryLong,
              )
              .timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final decoded = jsonDecode(res.body) as Map<String, dynamic>;
            final mappings = decoded['mappings'] as Map<String, dynamic>?;
            final rawMal = mappings?['mal_id'];
            if (rawMal != null) {
              malId = rawMal is int ? rawMal : int.tryParse(rawMal.toString());
            }
          }
        } catch (_) {}
      }

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
                  'query (\$search: String) { Media(search: \$search, type: ANIME, sort: [POPULARITY_DESC]) { id idMal } }',
              'variables': {
                'search': cleanTitle.isNotEmpty ? cleanTitle : animeTitle,
              },
            }),
            cacheConfig: CacheConfig.veryLong,
          );

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final rawMal = data?['data']?['Media']?['idMal'];
            final rawAni = data?['data']?['Media']?['id'];
            if (rawMal != null) {
              malId = rawMal is int ? rawMal : int.tryParse(rawMal.toString());
            }
            if (anilistId == null && rawAni != null) {
              anilistId = rawAni is int ? rawAni : int.tryParse(rawAni.toString());
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

      // 6. Fetch from AniSkip & JustAnime in parallel
      final futures = <Future<void>>[];

      if (malId != null) {
        _malIdCache[mediaId] = malId;
        _malIdCache[cacheKey] = malId;

        futures.add(() async {
          try {
            final effectiveLength = episodeLength > 0 ? episodeLength : 1440;
            final results = await aniSkipService.getSkipTimes(
              malId!,
              episodeNumber,
              effectiveLength,
            );
            if (requestGeneration == _requestGeneration) {
              _aniSkipSkips = results;
            }
          } catch (e) {
            AppLogger.w('AniSkip lookup failed: $e');
          }
        }());
      }

      // JustAnime Direct API Lookup (has exact intro/outro for virtually all anime)
      futures.add(() async {
        try {
          final jaSkips = await _fetchJustAnimeSkips(
            anilistId: anilistId?.toString() ?? mediaId,
            animeTitle: animeTitle,
            episodeNumber: episodeNumber,
          );
          if (requestGeneration == _requestGeneration && jaSkips.isNotEmpty) {
            _justAnimeSkips = jaSkips;
          }
        } catch (e) {
          AppLogger.w('JustAnime intro/outro lookup failed: $e');
        }
      }());

      await Future.wait(futures);
      if (requestGeneration != _requestGeneration) return;

      state = _mergeSkips(
        aniSkipSkips: _aniSkipSkips,
        justAnimeSkips: _justAnimeSkips,
        sourceSkips: _sourceSkips,
      );
      AppLogger.d(
        'AniSkip: ${state.length} active skip intervals for ep $episodeNumber (AniSkip: ${_aniSkipSkips.length}, JustAnime: ${_justAnimeSkips.length}, Source: ${_sourceSkips.length})',
      );
    } catch (e) {
      AppLogger.w('Failed to fetch skip times for ep $episodeNumber: $e');
    }
  }

  Future<List<AniSkipResultItem>> _fetchJustAnimeSkips({
    required String? anilistId,
    required String? animeTitle,
    required int episodeNumber,
  }) async {
    final results = <AniSkipResultItem>[];
    final candidateIds = <String>[];
    if (anilistId != null && anilistId.isNotEmpty) {
      candidateIds.add(anilistId);
    }
    if (animeTitle != null && animeTitle.isNotEmpty) {
      final clean = animeTitle
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      if (clean.isNotEmpty && !candidateIds.contains(clean)) {
        candidateIds.add(clean);
      }
    }

    for (final id in candidateIds) {
      try {
        final endpoints = [
          'https://core.justanime.to/api/watch/$id/episode/$episodeNumber/megaplay',
          'https://core.justanime.to/api/watch/$id/episode/$episodeNumber',
        ];
        for (final url in endpoints) {
          final res = await UniversalHttpClient.instance
              .get(
                Uri.parse(url),
                headers: {
                  'Origin': 'https://justanime.to',
                  'Referer': 'https://justanime.to/',
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
                  'Accept': 'application/json',
                },
                cacheConfig: CacheConfig.veryLong,
              )
              .timeout(const Duration(seconds: 5));
          if (res.statusCode == 200) {
            final decoded = jsonDecode(res.body);
            if (decoded is Map<String, dynamic>) {
              final sub = decoded['sub'] as Map<String, dynamic>?;
              final dub = decoded['dub'] as Map<String, dynamic>?;
              final rawIntro =
                  sub?['intro'] ?? dub?['intro'] ?? decoded['intro'];
              final rawOutro =
                  sub?['outro'] ?? dub?['outro'] ?? decoded['outro'];

              if (rawIntro is Map) {
                final start = (rawIntro['start'] as num?)?.toDouble();
                final end = (rawIntro['end'] as num?)?.toDouble();
                if (start != null &&
                    end != null &&
                    end > start &&
                    (end - start) >= 5) {
                  results.add(
                    AniSkipResultItem(
                      interval: AniSkipInterval(startTime: start, endTime: end),
                      skipType: SkipType.op,
                      action: 'skip',
                      episodeLength: 0,
                      skipId: 'justanime-intro',
                    ),
                  );
                }
              }

              if (rawOutro is Map) {
                final start = (rawOutro['start'] as num?)?.toDouble();
                final end = (rawOutro['end'] as num?)?.toDouble();
                if (start != null &&
                    end != null &&
                    end > start &&
                    (end - start) >= 5) {
                  results.add(
                    AniSkipResultItem(
                      interval: AniSkipInterval(startTime: start, endTime: end),
                      skipType: SkipType.ed,
                      action: 'skip',
                      episodeLength: 0,
                      skipId: 'justanime-outro',
                    ),
                  );
                }
              }

              if (results.isNotEmpty) return results;
            }
          }
        }
      } catch (_) {}
    }
    return results;
  }

  List<AniSkipResultItem> _aniSkipSkips = [];
  List<AniSkipResultItem> _justAnimeSkips = [];
  List<AniSkipResultItem> _sourceSkips = [];

  List<AniSkipResultItem> _mergeSkips({
    required List<AniSkipResultItem> aniSkipSkips,
    required List<AniSkipResultItem> justAnimeSkips,
    required List<AniSkipResultItem> sourceSkips,
  }) {
    final list = <AniSkipResultItem>[];

    // Helper to sanitize an item to ensure it cannot be classified as OP if > 720s or ED if < 360s
    AniSkipResultItem sanitizeSkip(AniSkipResultItem item) {
      final interval = item.interval;
      if (interval == null) return item;
      final start = interval.startTime;
      var type = item.skipType;
      if (type == SkipType.ed && start < 360) {
        type = SkipType.op;
      } else if (type == SkipType.op && start >= 480) {
        type = SkipType.ed;
      }
      return item.copyWith(skipType: type);
    }

    // 1. Source Skips (Exact stream source intro/outro from active provider)
    for (final s in sourceSkips) {
      if (s.interval != null && s.interval!.endTime > s.interval!.startTime) {
        list.add(sanitizeSkip(s));
      }
    }

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

    // 2. JustAnime Direct Skips (exact web stream markers)
    for (final ja in justAnimeSkips) {
      final sanitized = sanitizeSkip(ja);
      final isJaOp = sanitized.skipType == SkipType.op;
      final isJaEd = sanitized.skipType == SkipType.ed;
      if ((isJaOp && !hasOp) || (isJaEd && !hasEd)) {
        list.add(sanitized);
      }
    }

    final hasOpNow = list.any(
      (s) =>
          s.skipType == SkipType.op ||
          (s.skipType == SkipType.mixed && (s.interval?.startTime ?? 0) <= 300),
    );
    final hasEdNow = list.any(
      (s) =>
          s.skipType == SkipType.ed ||
          (s.skipType == SkipType.mixed && (s.interval?.startTime ?? 0) > 300),
    );

    // 3. AniSkip community markers (highest precision fallback or duration refinement)
    for (final ani in aniSkipSkips) {
      final sanitized = sanitizeSkip(ani);
      final isAniOp = sanitized.skipType == SkipType.op;
      final isAniEd = sanitized.skipType == SkipType.ed;
      if ((isAniOp && !hasOpNow) || (isAniEd && !hasEdNow)) {
        list.add(sanitized);
      }
    }

    // Canonicalize standard 90s TV anime OP and ED lengths:
    // If a provider cut off the last 5-15s (duration between 70s and 88s), extend to 90s (start + 90)
    // or match against AniSkip's 90s interval so no residual song plays!
    for (int i = 0; i < list.length; i++) {
      final item = list[i];
      final interval = item.interval;
      if (interval == null) continue;
      final dur = interval.endTime - interval.startTime;
      if (dur >= 70 && dur <= 88) {
        // Look for matching AniSkip item
        final matchingAni = aniSkipSkips.firstWhereOrNull((a) =>
            a.interval != null &&
            (a.interval!.startTime - interval.startTime).abs() <= 15 &&
            (a.interval!.endTime - a.interval!.startTime) >= 88);
        if (matchingAni != null) {
          list[i] = item.copyWith(
            interval: AniSkipInterval(
              startTime: interval.startTime,
              endTime: matchingAni.interval!.endTime,
            ),
          );
        } else {
          list[i] = item.copyWith(
            interval: AniSkipInterval(
              startTime: interval.startTime,
              endTime: interval.startTime + 90.0,
            ),
          );
        }
      }
    }

    // 4. RECAP VALIDATION:
    // AniSkip crowd-sourced recap is only trusted if:
    // a) No OP exists and recap starts within first 5 mins (<= 300s), OR
    // b) An OP exists, and AniSkip's OP aligns within 15s of the actual OP (same cut), OR
    // c) AniSkip's recap ends before or at the start of the OP (never overlaps or plays during dialogue).
    final currentOp = list.firstWhereOrNull(
      (s) =>
          s.skipType == SkipType.op ||
          (s.skipType == SkipType.mixed && (s.interval?.startTime ?? 0) <= 300),
    );
    final aniOp = aniSkipSkips.firstWhereOrNull(
      (s) =>
          s.skipType == SkipType.op ||
          (s.skipType == SkipType.mixed && (s.interval?.startTime ?? 0) <= 300),
    );
    final aniRecap = aniSkipSkips.firstWhereOrNull(
      (s) => s.skipType == SkipType.recap,
    );

    if (aniRecap != null && aniRecap.interval != null && !hasRecap) {
      final recapStart = aniRecap.interval!.startTime;
      final recapEnd = aniRecap.interval!.endTime;
      final recapDuration = recapEnd - recapStart;

      if (recapDuration >= 5 && recapDuration <= 240) {
        if (currentOp == null) {
          if (recapStart >= 0 && recapStart <= 300) {
            list.add(aniRecap);
          }
        } else {
          final opStart = currentOp.interval?.startTime ?? 0;
          if (aniOp != null && aniOp.interval != null) {
            final offset = (aniOp.interval!.startTime - opStart).abs();
            if (offset <= 15) {
              final diff = aniOp.interval!.startTime - opStart;
              final adjustedStart = (recapStart - diff).clamp(0.0, opStart);
              final adjustedEnd = (recapEnd - diff).clamp(adjustedStart, opStart);
              if (adjustedEnd > adjustedStart && (adjustedEnd - adjustedStart) >= 5) {
                list.add(
                  AniSkipResultItem(
                    interval: AniSkipInterval(startTime: adjustedStart, endTime: adjustedEnd),
                    skipType: SkipType.recap,
                    action: 'skip',
                    episodeLength: 0,
                    skipId: 'ani-recap-aligned',
                  ),
                );
              }
            }
          } else if (recapEnd <= opStart + 3 && recapStart < opStart) {
            list.add(
              AniSkipResultItem(
                interval: AniSkipInterval(
                  startTime: recapStart.clamp(0.0, opStart),
                  endTime: recapEnd.clamp(0.0, opStart),
                ),
                skipType: SkipType.recap,
                action: 'skip',
                episodeLength: 0,
                skipId: 'ani-recap',
              ),
            );
          }
        }
      }
    }

    return list;
  }

  void setFallbackFromSource({Intro? intro, Intro? outro}) {
    final newSourceItems = <AniSkipResultItem>[];

    // Detect if provider swapped intro and outro
    if (intro != null && outro != null) {
      if ((intro.start ?? 0) > 480 && (outro.start ?? 0) < 360) {
        final temp = intro;
        intro = outro;
        outro = temp;
      }
    }

    if (intro != null &&
        intro.start != null &&
        intro.end != null &&
        intro.end! > intro.start!) {
      final start = intro.start!.toDouble();
      final end = intro.end!.toDouble();
      final duration = end - start;

      if (start >= 0 && duration >= 3 && duration <= 360) {
        final isEd = start >= 480;
        newSourceItems.add(
          AniSkipResultItem(
            interval: AniSkipInterval(startTime: start, endTime: end),
            skipType: isEd ? SkipType.ed : SkipType.op,
            action: 'skip',
            episodeLength: 0,
            skipId: isEd ? 'source-outro' : 'source-intro',
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

      if (start >= 0 && duration >= 3 && duration <= 360) {
        final isOp = start < 360;
        newSourceItems.add(
          AniSkipResultItem(
            interval: AniSkipInterval(startTime: start, endTime: end),
            skipType: isOp ? SkipType.op : SkipType.ed,
            action: 'skip',
            episodeLength: 0,
            skipId: isOp ? 'source-intro' : 'source-outro',
          ),
        );
      } else {
        AppLogger.w('AniSkip: Rejected invalid source outro ($start -> $end).');
      }
    }

    _sourceSkips = newSourceItems;
    state = _mergeSkips(
      aniSkipSkips: _aniSkipSkips,
      justAnimeSkips: _justAnimeSkips,
      sourceSkips: _sourceSkips,
    );
    AppLogger.d(
      'AniSkip: Applied ${newSourceItems.length} validated fallback intro/outro from source (Active total: ${state.length})',
    );
  }

  /// Removes timestamps supplied by the previous stream/server while keeping
  /// provider-independent AniSkip data. This prevents a failed stream from
  /// leaking its intro/outro markers into the next playback attempt.
  void clearSourceFallback() {
    _sourceSkips = [];
    state = _mergeSkips(
      aniSkipSkips: _aniSkipSkips,
      justAnimeSkips: _justAnimeSkips,
      sourceSkips: const [],
    );
  }

  void clear() {
    _requestGeneration++;
    _aniSkipSkips = [];
    _justAnimeSkips = [];
    _sourceSkips = [];
    state = [];
  }
}
