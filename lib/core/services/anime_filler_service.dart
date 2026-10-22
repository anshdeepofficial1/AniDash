import 'dart:convert';
import 'package:ani_dash/core/jikan/jikan_service.dart';
import 'package:ani_dash/core/network/http_client.dart';
import 'package:ani_dash/core/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnimeFillerInfo {
  final Set<int> fillers;
  final Set<int> mixed;

  const AnimeFillerInfo({this.fillers = const {}, this.mixed = const {}});

  Map<String, dynamic> toJson() => {
        'fillers': fillers.toList(),
        'mixed': mixed.toList(),
      };

  factory AnimeFillerInfo.fromJson(Map<String, dynamic> json) {
    final fillersList =
        (json['fillers'] as List?)
            ?.map((e) => (e as num).toInt())
            .toSet() ??
        <int>{};
    final mixedList =
        (json['mixed'] as List?)
            ?.map((e) => (e as num).toInt())
            .toSet() ??
        <int>{};
    return AnimeFillerInfo(fillers: fillersList, mixed: mixedList);
  }
}

class AnimeFillerService {
  static final AnimeFillerService _instance = AnimeFillerService._internal();
  factory AnimeFillerService() => _instance;
  AnimeFillerService._internal() {
    _initPersistentCache();
  }

  static const String _diskPrefix = 'anime_filler_v2_';
  final Map<String, AnimeFillerInfo> _cache = {};
  final JikanService _jikan = JikanService();
  bool _initialized = false;

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  Future<void> _initPersistentCache() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_diskPrefix));
      for (final k in keys) {
        final cacheKey = k.substring(_diskPrefix.length);
        final raw = prefs.getString(k);
        if (raw != null && raw.isNotEmpty) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          _cache[cacheKey] = AnimeFillerInfo.fromJson(map);
        }
      }
      _initialized = true;
    } catch (_) {}
  }

  /// Synchronously returns cached filler info if available in RAM.
  AnimeFillerInfo? getCachedFillerInfo(String title) {
    final key = _normalizeKey(title);
    return _cache[key];
  }

  String _normalizeKey(String title) =>
      title.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  /// Returns full filler and mixed canon/filler info for the specified anime.
  Future<AnimeFillerInfo> getFillerInfo({
    required String title,
    int? malId,
    List<String> alternateTitles = const [],
  }) async {
    final cacheKey = _normalizeKey(title);

    // 1. Check in-memory cache (0ms instant return)
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (cached.fillers.isNotEmpty || cached.mixed.isNotEmpty) {
        return cached;
      }
    }

    // 2. Check disk cache
    final fromDisk = await _loadFromDisk(cacheKey);
    if (fromDisk != null &&
        (fromDisk.fillers.isNotEmpty || fromDisk.mixed.isNotEmpty)) {
      _cache[cacheKey] = fromDisk;
      return fromDisk;
    }

    // 3. Fast Network: AnimeFillerList probe FIRST (Single fast request ~250-400ms)
    final aflInfo = await _fetchFromAnimeFillerList(
      title,
      alternateTitles: alternateTitles,
    );
    if (aflInfo.fillers.isNotEmpty || aflInfo.mixed.isNotEmpty) {
      _cache[cacheKey] = aflInfo;
      await _saveToDisk(cacheKey, aflInfo);
      AppLogger.success(
        '[AnimeFillerService] Found ${aflInfo.fillers.length} fillers and ${aflInfo.mixed.length} mixed episodes from AnimeFillerList for "$title"',
      );
      return aflInfo;
    }

    // 4. Fallback to Jikan API if MAL ID is available (fast capped timeout)
    if (malId != null && malId > 0) {
      final jikanFillers = await _fetchFromJikan(malId);
      if (jikanFillers.isNotEmpty) {
        final jikanInfo = AnimeFillerInfo(fillers: jikanFillers);
        _cache[cacheKey] = jikanInfo;
        await _saveToDisk(cacheKey, jikanInfo);
        return jikanInfo;
      }
    }

    return const AnimeFillerInfo();
  }

  Future<void> _saveToDisk(String key, AnimeFillerInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(info.toJson());
      await prefs.setString('$_diskPrefix$key', jsonStr);
    } catch (_) {}
  }

  Future<AnimeFillerInfo?> _loadFromDisk(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('$_diskPrefix$key');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return AnimeFillerInfo.fromJson(map);
      }
    } catch (_) {}
    return null;
  }

  /// Returns the set of episode numbers that are identified as filler.
  Future<Set<int>> getFillerEpisodes({
    required String title,
    int? malId,
    List<String> alternateTitles = const [],
  }) async {
    final info = await getFillerInfo(
      title: title,
      malId: malId,
      alternateTitles: alternateTitles,
    );
    return info.fillers;
  }

  Future<AnimeFillerInfo> _fetchFromAnimeFillerList(
    String title, {
    List<String> alternateTitles = const [],
  }) async {
    final candidateSlugs = _generateSlugs([title, ...alternateTitles]);

    for (final slug in candidateSlugs) {
      try {
        final url = Uri.parse('https://www.animefillerlist.com/shows/$slug');
        final response = await UniversalHttpClient.instance
            .get(url, headers: _headers, cacheConfig: CacheConfig.long)
            .timeout(const Duration(seconds: 4));

        if (response.statusCode != 200) continue;

        final body = response.body;
        if (!body.contains('EpisodeList')) continue;

        final regex = RegExp(
          r'<tr class="([^"]*)" id="eps-(\d+)">.*?<td class="Type"><span>([^<]+)</span></td>',
          dotAll: true,
        );
        final matches = regex.allMatches(body);
        if (matches.isEmpty) continue;

        final fillers = <int>{};
        final mixed = <int>{};
        for (final m in matches) {
          final rowClass = (m.group(1) ?? '').toLowerCase();
          final epNum = int.tryParse(m.group(2) ?? '') ?? 0;
          final type = (m.group(3) ?? '').toLowerCase();

          if (rowClass.contains('mixed') || type.contains('mixed')) {
            mixed.add(epNum);
          } else if (rowClass.contains('filler') || type.contains('filler')) {
            fillers.add(epNum);
          }
        }

        if (fillers.isNotEmpty || mixed.isNotEmpty) {
          return AnimeFillerInfo(fillers: fillers, mixed: mixed);
        }
      } catch (e) {
        AppLogger.d(
          '[AnimeFillerService] AFL probe failed for slug "$slug": $e',
        );
      }
    }

    return const AnimeFillerInfo();
  }

  List<String> _generateSlugs(List<String> titles) {
    final slugs = <String>{};

    for (final raw in titles) {
      if (raw.trim().isEmpty) continue;

      // Clean brackets, suffixes, Dub/Sub markers
      var cleaned =
          raw
              .replaceAll(
                RegExp(
                  r'\s*\((?:dub|sub|tv|audio|uncensored|season\s*\d*)[^)]*\)',
                  caseSensitive: false,
                ),
                '',
              )
              .replaceAll(
                RegExp(
                  r'\s*\[(?:dub|sub|tv|audio|uncensored)[^\]]*\]',
                  caseSensitive: false,
                ),
                '',
              )
              .replaceAll(
                RegExp(r'\s*-\s*(?:dub|sub)$', caseSensitive: false),
                '',
              )
              .replaceAll(RegExp(r'[:!]'), '')
              .toLowerCase()
              .trim();

      String toSlug(String s) => s
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');

      final baseSlug = toSlug(cleaned);
      if (baseSlug.isNotEmpty) {
        slugs.add(baseSlug);
      }

      // Specific popular series variations
      if (baseSlug.contains('shippuden') && !baseSlug.startsWith('naruto-')) {
        slugs.add('naruto-shippuden');
      }
      if (baseSlug == 'naruto' || baseSlug.startsWith('naruto-')) {
        slugs.add('naruto');
      }
      if (baseSlug.contains('bleach')) {
        slugs.add('bleach');
      }
      if (baseSlug.contains('one-piece')) {
        slugs.add('one-piece');
      }
      if (baseSlug.contains('fairy-tail')) {
        slugs.add('fairy-tail');
      }
      if (baseSlug.contains('boruto')) {
        slugs.add('boruto-naruto-next-generations');
      }
      if (baseSlug.contains('conan') || baseSlug.contains('case-closed')) {
        slugs.add('detective-conan');
      }
      if (baseSlug.contains('dragon-ball-z')) {
        slugs.add('dragon-ball-z');
      }
      if (baseSlug.contains('dragon-ball-super')) {
        slugs.add('dragon-ball-super');
      }
      if (baseSlug.contains('dragon-ball') &&
          !baseSlug.contains('super') &&
          !baseSlug.contains('-z')) {
        slugs.add('dragon-ball');
      }
      if (baseSlug.contains('black-clover')) {
        slugs.add('black-clover');
      }
      if (baseSlug.contains('gintama')) {
        slugs.add('gintama');
      }
      if (baseSlug.contains('hunter-x-hunter') ||
          baseSlug.contains('hunter-hunter')) {
        slugs.add('hunter-x-hunter-2011');
        slugs.add('hunter-x-hunter');
      }
      if (baseSlug.contains('rurouni-kenshin')) {
        slugs.add('rurouni-kenshin');
      }
      if (baseSlug.contains('inuyasha')) {
        slugs.add('inuyasha');
      }
      if (baseSlug.contains('boku-no-hero') ||
          baseSlug.contains('my-hero-academia')) {
        slugs.add('my-hero-academia');
      }
      if (baseSlug.contains('kimetsu-no-yaiba') ||
          baseSlug.contains('demon-slayer')) {
        slugs.add('demon-slayer-kimetsu-no-yaiba');
      }
      if (baseSlug.contains('shingeki-no-kyojin') ||
          baseSlug.contains('attack-on-titan')) {
        slugs.add('attack-on-titan');
      }
      if (baseSlug.contains('jujutsu-kaisen')) {
        slugs.add('jujutsu-kaisen');
      }
    }

    return slugs.toList();
  }

  Future<Set<int>> _fetchFromJikan(int malId) async {
    final fillers = <int>{};
    try {
      int page = 1;
      while (page <= 8) {
        final jikanEpisodes = await _jikan
            .getEpisodes(malId, page)
            .timeout(const Duration(seconds: 4));

        if (jikanEpisodes.isEmpty) break;

        for (final ep in jikanEpisodes) {
          if (ep.filler) {
            fillers.add(ep.malId);
          }
        }

        if (jikanEpisodes.length < 100) break;
        page++;
        // Throttle to respect Jikan's rate limit
        await Future.delayed(const Duration(milliseconds: 250));
      }
    } catch (e) {
      AppLogger.d('[AnimeFillerService] Jikan fallback failed: $e');
    }
    return fillers;
  }
}
