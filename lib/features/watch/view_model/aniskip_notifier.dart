import 'dart:async';
import 'dart:convert';

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

      // 1. Direct MAL ID parameter if provided
      if (malId == null || malId <= 0) {
        if (_malIdCache.containsKey(mediaId)) {
          malId = _malIdCache[mediaId];
        } else if (_malIdCache.containsKey(cacheKey)) {
          malId = _malIdCache[cacheKey];
        } else {
          malId = ref.read(episodeListProvider).malId;
        }
      }

      // 2. Authoritative check: Query JustAnime Core API for exact intro/outro timestamps
      final anilistId =
          int.tryParse(mediaId) ??
          int.tryParse(ref.read(episodeListProvider).animeId ?? '') ??
          int.tryParse(ref.read(episodeListProvider).mediaId ?? '');
      if (anilistId != null) {
        try {
          final res = await UniversalHttpClient.instance
              .get(
                Uri.parse(
                  'https://core.justanime.to/api/watch/$anilistId/episode/$episodeNumber/megaplay',
                ),
                headers: {
                  'Origin': 'https://justanime.to',
                  'Referer': 'https://justanime.to/',
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                },
              )
              .timeout(const Duration(seconds: 4));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final decoded = json.decode(res.body);
            if (decoded is Map) {
              final subMap = decoded['sub'] as Map?;
              final dubMap = decoded['dub'] as Map?;
              final rawIntro =
                  decoded['intro'] ?? subMap?['intro'] ?? dubMap?['intro'];
              final rawOutro =
                  decoded['outro'] ?? subMap?['outro'] ?? dubMap?['outro'];
              Intro? intro;
              Intro? outro;
              if (rawIntro is Map) {
                final s = (rawIntro['start'] as num?)?.toInt();
                final e = (rawIntro['end'] as num?)?.toInt();
                if (s != null && e != null && e > s) {
                  intro = Intro(start: s, end: e);
                }
              }
              if (rawOutro is Map) {
                final s = (rawOutro['start'] as num?)?.toInt();
                final e = (rawOutro['end'] as num?)?.toInt();
                if (s != null && e != null && e > s) {
                  outro = Intro(start: s, end: e);
                }
              }
              if (intro != null || outro != null) {
                if (requestGeneration != _requestGeneration) return;
                setFallbackFromSource(intro: intro, outro: outro);
                AppLogger.d(
                  'JustAnime Core API provided exact intro ($intro) and outro ($outro) for Ep $episodeNumber',
                );
              }
            }
          }
        } catch (e) {
          AppLogger.d('JustAnime Core API fast intro/outro check skipped: $e');
        }
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
          final res = await UniversalHttpClient.instance.post(
            Uri.parse('https://graphql.anilist.co'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'query':
                  'query (\$search: String) { Media(search: \$search, type: ANIME) { idMal } }',
              'variables': {'search': animeTitle},
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
          final results = await _jikan.getSearch(title: animeTitle, limit: 1);
          if (results.isNotEmpty) {
            malId = results.first.malId;
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
        // Merge AniSkip results: Stream source intro/outro always takes absolute priority!
        state = _mergeWithSourcePriority(results);
        AppLogger.d(
          'AniSkip: ${state.length} skip intervals active for ep $episodeNumber',
        );
      } else {
        AppLogger.w('Could not resolve MAL ID for $animeTitle ($mediaId)');
      }
    } catch (e) {
      AppLogger.w('Failed to fetch skip times for ep $episodeNumber: $e');
    }
  }

  List<AniSkipResultItem> _sourceSkips = [];

  List<AniSkipResultItem> _mergeWithSourcePriority(
    List<AniSkipResultItem> communitySkips,
  ) {
    // Start with sourceSkips as the ground truth
    final list = List<AniSkipResultItem>.from(_sourceSkips);
    for (final comm in communitySkips) {
      final hasType = list.any(
        (s) =>
            s.skipType == comm.skipType ||
            (s.skipType == SkipType.op && comm.skipType == SkipType.mixed) ||
            (s.skipType == SkipType.mixed && comm.skipType == SkipType.op),
      );
      if (!hasType) {
        list.add(comm);
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
      newSourceItems.add(
        AniSkipResultItem(
          interval: AniSkipInterval(
            startTime: intro.start!.toDouble(),
            endTime: intro.end!.toDouble(),
          ),
          skipType: SkipType.op,
          action: 'skip',
          episodeLength: 0,
          skipId: 'source-intro',
        ),
      );
    }
    if (outro != null &&
        outro.start != null &&
        outro.end != null &&
        outro.end! > outro.start!) {
      newSourceItems.add(
        AniSkipResultItem(
          interval: AniSkipInterval(
            startTime: outro.start!.toDouble(),
            endTime: outro.end!.toDouble(),
          ),
          skipType: SkipType.ed,
          action: 'skip',
          episodeLength: 0,
          skipId: 'source-outro',
        ),
      );
    }

    if (newSourceItems.isNotEmpty) {
      _sourceSkips = newSourceItems;
      // Overwrite/merge existing state so source intro/outro takes immediate precedence
      state = _mergeWithSourcePriority(state);
      AppLogger.d(
        'AniSkip: Applied ${newSourceItems.length} authoritative intro/outro from stream source (total: ${state.length})',
      );
    }
  }

  void clear() {
    // Invalidate any lookup still running for the previous episode so its
    // result cannot overwrite the next episode's intro/outro ranges.
    _requestGeneration++;
    _sourceSkips = [];
    state = [];
  }
}
