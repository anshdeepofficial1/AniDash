import 'package:ani_dash/core/models/anime/anime_model.dep.dart';
import 'package:ani_dash/core/models/anime/episode_model.dart';
import 'package:ani_dash/core/models/anime/page_model.dart';
import 'package:ani_dash/core/models/anime/server_model.dart';
import 'package:ani_dash/core/models/anime/source_model.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/registery/sources/anime/anime_provider.dart';
import 'package:ani_dash/core/registery/sources/anime/aniwatch/hianime.dart';
import 'package:html/parser.dart' as html;

/// AniKoto's former `.pw/api` endpoint was retired. The current catalogue is
/// served from anikototv.bz and uses the same AniList-indexed stream library as
/// HiAnime/MegaPlay. Keep AniKoto as an independent selectable catalogue while
/// sharing the maintained stream extraction implementation.
class AnikotoProvider extends AnimeProvider {
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

  final HiAnimeProvider _streamDelegate = HiAnimeProvider();
  final Map<String, String> _anilistIds = <String, String>{};

  AnikotoProvider()
    : super(
        baseUrl: 'https://anikototv.bz',
        apiUrl: 'https://anikototv.bz/ajax',
        providerName: 'anikoto',
      );

  @override
  Map<String, String> get headers => {
    'Referer': '$baseUrl/',
    'User-Agent': _userAgent,
  };

  @override
  Future<SearchPage> getSearch(String keyword, String? type, int page) async {
    final uri = Uri.parse('$baseUrl/filter').replace(
      queryParameters: {
        'keyword': keyword.replaceAll('-', ' '),
        if (page > 1) 'page': '$page',
      },
    );
    final response = await UniversalHttpClient.instance.get(
      uri,
      headers: headers,
      cacheConfig: CacheConfig.short,
    );
    if (response.statusCode != 200) return SearchPage(results: const []);

    final document = html.parse(response.body);
    final seen = <String>{};
    final results = <BaseAnimeModel>[];
    for (final item in document.querySelectorAll('#list-items .item')) {
      final titleLink = item.querySelector('a.name.d-title');
      final href = titleLink?.attributes['href'];
      final name = titleLink?.text.trim();
      if (href == null || name == null || name.isEmpty) continue;
      final segments = Uri.tryParse(href)?.pathSegments ?? const <String>[];
      final watchIndex = segments.indexOf('watch');
      if (watchIndex < 0 || watchIndex + 1 >= segments.length) continue;
      final slug = segments[watchIndex + 1];
      if (!seen.add(slug)) continue;

      results.add(
        BaseAnimeModel(
          id: slug,
          name: name,
          jname: titleLink?.attributes['data-jp'],
          poster: item.querySelector('.poster img')?.attributes['src'],
          type: item.querySelector('.poster .meta .right')?.text.trim(),
        ),
      );
    }
    return SearchPage(results: results);
  }

  @override
  Future<BaseEpisodeModel> getEpisodes(
    String animeId, {
    String? anilistId,
    String? malId,
  }) async {
    final resolvedId =
        anilistId ??
        _anilistIds[animeId] ??
        (RegExp(r'^\d+$').hasMatch(animeId) ? animeId : null);
    if (resolvedId != null) _anilistIds[animeId] = resolvedId;
    return _streamDelegate.getEpisodes(
      resolvedId ?? animeId,
      anilistId: resolvedId,
      malId: malId,
    );
  }

  @override
  Future<BaseSourcesModel> getSources(
    String animeId,
    String episodeId,
    String? serverName,
    String? category,
  ) {
    final resolvedId =
        _anilistIds[animeId] ??
        (RegExp(r'^\d+$').hasMatch(animeId) ? animeId : null);
    if (resolvedId == null) {
      return Future.value(BaseSourcesModel());
    }
    return _streamDelegate.getSources(
      resolvedId,
      episodeId,
      serverName,
      category,
    );
  }

  @override
  Future<BaseServerModel> getSupportedServers({dynamic metadata}) async {
    return BaseServerModel(
      sub: [
        ServerData(
          name: 'AniKoto • Japanese SUB',
          id: 'megaplay',
          isDub: false,
        ),
      ],
      dub: [
        ServerData(name: 'AniKoto • English DUB', id: 'megaplay', isDub: true),
      ],
    );
  }

  @override
  Future<DetailPage> getDetails(String animeId) => throw UnimplementedError();

  @override
  Future<HomePage> getHome() => throw UnimplementedError();

  @override
  Future<SearchPage> getPage(String route, int page) =>
      throw UnimplementedError();

  @override
  Future<WatchPage> getWatch(String animeId) => throw UnimplementedError();
}
