import 'dart:async';
import 'dart:convert';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/models/anime/anime_model.dep.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/models/anime/page_model.dart';
import 'package:ani_dash/core/models/anime/server_model.dart';
import 'package:ani_dash/core/models/anime/source_model.dart';
import 'package:ani_dash/core/registery/sources/anime/anime_provider.dart';

class JustAnimeProvider extends AnimeProvider {
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36';

  final Map<String, String> _sourceHeaders = {
    'Origin': 'https://justanime.to',
    'Referer': 'https://justanime.to/',
    'User-Agent': _userAgent,
  };

  JustAnimeProvider()
    : super(
        baseUrl: "https://justanime.to",
        apiUrl: "https://core.justanime.to/api",
        providerName: "justanime",
      );

  @override
  Map<String, String> get headers => _sourceHeaders;

  @override
  Future<DetailPage> getDetails(String animeId) {
    throw UnimplementedError();
  }

  @override
  Future<HomePage> getHome() {
    throw UnimplementedError();
  }

  @override
  Future<SearchPage> getPage(String route, int page) {
    throw UnimplementedError();
  }

  static final Map<String, ({DateTime time, SearchPage page})> _searchCache =
      {};

  @override
  Future<SearchPage> getSearch(String keyword, String? type, int page) async {
    final searchKey = keyword.trim().toLowerCase();
    if (page == 1) {
      final cached = _searchCache[searchKey];
      if (cached != null &&
          DateTime.now().difference(cached.time) <
              const Duration(minutes: 30)) {
        return cached.page;
      }
    }

    Future<SearchPage> doSearch(String q) async {
      try {
        final url = Uri.parse(
          '$apiUrl/search',
        ).replace(queryParameters: {'query': q, 'page': '$page'});
        final res = await UniversalHttpClient.instance
            .get(url, headers: headers)
            .timeout(const Duration(seconds: 20));
        final Map<String, dynamic> decoded = json.decode(res.body);
        final results = (decoded['results'] as List<dynamic>? ?? const []);
        final searchPage = SearchPage(
          results:
              results.map((raw) {
                final item = Map<String, dynamic>.from(raw as Map);
                final title = Map<String, dynamic>.from(
                  item['title'] as Map? ?? {},
                );
                return BaseAnimeModel(
                  id: item['id']?.toString(),
                  anilistId: int.tryParse(item['id']?.toString() ?? ''),
                  name: title['english'] ?? title['romaji'] ?? 'Unknown',
                  jname: title['romaji'],
                  type: item['type'],
                  poster: item['cover'],
                  releaseDate: item['year']?.toString(),
                  number: item['episodes'],
                );
              }).toList(),
        );
        if (page == 1 && searchPage.results.isNotEmpty) {
          _searchCache[searchKey] = (time: DateTime.now(), page: searchPage);
        }
        return searchPage;
      } catch (_) {
        return SearchPage(results: []);
      }
    }

    // 1. Cleaned query: remove colons, dashes, special punctuation that break JustAnime API
    final cleaned =
        keyword
            .replaceAll('-', ' ')
            .replaceAll(':', ' ')
            .replaceAll(RegExp(r'[^\w\s]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    var searchPage = await doSearch(cleaned);
    if (searchPage.results.isNotEmpty) return searchPage;

    // 2. Try lowercased query (API can fail on all-caps titles)
    final lower = cleaned.toLowerCase();
    if (lower != cleaned) {
      searchPage = await doSearch(lower);
      if (searchPage.results.isNotEmpty) return searchPage;
    }

    // 3. Try removing common movie prefixes/suffixes: "the movie", "movie", "film"
    final stripped =
        lower
            .replaceAll(RegExp(r'\b(the\s+movie|movie|film)\b'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    if (stripped.isNotEmpty && stripped != lower && stripped != cleaned) {
      searchPage = await doSearch(stripped);
      if (searchPage.results.isNotEmpty) return searchPage;
    }

    return searchPage;
  }

  Future<bool> probeAnimeExists(String animeId) async {
    try {
      final response = await UniversalHttpClient.instance
          .get(
            Uri.parse('$apiUrl/anime/$animeId/episodes?page=1'),
            headers: headers,
            cacheConfig: CacheConfig.short,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map) {
          final eps = decoded['episodes'];
          if (eps is List && eps.isNotEmpty) return true;
          if (decoded['totalPages'] != null || decoded['pageInfo'] != null) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  @override
  Future<BaseEpisodeModel> getEpisodes(
    String animeId, {
    String? anilistId,
    String? malId,
  }) async {
    Future<Map<String, dynamic>> fetchPage(int page) async {
      final response = await UniversalHttpClient.instance
          .get(
            Uri.parse('$apiUrl/anime/$animeId/episodes?page=$page'),
            headers: headers,
            cacheConfig: CacheConfig.short,
          )
          .timeout(const Duration(seconds: 25));
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }

    final first = await fetchPage(1);
    final pages = <Map<String, dynamic>>[first];
    final firstEps = first['episodes'] as List<dynamic>? ?? const [];

    int? totalPages = (first['totalPages'] as num?)?.toInt();
    if (totalPages == null && first['pageInfo'] is Map) {
      totalPages = (first['pageInfo']['lastPage'] as num?)?.toInt();
    }

    if (totalPages != null && totalPages > 1) {
      final additionalPages = await Future.wait([
        for (var page = 2; page <= totalPages; page++)
          fetchPage(page).catchError((_) => <String, dynamic>{'episodes': []}),
      ]);
      pages.addAll(additionalPages.where((p) => p.isNotEmpty));
    } else if (firstEps.length >= 100) {
      // Loop until less than 100 items or empty (up to max 25 pages)
      int currentPage = 2;
      while (currentPage <= 25) {
        try {
          final next = await fetchPage(currentPage);
          final nextEps = next['episodes'] as List<dynamic>? ?? const [];
          if (nextEps.isEmpty) break;
          pages.add(next);
          if (nextEps.length < 100) break;
          currentPage++;
        } catch (_) {
          break;
        }
      }
    }

    final episodes =
        pages
            .expand((page) => page['episodes'] as List<dynamic>? ?? const [])
            .map((raw) {
              final item = Map<String, dynamic>.from(raw as Map);
              final number = (item['number'] as num?)?.toInt();
              return EpisodeDataModel(
                id: number?.toString() ?? '1',
                number: number ?? 1,
                title: item['title'] ?? 'Episode ${number ?? 1}',
                thumbnail: item['image'],
                description: item['description'],
                date: item['airDate'],
                isFiller:
                    item['filler'] == true ||
                    item['filler'] == 1 ||
                    item['isFiller'] == true ||
                    item['type']?.toString().toLowerCase() == 'filler',
              );
            })
            .where((episode) => episode.number != null)
            .toList()
          ..sort((a, b) => a.number!.compareTo(b.number!));

    // For movies, if episodes list was empty, synthesize Episode 1
    if (episodes.isEmpty) {
      episodes.add(EpisodeDataModel(id: '1', number: 1, title: 'Full Movie'));
    }

    return BaseEpisodeModel(episodes: episodes, totalEpisodes: episodes.length);
  }

  static final Map<String, ({DateTime time, BaseSourcesModel data})>
  _sourcesCache = {};

  static void clearCache({String? animeId, int? episode}) {
    if (animeId == null) {
      _sourcesCache.clear();
      return;
    }
    if (episode == null) {
      _sourcesCache.removeWhere((k, _) => k.startsWith('$animeId:'));
    } else {
      _sourcesCache.removeWhere((k, _) => k.startsWith('$animeId:$episode:'));
    }
  }

  @override
  Future<BaseSourcesModel> getSources(
    String animeId,
    String episodeId,
    String? serverName,
    String? category,
  ) async {
    final rawEp = episodeId.split('+').last.replaceAll(RegExp(r'[^0-9]'), '');
    final episode = int.tryParse(rawEp) ?? int.tryParse(episodeId) ?? 1;
    final requestedAudio = category?.toLowerCase() == 'dub' ? 'dub' : 'sub';

    final cacheKey = '$animeId:$episode:$serverName:$requestedAudio';
    final cached = _sourcesCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.time) < const Duration(minutes: 20)) {
      return cached.data;
    }

    Future<Map<String, dynamic>?> request(String path) async {
      try {
        final response = await UniversalHttpClient.instance
            .get(Uri.parse('$apiUrl$path'), headers: headers)
            .timeout(const Duration(seconds: 10));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        final decoded = json.decode(response.body);
        if (decoded is! Map || decoded['error'] != null) return null;
        return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }

    BaseSourcesModel? parseSource(
      String endpoint,
      Map<String, dynamic>? payload,
    ) {
      if (payload == null) return null;

      Map<String, dynamic>? raw;
      String actualAudio = requestedAudio;

      if (payload.containsKey('sub') || payload.containsKey('dub')) {
        if (requestedAudio == 'dub') {
          raw = payload['dub'] as Map<String, dynamic>?;
          if (raw != null && (raw['sources'] as List?)?.isNotEmpty == true) {
            actualAudio = 'dub';
          } else {
            // When DUB was requested, do NOT silently fall back to SUB for this endpoint!
            // Return null so candidate endpoints (Zoko, AniNeko, Gigi) that actually have DUB can be tried!
            return null;
          }
        } else {
          raw = (payload['sub'] ?? payload['hsub']) as Map<String, dynamic>?;
          if (raw != null && (raw['sources'] as List?)?.isNotEmpty == true) {
            actualAudio = 'sub';
          } else {
            return null;
          }
        }
      } else {
        final endpointAudio = endpoint.contains('/dub') ? 'dub' : 'sub';
        if (endpoint.contains('/anineko/') && requestedAudio != endpointAudio) {
          return null;
        }
        raw = payload;
        actualAudio = endpointAudio;
      }

      final serverReferer =
          endpoint.contains('megaplay')
              ? 'https://megaplay.buzz/'
              : endpoint.contains('zoko')
              ? 'https://zokoanime.video/'
              : endpoint.contains('animegg')
              ? 'https://www.animegg.org/'
              : 'https://justanime.to/';

      final commonHeaders = {
        'User-Agent': _userAgent,
        'Referer': serverReferer,
        'Origin': serverReferer.replaceAll(RegExp(r'/+$'), ''),
        ...Map<String, String>.from(
          (raw['headers'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ) ??
              (payload['headers'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ) ??
              const {},
        ),
      };

      String serverLabel = 'Momo';
      if (endpoint.contains('megaplay')) {
        serverLabel = 'Momo';
      } else if (endpoint.contains('zokoanime')) {
        serverLabel = 'Zoko';
      } else if (endpoint.contains('anineko')) {
        serverLabel = 'Neko';
      } else if (endpoint.contains('animegg')) {
        serverLabel = 'Gigi';
      }

      final sources =
          (raw['sources'] as List<dynamic>? ?? const [])
              .map((value) {
                final item = Map<String, dynamic>.from(value as Map);
                final sourceHeaders = Map<String, String>.from(
                  (item['headers'] as Map?)?.map(
                        (key, value) =>
                            MapEntry(key.toString(), value.toString()),
                      ) ??
                      commonHeaders,
                );
                final urlStr = item['url']?.toString() ?? '';
                return Source(
                  url: urlStr,
                  quality: item['quality']?.toString() ?? 'Auto',
                  isM3U8: item['isM3U8'] == true || urlStr.contains('.m3u8'),
                  isDub: actualAudio == 'dub',
                  type: serverLabel,
                  headers: sourceHeaders,
                );
              })
              .where((source) => source.url?.isNotEmpty == true)
              .toList();

      if (sources.isEmpty) return null;

      final tracks =
          (raw['subtitles'] as List<dynamic>? ??
                  raw['tracks'] as List<dynamic>? ??
                  payload['subtitles'] as List<dynamic>? ??
                  const [])
              .map((value) {
                final item = Map<String, dynamic>.from(value as Map);
                return Subtitle(
                  url: (item['url'] ?? item['file'])?.toString(),
                  lang:
                      (item['lang'] ?? item['label'])?.toString() ?? 'English',
                  isSub: true,
                );
              })
              .where((track) => track.url?.isNotEmpty == true)
              .toList();

      Intro? intro;
      final subPayload = payload['sub'] as Map<String, dynamic>?;
      final dubPayload = payload['dub'] as Map<String, dynamic>?;
      final rawIntro =
          raw['intro'] ??
          payload['intro'] ??
          subPayload?['intro'] ??
          dubPayload?['intro'];
      if (rawIntro is Map) {
        final start = (rawIntro['start'] as num?)?.toInt();
        final end = (rawIntro['end'] as num?)?.toInt();
        if (start != null && end != null && end > start) {
          intro = Intro(start: start, end: end);
        }
      }

      Intro? outro;
      final rawOutro =
          raw['outro'] ??
          payload['outro'] ??
          subPayload?['outro'] ??
          dubPayload?['outro'];
      if (rawOutro is Map) {
        final start = (rawOutro['start'] as num?)?.toInt();
        final end = (rawOutro['end'] as num?)?.toInt();
        if (start != null && end != null && end > start) {
          outro = Intro(start: start, end: end);
        }
      }

      return BaseSourcesModel(
        sources: sources,
        tracks: tracks,
        headers: commonHeaders,
        intro: intro,
        outro: outro,
      );
    }

    final sName = serverName?.toLowerCase() ?? '';
    final endpoints = <String>[];
    if (sName.contains('zoko')) {
      endpoints.add('/watch/$animeId/episode/$episode/zokoanime');
    } else if (sName.contains('megaplay') || sName.contains('momo')) {
      endpoints.add('/watch/$animeId/episode/$episode/megaplay');
    } else if (sName.contains('neko') || sName.contains('anineko')) {
      endpoints.add('/watch/$animeId/episode/$episode/anineko/$requestedAudio');
    } else if (sName.contains('gigi') || sName.contains('animegg')) {
      endpoints.add('/watch/$animeId/episode/$episode/animegg');
    }

    // Priority order tuned for high-speed & reliable playback (Megaplay & Zoko first):
    final priorityEndpoints = [
      '/watch/$animeId/episode/$episode/megaplay',
      '/watch/$animeId/episode/$episode/zokoanime',
      if (requestedAudio == 'dub') ...[
        '/watch/$animeId/episode/$episode/animegg',
        '/watch/$animeId/episode/$episode/anineko/dub',
      ] else ...[
        '/watch/$animeId/episode/$episode/animegg',
        '/watch/$animeId/episode/$episode/anineko/sub',
      ],
    ];
    for (final ep in priorityEndpoints) {
      if (!endpoints.contains(ep)) {
        endpoints.add(ep);
      }
    }

    final completer = Completer<BaseSourcesModel?>();
    var isDone = false;
    var nextIndex = 0;
    var inFlight = 0;
    var failedCount = 0;
    Intro? discoveredIntro;
    Intro? discoveredOutro;

    void spawnNext() {
      if (isDone || nextIndex >= endpoints.length) return;
      final ep = endpoints[nextIndex++];
      inFlight++;

      request(ep)
          .timeout(const Duration(seconds: 12))
          .then((payload) {
            final model = parseSource(ep, payload);
            if (model != null) {
              if (model.intro != null && discoveredIntro == null) {
                discoveredIntro = model.intro;
              }
              if (model.outro != null && discoveredOutro == null) {
                discoveredOutro = model.outro;
              }
            }
            if (model != null && model.sources.isNotEmpty && !isDone) {
              isDone = true;
              final finalModel = BaseSourcesModel(
                sources: model.sources,
                tracks: model.tracks,
                headers: model.headers,
                intro: model.intro ?? discoveredIntro,
                outro: model.outro ?? discoveredOutro,
              );
              _sourcesCache[cacheKey] = (
                time: DateTime.now(),
                data: finalModel,
              );
              if (!completer.isCompleted) completer.complete(finalModel);
              return;
            }
            throw Exception('Empty or unplayable source');
          })
          .catchError((_) {
            failedCount++;
            inFlight--;
            if (failedCount >= endpoints.length && !isDone) {
              isDone = true;
              if (!completer.isCompleted) completer.complete(null);
            } else if (!isDone &&
                nextIndex < endpoints.length &&
                inFlight < 2) {
              spawnNext();
            }
          });
    }

    // Start candidate #1 (Momo/Megaplay) immediately
    spawnNext();

    // Hedge quickly with candidate #2 if the preferred host is slow. This
    // keeps a healthy primary uncontested while avoiding a long cold-start
    // penalty when its DNS, TLS, or extraction endpoint is delayed.
    Timer? hedgeTimer;
    if (endpoints.length > 1) {
      hedgeTimer = Timer(const Duration(milliseconds: 400), () {
        if (!isDone && inFlight < 2 && nextIndex < endpoints.length) {
          spawnNext();
        }
      });
    }

    var resolvedModel = await completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => null,
    );
    hedgeTimer?.cancel();

    if (resolvedModel != null && resolvedModel.sources.isNotEmpty) {
      if ((resolvedModel.intro == null || resolvedModel.outro == null) &&
          (discoveredIntro != null || discoveredOutro != null)) {
        resolvedModel = BaseSourcesModel(
          sources: resolvedModel.sources,
          tracks: resolvedModel.tracks,
          headers: resolvedModel.headers,
          intro: resolvedModel.intro ?? discoveredIntro,
          outro: resolvedModel.outro ?? discoveredOutro,
        );
      }
      return resolvedModel;
    }

    throw Exception(
      'No playable JustAnime source found for episode $episode ($requestedAudio)',
    );
  }

  @override
  Future<BaseServerModel> getSupportedServers({dynamic metadata}) async {
    final subServers = [
      ServerData(name: "Momo (HLS)", id: "megaplay", isDub: false),
      ServerData(name: "Zoko (HLS)", id: "zokoanime", isDub: false),
      ServerData(name: "Gigi (MP4)", id: "animegg", isDub: false),
      ServerData(name: "Neko (HLS)", id: "anineko", isDub: false),
    ];

    final dubServers = [
      ServerData(name: "Momo (HLS)", id: "megaplay", isDub: true),
      ServerData(name: "Zoko (HLS)", id: "zokoanime", isDub: true),
      ServerData(name: "Gigi (MP4)", id: "animegg", isDub: true),
      ServerData(name: "Neko (HLS)", id: "anineko", isDub: true),
    ];

    return BaseServerModel(sub: subServers, dub: dubServers);
  }

  @override
  Future<WatchPage> getWatch(String animeId) {
    throw UnimplementedError();
  }
}
