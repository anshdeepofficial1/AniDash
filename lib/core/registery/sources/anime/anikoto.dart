import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:html/parser.dart' as html;
import 'package:ani_dash/core/models/anime/anime_model.dep.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/models/anime/page_model.dart';
import 'package:ani_dash/core/models/anime/server_model.dart';
import 'package:ani_dash/core/models/anime/source_model.dart';
import 'package:ani_dash/core/registery/sources/anime/anime_provider.dart';
import 'package:ani_dash/core/registery/sources/anime/deps/kwik.dart';
import 'package:ani_dash/core/utils/app_logger.dart';

class AnikotoProvider extends AnimeProvider {
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36';

  final Map<String, String> _sourceHeaders = {
    'Cookie': '__ddg1=;__ddg2_=',
    'Referer': 'https://anikoto.pw/',
    'User-Agent': _userAgent,
  };

  AnikotoProvider()
    : super(
        baseUrl: "https://anikoto.pw",
        apiUrl: "https://anikoto.pw/api",
        providerName: "anikoto",
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

  @override
  Future<SearchPage> getSearch(String keyword, String? type, int page) async {
    var query = keyword.replaceAll("-", " ");
    final normalized =
        query
            .replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toLowerCase();
    // AniKoto catalogs the original 2000 film as "One Piece Movie 1".
    if (normalized == 'one piece the movie') {
      query = 'One Piece Movie 1';
    }
    final url = Uri.parse("$apiUrl?m=search&q=$query");

    final res = await UniversalHttpClient.instance.get(url, headers: headers);
    final Map<String, dynamic> decoded = json.decode(res.body);

    final List<dynamic>? results = decoded['data'];
    final List<BaseAnimeModel> searchResults = [];

    if (results != null) {
      for (final result in results) {
        searchResults.add(
          BaseAnimeModel(
            id: result['session'],
            anilistId: null,
            name: result['title'],
            jname: null,
            type: result['type'],
            description: null,
            poster: result['poster'],
            banner: null,
            genres: [],
            releaseDate: result['year']?.toString(),
            number: result['episodes'],
          ),
        );
      }
    }

    return SearchPage(results: searchResults);
  }

  @override
  Future<BaseEpisodeModel> getEpisodes(
    String animeId, {
    String? anilistId,
    String? malId,
  }) async {
    List<dynamic> list = [];
    String actualId = animeId;
    String url = "$apiUrl?m=release&id=$actualId&sort=episode_asc";

    var bodyDecoded = <String, dynamic>{};
    try {
      var res = await UniversalHttpClient.instance.get(
        Uri.parse(url),
        headers: headers,
      );
      bodyDecoded = json.decode(res.body);
    } catch (e) {
      bodyDecoded = {};
    }

    if (bodyDecoded['data'] == null ||
        (bodyDecoded['data'] is List && bodyDecoded['data'].isEmpty)) {
      try {
        final searchRes = await getSearch(
          animeId.replaceAll('-', ' '),
          null,
          1,
        );
        if (searchRes.results.isNotEmpty) {
          final queryTitle = animeId.replaceAll('-', ' ').trim().toLowerCase();
          final match = searchRes.results.firstWhereOrNull((r) {
            final name = r.name?.toLowerCase().trim() ?? '';
            return name == queryTitle || name.startsWith(queryTitle);
          });
          if (match?.id != null) {
            actualId = match!.id!;
            url = "$apiUrl?m=release&id=$actualId&sort=episode_asc";
            var res = await UniversalHttpClient.instance.get(
              Uri.parse(url),
              headers: headers,
            );
            bodyDecoded = json.decode(res.body);
          }
        }
      } catch (e) {
        bodyDecoded = {};
      }
    }

    if (bodyDecoded['data'] != null) {
      list.add(bodyDecoded['data']);
    }

    final int totalPages = bodyDecoded['last_page'] ?? 1;

    for (int i = 1; i < totalPages; i++) {
      final nextRes = await UniversalHttpClient.instance.get(
        Uri.parse("$url&page=${i + 1}"),
        headers: headers,
        cacheConfig:
            (i == (totalPages - 1) || (i == 0 && i == (totalPages - 1)))
                ? CacheConfig.short
                : CacheConfig.year,
      );
      final nextBody = json.decode(nextRes.body);
      if (nextBody['data'] != null) {
        list.add(nextBody['data']);
      }
    }

    final flatList = list.expand((item) => item as List<dynamic>).toList();
    List<EpisodeDataModel> episodes = [];

    for (int i = 0; i < flatList.length; i++) {
      final item = flatList[i];
      final String episodeSession = item['session'];
      final String combinedId = "$animeId+$episodeSession";

      final num? epNumFromApi = item['episode'];
      final int calculatedEpNum =
          (epNumFromApi != null) ? epNumFromApi.toInt() : (i + 1);

      String? title = item['title'];
      if (title != null && title.trim().isEmpty) {
        title = null;
      }

      final String? thumbnail = item['snapshot'];
      final bool isFiller = (item['filler'] ?? 0) != 0;

      episodes.add(
        EpisodeDataModel(
          id: combinedId,
          number: calculatedEpNum,
          title: title ?? 'Episode $calculatedEpNum',
          thumbnail: thumbnail,
          isFiller: isFiller,
        ),
      );
    }

    episodes.sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0));

    for (int i = 0; i < episodes.length; i++) {
      episodes[i] = episodes[i].copyWith(
        number: i + 1,
        title:
            episodes[i].title!.startsWith('Episode ')
                ? 'Episode ${i + 1}'
                : episodes[i].title,
      );
    }

    return BaseEpisodeModel(episodes: episodes, totalEpisodes: episodes.length);
  }

  @override
  Future<BaseSourcesModel> getSources(
    String animeId,
    String episodeId,
    String? serverName,
    String? category,
  ) async {
    final parts = episodeId.split("+");
    if (parts.length < 2) throw Exception("Invalid ID format");
    final String animeSession = parts[0];
    final String epSession = parts[1];

    final episodeUrl = "$baseUrl/play/$animeSession/$epSession";
    final bool isRequestingDub = category?.toLowerCase() == 'dub';

    final data = await UniversalHttpClient.instance.get(
      Uri.parse(episodeUrl),
      headers: headers,
      cacheConfig: CacheConfig.none,
    );
    final document = html.parse(data.body);

    final streams = document.querySelectorAll('div#resolutionMenu > button');

    List<Source> sources = [];
    List<Future<void>> extractTasks = [];

    for (final e in streams) {
      final link = e.attributes['data-src'] ?? '';
      if (link.isEmpty) continue;

      // Rely on the data-audio attribute for sub/dub filtering
      final audioAttr = e.attributes['data-audio'] ?? '';
      final bool isStreamDub = audioAttr == 'eng';

      if (isStreamDub != isRequestingDub) continue;

      final resAttr = e.attributes['data-resolution'];
      final String quality = resAttr != null ? "${resAttr}p" : e.text.trim();

      extractTasks.add(() async {
        try {
          final extracted = await Kwik()
              .extract(link, server: 'Kwik', quality: quality)
              .timeout(const Duration(seconds: 20));

          if (extracted.isNotEmpty) {
            sources.addAll(extracted.cast<Source>());
          }
        } catch (err) {
          AppLogger.e(
            "[anikoto] Failed to extract Kwik stream for $quality: $err",
          );
        }
      }());
    }

    await Future.wait(extractTasks);

    return BaseSourcesModel(
      sources: sources,
      tracks: [],
      intro: Intro(start: 0, end: 0),
      outro: Intro(start: 0, end: 0),
      headers: {'Referer': 'https://kwik.cx/', 'User-Agent': _userAgent},
    );
  }

  @override
  Future<BaseServerModel> getSupportedServers({dynamic metadata}) async {
    final subServers = [
      ServerData(name: "anikoto", id: "anikoto", isDub: false),
    ];

    final dubServers = [
      ServerData(name: "anikoto", id: "anikoto", isDub: true),
    ];

    return BaseServerModel(sub: subServers, dub: dubServers);
  }

  @override
  Future<WatchPage> getWatch(String animeId) {
    throw UnimplementedError();
  }
}
