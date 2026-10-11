import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:collection/collection.dart';
import 'package:html/dom.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/models/anime/page_model.dart';
import 'package:ani_dash/core/models/anime/server_model.dart';
import 'package:ani_dash/core/models/anime/source_model.dart';
import 'package:ani_dash/core/registery/sources/anime/aniwatch/extractors.dart';
import 'package:ani_dash/core/registery/sources/anime/anime_provider.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:ani_dash/core/utils/env_loader.dart';
import 'package:html/parser.dart' show parse;

class HiAnimeProvider extends AnimeProvider {
  static const String _fallbackApiUrl =
      'https://shonenx-aniwatch-instance.vercel.app/api/v2/hianime';
  final HomeExtractor homeExtractor;
  final DetailExtractor detailExtractor;
  final WatchExtractor watchExtractor;
  final SearchExtractor searchExtractor;
  final Map<String, String> _anilistIds = <String, String>{};

  static const _vidNestBase = 'https://new.vidnest.fun';
  static const _vidNestSecret = 'wSnEvGgWkkxb7nO1yyFgMxhDvogX_Q7Dr0Fi1E4qvn0';

  HiAnimeProvider({
    String? customApiUrl,
    this.homeExtractor = const HomeExtractor(),
    this.detailExtractor = const DetailExtractor(),
    this.watchExtractor = const WatchExtractor(),
    this.searchExtractor = const SearchExtractor(),
  }) : super(
         apiUrl:
             (customApiUrl != null && customApiUrl.isNotEmpty)
                 ? customApiUrl
                 : (API_URL.isNotEmpty ? API_URL : _fallbackApiUrl),
         baseUrl: 'https://hianime.ms',
         providerName: 'hianime',
       );

  @override
  Map<String, String> get headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
  };

  @override
  Future<HomePage> getHome() async {
    return HomePage();
    // final response =
    //     await UniversalHttpClient.instance.get(Uri.parse('$baseUrl/home'), headers: headers);

    // final document = parse(response.body);
    // return HomePage(
    //   spotlight: parseSpotlight(document, baseUrl),
    //   trending: parseTrending(document, baseUrl),
    //   featured: parseFeatured(document, baseUrl),
    // );
  }

  @override
  Future<DetailPage> getDetails(String animeId) async {
    final response = await UniversalHttpClient.instance.get(
      Uri.parse('$baseUrl/details/$animeId'),
      headers: headers,
    );
    final document = parse(response.body);
    return detailExtractor.parseDetail(document, baseUrl, animeId: animeId);
  }

  @override
  Future<WatchPage> getWatch(String animeId) async {
    final response = await UniversalHttpClient.instance.get(
      Uri.parse('$baseUrl/watch/$animeId'),
      headers: headers,
    );
    final document = parse(response.body);
    return watchExtractor.parseWatch(document, baseUrl, animeId: animeId);
  }

  // @override
  // Future<BaseEpisodeModel> getEpisodes(String animeId) async {

  //   final response = await UniversalHttpClient.instance.get(
  //       Uri.parse("$baseUrl/ajax/v2/episode/list/${animeId.split('-').last}"),
  //       headers: headers);

  //   final document = parse(json.decode(response.body)['html']);
  //   return parseEpisodes(document, "$baseUrl/ajax/v2/episode/list/",
  //       animeId: animeId);
  // }
  String _sanitizeEpisodeId(String animeId, String episodeId) {
    if (episodeId.isEmpty) return animeId;
    if (episodeId.startsWith('$animeId?')) return episodeId;
    if (episodeId.contains('?ep=')) {
      if (episodeId.startsWith(animeId)) return episodeId;
      return '$animeId?$episodeId';
    }
    if (episodeId.startsWith('?')) return '$animeId$episodeId';
    return '$animeId?$episodeId';
  }

  @override
  Future<BaseEpisodeModel> getEpisodes(
    String animeId, {
    String? anilistId,
    String? malId,
  }) async {
    try {
      final response = await UniversalHttpClient.instance.get(
        Uri.parse('$apiUrl/anime/$animeId/episodes'),
        cacheConfig: CacheConfig.medium,
      );
      if (response.statusCode != 200)
        throw StateError('Legacy API unavailable');
      final decoded = jsonDecode(response.body);
      final data = decoded['data'];
      if (data == null || data['episodes'] == null) {
        throw StateError('Legacy API returned no episodes');
      }

      return BaseEpisodeModel(
        episodes:
            (data['episodes'] as List<dynamic>)
                .map(
                  (episode) => EpisodeDataModel(
                    id: episode['episodeId']?.toString(),
                    number: (episode['number'] as num?)?.toInt() ?? 0,
                    title: episode['title']?.toString(),
                    isFiller: episode['isFiller'] == true,
                  ),
                )
                .toList(),
        totalEpisodes: (data['totalEpisodes'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      AppLogger.w('HiAnime legacy episode API unavailable: $e');
      return _getCurrentEpisodes(animeId, anilistId: anilistId);
    }
  }

  Future<String?> _resolveAniListId(String animeId) async {
    final cached = _anilistIds[animeId];
    if (cached != null) return cached;
    if (RegExp(r'^\d+$').hasMatch(animeId)) {
      _anilistIds[animeId] = animeId;
      return animeId;
    }
    try {
      final response = await UniversalHttpClient.instance.get(
        Uri.parse('$baseUrl/details/$animeId'),
        headers: headers,
        cacheConfig: CacheConfig.medium,
      );
      final match = RegExp(
        r'(?:vidnest\.fun|tryembed[^/]*)(?:/embed)?/anime/(\d+)/',
      ).firstMatch(response.body);
      final id = match?.group(1);
      if (id != null) _anilistIds[animeId] = id;
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<BaseEpisodeModel> _getCurrentEpisodes(
    String animeId, {
    String? anilistId,
  }) async {
    final id = anilistId ?? await _resolveAniListId(animeId);
    if (id == null) return BaseEpisodeModel(episodes: [], totalEpisodes: 0);
    _anilistIds[animeId] = id;
    try {
      final response = await UniversalHttpClient.instance.get(
        Uri.parse('https://api.ani.zip/mappings?anilist_id=$id'),
        cacheConfig: CacheConfig.medium,
      );
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawEpisodes = decoded['episodes'] as Map<String, dynamic>? ?? {};
      final episodes = <EpisodeDataModel>[];
      for (final entry in rawEpisodes.entries) {
        final number = int.tryParse(entry.key);
        if (number == null || entry.value is! Map) continue;
        final item = Map<String, dynamic>.from(entry.value as Map);
        final titles = item['title'] as Map?;
        final title =
            titles?['en']?.toString() ??
            titles?['x-jat']?.toString() ??
            titles?['ja']?.toString();
        episodes.add(
          EpisodeDataModel(
            id: number.toString(),
            number: number,
            title: title,
            thumbnail: item['image']?.toString(),
          ),
        );
      }
      episodes.sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0));
      return BaseEpisodeModel(
        episodes: episodes,
        totalEpisodes: episodes.length,
      );
    } catch (error) {
      AppLogger.w('HiAnime current episode metadata failed: $error');
      return BaseEpisodeModel(episodes: [], totalEpisodes: 0);
    }
  }

  String _base64UrlRandom(int length) {
    final random = Random.secure();
    return base64UrlEncode(
      List<int>.generate(length, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }

  Uint8List _decodeBase64Url(String value) {
    var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return Uint8List.fromList(base64Decode(normalized));
  }

  Future<Map<String, dynamic>> _fetchVidNest(String path) async {
    final uri = Uri.parse(
      '$_vidNestBase/$path',
    ).replace(queryParameters: {'_n': _base64UrlRandom(16)});
    final response = await UniversalHttpClient.instance.get(
      uri,
      cacheConfig: CacheConfig.none,
    );
    if (response.statusCode != 200) {
      throw StateError('HiAnime server returned ${response.statusCode}');
    }
    final envelope = jsonDecode(response.body) as Map<String, dynamic>;
    if (envelope['v'] != 2 || envelope['d'] == null) return envelope;
    final nonce = envelope['n']?.toString() ?? '';
    final encryptedBytes = _decodeBase64Url(envelope['d'].toString());
    if (encryptedBytes.length <= 12) throw StateError('Invalid stream data');
    final key = sha256.convert(utf8.encode('$nonce|$_vidNestSecret')).bytes;
    final iv = encrypt.IV(encryptedBytes.sublist(0, 12));
    final cipher = encrypt.Encrypted(encryptedBytes.sublist(12));
    final aes = encrypt.Encrypter(
      encrypt.AES(
        encrypt.Key(Uint8List.fromList(key)),
        mode: encrypt.AESMode.gcm,
        padding: null,
      ),
    );
    final plain = aes.decrypt(cipher, iv: iv);
    return Map<String, dynamic>.from(jsonDecode(plain) as Map);
  }

  String? retrieveServerId(Document document, int index, String category) {
    final serverItems = document.querySelectorAll(
      '.ps_-block.ps_-block-sub.servers-$category > .ps__-list .server-item',
    );
    return serverItems
        .firstWhereOrNull(
          (el) => el.attributes['data-server-id'] == index.toString(),
        )
        ?.attributes['data-id'];
  }

  @override
  Future<BaseSourcesModel> getSources(
    String animeId,
    String episodeId,
    String? serverName,
    String? category,
  ) async {
    final actualEpisodeId = _sanitizeEpisodeId(animeId, episodeId);
    final categoryParam = (category?.toLowerCase() == 'dub') ? 'dub' : 'sub';
    final serverParam =
        (serverName != null && serverName.isNotEmpty) ? serverName : 'hd-1';

    try {
      final sourceUri = Uri.parse(
        '$apiUrl/episode/sources?animeEpisodeId=$actualEpisodeId&server=$serverParam&category=$categoryParam',
      );
      final response = await UniversalHttpClient.instance.get(
        sourceUri,
        cacheConfig: CacheConfig.veryLong,
      );

      if (response.statusCode != 200) {
        AppLogger.w(
          'HiAnime getSources returned status ${response.statusCode}',
        );
        return _getVidNestSources(
          animeId,
          episodeId,
          serverName,
          categoryParam,
        );
      }

      final decoded = jsonDecode(response.body);
      final data = decoded['data'];
      if (data == null) {
        return _getVidNestSources(
          animeId,
          episodeId,
          serverName,
          categoryParam,
        );
      }

      final List rawTracks =
          (data['tracks'] as List?) ?? (data['subtitles'] as List?) ?? [];
      final tracks =
          rawTracks
              .map(
                (t) => Subtitle(
                  url: t['url']?.toString(),
                  lang: t['lang']?.toString(),
                  isSub: t['lang'] != 'thumbnails' && t['kind'] != 'thumbnails',
                ),
              )
              .where((t) => t.url != null && t.url!.isNotEmpty)
              .toList();

      final preview = tracks.firstWhereOrNull(
        (t) => t.isSub == false || t.lang?.toLowerCase() == 'thumbnails',
      );

      Intro? intro;
      if (data['intro'] is Map) {
        intro = Intro(
          start: (data['intro']['start'] as num?)?.toInt(),
          end: (data['intro']['end'] as num?)?.toInt(),
        );
      }

      Intro? outro;
      if (data['outro'] is Map) {
        outro = Intro(
          start: (data['outro']['start'] as num?)?.toInt(),
          end: (data['outro']['end'] as num?)?.toInt(),
        );
      }

      final sources =
          ((data['sources'] as List?) ?? [])
              .map(
                (source) => Source(
                  url: source['url']?.toString(),
                  isM3U8:
                      source['isM3U8'] == true ||
                      (source['url']?.toString().contains('.m3u8') ?? false),
                  quality: source['quality']?.toString() ?? 'Auto',
                  type: source['type']?.toString(),
                  isDub: categoryParam == 'dub',
                ),
              )
              .where((s) => s.url != null && s.url!.isNotEmpty)
              .toList();

      return BaseSourcesModel(
        headers:
            data['headers'] is Map
                ? Map<String, dynamic>.from(data['headers'])
                : null,
        preview: preview,
        intro: intro,
        outro: outro,
        sources: sources,
        anilistID: (data['anilistID'] as num?)?.toInt(),
        malID: (data['malID'] as num?)?.toInt(),
        tracks: tracks.where((t) => t.isSub == true).toList(),
      );
    } catch (e, st) {
      AppLogger.e('HiAnime getSources error: $e\n$st');
      return _getVidNestSources(animeId, episodeId, serverName, categoryParam);
    }
  }

  Future<BaseSourcesModel> _getVidNestSources(
    String animeId,
    String episodeId,
    String? serverName,
    String category,
  ) async {
    final anilistId = await _resolveAniListId(animeId);
    if (anilistId == null) return BaseSourcesModel();
    final episode =
        RegExp(r'(\d+(?:\.\d+)?)')
            .allMatches(episodeId)
            .map((match) => match.group(1))
            .whereType<String>()
            .lastOrNull ??
        '1';
    final requestedServer = serverName?.toLowerCase() ?? '';
    final paths = <String>[
      if (requestedServer.contains('hianime') ||
          requestedServer.contains('hd-2'))
        'hianime/anime/$anilistId/$episode/$category/hd-2'
      else if (requestedServer.contains('megaplay'))
        'animehub/$anilistId/$episode/$category'
      else
        'aniwave_hls/$anilistId/$episode/$category',
      'aniwave_hls/$anilistId/$episode/$category',
      'hianime/anime/$anilistId/$episode/$category/hd-2',
      'animehub/$anilistId/$episode/$category',
    ];

    Object? lastError;
    for (final path in paths.toSet()) {
      try {
        final data = await _fetchVidNest(
          path,
        ).timeout(const Duration(seconds: 6));
        final rawSources =
            (data['sources'] as List?) ?? (data['multiSrc'] as List?) ?? [];
        final sources =
            rawSources
                .whereType<Map>()
                .map((raw) {
                  final item = Map<String, dynamic>.from(raw);
                  final url = (item['url'] ?? item['file'])?.toString();
                  return Source(
                    url: url,
                    quality: item['quality']?.toString() ?? 'Auto',
                    isM3U8:
                        item['isM3U8'] == true ||
                        (url?.contains('.m3u8') ?? false),
                    isDub: category == 'dub',
                    type:
                        path.startsWith('aniwave')
                            ? 'AniWave'
                            : path.startsWith('hianime')
                            ? 'HiAnime HD-2'
                            : 'MegaPlay',
                    headers:
                        item['referer'] != null
                            ? {'Referer': item['referer'].toString()}
                            : const {},
                  );
                })
                .where((source) => source.url?.isNotEmpty == true)
                .toList();
        if (sources.isEmpty) throw StateError('No streams returned');
        final rawTracks =
            (data['subtitles'] as List?) ?? (data['tracks'] as List?) ?? [];
        final tracks =
            rawTracks
                .whereType<Map>()
                .map((raw) {
                  final item = Map<String, dynamic>.from(raw);
                  return Subtitle(
                    url: (item['url'] ?? item['file'])?.toString(),
                    lang:
                        (item['lang'] ?? item['label'])?.toString() ??
                        'English',
                    isSub: true,
                  );
                })
                .where((track) => track.url?.isNotEmpty == true)
                .toList();
        return BaseSourcesModel(
          sources: sources,
          tracks: tracks,
          intro:
              data['intro'] is Map
                  ? Intro.fromJson(Map<String, dynamic>.from(data['intro']))
                  : null,
          outro:
              data['outro'] is Map
                  ? Intro.fromJson(Map<String, dynamic>.from(data['outro']))
                  : null,
        );
      } catch (error) {
        lastError = error;
      }
    }
    AppLogger.w('All current HiAnime servers failed: $lastError');
    return BaseSourcesModel();
  }

  @override
  Future<SearchPage> getSearch(String keyword, String? type, int page) async {
    final hianimeType =
        type != null ? _mapTypeToHianimeType(type.toLowerCase()) : null;
    final url =
        hianimeType != null
            ? '$baseUrl/search?keyword=$keyword&type=$hianimeType&page=$page'
            : '$baseUrl/search?keyword=$keyword&page=$page';
    final response = await UniversalHttpClient.instance.get(
      Uri.parse(url),
      headers: headers,
    );
    final document = parse(response.body);
    return searchExtractor.parseSearch(
      document,
      baseUrl,
      keyword: keyword,
      page: page,
    );
  }

  @override
  Future<SearchPage> getPage(String route, int page) async {
    final response = await UniversalHttpClient.instance.get(
      Uri.parse('$baseUrl/$route?page=$page'),
      headers: headers,
    );
    final document = parse(response.body);
    return searchExtractor.parsePage(
      document,
      baseUrl,
      route: route,
      page: page,
    );
  }

  int? _mapTypeToHianimeType(String type) {
    return switch (type) {
      'movie' => 1,
      'tv' => 2,
      'ova' => 3,
      'ona' => 4,
      'special' => 5,
      'music' => 6,
      _ => null,
    };
  }

  @override
  Future<BaseServerModel> getSupportedServers({dynamic metadata}) async {
    try {
      final animeId = metadata?['id']?.toString() ?? '';
      final episodeId = metadata?['epId']?.toString() ?? '';

      if (animeId.isNotEmpty) {
        final actualEpisodeId = _sanitizeEpisodeId(animeId, episodeId);
        final res = await UniversalHttpClient.instance.get(
          Uri.parse('$apiUrl/episode/servers?animeEpisodeId=$actualEpisodeId'),
          cacheConfig: CacheConfig.veryLong,
        );

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final sub = data['data']?['sub'] as List?;
          final dub = data['data']?['dub'] as List?;

          final subServers =
              sub
                  ?.map(
                    (server) => ServerData(
                      id:
                          server['serverName']?.toString() ??
                          server['serverId']?.toString(),
                      name:
                          server['serverName']?.toString() ??
                          server['serverId']?.toString(),
                      isDub: false,
                    ),
                  )
                  .toList() ??
              [];

          final dubServers =
              dub
                  ?.map(
                    (server) => ServerData(
                      id:
                          server['serverName']?.toString() ??
                          server['serverId']?.toString(),
                      name:
                          server['serverName']?.toString() ??
                          server['serverId']?.toString(),
                      isDub: true,
                    ),
                  )
                  .toList() ??
              [];

          if (subServers.isNotEmpty || dubServers.isNotEmpty) {
            return BaseServerModel(sub: subServers, dub: dubServers);
          }
        }
      }
    } catch (e, st) {
      AppLogger.e('HiAnime getSupportedServers error: $e\n$st');
    }

    return BaseServerModel(
      sub: [
        ServerData(id: 'aniwave', name: 'AniWave • Japanese SUB', isDub: false),
        ServerData(
          id: 'hianime-hd-2',
          name: 'HiAnime HD-2 • Japanese SUB',
          isDub: false,
        ),
        ServerData(
          id: 'megaplay',
          name: 'MegaPlay • Japanese SUB',
          isDub: false,
        ),
      ],
      dub: [
        ServerData(id: 'aniwave', name: 'AniWave • English DUB', isDub: true),
        ServerData(
          id: 'hianime-hd-2',
          name: 'HiAnime HD-2 • English DUB',
          isDub: true,
        ),
        ServerData(id: 'megaplay', name: 'MegaPlay • English DUB', isDub: true),
      ],
    );
  }
}
