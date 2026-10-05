import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ani_dash/core/models/universal/universal_media.dart';
import 'package:ani_dash/core/services/mappers/universal_media_mapper.dart';
import 'package:ani_dash/core/utils/app_logger.dart';

class FranchiseWatchOrderItem {
  final UniversalMedia media;
  final String relationType;
  final bool isCurrent;
  final String
  chipLabel; // e.g., "Season 1", "Season 3 Part 1", "Season 3 Part 2", "Season 4 Part 1"
  final String orderLabel; // e.g., "Season 1", "Season 3 Part 2"
  final int? seasonNumber; // numeric season if available, e.g. 1, 2, 3, 4
  final String?
  placementNote; // e.g., "Watch after Season 1", "Recap • Optional"
  final bool isMainStory;

  const FranchiseWatchOrderItem({
    required this.media,
    required this.relationType,
    this.isCurrent = false,
    required this.chipLabel,
    required this.orderLabel,
    this.seasonNumber,
    this.placementNote,
    this.isMainStory = true,
  });

  String get id => media.id;
  int? get idMal => int.tryParse(media.idMal ?? '');
  UniversalTitle get title => media.title;
  String get displayTitle =>
      media.title.english ?? media.title.romaji ?? media.title.userPreferred;
  String? get format => media.format;
  int? get episodes => media.episodes;
  int? get year => media.startDate?.year ?? media.seasonYear;
  String get coverImage =>
      media.coverImage.large ?? media.coverImage.medium ?? '';
  bool get isTv => format == 'TV' || format == 'TV_SHORT';
  bool get isMovie => format == 'MOVIE';
  bool get isOvaOrSpecial =>
      format == 'OVA' || format == 'ONA' || format == 'SPECIAL';

  /// Exact episode boundary when the verified watch-order note provides one.
  int? get afterEpisode {
    final match = RegExp(
      r'after(?:\s+\w+)?\s+Episode\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(placementNote ?? '');
    return int.tryParse(match?.group(1) ?? '');
  }
}

class FranchiseWatchOrder {
  /// The linear canon main storyline following PREQUEL -> SEQUEL relations
  final List<FranchiseWatchOrderItem> mainStory;

  /// Optional side stories, recap/summary movies, OVAs, specials
  final List<FranchiseWatchOrderItem> optionalExtras;

  /// TV seasons/parts for the season selector chips
  final List<FranchiseWatchOrderItem> tvSeasons;

  final String currentMediaId;

  const FranchiseWatchOrder({
    required this.mainStory,
    required this.optionalExtras,
    required this.tvSeasons,
    required this.currentMediaId,
  });

  /// All entries combined (main story + extras)
  List<FranchiseWatchOrderItem> get allItems => [
    ...mainStory,
    ...optionalExtras,
  ];
}

class FranchiseService {
  static final FranchiseService _instance = FranchiseService._internal();
  factory FranchiseService() => _instance;
  FranchiseService._internal();

  // In-memory cache keyed by media ID pointing to the resolved franchise
  final Map<String, FranchiseWatchOrder> _cache = {};

  static const String _graphQlUrl = 'https://graphql.anilist.co';

  Future<FranchiseWatchOrder?> getFranchiseWatchOrderById(
    String mediaId,
  ) async {
    final cached = _cache[mediaId];
    if (cached != null) return _reindexForCurrent(cached, mediaId);
    final media = await _fetchMediaWithRelations(mediaId);
    if (media == null) return null;
    return getFranchiseWatchOrder(media);
  }

  Future<FranchiseWatchOrderItem?> movieAfterEpisode(
    String mediaId,
    int episode,
  ) async {
    final order = await getFranchiseWatchOrderById(mediaId);
    return order?.allItems.firstWhereOrNull(
      (item) => item.isMovie && item.afterEpisode == episode,
    );
  }

  static const String _franchiseNodeQuery = '''
query (\$id: Int) {
  Media(id: \$id, type: ANIME) {
    id
    idMal
    title {
      romaji
      english
      native
      userPreferred
    }
    format
    status
    description
    episodes
    seasonYear
    startDate {
      year
      month
      day
    }
    coverImage {
      large
      medium
    }
    relations {
      edges {
        relationType
        node {
          id
          idMal
          title {
            romaji
            english
            native
            userPreferred
          }
          format
          status
          description
          episodes
          seasonYear
          startDate {
            year
            month
            day
          }
          type
          coverImage {
            large
            medium
          }
        }
      }
    }
  }
}
''';

  /// Resolves the full franchise watch order for the given anime media.
  Future<FranchiseWatchOrder> getFranchiseWatchOrder(
    UniversalMedia rootMedia,
  ) async {
    final rootId = rootMedia.id;
    if (_cache.containsKey(rootId)) {
      final cached = _cache[rootId]!;
      if (cached.currentMediaId == rootId) {
        return cached;
      }
      return _reindexForCurrent(cached, rootId);
    }

    try {
      final mediaMap = <String, UniversalMedia>{};
      final relationTypeMap = <String, String>{};
      final visited = <String>{};
      final queue = <String>[rootId];

      mediaMap[rootId] = rootMedia;
      relationTypeMap[rootId] = 'CURRENT';

      // Seed with direct relations from rootMedia
      for (final rel in rootMedia.relations) {
        final relType = rel.relationType.toUpperCase();
        final relFormat = rel.media.format?.toUpperCase() ?? '';
        if (_isIgnoredFormat(relFormat)) continue;

        if (relType == 'PREQUEL' || relType == 'SEQUEL') {
          queue.add(rel.media.id);
          relationTypeMap.putIfAbsent(rel.media.id, () => relType);
        } else if (_isRelevantFranchiseRelation(relType, relFormat)) {
          mediaMap.putIfAbsent(rel.media.id, () => rel.media);
          relationTypeMap.putIfAbsent(rel.media.id, () => relType);
        }
      }

      var networkHops = 0;
      const maxHops = 15;

      while (queue.isNotEmpty && networkHops < maxHops) {
        final currentId = queue.removeAt(0);
        if (visited.contains(currentId)) continue;
        visited.add(currentId);

        UniversalMedia? currentMedia = mediaMap[currentId];
        final needsFetch =
            currentMedia == null || currentMedia.relations.isEmpty;

        if (needsFetch) {
          networkHops++;
          final fetched = await _fetchMediaWithRelations(currentId);
          if (fetched != null) {
            mediaMap[currentId] = fetched;
            currentMedia = fetched;
          }
        }

        if (currentMedia != null) {
          for (final rel in currentMedia.relations) {
            final relType = rel.relationType.toUpperCase();
            final relFormat = rel.media.format?.toUpperCase() ?? '';
            if (_isIgnoredFormat(relFormat)) continue;

            if (relType == 'PREQUEL' || relType == 'SEQUEL') {
              if (!visited.contains(rel.media.id)) {
                queue.add(rel.media.id);
              }
              mediaMap.putIfAbsent(rel.media.id, () => rel.media);
              relationTypeMap.putIfAbsent(rel.media.id, () => relType);
            } else if (_isRelevantFranchiseRelation(relType, relFormat)) {
              if (_hasSignificantTitleOverlap(rootMedia, rel.media)) {
                mediaMap.putIfAbsent(rel.media.id, () => rel.media);
                relationTypeMap.putIfAbsent(rel.media.id, () => relType);
              }
            }
          }
        }
      }

      // 1. Separate Main Story Line from Optional/Extras
      // Find the root/head of the PREQUEL -> SEQUEL chain
      final mainChain = _extractMainStoryChain(rootMedia, mediaMap);
      final mainChainIds = mainChain.map((m) => m.id).toSet();

      // Gather Extras (not in main linear chain, but related to the franchise)
      final extraMedia =
          mediaMap.values.where((m) {
            if (mainChainIds.contains(m.id)) return false;
            return _hasSignificantTitleOverlap(rootMedia, m);
          }).toList();

      // Sort extras by release date
      extraMedia.sort((a, b) {
        final yearA = a.startDate?.year ?? a.seasonYear ?? 9999;
        final yearB = b.startDate?.year ?? b.seasonYear ?? 9999;
        if (yearA != yearB) return yearA.compareTo(yearB);
        final monthA = a.startDate?.month ?? 1;
        final monthB = b.startDate?.month ?? 1;
        return monthA.compareTo(monthB);
      });

      // 2. Generate Human-Readable Labels for Main Story Chain
      final mainStoryItems = <FranchiseWatchOrderItem>[];
      final tvSeasons = <FranchiseWatchOrderItem>[];
      int tvCounter = 1;

      for (int i = 0; i < mainChain.length; i++) {
        final m = mainChain[i];
        final nextM = (i + 1 < mainChain.length) ? mainChain[i + 1] : null;

        // Check if followed by Part 2 of the same season
        final title =
            m.title.english ?? m.title.romaji ?? m.title.userPreferred;
        final nextTitle =
            nextM != null
                ? (nextM.title.english ??
                    nextM.title.romaji ??
                    nextM.title.userPreferred)
                : '';
        final isFollowedByPart2 = RegExp(
          r'Part\s*2|Cour\s*2',
          caseSensitive: false,
        ).hasMatch(nextTitle);

        final labels = _deriveLabels(
          title: title,
          format: m.format ?? 'TV',
          tvIndex: tvCounter,
          hasPart2: isFollowedByPart2,
        );

        if (m.format == 'TV' || m.format == 'TV_SHORT') {
          tvCounter++;
        }

        final item = FranchiseWatchOrderItem(
          media: m,
          relationType: relationTypeMap[m.id] ?? 'SEQUEL',
          isCurrent: m.id == rootId,
          chipLabel: labels.chipLabel,
          orderLabel: labels.orderLabel,
          seasonNumber: labels.seasonNumber,
          isMainStory: true,
        );

        mainStoryItems.add(item);
        if (m.format == 'TV' ||
            m.format == 'TV_SHORT' ||
            m.format == 'SPECIAL') {
          tvSeasons.add(item);
        }
      }

      // 3. Inline Movies with Verified Placement into Main Story
      final remainingExtras = <UniversalMedia>[];
      for (final m in extraMedia) {
        final format = m.format?.toUpperCase() ?? 'SPECIAL';
        final isMovie = format == 'MOVIE';

        final placement = isMovie ? _resolveMoviePlacement(m, mainChain) : null;
        if (placement != null) {
          final title =
              m.title.english ?? m.title.romaji ?? m.title.userPreferred;
          final labels = _deriveLabels(
            title: title,
            format: format,
            tvIndex: tvCounter,
          );

          final movieItem = FranchiseWatchOrderItem(
            media: m,
            relationType: relationTypeMap[m.id] ?? 'RELATED',
            isCurrent: m.id == rootId,
            chipLabel: labels.chipLabel,
            orderLabel: labels.orderLabel,
            seasonNumber: null,
            placementNote: placement.note,
            isMainStory: true,
          );

          // Find where to insert
          int insertIdx = -1;
          if (placement.insertAfterId != null) {
            final targetIdx = mainStoryItems.indexWhere(
              (item) => item.id == placement.insertAfterId,
            );
            if (targetIdx != -1) {
              insertIdx = targetIdx + 1;
              while (insertIdx < mainStoryItems.length &&
                  mainStoryItems[insertIdx].isMovie) {
                insertIdx++;
              }
            }
          }

          if (insertIdx != -1 && insertIdx <= mainStoryItems.length) {
            mainStoryItems.insert(insertIdx, movieItem);
          } else {
            mainStoryItems.add(movieItem);
          }
        } else {
          remainingExtras.add(m);
        }
      }

      // 4. Generate Placement Notes for Remaining Optional/Extras
      final optionalExtras = <FranchiseWatchOrderItem>[];
      for (final m in remainingExtras) {
        final relType = relationTypeMap[m.id] ?? 'RELATED';
        final format = m.format?.toUpperCase() ?? 'SPECIAL';
        final isMovie = format == 'MOVIE';
        final isOva = format == 'OVA';

        String note;
        if (relType == 'SUMMARY') {
          note = 'Recap • Optional';
        } else if (relType == 'ALTERNATIVE') {
          note = 'Alternative Version • Optional';
        } else if (isMovie) {
          note = 'Movie • Optional / Side Story';
        } else if (isOva) {
          note = 'OVA • Side Story';
        } else {
          note = 'Special • Optional';
        }

        final title =
            m.title.english ?? m.title.romaji ?? m.title.userPreferred;
        final labels = _deriveLabels(
          title: title,
          format: format,
          tvIndex: tvCounter,
        );

        final item = FranchiseWatchOrderItem(
          media: m,
          relationType: relType,
          isCurrent: m.id == rootId,
          chipLabel: labels.chipLabel,
          orderLabel: labels.orderLabel,
          placementNote: note,
          isMainStory: false,
        );

        optionalExtras.add(item);
      }

      final franchise = FranchiseWatchOrder(
        mainStory: mainStoryItems,
        optionalExtras: optionalExtras,
        tvSeasons: tvSeasons.isNotEmpty ? tvSeasons : mainStoryItems,
        currentMediaId: rootId,
      );

      for (final item in franchise.allItems) {
        _cache[item.id] = franchise;
      }

      AppLogger.i(
        '[FranchiseService] Resolved franchise for "${rootMedia.title.userPreferred}": '
        '${mainStoryItems.length} main story items, ${optionalExtras.length} extras, '
        '${tvSeasons.length} season chips',
      );

      return franchise;
    } catch (e, st) {
      AppLogger.w('[FranchiseService] Failed to resolve franchise: $e', e, st);
      final fallbackItem = FranchiseWatchOrderItem(
        media: rootMedia,
        relationType: 'CURRENT',
        isCurrent: true,
        chipLabel: 'Season 1',
        orderLabel: 'Season 1',
        seasonNumber: 1,
        isMainStory: true,
      );
      return FranchiseWatchOrder(
        mainStory: [fallbackItem],
        optionalExtras: [],
        tvSeasons: [fallbackItem],
        currentMediaId: rootId,
      );
    }
  }

  /// Extracts the linear canonical PREQUEL -> SEQUEL chain
  List<UniversalMedia> _extractMainStoryChain(
    UniversalMedia root,
    Map<String, UniversalMedia> pool,
  ) {
    // 1. Trace backwards along PREQUEL relations to find the start of the TV story
    UniversalMedia head = root;
    final visitedBackward = <String>{root.id};

    while (true) {
      UniversalMedia? prequelNode;
      for (final rel in head.relations) {
        if (rel.relationType.toUpperCase() == 'PREQUEL') {
          final cand = pool[rel.media.id] ?? rel.media;
          final candFormat = cand.format?.toUpperCase() ?? '';
          // Only trace backward into main story if it's TV or canon prequel
          if (candFormat == 'TV' || candFormat == 'TV_SHORT') {
            prequelNode = cand;
            break;
          }
        }
      }
      if (prequelNode != null && !visitedBackward.contains(prequelNode.id)) {
        visitedBackward.add(prequelNode.id);
        head = prequelNode;
      } else {
        break;
      }
    }

    // 2. Trace forward along SEQUEL relations from head
    final chain = <UniversalMedia>[head];
    final visitedForward = <String>{head.id};
    UniversalMedia current = head;

    while (true) {
      UniversalMedia? sequelNode;
      // First preference: TV sequel
      for (final rel in current.relations) {
        if (rel.relationType.toUpperCase() == 'SEQUEL') {
          final cand = pool[rel.media.id] ?? rel.media;
          final candFormat = cand.format?.toUpperCase() ?? '';
          if (candFormat == 'TV' || candFormat == 'TV_SHORT') {
            sequelNode = cand;
            break;
          }
        }
      }

      // Second preference: Canonical continuation specials/movies (e.g. AoT Final Chapters, Mugen Train Movie)
      if (sequelNode == null) {
        for (final rel in current.relations) {
          if (rel.relationType.toUpperCase() == 'SEQUEL') {
            final cand = pool[rel.media.id] ?? rel.media;
            final candFormat = cand.format?.toUpperCase() ?? '';
            if (candFormat == 'SPECIAL' || candFormat == 'MOVIE') {
              if (_hasSignificantTitleOverlap(root, cand)) {
                sequelNode = cand;
                break;
              }
            }
          }
        }
      }

      if (sequelNode != null && !visitedForward.contains(sequelNode.id)) {
        visitedForward.add(sequelNode.id);
        chain.add(sequelNode);
        current = sequelNode;
      } else {
        break;
      }
    }

    // Ensure root is in chain if it is a TV series and was missed
    if (!chain.any((m) => m.id == root.id) &&
        (root.format == 'TV' || root.format == 'TV_SHORT')) {
      chain.add(root);
      // Sort chain by release date if disconnected
      chain.sort((a, b) {
        final yA = a.startDate?.year ?? a.seasonYear ?? 9999;
        final yB = b.startDate?.year ?? b.seasonYear ?? 9999;
        if (yA != yB) return yA.compareTo(yB);
        final mA = a.startDate?.month ?? 1;
        final mB = b.startDate?.month ?? 1;
        return mA.compareTo(mB);
      });
    }

    return chain;
  }

  /// Derives human-friendly season and chip labels
  ({String chipLabel, String orderLabel, int? seasonNumber}) _deriveLabels({
    required String title,
    required String format,
    required int tvIndex,
    bool hasPart2 = false,
  }) {
    final clean = title.trim();
    final cleanLower = clean.toLowerCase();
    final isAoT =
        cleanLower.contains('attack on titan') ||
        cleanLower.contains('shingeki no kyojin');

    // Final Chapters (AoT Specials)
    final finalChaptersMatch = RegExp(
      r'Final\s+Chapters.*?(?:Part|Special)?\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(clean);
    if (finalChaptersMatch != null) {
      final num = finalChaptersMatch.group(1);
      return (
        chipLabel: 'Final Chapters $num',
        orderLabel: 'Final Chapters $num',
        seasonNumber: 4,
      );
    }

    // Final Season Part X
    final finalSeasonPartMatch = RegExp(
      r'(?:The\s+)?Final\s+Season.*?(?:Part\s*(\d+)|Cour\s*(\d+))',
      caseSensitive: false,
    ).firstMatch(clean);
    if (finalSeasonPartMatch != null) {
      final part =
          finalSeasonPartMatch.group(1) ?? finalSeasonPartMatch.group(2) ?? '1';
      final sNum = isAoT ? 4 : tvIndex;
      return (
        chipLabel: 'Season $sNum Part $part',
        orderLabel: 'Season $sNum Part $part',
        seasonNumber: sNum,
      );
    }

    // Final Season (plain)
    if (RegExp(
      r'(?:The\s+)?Final\s+Season',
      caseSensitive: false,
    ).hasMatch(clean)) {
      final sNum = isAoT ? 4 : tvIndex;
      final part = hasPart2 ? 'Part 1' : '';
      final label = part.isNotEmpty ? 'Season $sNum $part' : 'Season $sNum';
      return (chipLabel: label, orderLabel: label, seasonNumber: sNum);
    }

    // Season X Part Y
    final sPartMatch = RegExp(
      r'(?:Season\s*(\d+)|(\d+)(?:st|nd|rd|th)\s*Season).*?(?:Part\s*(\d+)|Cour\s*(\d+))',
      caseSensitive: false,
    ).firstMatch(clean);
    if (sPartMatch != null) {
      final sNum =
          int.tryParse(sPartMatch.group(1) ?? sPartMatch.group(2) ?? '1') ?? 1;
      final pNum = sPartMatch.group(3) ?? sPartMatch.group(4) ?? '1';
      return (
        chipLabel: 'Season $sNum Part $pNum',
        orderLabel: 'Season $sNum Part $pNum',
        seasonNumber: sNum,
      );
    }

    // Season X
    final sMatch = RegExp(
      r'(?:Season\s*(\d+)|(\d+)(?:st|nd|rd|th)\s*Season)',
      caseSensitive: false,
    ).firstMatch(clean);
    if (sMatch != null) {
      final sNum = int.tryParse(sMatch.group(1) ?? sMatch.group(2) ?? '1') ?? 1;
      final part = hasPart2 ? 'Part 1' : '';
      final label = part.isNotEmpty ? 'Season $sNum $part' : 'Season $sNum';
      return (chipLabel: label, orderLabel: label, seasonNumber: sNum);
    }

    // Named Arcs (Demon Slayer, etc.)
    final arcMatch = RegExp(
      r'(Mugen Train|Entertainment District|Swordsmith Village|Hashira Training|Infinity Castle)(?:\s*Arc)?',
      caseSensitive: false,
    ).firstMatch(clean);
    if (arcMatch != null) {
      final name = '${arcMatch.group(1)} Arc';
      return (chipLabel: name, orderLabel: name, seasonNumber: tvIndex);
    }

    // Fallback to Season index for TV
    if (format == 'TV' || format == 'TV_SHORT') {
      return (
        chipLabel: 'Season $tvIndex',
        orderLabel: 'Season $tvIndex',
        seasonNumber: tvIndex,
      );
    }

    // Extract subtitle if present (e.g. "My Hero Academia: Two Heroes" -> "Two Heroes")
    String? subtitle;
    if (clean.contains(':')) {
      subtitle = clean.split(':').last.trim();
    } else if (clean.contains(' - ')) {
      subtitle = clean.split(' - ').last.trim();
    }

    if (format == 'MOVIE') {
      final label =
          (subtitle != null && subtitle.length > 2 && subtitle.length < 32)
              ? subtitle
              : 'Movie';
      return (chipLabel: label, orderLabel: label, seasonNumber: null);
    }

    if (format == 'SPECIAL' || format == 'OVA' || format == 'ONA') {
      final prefix = format == 'SPECIAL' ? 'Special' : format;
      final label =
          (subtitle != null && subtitle.length > 2 && subtitle.length < 32)
              ? '$prefix: $subtitle'
              : prefix;
      return (chipLabel: label, orderLabel: label, seasonNumber: null);
    }

    return (chipLabel: format, orderLabel: format, seasonNumber: null);
  }

  bool _matchesSeasonNum(UniversalMedia m, int targetSeasonNum) {
    final t =
        (m.title.english ?? m.title.romaji ?? m.title.userPreferred)
            .toLowerCase();
    if (t.contains('season $targetSeasonNum') ||
        t.contains('${targetSeasonNum}nd season') ||
        t.contains('${targetSeasonNum}rd season') ||
        t.contains('${targetSeasonNum}th season') ||
        t.contains('${targetSeasonNum}st season')) {
      return true;
    }
    return false;
  }

  ({String note, String? insertAfterId})? _resolveMoviePlacement(
    UniversalMedia movie,
    List<UniversalMedia> mainChain,
  ) {
    final title =
        (movie.title.english ?? movie.title.userPreferred).toLowerCase();
    if (title.contains('recap') || title.contains('summary')) {
      return null;
    }

    // 1. Specific known placements
    // My Hero Academia
    if (title.contains('two heroes')) {
      final s =
          mainChain.firstWhereOrNull((m) => _matchesSeasonNum(m, 2)) ??
          mainChain.elementAtOrNull(1);
      return (note: 'Movie • Watch after Season 2', insertAfterId: s?.id);
    }
    if (title.contains('heroes rising') || title.contains('heroes: rising')) {
      final s =
          mainChain.firstWhereOrNull((m) => _matchesSeasonNum(m, 4)) ??
          mainChain.elementAtOrNull(3);
      return (note: 'Movie • Watch after Season 4', insertAfterId: s?.id);
    }
    if (title.contains('world heroes')) {
      final s =
          mainChain.firstWhereOrNull((m) => _matchesSeasonNum(m, 5)) ??
          mainChain.elementAtOrNull(4);
      return (note: 'Movie • Watch after Season 5', insertAfterId: s?.id);
    }
    if (title.contains("you're next") || title.contains("you are next")) {
      final s =
          mainChain.firstWhereOrNull((m) => _matchesSeasonNum(m, 7)) ??
          mainChain.elementAtOrNull(6);
      return (note: 'Movie • Watch after Season 7', insertAfterId: s?.id);
    }

    // Demon Slayer
    if (title.contains('mugen train') || title.contains('mugen ressha')) {
      final s =
          mainChain.firstWhereOrNull((m) => _matchesSeasonNum(m, 1)) ??
          mainChain.firstOrNull;
      return (
        note: 'Movie • Watch after Season 1 (Canon Bridge)',
        insertAfterId: s?.id,
      );
    }

    // Jujutsu Kaisen 0
    if (title.contains('jujutsu kaisen 0') ||
        (title.contains('jujutsu kaisen') && title.contains(' 0'))) {
      final s =
          mainChain.firstWhereOrNull((m) => _matchesSeasonNum(m, 1)) ??
          mainChain.firstOrNull;
      return (
        note: 'Prequel Movie • Watch after Season 1 (or before)',
        insertAfterId: s?.id,
      );
    }

    // Konosuba
    if (title.contains('legend of crimson') ||
        title.contains('kurenai densetsu')) {
      final s =
          mainChain.firstWhereOrNull((m) => _matchesSeasonNum(m, 2)) ??
          mainChain.elementAtOrNull(1);
      return (
        note: 'Movie • Watch after Season 2 (Canon Bridge)',
        insertAfterId: s?.id,
      );
    }

    // Made in Abyss
    if (title.contains('dawn of the deep soul') ||
        title.contains('fukaki tamashii')) {
      final s =
          mainChain.firstWhereOrNull((m) => _matchesSeasonNum(m, 1)) ??
          mainChain.firstOrNull;
      return (
        note: 'Movie • Watch after Season 1 (Canon Bridge)',
        insertAfterId: s?.id,
      );
    }

    // Rascal Does Not Dream
    if (title.contains('dreaming girl')) {
      final s =
          mainChain.firstWhereOrNull((m) => _matchesSeasonNum(m, 1)) ??
          mainChain.firstOrNull;
      return (note: 'Movie • Watch after Season 1', insertAfterId: s?.id);
    }

    // Haikyu!!
    if (title.contains('dumpster battle') || title.contains('gomi suteba')) {
      final s =
          mainChain.firstWhereOrNull((m) => _matchesSeasonNum(m, 4)) ??
          mainChain.elementAtOrNull(3);
      return (note: 'Movie • Watch after Season 4', insertAfterId: s?.id);
    }

    // Black Clover
    if (title.contains('sword of the wizard king')) {
      return (
        note: 'Movie • Watch after Episode 170',
        insertAfterId: mainChain.lastOrNull?.id,
      );
    }

    // Naruto
    if (title.contains('the last')) {
      return (
        note: 'Movie • Watch after Shippuden Episode 493',
        insertAfterId: mainChain.lastOrNull?.id,
      );
    }
    if (title.contains('boruto: naruto the movie')) {
      return (
        note: 'Movie • Watch after Shippuden Episode 500',
        insertAfterId: mainChain.lastOrNull?.id,
      );
    }

    // One Piece
    if (title.contains('strong world')) {
      return (
        note: 'Film 10 • Watch after Episode 429',
        insertAfterId: mainChain.lastOrNull?.id,
      );
    }
    if (title.contains('film z')) {
      return (
        note: 'Film 12 • Watch after Episode 578',
        insertAfterId: mainChain.lastOrNull?.id,
      );
    }
    if (title.contains('film gold')) {
      return (
        note: 'Film 13 • Watch after Episode 750',
        insertAfterId: mainChain.lastOrNull?.id,
      );
    }
    if (title.contains('stampede')) {
      return (
        note: 'Film 14 • Watch after Episode 896',
        insertAfterId: mainChain.lastOrNull?.id,
      );
    }
    if (title.contains('film red')) {
      return (
        note: 'Film 15 • Watch after Episode 1030',
        insertAfterId: mainChain.lastOrNull?.id,
      );
    }

    // Spy x Family
    if (title.contains('code: white')) {
      final s =
          mainChain.firstWhereOrNull((m) => _matchesSeasonNum(m, 1)) ??
          mainChain.firstOrNull;
      return (note: 'Movie • Watch after Season 1', insertAfterId: s?.id);
    }

    // General Chronological Placement by Release Date
    final mYear = movie.startDate?.year ?? movie.seasonYear;
    if (mYear != null && mainChain.isNotEmpty) {
      UniversalMedia? bestTvPredecessor;
      for (final tv in mainChain) {
        final tvYear = tv.startDate?.year ?? tv.seasonYear;
        if (tvYear != null && tvYear <= mYear) {
          bestTvPredecessor = tv;
        }
      }
      if (bestTvPredecessor != null) {
        final tvTitle =
            bestTvPredecessor.title.english ??
            bestTvPredecessor.title.userPreferred;
        final shortTv =
            RegExp(
              r'(?:Season\s*\d+|Final Season|\bPart\s*\d+)',
            ).firstMatch(tvTitle)?.group(0) ??
            'TV Series';
        return (
          note: 'Movie • Watch after $shortTv',
          insertAfterId: bestTvPredecessor.id,
        );
      }
    }

    return null;
  }

  FranchiseWatchOrder _reindexForCurrent(
    FranchiseWatchOrder original,
    String currentId,
  ) {
    final updatedMain =
        original.mainStory.map((item) {
          return FranchiseWatchOrderItem(
            media: item.media,
            relationType: item.relationType,
            isCurrent: item.id == currentId,
            chipLabel: item.chipLabel,
            orderLabel: item.orderLabel,
            seasonNumber: item.seasonNumber,
            placementNote: item.placementNote,
            isMainStory: true,
          );
        }).toList();

    final updatedExtras =
        original.optionalExtras.map((item) {
          return FranchiseWatchOrderItem(
            media: item.media,
            relationType: item.relationType,
            isCurrent: item.id == currentId,
            chipLabel: item.chipLabel,
            orderLabel: item.orderLabel,
            seasonNumber: item.seasonNumber,
            placementNote: item.placementNote,
            isMainStory: false,
          );
        }).toList();

    final updatedTv =
        original.tvSeasons.map((item) {
          return FranchiseWatchOrderItem(
            media: item.media,
            relationType: item.relationType,
            isCurrent: item.id == currentId,
            chipLabel: item.chipLabel,
            orderLabel: item.orderLabel,
            seasonNumber: item.seasonNumber,
            placementNote: item.placementNote,
            isMainStory: item.isMainStory,
          );
        }).toList();

    return FranchiseWatchOrder(
      mainStory: updatedMain,
      optionalExtras: updatedExtras,
      tvSeasons: updatedTv,
      currentMediaId: currentId,
    );
  }

  Future<UniversalMedia?> _fetchMediaWithRelations(String mediaId) async {
    try {
      final res = await http
          .post(
            Uri.parse(_graphQlUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'AniDash',
            },
            body: jsonEncode({
              'query': _franchiseNodeQuery,
              'variables': {'id': int.tryParse(mediaId)},
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode != 200 || res.body.isEmpty) return null;

      final data = jsonDecode(res.body);
      final mediaJson = data['data']?['Media'];
      if (mediaJson == null) return null;

      return UniversalMediaMapper.fromAnilist(mediaJson);
    } catch (e) {
      AppLogger.d('[FranchiseService] Error fetching node $mediaId: $e');
      return null;
    }
  }

  bool _isIgnoredFormat(String format) {
    const ignored = {'MANGA', 'NOVEL', 'ONE_SHOT', 'MUSIC'};
    return ignored.contains(format);
  }

  bool _isRelevantFranchiseRelation(String relationType, String format) {
    const validRelations = {
      'PARENT',
      'SIDE_STORY',
      'SUMMARY',
      'ALTERNATIVE',
      'OTHER',
      'SPIN_OFF',
    };
    const validFormats = {'TV', 'TV_SHORT', 'MOVIE', 'OVA', 'ONA', 'SPECIAL'};
    return validRelations.contains(relationType) &&
        validFormats.contains(format);
  }

  bool _hasSignificantTitleOverlap(UniversalMedia base, UniversalMedia rel) {
    final baseTitles =
        [
          base.title.english,
          base.title.romaji,
          base.title.userPreferred,
        ].whereType<String>().map((s) => s.toLowerCase()).toList();

    final relTitles =
        [
          rel.title.english,
          rel.title.romaji,
          rel.title.userPreferred,
        ].whereType<String>().map((s) => s.toLowerCase()).toList();

    if (baseTitles.isEmpty || relTitles.isEmpty) return true;

    const stopWords = {
      'the',
      'a',
      'an',
      'and',
      'or',
      'of',
      'in',
      'on',
      'at',
      'to',
      'for',
      'with',
      'no',
      'ni',
      'wa',
      'wo',
      'ga',
      'de',
      'na',
      'season',
      'part',
      'movie',
      'tv',
      'ova',
      'ona',
      'special',
      'act',
      'chapter',
      'arc',
      'final',
    };

    final baseTokens =
        baseTitles
            .expand(
              (t) =>
                  t.replaceAll(RegExp(r'[^\w\s]'), ' ').split(RegExp(r'\s+')),
            )
            .where((w) => w.length >= 2 && !stopWords.contains(w))
            .toSet();

    if (baseTokens.isEmpty) return true;

    final relTokens =
        relTitles
            .expand(
              (t) =>
                  t.replaceAll(RegExp(r'[^\w\s]'), ' ').split(RegExp(r'\s+')),
            )
            .where((w) => w.length >= 2 && !stopWords.contains(w))
            .toSet();

    return baseTokens.intersection(relTokens).isNotEmpty;
  }
}

final franchiseWatchOrderProvider =
    FutureProvider.family<FranchiseWatchOrder, UniversalMedia>((
      ref,
      anime,
    ) async {
      return FranchiseService().getFranchiseWatchOrder(anime);
    });
